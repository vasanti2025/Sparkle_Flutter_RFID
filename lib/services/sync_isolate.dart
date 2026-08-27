import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

/// Background isolate entry for large labelled-stock sync (5–8L+ rows).
///
/// Mapping / skip / EPC-uniqueness rules are unchanged vs Sparkle.
/// Speed + crash fixes for ~5 lakh rows:
/// - Stream RFID JSON (no full-body decode)
/// - Recreate bulk_items without UNIQUE during insert, add unique index after
/// - Multi-row INSERT overlapping with parse/download
/// - HashSet EPC tracking, smaller SQLite cache (avoid OOM)
/// - Insert maps directly (no BulkItem per row)
class SyncIsolate {
  static const int _batchSize = 8000;
  static const int _rfidBatchSize = 2000;
  static const int _maxSkipped = 1000;
  static const int _progressIntervalMs = 1000;
  static const int _sqlChunkRows = 120;
  static const int _sqlChunkChars = 350000;

  static const String _createBulkItemsSql = '''
CREATE TABLE IF NOT EXISTS bulk_items (
  id INTEGER PRIMARY KEY,
  bulkItemId INTEGER,
  productName TEXT,
  itemCode TEXT,
  rfid TEXT,
  grossWeight TEXT,
  stoneWeight TEXT,
  diamondWeight TEXT,
  netWeight TEXT,
  category TEXT,
  design TEXT,
  purity TEXT,
  makingPerGram TEXT,
  makingPercent TEXT,
  fixMaking TEXT,
  fixWastage TEXT,
  stoneAmount TEXT,
  diamondAmount TEXT,
  sku TEXT,
  epc TEXT,
  vendor TEXT,
  tid TEXT,
  box TEXT,
  designCode TEXT,
  productCode TEXT,
  imageUrl TEXT,
  totalQty INTEGER,
  pcs INTEGER,
  matchedPcs INTEGER,
  totalGwt REAL,
  matchGwt REAL,
  totalStoneWt REAL,
  matchStoneWt REAL,
  totalNetWt REAL,
  matchNetWt REAL,
  unmatchedQty INTEGER,
  matchedQty INTEGER,
  unmatchedGrossWt REAL,
  mrp REAL,
  counterName TEXT,
  counterId INTEGER,
  boxId INTEGER,
  boxName TEXT,
  branchId INTEGER,
  branchName TEXT,
  packetId INTEGER,
  packetName TEXT,
  scannedStatus TEXT,
  categoryId INTEGER,
  productId INTEGER,
  branchType TEXT,
  designId INTEGER,
  isScanned INTEGER,
  totalWt REAL,
  categoryWt TEXT,
  skuId INTEGER,
  purityId INTEGER,
  status TEXT
)''';

