import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../models/bulk_item.dart';

/// Background isolate entry for large labelled-stock sync (5–8L+ rows).
/// Mirrors Kotlin [BulkRepositoryImpl.syncBulkItemsFromServer]:
/// stream JSON, map items, batch-insert into SQLite — no full in-memory load.
///
/// Speed focus (mapping rules unchanged):
/// - Insert batches of 1000
/// - Preload RFID barcode→TID map (no per-row DB lookup)
/// - Drop secondary indexes during insert, recreate after
/// - Dual RFID / null→hex mapping stays the same
class SyncIsolate {
  static const int _batchSize = 1000;
  static const int _rfidBatchSize = 1000;
  static const int _maxSkipped = 1000;
  static const int _progressIntervalMs = 1000;

  static const List<String> _bulkSecondaryIndexes = [
    'idx_bulk_items_epc',
    'idx_bulk_items_bulkItemId',
    'idx_bulk_items_counterName',
    'idx_bulk_items_boxName',
    'idx_bulk_items_branchName',
    'idx_bulk_items_category',
    'idx_bulk_items_productName',
    'idx_bulk_items_design',
    'idx_bulk_items_rfid',
    'idx_bulk_items_itemCode',
    'idx_bulk_items_tid',
  ];

  static void run(Map<String, dynamic> params) async {
    final RootIsolateToken? rootToken = params['token'];
    final SendPort sendPort = params['sendPort'];
    final String baseUrl = params['baseUrl'];
    final String clientCode = params['clientCode'];
    final int roleId = params['roleId'];
    final List<int> branchIds = List<int>.from(params['branchIds']);
    final String token = params['tokenStr'];
    final String dbPath = params['dbPath'];
    final String tagTypeRaw =
        (params['tagType'] as String? ?? 'webreusable').trim().toLowerCase();
    // Sparkle compares to "webreusable"; also accept Web_Reusable / reusable.
    final String tagType = tagTypeRaw.replaceAll(RegExp(r'[\s_-]+'), '');
    final bool isWebReusable =
        tagType == 'webreusable' || tagType.contains('reusable');
    final bool allowSingleAndWebReusable =
        params['allowSingleAndWebReusable'] as bool? ?? true;
    final usedEpcSet = <String>{};

    if (rootToken != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
    }

    Database? db;
    HttpClient? httpClient;

    void sendProgress({
      required String status,
      required int processed,
      required int synced,
      required int total,
      String? message,
    }) {
      sendPort.send({
        'status': status,
        'processed': processed,
        'synced': synced,
        'total': total,
        if (message != null) 'message': message,
      });
    }

    try {
      sendPort.send({'status': 'init', 'message': 'Initializing database...'});
      db = await openDatabase(
        dbPath,
        onConfigure: (database) async {
          await database.rawQuery('PRAGMA journal_mode=WAL;');
        },
      );

      await _configureBulkInsertPragmas(db);

      httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 60);
      httpClient.idleTimeout = const Duration(minutes: 15);

      // Sparkle login syncs GetAllRFID first so Barcode↔TID lookup works during mapping.
      sendPort.send({'status': 'rfid', 'message': 'Syncing RFID tags...'});
      await _syncRfidTagsFromServer(
        httpClient: httpClient,
        baseUrl: baseUrl,
        clientCode: clientCode,
        token: token,
        db: db,
      );

      sendPort.send({'status': 'rfid', 'message': 'Loading RFID lookup...'});
      final rfidByBarcode = await _loadRfidBarcodeMap(db);

      // Drop secondary indexes before wipe+bulk insert (UNIQUE(epc) stays).
      sendPort.send({'status': 'init', 'message': 'Preparing database...'});
      await _dropBulkSecondaryIndexes(db);
      await db.delete('bulk_items');

      sendPort.send({
        'status': 'downloading',
        'message': 'Connecting to stock API...',
      });

      final stockUrl = Uri.parse(
        '${baseUrl}api/ProductMaster/branch-labelled-stocks/search',
      );
      final stockRequest = await httpClient.postUrl(stockUrl);
      stockRequest.headers.contentType = ContentType.json;
      if (token.isNotEmpty) {
        stockRequest.headers.set('Authorization', 'Bearer $token');
      }

      final requestBody = {
        'ClientCode': clientCode,
        'RoleId': roleId,
        'ReturnAll': true,
        if (roleId != 1) 'branchIds': branchIds,
      };
      stockRequest.write(jsonEncode(requestBody));

      final stockResponse = await stockRequest.close();
      if (stockResponse.statusCode != 200) {
        throw Exception('Stock API returned status: ${stockResponse.statusCode}');
      }

      int totalCount = 0;
      int processedCount = 0;
      int syncedCount = 0;
      final List<BulkItem> queue = [];
      final List<String> skippedItemCodes = [];
      int lastProgressMs = 0;

      void maybeSendProgress({bool force = false}) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (!force && now - lastProgressMs < _progressIntervalMs) return;
        lastProgressMs = now;
        sendProgress(
          status: 'syncing',
          processed: processedCount,
          synced: syncedCount,
          total: totalCount,
          message: totalCount > 0
              ? 'Processing $syncedCount of $totalCount'
              : 'Processing $syncedCount items...',
        );
      }

