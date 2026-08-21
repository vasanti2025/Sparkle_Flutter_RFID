import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../models/bulk_item.dart';

/// Background isolate entry for large labelled-stock sync (10L+ rows).
/// Mirrors Kotlin [BulkRepositoryImpl.syncBulkItemsFromServer]:
/// stream JSON, map items, batch-insert into SQLite — no full in-memory load.
class SyncIsolate {
  static const int _batchSize = 500;
  static const int _maxSkipped = 1000;
  static const int _progressIntervalMs = 700;
  static const int _rfidCacheMax = 50000;

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
    final rfidLookup = _RfidLookupCache(maxEntries: _rfidCacheMax);

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
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode=WAL;');
        },
      );

      await _configureBulkInsertPragmas(db);

      httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 60);
      httpClient.idleTimeout = const Duration(minutes: 10);

      // Sparkle login syncs GetAllRFID first so Barcode↔TID lookup works during mapping.
      sendPort.send({'status': 'rfid', 'message': 'Syncing RFID tags...'});
      await _syncRfidTagsFromServer(
        httpClient: httpClient,
        baseUrl: baseUrl,
        clientCode: clientCode,
        token: token,
        db: db,
      );

      // Kotlin clears only bulk_items before streaming stock data.
      sendPort.send({'status': 'init', 'message': 'Clearing old stock data...'});
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
            final mapped = await _mapServerItem(
              db: db!,
              rfidLookup: rfidLookup,
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
    await db.rawQuery('PRAGMA cache_size = -64000');
  }

  static Future<void> _restoreDbPragmas(Database db) async {
    await db.rawQuery('PRAGMA synchronous = NORMAL');
  }

  static Future<void> _insertBulkBatch(Database db, List<BulkItem> items) async {
    if (items.isEmpty) return;
    final batch = db.batch();
    for (final item in items) {
      // NEVER use REPLACE here — UNIQUE(epc) + REPLACE deletes the other row
      // (wipes RFID items when hex EPCs collide, and vice versa) on 10k syncs.
      batch.insert(
        'bulk_items',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
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

      final batch = <Map<String, dynamic>>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final barcode = BulkItem.apiString(map, ['BarcodeNumber', 'barcodeNumber', 'RFIDCode']);
        final tid = BulkItem.apiString(map, ['TidValue', 'TIDNumber', 'TidNumber', 'EPC']);
        if (barcode.isEmpty) continue;
        batch.add({
          'BarcodeNumber': barcode,
          'TidValue': tid,
          'ClientCode': BulkItem.apiString(map, ['ClientCode']),
          'CreatedOn': BulkItem.apiString(map, ['CreatedOn']),
          'LastUpdated': BulkItem.apiString(map, ['LastUpdated']),
          'StatusType': (map['StatusType'] == true || map['StatusType'] == 1) ? 1 : 0,
        });
        if (batch.length >= 500) {
          final b = db.batch();
          for (final row in batch) {
            b.insert('rfid_tags', row, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await b.commit(noResult: true);
          batch.clear();
        }
      }
      if (batch.isNotEmpty) {
        final b = db.batch();
        for (final row in batch) {
          b.insert('rfid_tags', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await b.commit(noResult: true);
      }
    } catch (_) {
      // RFID sheet sync is best-effort; stock sync must continue.
    }
  }

  /// Per-item dual mapping for mixed ~10k stock (both flows in one sync):
  /// 1) API RFIDCode present → keep RFID, EPC from TIDNumber or rfid_tags lookup
  /// 2) API RFIDCode null    → EPC/TID = convertToHex(itemCode), RFID blank
  /// Global tagType must NOT wipe RFID when the API sent RFIDCode.
  static Future<BulkItem?> _mapServerItem({
    required Database db,
    required _RfidLookupCache rfidLookup,
    required Map<String, dynamic> itemJson,
    required bool isWebReusable,
    required bool allowSingleAndWebReusable,
    required Set<String> usedEpcSet,
    required List<String> skippedItemCodes,
  }) async {
    // Tag-type flags kept for isolate API; mapping is per-item so both flows
    // work in the same ~10k sync (RFID present vs RFID null→hex).
    // ignore: unnecessary_statements
    (isWebReusable, allowSingleAndWebReusable);

    final status = BulkItem.apiString(itemJson, ['Status', 'status']);
    final itemCode = BulkItem.apiString(itemJson, ['ItemCode', 'itemCode']);
    final categoryId = _apiInt(itemJson, ['CategoryId', 'categoryId']);
    final categoryName = BulkItem.apiString(itemJson, ['CategoryName', 'categoryName']);
    final productId = _apiInt(itemJson, ['ProductId', 'productId']);
    final productName = BulkItem.apiString(itemJson, ['ProductName', 'productName']);

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

    String rfid;
    String epc;
    String tid;

    if (apiRfid.isNotEmpty) {
      // -------- Approach 1: RFID present (never clear, never force itemCode hex) --------
      rfid = apiRfid;
      tid = apiTid;
      epc = apiTid;
      if (epc.isEmpty) {
        final lookupEpc = await rfidLookup.lookup(db, apiRfid);
        if (lookupEpc != null && lookupEpc.isNotEmpty) {
          epc = lookupEpc;
          tid = lookupEpc;
        }
      }
    } else {
      // -------- Approach 2: RFID null → itemCode hex (Sparkle convertToHex) --------
      rfid = '';
      epc = _convertToHex(itemCode);
      tid = epc;
    }

    // RFID row with no EPC yet: store empty (NULL in DB — multiple NULLs OK).
    // Do NOT invent itemCode hex here (that breaks Approach 1).
    if (epc.trim().isEmpty) {
      return _withEpcTidRfid(bulkItem, rfid: rfid, epc: '', tid: tid);
    }

    // UNIQUE(epc): uniquify collisions instead of REPLACE/skip (keeps all ~10k rows).
    epc = _uniqueEpc(epc, bulkItem.bulkItemId, itemCode, usedEpcSet);
    if (tid.isEmpty) tid = epc;

    return _withEpcTidRfid(bulkItem, rfid: rfid, epc: epc, tid: tid);
  }

  /// Ensure epc is unique in this sync so SQLite UNIQUE + IGNORE does not drop rows.
  static String _uniqueEpc(
    String epc,
    int bulkItemId,
    String itemCode,
    Set<String> usedEpcSet,
  ) {
    var value = epc.trim();
    var key = value.toUpperCase();
    if (!usedEpcSet.contains(key)) {
      usedEpcSet.add(key);
      return value;
    }
    final suffix = bulkItemId != 0 ? bulkItemId : usedEpcSet.length + 1;
    value = '$value#$suffix';
    usedEpcSet.add(value.toUpperCase());
    return value;
  }

  static BulkItem _withEpcTidRfid(
    BulkItem item, {
    required String rfid,
    required String epc,
    required String tid,
  }) {
    return BulkItem(
      id: item.id,
      bulkItemId: item.bulkItemId,
      productName: item.productName,
      itemCode: item.itemCode,
      rfid: rfid,
      grossWeight: item.grossWeight,
      stoneWeight: item.stoneWeight,
      diamondWeight: item.diamondWeight,
      netWeight: item.netWeight,
      category: item.category,
      design: item.design,
      purity: item.purity,
      makingPerGram: item.makingPerGram,
      makingPercent: item.makingPercent,
      fixMaking: item.fixMaking,
      fixWastage: item.fixWastage,
      stoneAmount: item.stoneAmount,
      diamondAmount: item.diamondAmount,
      sku: item.sku,
      epc: epc,
      vendor: item.vendor,
      tid: tid,
      box: item.box,
      designCode: item.designCode,
      productCode: item.productCode,
      imageUrl: item.imageUrl,
      totalQty: item.totalQty,
      pcs: item.pcs,
      matchedPcs: item.matchedPcs,
      totalGwt: item.totalGwt,
      matchGwt: item.matchGwt,
      totalStoneWt: item.totalStoneWt,
      matchStoneWt: item.matchStoneWt,
      totalNetWt: item.totalNetWt,
      matchNetWt: item.matchNetWt,
      unmatchedQty: item.unmatchedQty,
      matchedQty: item.matchedQty,
      unmatchedGrossWt: item.unmatchedGrossWt,
      mrp: item.mrp,
      counterName: item.counterName,
      counterId: item.counterId,
      boxId: item.boxId,
      boxName: item.boxName,
      branchId: item.branchId,
      branchName: item.branchName,
      packetId: item.packetId,
      packetName: item.packetName,
      scannedStatus: item.scannedStatus,
      categoryId: item.categoryId,
      productId: item.productId,
      branchType: item.branchType,
      designId: item.designId,
      isScanned: item.isScanned,
      totalWt: item.totalWt,
      categoryWt: item.categoryWt,
      skuId: item.skuId,
      purityId: item.purityId,
      status: item.status,
    );
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

/// LRU cache for RFID barcode <-> TID lookups (avoids loading all RFID into RAM).
class _RfidLookupCache {
  _RfidLookupCache({required int maxEntries}) : _maxEntries = maxEntries;

  final int _maxEntries;
  final Map<String, String> _barcodeToTid = {};
  final Map<String, String> _tidToBarcode = {};

  Future<String?> lookup(Database db, String rfid) async {
    final key = rfid.trim().toUpperCase();
    if (key.isEmpty) return null;

    final cached = _barcodeToTid[key];
    if (cached != null) return cached.isEmpty ? null : cached;

    final rows = await db.query(
      'rfid_tags',
      columns: ['TidValue'],
      where: 'UPPER(TRIM(BarcodeNumber)) = ?',
      whereArgs: [key],
      limit: 1,
    );
    final tid = rows.isEmpty
        ? ''
        : (rows.first['TidValue'] as String? ?? '').trim().toUpperCase();

    _put(_barcodeToTid, key, tid);
    if (tid.isNotEmpty) _put(_tidToBarcode, tid, key);
    return tid.isEmpty ? null : tid;
  }

  /// Sparkle BulkItemDao.getItemCodeByEpc — TidValue → BarcodeNumber.
  Future<String?> lookupBarcodeByTid(Database db, String tid) async {
    final key = tid.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (key.isEmpty) return null;

    final cached = _tidToBarcode[key];
    if (cached != null) return cached.isEmpty ? null : cached;

    final rows = await db.query(
      'rfid_tags',
      columns: ['BarcodeNumber'],
      where: 'UPPER(TRIM(TidValue)) = ?',
      whereArgs: [tid.trim().toUpperCase()],
      limit: 1,
    );
    final barcode = rows.isEmpty
        ? ''
        : (rows.first['BarcodeNumber'] as String? ?? '').trim();

    _put(_tidToBarcode, key, barcode);
    if (barcode.isNotEmpty) {
      _put(_barcodeToTid, barcode.toUpperCase(), key);
    }
    return barcode.isEmpty ? null : barcode;
  }

  void _put(Map<String, String> map, String key, String value) {
    if (map.length >= _maxEntries) {
      map.remove(map.keys.first);
    }
    map[key] = value;
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

      final itemsIndex = _headerBuffer.indexOf(RegExp(r'"(Items|items)"\s*:\s*\['));
      if (itemsIndex != -1) {
        _inItemsArray = true;
        final startIndex = _headerBuffer.indexOf('[', itemsIndex) + 1;
        final remainingChunk = _headerBuffer.substring(startIndex);
        _headerBuffer = '';
        await _processItemsContent(remainingChunk);
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