  static const String _createRfidTagsSql = '''
CREATE TABLE IF NOT EXISTS rfid_tags (
  id INTEGER PRIMARY KEY,
  BarcodeNumber TEXT,
  TidValue TEXT,
  ClientCode TEXT,
  CreatedOn TEXT,
  LastUpdated TEXT,
  StatusType INTEGER
)''';

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
    final String tagType = tagTypeRaw.replaceAll(RegExp(r'[\s_-]+'), '');
    final bool isWebReusable =
        tagType == 'webreusable' || tagType.contains('reusable');
    final bool allowSingleAndWebReusable =
        params['allowSingleAndWebReusable'] as bool? ?? true;
    final usedEpcSet = HashSet<String>();

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
        'message': ?message,
      });
    }

    try {
      sendPort.send({'status': 'init', 'message': 'Initializing database...'});
      db = await openDatabase(
        dbPath,
        onConfigure: (database) async {
          await database.rawQuery('PRAGMA journal_mode=WAL;');
          await database.rawQuery('PRAGMA busy_timeout=30000;');
        },
      );

      await _configureBulkInsertPragmas(db);

      httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 120);
      httpClient.idleTimeout = const Duration(minutes: 20);
      httpClient.autoUncompress = true;
      httpClient.maxConnectionsPerHost = 8;

      // Start labelled-stock POST while RFID downloads so the server can
      // generate the big payload in parallel (socket backpressure avoids OOM).
      final stockResponseFuture = _postStockSearch(
        httpClient: httpClient,
        baseUrl: baseUrl,
        clientCode: clientCode,
        roleId: roleId,
        branchIds: branchIds,
        token: token,
      );

      sendPort.send({'status': 'rfid', 'message': 'Syncing RFID tags...'});
      final rfidByBarcode = await _syncRfidTagsFromServer(
        httpClient: httpClient,
        baseUrl: baseUrl,
        clientCode: clientCode,
        token: token,
        db: db,
      );

      sendPort.send({'status': 'rfid', 'message': 'Loading RFID lookup...'});
      sendPort.send({'status': 'init', 'message': 'Preparing database...'});
      await _resetBulkItemsTable(db);

      sendPort.send({
        'status': 'downloading',
        'message': 'Connecting to stock API...',
      });

      final stockResponse = await stockResponseFuture;
      if (stockResponse.statusCode != 200) {
        throw Exception('Stock API returned status: ${stockResponse.statusCode}');
      }

      int totalCount = 0;
      int processedCount = 0;
      int syncedCount = 0;
      var fillQueue = <List<Object?>>[];
      final List<String> skippedItemCodes = [];
      int lastProgressMs = 0;
      Future<void>? inflightInsert;
      final jsonView = _JsonView();

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

      Future<void> kickInsert({bool force = false}) async {
        if (fillQueue.isEmpty) return;
        if (!force && fillQueue.length < _batchSize) return;
        if (inflightInsert != null) {
          await inflightInsert;
          inflightInsert = null;
        }
        final toInsert = fillQueue;
        fillQueue = <List<Object?>>[];
        inflightInsert = _insertBulkBatch(db!, toInsert);
        maybeSendProgress();
      }

      final parser = _StreamingJsonParser(
        onTotalCountFound: (total) {
          totalCount = total;
          maybeSendProgress(force: true);
        },
        onItemFound: (itemJson) {
          processedCount++;
          try {
            jsonView.reset(itemJson);
            final mapped = _mapServerItemToRow(
              view: jsonView,
              rfidByBarcode: rfidByBarcode,
              isWebReusable: isWebReusable,
              allowSingleAndWebReusable: allowSingleAndWebReusable,
              usedEpcSet: usedEpcSet,
              skippedItemCodes: skippedItemCodes,
            );
            if (mapped != null) {
              fillQueue.add(mapped);
              syncedCount++;
            }
          } catch (_) {
            final code = _apiString(itemJson, const ['ItemCode', 'itemCode']);
            if (skippedItemCodes.length < _maxSkipped) {
              skippedItemCodes.add('$code - Mapping failed');
            }
          }
        },
        shouldFlush: () => fillQueue.length >= _batchSize,
        flush: kickInsert,
      );

      await for (final chunk in stockResponse.transform(utf8.decoder)) {
        await parser.addChunk(chunk);
      }

      await kickInsert(force: true);
      if (inflightInsert != null) {
        await inflightInsert;
      }

      sendPort.send({
        'status': 'init',
        'message': 'Building indexes...',
      });
      await _createBulkSecondaryIndexes(db);
      await db.execute(_createRfidTagsSql);
      await _createRfidIndexes(db);
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
          await db.execute(_createBulkItemsSql);
          await _createBulkSecondaryIndexes(db);
          await db.execute(_createRfidTagsSql);
          await _createRfidIndexes(db);
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
    // 64MB cache — 200MB was a crash source on 5L rows + RFID maps.
    await db.rawQuery('PRAGMA cache_size = -65536');
    await db.rawQuery('PRAGMA locking_mode = EXCLUSIVE');
    try {
      await db.rawQuery('PRAGMA journal_mode = OFF');
    } catch (_) {}
    try {
      await db.rawQuery('PRAGMA mmap_size = 67108864');
    } catch (_) {}
  }

  static Future<void> _restoreDbPragmas(Database db) async {
    try {
      await db.rawQuery('PRAGMA journal_mode = WAL');
    } catch (_) {}
    await db.rawQuery('PRAGMA synchronous = NORMAL');
    try {
      await db.rawQuery('PRAGMA locking_mode = NORMAL');
    } catch (_) {}
  }

  static Future<HttpClientResponse> _postStockSearch({
    required HttpClient httpClient,
    required String baseUrl,
    required String clientCode,
    required int roleId,
    required List<int> branchIds,
    required String token,
  }) async {
    final stockUrl = Uri.parse(
      '${baseUrl}api/ProductMaster/branch-labelled-stocks/search',
    );
    final stockRequest = await httpClient.postUrl(stockUrl);
    stockRequest.headers.contentType = ContentType.json;
    if (token.isNotEmpty) {
      stockRequest.headers.set('Authorization', 'Bearer $token');
    }
    stockRequest.write(
      jsonEncode({
        'ClientCode': clientCode,
        'RoleId': roleId,
        'ReturnAll': true,
        if (roleId != 1) 'branchIds': branchIds,
      }),
    );
    return stockRequest.close();
  }

  static Future<void> _resetBulkItemsTable(Database db) async {
    await db.execute('DROP TABLE IF EXISTS bulk_items');
    await db.execute(_createBulkItemsSql);
  }

  static Future<void> _resetRfidTagsTable(Database db) async {
    await db.execute('DROP TABLE IF EXISTS rfid_tags');
    await db.execute(_createRfidTagsSql);
  }

  static Future<void> _createBulkSecondaryIndexes(Database db) async {
    const stmts = [
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_bulk_items_epc ON bulk_items(epc)',
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
    for (var i = 0; i < stmts.length; i++) {
      try {
        await db.execute(stmts[i]);
      } catch (_) {
        if (i == 0) {
          try {
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_bulk_items_epc ON bulk_items(epc)',
            );
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> _createRfidIndexes(Database db) async {
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_rfid_tags_barcode ON rfid_tags(BarcodeNumber)',
      );
    } catch (_) {
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_rfid_tags_barcode ON rfid_tags(BarcodeNumber)',
        );
      } catch (_) {}
    }
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_rfid_tags_tid ON rfid_tags(TidValue)',
      );
    } catch (_) {}
  }

  static String _sqlLiteral(Object? v) {
    if (v == null) return 'NULL';
    if (v is int) return v.toString();
    if (v is double) {
      if (v.isNaN || v.isInfinite) return '0';
      return v.toString();
    }
    return "'${v.toString().replaceAll("'", "''")}'";
  }

  /// Multi-row INSERT via SQL literals: stays under Android Binder ~1MB limit
  /// (sqflite batch of thousands of maps can crash) and avoids SQLITE 999-bind cap.
  static Future<void> _insertBulkBatch(
    Database db,
    List<List<Object?>> items,
  ) async {
    if (items.isEmpty) return;
    const prefix =
        'INSERT INTO bulk_items (bulkItemId,productName,itemCode,rfid,grossWeight,stoneWeight,diamondWeight,netWeight,category,design,purity,makingPerGram,makingPercent,fixMaking,fixWastage,stoneAmount,diamondAmount,sku,epc,vendor,tid,box,designCode,productCode,imageUrl,totalQty,pcs,matchedPcs,totalGwt,matchGwt,totalStoneWt,matchStoneWt,totalNetWt,matchNetWt,unmatchedQty,matchedQty,unmatchedGrossWt,mrp,counterName,counterId,boxId,boxName,branchId,branchName,packetId,packetName,scannedStatus,categoryId,productId,branchType,designId,isScanned,totalWt,categoryWt,skuId,purityId,status) VALUES ';
    await db.transaction((txn) async {
      final buf = StringBuffer();
      var rowsInStmt = 0;

      Future<void> flush() async {
        if (rowsInStmt == 0) return;
        await txn.execute(buf.toString());
        buf.clear();
        rowsInStmt = 0;
      }

      for (final row in items) {
        if (rowsInStmt == 0) {
          buf.write(prefix);
        } else {
          buf.write(',');
        }
        buf.write('(');
        for (var c = 0; c < row.length; c++) {
          if (c > 0) buf.write(',');
          buf.write(_sqlLiteral(row[c]));
        }
        buf.write(')');
        rowsInStmt++;
        if (rowsInStmt >= _sqlChunkRows || buf.length >= _sqlChunkChars) {
          await flush();
        }
      }
      await flush();
    });
  }

  static Future<void> _insertRfidBatch(
    Database db,
    List<List<Object?>> rows,
  ) async {
    if (rows.isEmpty) return;
    const prefix =
        'INSERT INTO rfid_tags (BarcodeNumber,TidValue,ClientCode,CreatedOn,LastUpdated,StatusType) VALUES ';
    await db.transaction((txn) async {
      final buf = StringBuffer();
      var rowsInStmt = 0;

      Future<void> flush() async {
        if (rowsInStmt == 0) return;
        await txn.execute(buf.toString());
        buf.clear();
        rowsInStmt = 0;
      }

      for (final row in rows) {
        if (rowsInStmt == 0) {
          buf.write(prefix);
        } else {
          buf.write(',');
        }
        buf.write('(');
        for (var c = 0; c < row.length; c++) {
          if (c > 0) buf.write(',');
          buf.write(_sqlLiteral(row[c]));
        }
        buf.write(')');
        rowsInStmt++;
        if (rowsInStmt >= _sqlChunkRows || buf.length >= _sqlChunkChars) {
          await flush();
        }
      }
      await flush();
    });
  }

  /// Streams GetAllRFID, builds barcode→TID map, persists tags. Best-effort.
  static Future<Map<String, String>> _syncRfidTagsFromServer({
    required HttpClient httpClient,
    required String baseUrl,
    required String clientCode,
    required String token,
    required Database db,
  }) async {
    final map = HashMap<String, String>();
    if (clientCode.trim().isEmpty) return map;

    try {
      final url = Uri.parse('${baseUrl}api/ProductMaster/GetAllRFID');
      final request = await httpClient.postUrl(url);
      request.headers.contentType = ContentType.json;
      if (token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      request.write(jsonEncode({'ClientCode': clientCode}));
      final response = await request.close();
      if (response.statusCode != 200) return map;

      var tableReady = false;
      var fill = <List<Object?>>[];
      Future<void>? inflight;
      final view = _JsonView();

      Future<void> kick({bool force = false}) async {
        if (fill.isEmpty) return;
        if (!force && fill.length < _rfidBatchSize) return;
        if (inflight != null) {
          await inflight;
          inflight = null;
        }
        final toInsert = fill;
        fill = <List<Object?>>[];
        inflight = _insertRfidBatch(db, toInsert);
      }

      final parser = _StreamingJsonParser(
        topLevelArray: true,
        onArrayStarted: () async {
          if (!tableReady) {
            await _resetRfidTagsTable(db);
            tableReady = true;
          }
        },
        onItemFound: (raw) {
          view.reset(raw);
          final barcode = view.str(const [
            'BarcodeNumber',
            'barcodeNumber',
            'RFIDCode',
          ]);
          if (barcode.isEmpty) return;
          final tid = view.str(const [
            'TidValue',
            'TIDNumber',
            'TidNumber',
            'EPC',
          ]);
          map[barcode.toUpperCase()] = tid.toUpperCase();
          fill.add([
            barcode,
            tid,
            view.str(const ['ClientCode']),
            view.str(const ['CreatedOn']),
            view.str(const ['LastUpdated']),
            (raw['StatusType'] == true || raw['StatusType'] == 1) ? 1 : 0,
          ]);
        },
        shouldFlush: () => fill.length >= _rfidBatchSize,
        flush: kick,
      );

      await for (final chunk in response.transform(utf8.decoder)) {
        if (parser.rejectedNonArray) break;
        await parser.addChunk(chunk);
      }

      if (!tableReady) return map;

      await kick(force: true);
      if (inflight != null) await inflight;
      // Indexes created after labelled-stock insert so RFID unique-index
      // build does not block the main 5L stock download.
    } catch (_) {
      try {
        await db.execute(_createRfidTagsSql);
      } catch (_) {}
    }
    return map;
  }

  /// Per-item dual mapping (unchanged rules):
  /// 1) API RFIDCode present → keep RFID, EPC from TIDNumber or rfid lookup
  /// 2) API RFIDCode null → EPC/TID = convertToHex(itemCode), RFID blank
  static List<Object?>? _mapServerItemToRow({
    required _JsonView view,
    required Map<String, String> rfidByBarcode,
    required bool isWebReusable,
    required bool allowSingleAndWebReusable,
    required Set<String> usedEpcSet,
    required List<String> skippedItemCodes,
  }) {
    // Tag-type flags kept for isolate API; mapping is per-item so both flows
    // work in the same sync (RFID present vs RFID null→hex).
    // ignore: unnecessary_statements
    (isWebReusable, allowSingleAndWebReusable);

    final status = view.str(const ['Status', 'status']);
    final itemCode = view.str(const ['ItemCode', 'itemCode']);
    final categoryId = view.asInt(const ['CategoryId', 'categoryId']);
    final categoryName = view.str(const ['CategoryName', 'categoryName']);
    final productId = view.asInt(const ['ProductId', 'productId']);
    final productName = view.str(const ['ProductName', 'productName']);

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

    final apiRfid = view.str(const [
      'RFIDCode',
      'RfidCode',
      'rfidCode',
      'RFID',
      'rfid',
      'RfidBarcode',
      'rfidBarcode',
    ]).trim();
    final apiTid = view.str(const [
      'TIDNumber',
      'TidNumber',
      'tidNumber',
      'TidValue',
      'tidValue',
      'TID',
      'tid',
      'EPC',
      'Epc',
      'epc',
      'EpcValue',
      'epcValue',
    ]).trim();

    late final String epcOut;
    late final String tidOut;

    if (apiRfid.isNotEmpty) {
      var tid = apiTid;
      var epc = apiTid;
      if (epc.isEmpty) {
        final lookupEpc = rfidByBarcode[apiRfid.toUpperCase()];
        if (lookupEpc != null && lookupEpc.isNotEmpty) {
          epc = lookupEpc;
          tid = lookupEpc;
        } else {
          epc = apiRfid;
        }
      }

      if (epc.trim().isEmpty) {
        epcOut = '';
        tidOut = tid;
      } else {
        final epcKey = epc.trim().toUpperCase();
        if (usedEpcSet.contains(epcKey)) {
          epcOut = '';
          tidOut = tid;
        } else {
          usedEpcSet.add(epcKey);
          epcOut = epc;
          tidOut = tid.isEmpty ? epc : tid;
        }
      }
    } else {
      final hex = _convertToHex(itemCode);
      final epcKey = hex.toUpperCase();
      if (usedEpcSet.contains(epcKey)) {
        epcOut = '';
        tidOut = '';
      } else {
        usedEpcSet.add(epcKey);
        epcOut = hex;
        tidOut = hex;
      }
    }

    final epcTrim = epcOut.trim();
    final tidTrim = tidOut.trim();

    return [
      view.rawInt('Id', 'id'),
      productName,
      itemCode,
      apiRfid,
      view.str(const ['GrossWt', 'grossWt']),
      view.str(const ['TotalStoneWeight', 'totalStoneWeight']),
      view.str(const ['TotalDiamondWeight', 'totalDiamondWeight']),
      view.str(const ['NetWt', 'netWt']),
      categoryName,
      view.str(const ['DesignName', 'designName']),
      view.str(const ['PurityName', 'purityName']),
      view.str(const ['MakingPerGram', 'makingPerGram']),
      view.str(const ['MakingPercentage', 'makingPercentage']),
      view.str(const ['MakingFixedAmt', 'makingFixedAmt']),
      view.str(const ['MakingFixedWastage', 'makingFixedWastage']),
      view.str(const ['TotalStoneAmount', 'totalStoneAmount']),
      view.str(const ['TotalDiamondAmount', 'totalDiamondAmount']),
      view.str(const ['SKU', 'sku']),
      epcTrim.isEmpty ? null : epcTrim,
      view.str(const ['VendorName', 'vendorName']),
      tidTrim.isEmpty ? null : tidTrim,
      '',
      '',
      view.str(const ['ProductCode', 'productCode']),
      view.str(const ['Images', 'image', 'Image', 'images']),
      view.rawInt('Quantity'),
      view.rawInt('Pieces'),
      0,
      0.0,
      0.0,
      view.rawDouble('TotalStoneWeight'),
      0.0,
      view.rawDouble('NetWt'),
      0.0,
      0,
      0,
      0.0,
      view.rawDouble('MRP'),
      view.str(const ['CounterName', 'counterName']),
      view.rawInt('CounterId'),
      view.rawInt('BoxId'),
      view.str(const ['BoxName', 'boxName']),
      view.rawInt('BranchId'),
      view.str(const ['BranchName', 'branchName']),
      view.rawInt('PacketId'),
      view.str(const ['PacketName', 'packetName']),
      '',
      view.rawInt('CategoryId'),
      view.rawInt('ProductId'),
      view.str(const ['BranchType', 'branchType']),
      view.rawInt('DesignId'),
      0,
      view.rawDouble('TotalWeight'),
      view.str(const ['WeightCategory', 'weightCategory']),
      view.rawInt('SKUId'),
      view.rawInt('PurityId'),
      status,
    ];
  }

  static String _apiString(Map<String, dynamic> json, List<String> keys) {
    final view = _JsonView()..reset(json);
    return view.str(keys);
  }

  static final List<String> _hexByte = List<String>.generate(
    256,
    (i) => i.toRadixString(16).padLeft(2, '0').toUpperCase(),
  );

  /// Matches Sparkle [BulkViewModel.convertToHex] exactly:
  /// each char → 2-digit hex, then prepend "00" until length % 4 == 0.
  static String _convertToHex(String input) {
    final buf = StringBuffer();
    for (final unit in input.trim().codeUnits) {
      if (unit <= 255) {
        buf.write(_hexByte[unit]);
      } else {
        buf.write(unit.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
    }
    var hex = buf.toString();
    while (hex.length % 4 != 0) {
      hex = '00$hex';
    }
    return hex;
  }
}

/// Case-insensitive API reader; builds the lower-key map at most once per item.
class _JsonView {
  _JsonView();
  Map<String, dynamic> raw = const {};
  Map<String, dynamic>? _lower;

  void reset(Map<String, dynamic> json) {
    raw = json;
    _lower = null;
  }

  Map<String, dynamic> get lower => _lower ??= {
        for (final e in raw.entries) e.key.toLowerCase(): e.value,
      };

  static String? _pick(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return null;
      return s;
    }
    final s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  String str(List<String> keys) {
    for (final key in keys) {
      final s = _pick(raw[key]);
      if (s != null) return s;
    }
    for (final key in keys) {
      final s = _pick(lower[key.toLowerCase()]);
      if (s != null) return s;
    }
    return '';
  }

  int? asInt(List<String> keys) {
    for (final key in keys) {
      final rawVal = raw[key];
      if (rawVal == null) continue;
      if (rawVal is int) return rawVal;
      final v = int.tryParse(rawVal.toString());
      if (v != null) return v;
    }
    for (final key in keys) {
      final v = int.tryParse(lower[key.toLowerCase()]?.toString() ?? '');
      if (v != null) return v;
    }
    return null;
  }

  int rawInt(String key, [String? key2]) {
    final v = raw[key] ?? (key2 != null ? raw[key2] : null);
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double rawDouble(String key) {
    final v = raw[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}

/// Streams JSON objects from `{ TotalCount, Items: [...] }` or a top-level
/// array without loading the full response into memory.
class _StreamingJsonParser {
  final void Function(int)? onTotalCountFound;
  final void Function(Map<String, dynamic>) onItemFound;
  final Future<void> Function()? onArrayStarted;
  final bool Function()? shouldFlush;
  final Future<void> Function()? flush;
  final bool topLevelArray;

  _StreamingJsonParser({
    required this.onItemFound,
    this.onTotalCountFound,
    this.onArrayStarted,
    this.shouldFlush,
    this.flush,
    this.topLevelArray = false,
  });

  bool _inItemsArray = false;
  bool _totalCountEmitted = false;
  bool _arrayStartedNotified = false;
  bool rejectedNonArray = false;
  int _braceCount = 0;
  bool _inString = false;
  bool _escape = false;
  final StringBuffer _carry = StringBuffer();
  final StringBuffer _headerBuffer = StringBuffer();

  Future<void> addChunk(String chunk) async {
    if (rejectedNonArray) return;

    if (!_inItemsArray) {
      if (topLevelArray) {
        await _enterTopLevelArray(chunk);
        return;
      }

      _headerBuffer.write(chunk);
      var header = _headerBuffer.toString();
      if (header.length > 65536) {
        header = header.substring(header.length - 32768);
        _headerBuffer
          ..clear()
          ..write(header);
      }

      if (!_totalCountEmitted && header.contains('TotalCount')) {
        final match = RegExp(r'"TotalCount"\s*:\s*(\d+)').firstMatch(header);
        if (match != null) {
          final total = int.tryParse(match.group(1) ?? '');
          if (total != null) {
            _totalCountEmitted = true;
            onTotalCountFound?.call(total);
          }
        }
      }

      var itemsIndex = header.indexOf('"Items"');
      if (itemsIndex < 0) itemsIndex = header.indexOf('"items"');
      if (itemsIndex >= 0) {
        final bracket = header.indexOf('[', itemsIndex);
        if (bracket >= 0) {
          _inItemsArray = true;
          final remainingChunk = header.substring(bracket + 1);
          _headerBuffer.clear();
          await _notifyArrayStarted();
          await _processItemsContent(remainingChunk);
        }
      }
    } else {
      await _processItemsContent(chunk);
    }
  }

  Future<void> _enterTopLevelArray(String chunk) async {
    for (var i = 0; i < chunk.length; i++) {
      final code = chunk.codeUnitAt(i);
      if (code == 32 || code == 9 || code == 10 || code == 13) continue;
      if (code == 91) {
        _inItemsArray = true;
        await _notifyArrayStarted();
        await _processItemsContent(chunk.substring(i + 1));
        return;
      }
      rejectedNonArray = true;
      return;
    }
  }

  Future<void> _notifyArrayStarted() async {
    if (_arrayStartedNotified) return;
    _arrayStartedNotified = true;
    await onArrayStarted?.call();
  }

  Future<void> _processItemsContent(String chunk) async {
    final n = chunk.length;
    var copyStart = _braceCount >= 1 ? 0 : -1;

    for (var i = 0; i < n; i++) {
      final code = chunk.codeUnitAt(i);

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

      if (_inString) continue;

      if (code == 123) {
        if (_braceCount == 0) {
          copyStart = i;
          _carry.clear();
        }
        _braceCount++;
      } else if (code == 125) {
        if (_braceCount <= 0) continue;
        _braceCount--;
        if (_braceCount == 0 && copyStart >= 0) {
          final slice = chunk.substring(copyStart, i + 1);
          final itemStr =
              _carry.isEmpty ? slice : '${_carry.toString()}$slice';
          _carry.clear();
          copyStart = -1;
          await _emitItem(itemStr);
        }
      } else if (code == 93 && _braceCount == 0) {
        _inItemsArray = false;
        return;
      }
    }

    if (_braceCount >= 1 && copyStart >= 0) {
      _carry.write(chunk.substring(copyStart));
    }
  }

  Future<void> _emitItem(String itemStr) async {
    try {
      final jsonMap = jsonDecode(itemStr);
      if (jsonMap is Map<String, dynamic>) {
        onItemFound(jsonMap);
      } else if (jsonMap is Map) {
        onItemFound(Map<String, dynamic>.from(jsonMap));
      } else {
        return;
      }
      if (shouldFlush?.call() == true) {
        await flush?.call();
      }
    } catch (_) {}
  }
}