      Future<void> flushQueue() async {
        if (queue.isEmpty || db == null) return;
        final itemsToInsert = List<BulkItem>.from(queue);
        queue.clear();
        await _insertBulkBatch(db, itemsToInsert);
        maybeSendProgress();
      }

      final parser = _StreamingJsonParser(
        onTotalCountFound: (total) async {
          totalCount = total;
          maybeSendProgress(force: true);
        },
        onItemFound: (itemJson) async {
          processedCount++;

          try {
            final mapped = _mapServerItem(
              rfidByBarcode: rfidByBarcode,
              itemJson: itemJson,
              isWebReusable: isWebReusable,
              allowSingleAndWebReusable: allowSingleAndWebReusable,
              usedEpcSet: usedEpcSet,
              skippedItemCodes: skippedItemCodes,
            );
            if (mapped != null) {
              queue.add(mapped);
              syncedCount++;
            }
          } catch (_) {
            final code = BulkItem.apiString(itemJson, ['ItemCode', 'itemCode']);
            if (skippedItemCodes.length < _maxSkipped) {
              skippedItemCodes.add('$code - Mapping failed');
            }
          }

          if (queue.length >= _batchSize) {
            await flushQueue();
          }
        },
      );

      await for (final chunk in stockResponse.transform(utf8.decoder)) {
        await parser.addChunk(chunk);
        if (queue.length >= _batchSize) {
          await flushQueue();
        }
      }

      await flushQueue();

      sendPort.send({
        'status': 'init',
        'message': 'Building indexes...',
      });
      await _createBulkSecondaryIndexes(db);
      await _restoreDbPragmas(db);

      sendPort.send({
        'status': 'completed',
        'processed': processedCount,
        'synced': syncedCount,
        'total': totalCount == 0 ? processedCount : totalCount,
        'skipped': skippedItemCodes,
      });
    } catch (e) {
      if (db != null) {
        try {
          await _createBulkSecondaryIndexes(db);
        } catch (_) {}
        try {
          await _restoreDbPragmas(db);
        } catch (_) {}
      }
      sendPort.send({
        'status': 'error',
        'message': e.toString().replaceFirst('Exception: ', ''),
      });
    } finally {
      httpClient?.close(force: true);
      if (db != null) {
        try {
          await db.close();
        } catch (_) {}
      }
    }
  }

  static Future<void> _configureBulkInsertPragmas(Database db) async {
    await db.rawQuery('PRAGMA synchronous = OFF');
    await db.rawQuery('PRAGMA temp_store = MEMORY');
    await db.rawQuery('PRAGMA cache_size = -200000'); // ~200MB page cache
    await db.rawQuery('PRAGMA locking_mode = EXCLUSIVE');
    try {
      await db.rawQuery('PRAGMA mmap_size = 268435456');
    } catch (_) {}
  }

  static Future<void> _restoreDbPragmas(Database db) async {
    await db.rawQuery('PRAGMA synchronous = NORMAL');
    try {
      await db.rawQuery('PRAGMA locking_mode = NORMAL');
    } catch (_) {}
  }

  static Future<void> _dropBulkSecondaryIndexes(Database db) async {
    for (final name in _bulkSecondaryIndexes) {
      try {
        await db.execute('DROP INDEX IF EXISTS $name');
      } catch (_) {}
    }
  }

  static Future<void> _createBulkSecondaryIndexes(Database db) async {
    const stmts = [
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_epc ON bulk_items(epc)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_bulkItemId ON bulk_items(bulkItemId)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_counterName ON bulk_items(counterName)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_boxName ON bulk_items(boxName)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_branchName ON bulk_items(branchName)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_category ON bulk_items(category)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_productName ON bulk_items(productName)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_design ON bulk_items(design)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_rfid ON bulk_items(rfid)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_itemCode ON bulk_items(itemCode)',
      'CREATE INDEX IF NOT EXISTS idx_bulk_items_tid ON bulk_items(tid)',
    ];
    for (final sql in stmts) {
      try {
        await db.execute(sql);
      } catch (_) {}
    }
  }

  static Future<void> _insertBulkBatch(Database db, List<BulkItem> items) async {
    if (items.isEmpty) return;
    final batch = db.batch();
    for (final item in items) {
      // NEVER use REPLACE — UNIQUE(epc) + REPLACE deletes the other row.
      batch.insert(
        'bulk_items',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Full barcode→TID map once (O(1) lookup per stock row; critical for 5–8L).
  static Future<Map<String, String>> _loadRfidBarcodeMap(Database db) async {
    final map = <String, String>{};
    try {
      final rows = await db.rawQuery(
        'SELECT BarcodeNumber, TidValue FROM rfid_tags',
      );
      for (final row in rows) {
        final barcode =
            (row['BarcodeNumber'] as String? ?? '').trim().toUpperCase();
        if (barcode.isEmpty) continue;
        final tid = (row['TidValue'] as String? ?? '').trim().toUpperCase();
        map[barcode] = tid;
      }
    } catch (_) {}
    return map;
  }

  static Future<void> _syncRfidTagsFromServer({
    required HttpClient httpClient,
    required String baseUrl,
    required String clientCode,
    required String token,
    required Database db,
  }) async {
    if (clientCode.trim().isEmpty) return;
    try {
      final url = Uri.parse('${baseUrl}api/ProductMaster/GetAllRFID');
      final request = await httpClient.postUrl(url);
      request.headers.contentType = ContentType.json;
      if (token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      request.write(jsonEncode({'ClientCode': clientCode}));
      final response = await request.close();
      if (response.statusCode != 200) return;

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! List) return;

      try {
        await db.delete('rfid_tags');
      } catch (_) {}

      final batch = <Map<String, dynamic>>[];
      Future<void> flushRfid() async {
        if (batch.isEmpty) return;
        final b = db.batch();
        for (final row in batch) {
          b.insert('rfid_tags', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await b.commit(noResult: true);
        batch.clear();
      }

      for (final raw in decoded) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final barcode = BulkItem.apiString(map, [
          'BarcodeNumber',
          'barcodeNumber',
          'RFIDCode',
        ]);
        final tid = BulkItem.apiString(map, [
          'TidValue',
          'TIDNumber',
          'TidNumber',
          'EPC',
        ]);
        if (barcode.isEmpty) continue;
        batch.add({
          'BarcodeNumber': barcode,
          'TidValue': tid,
          'ClientCode': BulkItem.apiString(map, ['ClientCode']),
          'CreatedOn': BulkItem.apiString(map, ['CreatedOn']),
          'LastUpdated': BulkItem.apiString(map, ['LastUpdated']),
          'StatusType':
              (map['StatusType'] == true || map['StatusType'] == 1) ? 1 : 0,
        });
        if (batch.length >= _rfidBatchSize) {
          await flushRfid();
        }
      }
      await flushRfid();
    } catch (_) {
      // RFID sheet sync is best-effort; stock sync must continue.
    }
  }

  /// Per-item dual mapping (unchanged rules):
  /// 1) API RFIDCode present → keep RFID, EPC from TIDNumber or rfid lookup
  /// 2) API RFIDCode null → EPC/TID = convertToHex(itemCode), RFID blank
  static BulkItem? _mapServerItem({
    required Map<String, String> rfidByBarcode,
    required Map<String, dynamic> itemJson,
    required bool isWebReusable,
    required bool allowSingleAndWebReusable,
    required Set<String> usedEpcSet,
    required List<String> skippedItemCodes,
  }) {
    // Tag-type flags kept for isolate API; mapping is per-item so both flows
    // work in the same sync (RFID present vs RFID null→hex).
    // ignore: unnecessary_statements
    (isWebReusable, allowSingleAndWebReusable);

    final status = BulkItem.apiString(itemJson, ['Status', 'status']);
    final itemCode = BulkItem.apiString(itemJson, ['ItemCode', 'itemCode']);
    final categoryId = _apiInt(itemJson, ['CategoryId', 'categoryId']);
    final categoryName =
        BulkItem.apiString(itemJson, ['CategoryName', 'categoryName']);
    final productId = _apiInt(itemJson, ['ProductId', 'productId']);
    final productName =
        BulkItem.apiString(itemJson, ['ProductName', 'productName']);

    void addSkipped(String reason) {
      if (skippedItemCodes.length < _maxSkipped) {
        skippedItemCodes.add('$itemCode - $reason');
      }
    }

    if (status != 'ApiActive' && status != 'Active') {
      addSkipped('Inactive status: $status');
      return null;
    }
    if (itemCode.isEmpty) {
      addSkipped('ItemCode is null or blank');
      return null;
    }
    if (categoryId == null || categoryName.isEmpty) {
      addSkipped('Category is null');
      return null;
    }
    if (productId == null || productName.isEmpty) {
      addSkipped('Product is null');
      return null;
    }

    final bulkItem = BulkItem.fromApi(itemJson);
    final apiRfid = bulkItem.rfid.trim();
    final apiTid = bulkItem.tid.trim();

    if (apiRfid.isNotEmpty) {
      // -------- Approach 1: RFID present (never clear, never force itemCode hex) --------
      var tid = apiTid;
      var epc = apiTid;
      if (epc.isEmpty) {
        final lookupEpc = rfidByBarcode[apiRfid.toUpperCase()];
        if (lookupEpc != null && lookupEpc.isNotEmpty) {
          epc = lookupEpc;
          tid = lookupEpc;
        } else {
          // Sparkle: epc = tid ?: rfid
          epc = apiRfid;
        }
      }

      if (epc.trim().isEmpty) {
        bulkItem.epc = '';
        bulkItem.tid = tid;
        return bulkItem;
      }

      final epcKey = epc.trim().toUpperCase();
      if (usedEpcSet.contains(epcKey)) {
        // Keep row; blank EPC so UNIQUE does not drop it / break scan keys.
        bulkItem.epc = '';
        bulkItem.tid = tid;
        return bulkItem;
      }
      usedEpcSet.add(epcKey);
      bulkItem.epc = epc;
      bulkItem.tid = tid.isEmpty ? epc : tid;
      return bulkItem;
    }

    // -------- Approach 2: RFID null → itemCode hex (Sparkle convertToHex) --------
    final hex = _convertToHex(itemCode);
    final epcKey = hex.toUpperCase();
    if (usedEpcSet.contains(epcKey)) {
      bulkItem.epc = '';
      bulkItem.tid = '';
      return bulkItem;
    }
    usedEpcSet.add(epcKey);
    bulkItem.epc = hex;
    bulkItem.tid = hex;
    return bulkItem;
  }

  static int? _apiInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key)) {
        final v = int.tryParse(json[key]?.toString() ?? '');
        if (v != null) return v;
      }
    }
    final lower = <String, dynamic>{
      for (final e in json.entries) e.key.toLowerCase(): e.value,
    };
    for (final key in keys) {
      final v = int.tryParse(lower[key.toLowerCase()]?.toString() ?? '');
      if (v != null) return v;
    }
    return null;
  }

  /// Matches Sparkle [BulkViewModel.convertToHex] exactly:
  /// each char → 2-digit hex, then prepend "00" until length % 4 == 0.
  /// Example: `"18001"` → `"003138303031"`.
  static String _convertToHex(String input) {
    final buf = StringBuffer();
    for (final unit in input.trim().codeUnits) {
      buf.write(unit.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    var hex = buf.toString();
    while (hex.length % 4 != 0) {
      hex = '00$hex';
    }
    return hex;
  }
}

/// Streams the Items array from `{ TotalCount, Items: [...] }` without loading
/// the full response into memory.
class _StreamingJsonParser {
  final Future<void> Function(int) onTotalCountFound;
  final Future<void> Function(Map<String, dynamic>) onItemFound;

  _StreamingJsonParser({
    required this.onTotalCountFound,
    required this.onItemFound,
  });

  bool _inItemsArray = false;
  bool _totalCountEmitted = false;
  int _braceCount = 0;
  bool _inString = false;
  bool _escape = false;
  final StringBuffer _currentItem = StringBuffer();
  String _headerBuffer = '';

  Future<void> addChunk(String chunk) async {
    if (!_inItemsArray) {
      _headerBuffer += chunk;
      if (_headerBuffer.length > 65536) {
        _headerBuffer = _headerBuffer.substring(_headerBuffer.length - 32768);
      }

      if (!_totalCountEmitted && _headerBuffer.contains('TotalCount')) {
        final match =
            RegExp(r'"TotalCount"\s*:\s*(\d+)').firstMatch(_headerBuffer);
        if (match != null) {
          final total = int.tryParse(match.group(1) ?? '');
          if (total != null) {
            _totalCountEmitted = true;
            await onTotalCountFound(total);
          }
        }
      }

      // Fast path: avoid RegExp scan on every chunk for large downloads.
      var itemsIndex = _headerBuffer.indexOf('"Items"');
      if (itemsIndex < 0) itemsIndex = _headerBuffer.indexOf('"items"');
      if (itemsIndex >= 0) {
        final bracket = _headerBuffer.indexOf('[', itemsIndex);
        if (bracket >= 0) {
          _inItemsArray = true;
          final remainingChunk = _headerBuffer.substring(bracket + 1);
          _headerBuffer = '';
          await _processItemsContent(remainingChunk);
        }
      }
    } else {
      await _processItemsContent(chunk);
    }
  }

  Future<void> _processItemsContent(String chunk) async {
    for (int i = 0; i < chunk.length; i++) {
      final code = chunk.codeUnitAt(i);

      if (_braceCount >= 1) {
        _currentItem.writeCharCode(code);
      }

      if (_escape) {
        _escape = false;
        continue;
      }

      if (code == 92) {
        _escape = true;
        continue;
      }

      if (code == 34) {
        _inString = !_inString;
        continue;
      }

      if (!_inString) {
        if (code == 123) {
          if (_braceCount == 0) {
            _currentItem.clear();
            _currentItem.writeCharCode(code);
          }
          _braceCount++;
        } else if (code == 125) {
          _braceCount--;
          if (_braceCount == 0) {
            final itemStr = _currentItem.toString();
            try {
              final jsonMap = jsonDecode(itemStr);
              if (jsonMap is Map<String, dynamic>) {
                await onItemFound(jsonMap);
              } else if (jsonMap is Map) {
                await onItemFound(Map<String, dynamic>.from(jsonMap));
              }
            } catch (_) {}
            _currentItem.clear();
          }
        } else if (code == 93 && _braceCount == 0) {
          _inItemsArray = false;
        }
      }
    }
  }
}
