import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/bulk_item.dart';
import '../models/epc_dto.dart';
import '../models/location_item.dart';

class DbService {
  static Database? _database;
  List<BulkItem>? _bulkItemsCache;
  Map<String, BulkItem>? _scanKeyIndex;
  Map<String, String>? _tidToRfidCache;
  Map<String, List<String>>? _distinctValuesCache;

  void invalidateBulkCache() {
    _bulkItemsCache = null;
    _scanKeyIndex = null;
    _tidToRfidCache = null;
    _distinctValuesCache = null;
  }

  String _normalizeScanKey(String raw) => raw.trim().toUpperCase().replaceAll(' ', '');

  void _cacheScanItem(String key, BulkItem item) {
    _scanKeyIndex ??= {};
    void put(String raw) {
      final k = _normalizeScanKey(raw);
      if (k.isEmpty) return;
      _scanKeyIndex![k] = item;
    }
    put(key);
    put(item.epc);
    put(item.tid);
    put(item.rfid);
    put(item.itemCode);
    while (_scanKeyIndex!.length > 2000) {
      _scanKeyIndex!.remove(_scanKeyIndex!.keys.first);
    }
  }

  /// Do not load 5L+ rows into RAM. Lookups use indexed SQL (see findBulkItemByScanKey).
  Future<void> warmScanKeyIndex() async {
    await database;
  }

  Future<BulkItem?> findBulkItemByScanKey(String raw) async {
    final key = _normalizeScanKey(raw);
    if (key.isEmpty) return null;
    final cached = findBulkItemByScanKeySync(raw);
    if (cached != null) return cached;
    return _queryBulkItemByScanKeyIndexed(key);
  }

  BulkItem? findBulkItemByScanKeySync(String raw) {
    final key = _normalizeScanKey(raw);
    if (key.isEmpty || _scanKeyIndex == null) return null;
    return _scanKeyIndex![key];
  }

  List<String> scanKeysForNativeMatch({int limit = 8000}) {
    // Never send a partial LRU as a native allow-list — that drops real tags.
    return const [];
  }

  /// Indexed equality on epc/tid/rfid/itemCode. Avoid UPPER() full-table scans on 5L rows.
  Future<BulkItem?> _queryBulkItemByScanKeyIndexed(String key) async {
    final db = await database;
    for (final col in ['epc', 'tid', 'rfid', 'itemCode']) {
      final maps = await db.query(
        'bulk_items',
        where: '$col = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (maps.isEmpty) continue;
      final item = BulkItem.fromMap(maps.first);
      _cacheScanItem(key, item);
      return item;
    }
    return null;
  }

  Future<List<BulkItem>> searchBulkItemsByCodePrefix(String query, {int limit = 25}) async {
    final q = query.trim().toUpperCase();
    if (q.isEmpty) return const [];
    final db = await database;
    final maps = await db.query(
      'bulk_items',
      where: 'UPPER(itemCode) LIKE ? OR UPPER(rfid) LIKE ?',
      whereArgs: ['$q%', '$q%'],
      limit: limit,
    );
    return maps.map((m) => BulkItem.fromMap(m)).toList();
  }

  /// Loads only rows matching issue item codes (Sample In scan scope).
  Future<Map<String, BulkItem>> findBulkItemsByItemCodes(Set<String> codes) async {
    if (codes.isEmpty) return {};
    final normalized = codes.map((c) => c.trim().toUpperCase()).where((c) => c.isNotEmpty).toSet();
    if (normalized.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(normalized.length, '?').join(',');
    final maps = await db.query(
      'bulk_items',
      where: 'UPPER(itemCode) IN ($placeholders)',
      whereArgs: normalized.toList(),
    );
    final result = <String, BulkItem>{};
    for (final map in maps) {
      final item = BulkItem.fromMap(map);
      final code = item.itemCode.trim().toUpperCase();
      if (code.isNotEmpty) result[code] = item;
    }
    return result;
  }

  /// Fast RFID lookup for Scan to Desktop (TidValue → BarcodeNumber).
  Future<String> lookupRfidForTid(String tid) async {
    final key = tid.trim().toUpperCase();
    if (key.isEmpty) return '';
    _tidToRfidCache ??= {};
    if (_tidToRfidCache!.containsKey(key)) return _tidToRfidCache![key]!;

    final db = await database;
    final rfidResults = await db.query(
      'rfid_tags',
      columns: ['BarcodeNumber'],
      where: 'UPPER(TidValue) = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rfidResults.isNotEmpty) {
      final rfid = rfidResults.first['BarcodeNumber']?.toString() ?? '';
      _tidToRfidCache![key] = rfid;
      return rfid;
    }

    final bulkResults = await db.query(
      'bulk_items',
      columns: ['rfid'],
      where: 'UPPER(epc) = ?',
      whereArgs: [key],
      limit: 1,
    );
    final rfid = bulkResults.isNotEmpty ? bulkResults.first['rfid']?.toString() ?? '' : '';
    _tidToRfidCache![key] = rfid;
    return rfid;
  }

  static const List<String> _labelledTransferColumns = [
    'id',
    'bulkItemId',
    'productName',
    'itemCode',
    'rfid',
    'epc',
    'tid',
    'grossWeight',
    'netWeight',
    'category',
    'design',
    'counterName',
    'counterId',
    'branchName',
    'branchId',
    'boxName',
    'boxId',
    'packetName',
    'packetId',
    'categoryId',
    'productId',
    'designId',
  ];

  /// Call after background sync isolate closes its DB connection.
  Future<void> resetConnection() async {
    if (_database != null) {
      try {
        await _database!.close();
      } catch (_) {}
      _database = null;
    }
    invalidateBulkCache();
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'sparkle_rfid.db');

    return await openDatabase(
      path,
      version: 10,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL;');
        await db.rawQuery('PRAGMA cache_size=-2048');
        await db.rawQuery('PRAGMA temp_store=MEMORY');
      },
      onCreate: (db, version) async {
        // Create bulk_items table
        await db.execute('''
          CREATE TABLE bulk_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
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
            epc TEXT UNIQUE,
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
          )
        ''');

        // Create indexes for faster matching and bulk sync
        await db.execute('CREATE INDEX idx_bulk_items_epc ON bulk_items(epc)');
        await db.execute(
          'CREATE INDEX idx_bulk_items_bulkItemId ON bulk_items(bulkItemId)',
        );
        await db.execute('CREATE INDEX idx_bulk_items_counterName ON bulk_items(counterName)');
        await db.execute('CREATE INDEX idx_bulk_items_boxName ON bulk_items(boxName)');
        await db.execute('CREATE INDEX idx_bulk_items_branchName ON bulk_items(branchName)');
        await db.execute('CREATE INDEX idx_bulk_items_category ON bulk_items(category)');
        await db.execute('CREATE INDEX idx_bulk_items_productName ON bulk_items(productName)');
        await db.execute('CREATE INDEX idx_bulk_items_design ON bulk_items(design)');
        await db.execute('CREATE INDEX idx_bulk_items_rfid ON bulk_items(rfid)');
        await db.execute('CREATE INDEX idx_bulk_items_itemCode ON bulk_items(itemCode)');

        // Create rfid_tags table
        await db.execute('''
          CREATE TABLE rfid_tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            BarcodeNumber TEXT UNIQUE,
            TidValue TEXT,
            ClientCode TEXT,
            CreatedOn TEXT,
            LastUpdated TEXT,
            StatusType INTEGER
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_rfid_tags_barcode ON rfid_tags(BarcodeNumber)',
        );
        await db.execute(
          'CREATE INDEX idx_rfid_tags_tid ON rfid_tags(TidValue)',
        );
        await db.execute('CREATE INDEX idx_bulk_items_tid ON bulk_items(tid)');

        await db.execute('CREATE TABLE local_categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
        await db.execute('CREATE TABLE local_products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
        await db.execute('CREATE TABLE local_designs (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');

        await db.execute('''
          CREATE TABLE location_table (
            Id INTEGER PRIMARY KEY,
            ClientCode TEXT,
            UserId INTEGER,
            BranchId INTEGER,
            Latitude TEXT,
            Longitude TEXT,
            Address TEXT,
            CreatedOn TEXT,
            LastUpdated TEXT,
            StatusType INTEGER
          )
        ''');

        await _createOrderOfflineTables(db);
        await _createPendingCustomersTable(db);
        await _createHeldSampleStockTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_bulk_items_bulkItemId ON bulk_items(bulkItemId)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_rfid_tags_barcode ON rfid_tags(BarcodeNumber)',
          );
        }
        if (oldVersion < 3) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_counterName ON bulk_items(counterName)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_boxName ON bulk_items(boxName)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_branchName ON bulk_items(branchName)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_category ON bulk_items(category)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_productName ON bulk_items(productName)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_design ON bulk_items(design)');
        }
        if (oldVersion < 4) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_rfid ON bulk_items(rfid)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_itemCode ON bulk_items(itemCode)');
        }
        if (oldVersion < 5) {
          await db.execute('CREATE TABLE IF NOT EXISTS local_categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
          await db.execute('CREATE TABLE IF NOT EXISTS local_products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
          await db.execute('CREATE TABLE IF NOT EXISTS local_designs (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS location_table (
              Id INTEGER PRIMARY KEY,
              ClientCode TEXT,
              UserId INTEGER,
              BranchId INTEGER,
              Latitude TEXT,
              Longitude TEXT,
              Address TEXT,
              CreatedOn TEXT,
              LastUpdated TEXT,
              StatusType INTEGER
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_rfid_tags_tid ON rfid_tags(TidValue)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bulk_items_tid ON bulk_items(tid)');
        }
        if (oldVersion < 8) {
          await _createOrderOfflineTables(db);
        }
        if (oldVersion < 9) {
          await _createPendingCustomersTable(db);
        }
        if (oldVersion < 10) {
          await _createHeldSampleStockTable(db);
        }
      },
    );
  }

  static const List<String> _scanDisplayColumns = [
    'id',
    'bulkItemId',
    'productName',
    'itemCode',
    'rfid',
    'epc',
    'imageUrl',
    'grossWeight',
    'netWeight',
    'stoneWeight',
    'diamondWeight',
    'category',
    'design',
    'purity',
    'counterName',
    'boxName',
    'branchName',
    'branchType',
    'counterId',
    'categoryId',
    'productId',
    'designId',
    'branchId',
    'isScanned',
    'pcs',
    'mrp',
    'scannedStatus',
    'status',
    'boxId',
    'packetId',
    'packetName',
    'skuId',
    'purityId',
  ];

  ({String? where, List<dynamic>? args}) _verificationFilter(
    String filterType,
    String filterValue,
  ) {
    // Inventory multi-select joins values with Unit Separator (\u001F).
    final values = filterValue
        .split('\u001F')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (values.isEmpty) return (where: null, args: null);

    final typeLower = filterType.toLowerCase();
    final placeholders = List.filled(values.length, '?').join(',');

    if (typeLower == 'counter') {
      return (
        where: values.length == 1
            ? 'counterName = ?'
            : 'counterName IN ($placeholders)',
        args: values,
      );
    }
    if (typeLower == 'box') {
      return (
        where: values.length == 1
            ? 'boxName = ?'
            : 'boxName IN ($placeholders)',
        args: values,
      );
    }
    if (typeLower == 'branch') {
      return (
        where: values.length == 1
            ? 'branchName = ?'
            : 'branchName IN ($placeholders)',
        args: values,
      );
    }
    if (typeLower == 'exhibition') {
      return (
        where: values.length == 1
            ? "branchName = ? AND LOWER(branchType) = 'exhibition'"
            : "branchName IN ($placeholders) AND LOWER(branchType) = 'exhibition'",
        args: values,
      );
    }
    return (where: null, args: null);
  }

  List<BulkItem> _mapsToBulkItems(List<Map<String, dynamic>> maps) {
    return maps.map(BulkItem.fromMap).toList();
  }

  /// Fast count for scan display loading progress.
  Future<int> getScanDisplayItemCount({
    String? filterType,
    String? filterValue,
  }) async {
    final db = await database;
    if (filterType != null &&
        filterType.isNotEmpty &&
        filterValue != null &&
        filterValue.isNotEmpty) {
      final filter = _verificationFilter(filterType, filterValue);
      if (filter.where != null) {
        final result = await db.rawQuery(
          'SELECT COUNT(*) FROM bulk_items WHERE ${filter.where}',
          filter.args,
        );
        return Sqflite.firstIntValue(result) ?? 0;
      }
    }
    return getTotalItemCount();
  }

  /// Paginated minimal-column load for scan display (10L+ rows).
  Future<List<BulkItem>> getScanDisplayItemsPaged(
    int limit,
    int offset, {
    String? filterType,
    String? filterValue,
  }) async {
    final db = await database;
    String? whereString;
    List<dynamic>? whereArgs;

    if (filterType != null &&
        filterType.isNotEmpty &&
        filterValue != null &&
        filterValue.isNotEmpty) {
      final filter = _verificationFilter(filterType, filterValue);
      whereString = filter.where;
      whereArgs = filter.args;
    }

    final maps = await db.query(
      'bulk_items',
      columns: _scanDisplayColumns,
      where: whereString,
      whereArgs: whereArgs,
      orderBy: 'bulkItemId',
      limit: limit,
      offset: offset,
    );
    return _mapsToBulkItems(maps);
  }

  /// Exact RFID / item code / EPC / TID search — indexed, no full-table scan.
  Future<List<BulkItem>> searchItemsExact(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final qu = q.toUpperCase();

    final args = q == qu ? [q] : [q, qu];
    final placeholders = List.filled(args.length, '?').join(', ');

    final db = await database;
    final maps = await db.rawQuery(
      '''
      SELECT ${_scanDisplayColumns.join(', ')}
      FROM bulk_items
      WHERE rfid IN ($placeholders)
         OR itemCode IN ($placeholders)
         OR epc IN ($placeholders)
         OR tid IN ($placeholders)
      LIMIT 50
      ''',
      [...args, ...args, ...args, ...args],
    );
    return _mapsToBulkItems(maps);
  }

  // Clear all bulk items
  Future<void> clearAllItems() async {
    final db = await database;
    await db.delete('bulk_items');
    invalidateBulkCache();
  }

  // Get all bulk items (cached in memory until DB writes)
  Future<List<BulkItem>> getAllBulkItems({bool forceRefresh = false}) async {
    if (!forceRefresh && _bulkItemsCache != null) return _bulkItemsCache!;
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('bulk_items');
    _bulkItemsCache = maps.map((m) => BulkItem.fromMap(m)).toList();
    return _bulkItemsCache!;
  }

  // Clear all RFID tags
  Future<void> clearAllRFID() async {
    final db = await database;
    await db.delete('rfid_tags');
  }

  Future<void> clearAllLocalData() async {
    final db = await database;
    await db.delete('bulk_items');
    await db.delete('rfid_tags');
    await db.delete('location_table');
    invalidateBulkCache();
  }

  Future<List<LocationItem>> getAllLocations() async {
    final db = await database;
    final rows = await db.query('location_table', orderBy: 'CreatedOn DESC');
    return rows.map(LocationItem.fromMap).toList();
  }

  Future<void> replaceAllLocations(List<LocationItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('location_table');
      final batch = txn.batch();
      for (final item in items) {
        batch.insert('location_table', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  // Fast Bulk Insert of BulkItem using Transaction and Batch (chunked for large imports).
  Future<void> insertBulkItemsInBatch(
    List<BulkItem> items, {
    void Function(int done, int total)? onProgress,
    int? chunkSize,
  }) async {
    if (items.isEmpty) {
      invalidateBulkCache();
      return;
    }
    final db = await database;
    final total = items.length;
    
    // Dynamically scale chunk size to target ~100 progress updates, preventing UI thread
    // thrashing and excessive SQLite commits (which slow down 10L imports by 100x).
    final calculatedChunk = (total / 100).clamp(2000, 25000).toInt();
    final size = chunkSize ?? calculatedChunk;
    
    var done = 0;
    for (var i = 0; i < items.length; i += size) {
      final end = (i + size > items.length) ? items.length : i + size;
      final slice = items.sublist(i, end);
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final item in slice) {
          batch.insert(
            'bulk_items',
            item.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
      done = end;
      onProgress?.call(done, total);
      // Yield so UI progress can paint during large imports.
      await Future<void>.delayed(Duration.zero);
    }
    invalidateBulkCache();
  }

  // Fast Bulk Insert of EpcDto using Transaction and Batch
  Future<void> insertRFIDTagsInBatch(List<EpcDto> tags) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final tag in tags) {
        batch.insert(
          'rfid_tags',
          tag.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  // Query paginated items
  Future<List<BulkItem>> getMinimalItemsPaged(int limit, int offset) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'bulk_items',
      columns: [
        'id',
        'bulkItemId',
        'productName',
        'itemCode',
        'rfid',
        'epc',
        'imageUrl',
        'isScanned',
        'counterName',
        'branchName',
        'boxName',
        'branchType',
        'totalQty',
        'totalNetWt',
        'mrp',
        'categoryId',
        'category',
        'design',
        'pcs',
        'grossWeight',
        'netWeight',
        'purity',
        'status'
      ],
      orderBy: 'bulkItemId',
      limit: limit,
      offset: offset,
    );

    return List.generate(maps.length, (i) {
      return BulkItem.fromMap(maps[i]);
    });
  }

  // Get total count of bulk items
  Future<int> getTotalItemCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM bulk_items');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Get RFID tags map for fast lookups (BarcodeNumber -> TidValue)
  Future<Map<String, String>> getRFIDTagsMap() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'rfid_tags',
      columns: ['BarcodeNumber', 'TidValue'],
    );
    final map = <String, String>{};
    for (final row in maps) {
      final barcode = row['BarcodeNumber'] as String? ?? '';
      final tid = row['TidValue'] as String? ?? '';
      if (barcode.isNotEmpty) {
        map[barcode.toUpperCase()] = tid.toUpperCase();
      }
    }
    return map;
  }

  // Query paginated items with filtering
  Future<List<BulkItem>> getMinimalItemsPagedFiltered(
    int limit,
    int offset, {
    String? searchQuery,
    String? sku,
    String? category,
    String? productName,
    String? design,
    String? purity,
  }) async {
    final db = await database;
    
    // Construct dynamic where clause
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      whereClauses.add('(itemCode LIKE ? OR productName LIKE ? OR rfid LIKE ? OR epc LIKE ?)');
      whereArgs.addAll([query, query, query, query]);
    }

    if (sku != null && sku.isNotEmpty) {
      whereClauses.add('sku = ?');
      whereArgs.add(sku);
    }
    if (category != null && category.isNotEmpty) {
      whereClauses.add('category = ?');
      whereArgs.add(category);
    }
    if (productName != null && productName.isNotEmpty) {
      whereClauses.add('productName = ?');
      whereArgs.add(productName);
    }
    if (design != null && design.isNotEmpty) {
      whereClauses.add('design = ?');
      whereArgs.add(design);
    }
    if (purity != null && purity.isNotEmpty) {
      whereClauses.add('purity = ?');
      whereArgs.add(purity);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final List<Map<String, dynamic>> maps = await db.query(
      'bulk_items',
      where: whereString,
      whereArgs: whereArgs,
      orderBy: 'bulkItemId',
      limit: limit,
      offset: offset,
    );

    return List.generate(maps.length, (i) {
      return BulkItem.fromMap(maps[i]);
    });
  }

  // Get total count of items with filtering
  Future<int> getTotalItemCountFiltered({
    String? searchQuery,
    String? sku,
    String? category,
    String? productName,
    String? design,
    String? purity,
  }) async {
    final db = await database;
    
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      whereClauses.add('(itemCode LIKE ? OR productName LIKE ? OR rfid LIKE ? OR epc LIKE ?)');
      whereArgs.addAll([query, query, query, query]);
    }

    if (sku != null && sku.isNotEmpty) {
      whereClauses.add('sku = ?');
      whereArgs.add(sku);
    }
    if (category != null && category.isNotEmpty) {
      whereClauses.add('category = ?');
      whereArgs.add(category);
    }
    if (productName != null && productName.isNotEmpty) {
      whereClauses.add('productName = ?');
      whereArgs.add(productName);
    }
    if (design != null && design.isNotEmpty) {
      whereClauses.add('design = ?');
      whereArgs.add(design);
    }
    if (purity != null && purity.isNotEmpty) {
      whereClauses.add('purity = ?');
      whereArgs.add(purity);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final result = await db.query(
      'bulk_items',
      columns: ['COUNT(*)'],
      where: whereString,
      whereArgs: whereArgs,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Get ALL matching items (no pagination) for PDF Export
  Future<List<BulkItem>> getAllMinimalItemsFiltered({
    String? searchQuery,
    String? sku,
    String? category,
    String? productName,
    String? design,
    String? purity,
  }) async {
    final db = await database;
    
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final query = '%${searchQuery.trim()}%';
      whereClauses.add('(itemCode LIKE ? OR productName LIKE ? OR rfid LIKE ? OR epc LIKE ?)');
      whereArgs.addAll([query, query, query, query]);
    }

    if (sku != null && sku.isNotEmpty) {
      whereClauses.add('sku = ?');
      whereArgs.add(sku);
    }
    if (category != null && category.isNotEmpty) {
      whereClauses.add('category = ?');
      whereArgs.add(category);
    }
    if (productName != null && productName.isNotEmpty) {
      whereClauses.add('productName = ?');
      whereArgs.add(productName);
    }
    if (design != null && design.isNotEmpty) {
      whereClauses.add('design = ?');
      whereArgs.add(design);
    }
    if (purity != null && purity.isNotEmpty) {
      whereClauses.add('purity = ?');
      whereArgs.add(purity);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final List<Map<String, dynamic>> maps = await db.query(
      'bulk_items',
      where: whereString,
      whereArgs: whereArgs,
      orderBy: 'bulkItemId',
    );

    return List.generate(maps.length, (i) {
      return BulkItem.fromMap(maps[i]);
    });
  }

  // Get distinct values from a column for filter dropdowns
  Future<List<String>> getDistinctValues(String column) async {
    _distinctValuesCache ??= {};
    if (_distinctValuesCache!.containsKey(column)) {
      return List<String>.from(_distinctValuesCache![column]!);
    }
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT $column FROM bulk_items WHERE $column IS NOT NULL AND $column != "" ORDER BY $column ASC'
    );
    final values = maps.map((row) => row[column] as String? ?? '').where((val) => val.isNotEmpty).toList();
    _distinctValuesCache![column] = values;
    return values;
  }

  // Get distinct exhibitions (where branchType = 'Exhibition')
  Future<List<String>> getDistinctExhibitions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      "SELECT DISTINCT branchName FROM bulk_items WHERE branchName IS NOT NULL AND branchName != '' AND LOWER(branchType) = 'exhibition' ORDER BY branchName ASC"
    );
    return maps.map((row) => row['branchName'] as String? ?? '').where((val) => val.isNotEmpty).toList();
  }

  Future<List<String>> getDistinctPacketNames() async => getDistinctValues('packetName');

  Future<int?> getEntityIdByName(String type, String name) async {
    if (name.trim().isEmpty) return null;
    final db = await database;
    final t = type.toLowerCase();
    String column;
    String idColumn;
    switch (t) {
      case 'counter':
        column = 'counterName';
        idColumn = 'counterId';
      case 'branch':
        column = 'branchName';
        idColumn = 'branchId';
      case 'box':
        column = 'boxName';
        idColumn = 'boxId';
      case 'packet':
        column = 'packetName';
        idColumn = 'packetId';
      default:
        return null;
    }
    final rows = await db.query(
      'bulk_items',
      columns: [idColumn],
      where: '$column = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first[idColumn] as num?)?.toInt();
  }

  Future<List<BulkItem>> getLabelledBulkItems() async {
    final db = await database;
    final maps = await db.query(
      'bulk_items',
      columns: _labelledTransferColumns,
      where: "TRIM(itemCode) != ''",
    );
    return maps.map((m) => BulkItem.fromMap(m)).toList();
  }

  Future<List<BulkItem>> getLabelledBulkItemsPaged(int limit, int offset) async {
    final db = await database;
    final maps = await db.query(
      'bulk_items',
      columns: _labelledTransferColumns,
      where: "TRIM(itemCode) != ''",
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => BulkItem.fromMap(m)).toList();
  }

  Future<List<BulkItem>> getLabelledBulkItemsFiltered({
    required String fromType,
    required String fromValue,
  }) async {
    final db = await database;
    String where = "TRIM(itemCode) != ''";
    final args = <Object?>[];
    final value = fromValue.trim();

    switch (fromType) {
      case 'counter':
        where += ' AND LOWER(TRIM(counterName)) = LOWER(?)';
        args.add(value);
        break;
      case 'branch':
        where += ' AND LOWER(TRIM(branchName)) = LOWER(?)';
        args.add(value);
        break;
      case 'box':
        where += ' AND LOWER(TRIM(boxName)) = LOWER(?)';
        args.add(value);
        break;
      case 'packet':
        where += ' AND LOWER(TRIM(packetName)) = LOWER(?)';
        args.add(value);
        break;
      case 'display':
        where += ' AND (counterId = 0 OR TRIM(counterName) = \'\')';
        break;
    }

    final maps = await db.query(
      'bulk_items',
      columns: _labelledTransferColumns,
      where: where,
      whereArgs: args.isEmpty ? null : args,
    );
    return maps.map((m) => BulkItem.fromMap(m)).toList();
  }

  // Delete an item locally by its bulkItemId
  Future<int> deleteItemLocally(int bulkItemId) async {
    final db = await database;
    final count = await db.delete(
      'bulk_items',
      where: 'bulkItemId = ?',
      whereArgs: [bulkItemId],
    );
    if (count > 0) invalidateBulkCache();
    return count;
  }

  String _normStockKey(String raw) =>
      raw.trim().toUpperCase().replaceAll(' ', '').replaceAll('-', '');

  List<String> _uniqueNormKeys(Iterable<String> raw) {
    final out = <String>{};
    for (final v in raw) {
      final n = _normStockKey(v);
      if (n.isNotEmpty) out.add(n);
    }
    return out.toList();
  }

  /// Snapshot matching labelled-stock rows, then remove them from [bulk_items]
  /// so Product List count drops immediately after Sample Out / Delivery Challan.
  Future<int> holdAndRemoveStock({
    Iterable<int> labelledStockIds = const [],
    Iterable<String> itemCodes = const [],
    Iterable<String> rfids = const [],
    Iterable<String> tids = const [],
  }) async {
    final ids = labelledStockIds.where((id) => id > 0).toSet().toList();
    final codes = _uniqueNormKeys(itemCodes);
    final rfidKeys = _uniqueNormKeys(rfids);
    final tidKeys = _uniqueNormKeys(tids);
    if (ids.isEmpty && codes.isEmpty && rfidKeys.isEmpty && tidKeys.isEmpty) {
      return 0;
    }

    final db = await database;
    await _createHeldSampleStockTable(db);

    final clauses = <String>[];
    final args = <Object?>[];
    if (ids.isNotEmpty) {
      clauses.add(
        'bulkItemId IN (${List.filled(ids.length, '?').join(',')})',
      );
      args.addAll(ids);
    }
    if (codes.isNotEmpty) {
      clauses.add(
        'UPPER(REPLACE(REPLACE(TRIM(itemCode), \' \', \'\'), \'-\', \'\')) IN (${List.filled(codes.length, '?').join(',')})',
      );
      args.addAll(codes);
    }
    if (rfidKeys.isNotEmpty) {
      clauses.add(
        'UPPER(REPLACE(REPLACE(TRIM(rfid), \' \', \'\'), \'-\', \'\')) IN (${List.filled(rfidKeys.length, '?').join(',')})',
      );
      args.addAll(rfidKeys);
    }
    if (tidKeys.isNotEmpty) {
      clauses.add(
        'UPPER(REPLACE(REPLACE(TRIM(IFNULL(tid, \'\')), \' \', \'\'), \'-\', \'\')) IN (${List.filled(tidKeys.length, '?').join(',')})',
      );
      args.addAll(tidKeys);
    }

    final rows = await db.query(
      'bulk_items',
      where: clauses.join(' OR '),
      whereArgs: args,
    );
    if (rows.isEmpty) return 0;

    await db.transaction((txn) async {
      for (final row in rows) {
        final bulkId = (row['bulkItemId'] as num?)?.toInt() ?? 0;
        await txn.insert(
          'held_sample_stock',
          {
            'bulkItemId': bulkId,
            'itemCode': (row['itemCode'] ?? '').toString(),
            'rfid': (row['rfid'] ?? '').toString(),
            'tid': (row['tid'] ?? '').toString(),
            'payload': jsonEncode(row),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (bulkId > 0) {
          await txn.delete(
            'bulk_items',
            where: 'bulkItemId = ?',
            whereArgs: [bulkId],
          );
        } else {
          await txn.delete(
            'bulk_items',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    });
    invalidateBulkCache();
    return rows.length;
  }

  /// Put Sample In (returned) items back into [bulk_items] so Product List count
  /// matches stock again.
  Future<int> restoreHeldStock({
    Iterable<int> labelledStockIds = const [],
    Iterable<String> itemCodes = const [],
  }) async {
    final ids = labelledStockIds.where((id) => id > 0).toSet().toList();
    final codes = _uniqueNormKeys(itemCodes);
    if (ids.isEmpty && codes.isEmpty) return 0;

    final db = await database;
    await _createHeldSampleStockTable(db);

    final clauses = <String>[];
    final args = <Object?>[];
    if (ids.isNotEmpty) {
      clauses.add(
        'bulkItemId IN (${List.filled(ids.length, '?').join(',')})',
      );
      args.addAll(ids);
    }
    if (codes.isNotEmpty) {
      clauses.add(
        'UPPER(REPLACE(REPLACE(TRIM(itemCode), \' \', \'\'), \'-\', \'\')) IN (${List.filled(codes.length, '?').join(',')})',
      );
      args.addAll(codes);
    }

    final held = await db.query(
      'held_sample_stock',
      where: clauses.join(' OR '),
      whereArgs: args,
    );
    if (held.isEmpty) return 0;

    var restored = 0;
    await db.transaction((txn) async {
      for (final h in held) {
        Map<String, dynamic> payload;
        try {
          payload = Map<String, dynamic>.from(
            jsonDecode(h['payload'] as String) as Map,
          );
        } catch (_) {
          continue;
        }
        payload.remove('id');
        final bulkId = (payload['bulkItemId'] as num?)?.toInt() ??
            (h['bulkItemId'] as num?)?.toInt() ??
            0;
        if (bulkId > 0) {
          await txn.delete(
            'bulk_items',
            where: 'bulkItemId = ?',
            whereArgs: [bulkId],
          );
        }
        try {
          await txn.insert(
            'bulk_items',
            payload,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {
          payload['epc'] = null;
          await txn.insert(
            'bulk_items',
            payload,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await txn.delete(
          'held_sample_stock',
          where: 'bulkItemId = ?',
          whereArgs: [h['bulkItemId']],
        );
        restored++;
      }
    });
    if (restored > 0) invalidateBulkCache();
    return restored;
  }

  // Update an item locally
  Future<int> updateItemLocally(BulkItem item) async {
    final db = await database;
    final count = await db.update(
      'bulk_items',
      item.toMap(),
      where: 'bulkItemId = ?',
      whereArgs: [item.bulkItemId],
    );
    if (count > 0) invalidateBulkCache();
    return count;
  }

  // Bulk update scan status (chunked for 2–5L inventories).
  Future<void> saveScanResultsLocally(List<BulkItem> items) async {
    if (items.isEmpty) return;
    final db = await database;
    const chunk = 5000;
    for (var i = 0; i < items.length; i += chunk) {
      final end = (i + chunk < items.length) ? i + chunk : items.length;
      final slice = items.sublist(i, end);
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final item in slice) {
          batch.update(
            'bulk_items',
            {
              'isScanned': item.isScanned,
              'scannedStatus': item.scannedStatus,
            },
            where: 'bulkItemId = ?',
            whereArgs: [item.bulkItemId],
          );
        }
        await batch.commit(noResult: true);
      });
    }
    invalidateBulkCache();
  }

  // Get items scoped for verification (minimal columns for speed)
  Future<List<BulkItem>> getItemsForVerification({
    required String filterType,
    required String filterValue,
  }) async {
    final db = await database;
    final filter = _verificationFilter(filterType, filterValue);
    if (filter.where == null) return [];

    final maps = await db.query(
      'bulk_items',
      columns: _scanDisplayColumns,
      where: filter.where,
      whereArgs: filter.args,
      orderBy: 'bulkItemId',
    );
    return _mapsToBulkItems(maps);
  }

  Future<void> _ensureLocalDropdownTables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS local_categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS local_products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS local_designs (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)',
    );
  }

  Future<({List<String> categories, List<String> products, List<String> designs})>
      getLocalDropdownData() async {
    final db = await database;
    await _ensureLocalDropdownTables(db);
    final results = await Future.wait([
      db.query('local_categories', orderBy: 'name'),
      db.query('local_products', orderBy: 'name'),
      db.query('local_designs', orderBy: 'name'),
    ]);
    return (
      categories: results[0].map((r) => r['name'] as String).toList(),
      products: results[1].map((r) => r['name'] as String).toList(),
      designs: results[2].map((r) => r['name'] as String).toList(),
    );
  }

  Future<List<String>> getLocalCategories() async {
    final db = await database;
    await _ensureLocalDropdownTables(db);
    final rows = await db.query('local_categories', orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<List<String>> getLocalProducts() async {
    final db = await database;
    await _ensureLocalDropdownTables(db);
    final rows = await db.query('local_products', orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<List<String>> getLocalDesigns() async {
    final db = await database;
    await _ensureLocalDropdownTables(db);
    final rows = await db.query('local_designs', orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> insertLocalCategory(String name) async {
    if (name.trim().isEmpty) return;
    final db = await database;
    await _ensureLocalDropdownTables(db);
    await db.insert('local_categories', {'name': name.trim()}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> insertLocalProduct(String name) async {
    if (name.trim().isEmpty) return;
    final db = await database;
    await _ensureLocalDropdownTables(db);
    await db.insert('local_products', {'name': name.trim()}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> insertLocalDesign(String name) async {
    if (name.trim().isEmpty) return;
    final db = await database;
    await _ensureLocalDropdownTables(db);
    await db.insert('local_designs', {'name': name.trim()}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // ---- Order offline tables (v8) -------------------------------------------

  static Future<void> _createOrderOfflineTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_master_cache (
        client_code TEXT PRIMARY KEY,
        customers_json TEXT NOT NULL,
        daily_rates_json TEXT NOT NULL,
        branches_json TEXT NOT NULL,
        last_order_no INTEGER DEFAULT 0,
        cached_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_orders (
        local_id TEXT PRIMARY KEY,
        client_code TEXT NOT NULL,
        custom_order_id INTEGER DEFAULT 0,
        order_no TEXT,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        created_at TEXT NOT NULL,
        synced_at TEXT,
        last_error TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders_history_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_code TEXT NOT NULL,
        custom_order_id INTEGER,
        order_json TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_orders_client ON pending_orders(client_code, sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_history_client ON orders_history_cache(client_code)',
    );
  }

  static Future<void> _createPendingCustomersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_customers (
        local_id TEXT PRIMARY KEY,
        client_code TEXT NOT NULL,
        temp_customer_id INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        created_at TEXT NOT NULL,
        synced_at TEXT,
        last_error TEXT,
        server_customer_id INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_customers_client ON pending_customers(client_code, sync_status)',
    );
  }

  static Future<void> _createHeldSampleStockTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS held_sample_stock (
        bulkItemId INTEGER PRIMARY KEY,
        itemCode TEXT,
        rfid TEXT,
        tid TEXT,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_held_sample_itemCode ON held_sample_stock(itemCode)',
    );
  }

  Future<void> saveOrderMasterCache({
    required String clientCode,
    required String customersJson,
    required String dailyRatesJson,
    required String branchesJson,
    required int lastOrderNo,
  }) async {
    final db = await database;
    await db.insert(
      'order_master_cache',
      {
        'client_code': clientCode,
        'customers_json': customersJson,
        'daily_rates_json': dailyRatesJson,
        'branches_json': branchesJson,
        'last_order_no': lastOrderNo,
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadOrderMasterCache(String clientCode) async {
    final db = await database;
    final rows = await db.query(
      'order_master_cache',
      where: 'client_code = ?',
      whereArgs: [clientCode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> updateCachedLastOrderNo(String clientCode, int lastOrderNo) async {
    final db = await database;
    await db.update(
      'order_master_cache',
      {'last_order_no': lastOrderNo, 'cached_at': DateTime.now().toIso8601String()},
      where: 'client_code = ?',
      whereArgs: [clientCode],
    );
  }

  Future<void> insertPendingOrder({
    required String localId,
    required String clientCode,
    required int customOrderId,
    required String orderNo,
    required String operation,
    required String payloadJson,
  }) async {
    final db = await database;
    await db.insert(
      'pending_orders',
      {
        'local_id': localId,
        'client_code': clientCode,
        'custom_order_id': customOrderId,
        'order_no': orderNo,
        'operation': operation,
        'payload_json': payloadJson,
        'sync_status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingOrders(String clientCode) async {
    final db = await database;
    // Prefer exact client match; if empty (legacy rows), also load blank client_code.
    var rows = await db.query(
      'pending_orders',
      where: "sync_status = 'pending' AND (client_code = ? OR client_code = '' OR client_code IS NULL)",
      whereArgs: [clientCode],
      orderBy: 'created_at ASC',
    );
    // Legacy / wrong client_code: still surface pending so sync + * work.
    if (rows.isEmpty) {
      rows = await db.query(
        'pending_orders',
        where: "sync_status = 'pending'",
        orderBy: 'created_at ASC',
      );
    }
    return rows;
  }

  /// All pending orders for any client (used when remapping / diagnostics).
  Future<List<Map<String, dynamic>>> getAllPendingOrders() async {
    final db = await database;
    return db.query(
      'pending_orders',
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
    );
  }

  Future<int> countPendingOrders(String clientCode) async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) as c FROM pending_orders WHERE sync_status = 'pending' "
      "AND (client_code = ? OR client_code = '' OR client_code IS NULL)",
      [clientCode],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> markPendingOrderSynced(String localId, {int? customOrderId}) async {
    final db = await database;
    final data = <String, Object?>{
      'sync_status': 'synced',
      'synced_at': DateTime.now().toIso8601String(),
      'last_error': null,
    };
    if (customOrderId != null && customOrderId > 0) {
      data['custom_order_id'] = customOrderId;
    }
    await db.update(
      'pending_orders',
      data,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Re-queue create/update orders marked synced locally but never got a server id.
  Future<int> requeueUnconfirmedOrderUploads(String clientCode) async {
    final db = await database;
    return db.rawUpdate(
      "UPDATE pending_orders SET sync_status = 'pending', last_error = NULL "
      "WHERE client_code = ? AND sync_status = 'synced' AND operation = 'update' "
      "AND (custom_order_id IS NULL OR custom_order_id <= 0)",
      [clientCode],
    );
  }

  /// Remove create rows marked synced without a server id (already uploaded; re-upload
  /// would duplicate OrderNo on the server).
  Future<int> purgeUnconfirmedSyncedCreates(String clientCode) async {
    final db = await database;
    return db.delete(
      'pending_orders',
      where: "client_code = ? AND sync_status = 'synced' AND "
          "(operation = 'create' OR operation IS NULL OR operation = '') AND "
          "(custom_order_id IS NULL OR custom_order_id <= 0)",
      whereArgs: [clientCode],
    );
  }

  Future<void> markPendingOrderFailed(String localId, String error) async {
    final db = await database;
    await db.update(
      'pending_orders',
      {'last_error': error},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<bool> deletePendingOrder(String localId) async {
    final db = await database;
    final n = await db.delete(
      'pending_orders',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
    return n > 0;
  }

  Future<bool> deletePendingByCustomOrderId(int customOrderId) async {
    final db = await database;
    final n = await db.delete(
      'pending_orders',
      where: 'custom_order_id = ?',
      whereArgs: [customOrderId],
    );
    return n > 0;
  }

  Future<void> replaceOrdersHistoryCache(String clientCode, List<dynamic> orders) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('orders_history_cache', where: 'client_code = ?', whereArgs: [clientCode]);
    final now = DateTime.now().toIso8601String();
    for (final o in orders) {
      if (o is! Map) continue;
      batch.insert('orders_history_cache', {
        'client_code': clientCode,
        'custom_order_id': o['CustomOrderId'] as int? ?? 0,
        'order_json': jsonEncode(o),
        'cached_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<dynamic>> loadOrdersHistoryCache(String clientCode) async {
    final db = await database;
    final rows = await db.query(
      'orders_history_cache',
      where: 'client_code = ?',
      whereArgs: [clientCode],
      orderBy: 'custom_order_id DESC',
    );
    return rows.map((r) => jsonDecode(r['order_json'] as String)).toList();
  }

  Future<void> replaceCustomersInMasterCache(String clientCode, String customersJson) async {
    final row = await loadOrderMasterCache(clientCode);
    if (row == null) return;
    await saveOrderMasterCache(
      clientCode: clientCode,
      customersJson: customersJson,
      dailyRatesJson: row['daily_rates_json'] as String? ?? '[]',
      branchesJson: row['branches_json'] as String? ?? '[]',
      lastOrderNo: row['last_order_no'] as int? ?? 0,
    );
  }

  Future<void> insertPendingCustomer({
    required String localId,
    required String clientCode,
    required int tempCustomerId,
    required String payloadJson,
  }) async {
    final db = await database;
    await db.insert(
      'pending_customers',
      {
        'local_id': localId,
        'client_code': clientCode,
        'temp_customer_id': tempCustomerId,
        'payload_json': payloadJson,
        'sync_status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingCustomers(String clientCode) async {
    final db = await database;
    var rows = await db.query(
      'pending_customers',
      where: "client_code = ? AND sync_status = 'pending'",
      whereArgs: [clientCode],
      orderBy: 'created_at ASC',
    );
    if (rows.isEmpty) {
      rows = await db.query(
        'pending_customers',
        where: "sync_status = 'pending'",
        orderBy: 'created_at ASC',
      );
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> getAllPendingCustomers() async {
    final db = await database;
    return db.query(
      'pending_customers',
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
    );
  }

  Future<int> countPendingCustomers(String clientCode) async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) as c FROM pending_customers WHERE client_code = ? AND sync_status = 'pending'",
      [clientCode],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> markPendingCustomerSynced(String localId, int serverCustomerId) async {
    final db = await database;
    await db.update(
      'pending_customers',
      {
        'sync_status': 'synced',
        'synced_at': DateTime.now().toIso8601String(),
        'server_customer_id': serverCustomerId,
        'last_error': null,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markPendingCustomerFailed(String localId, String error) async {
    final db = await database;
    await db.update(
      'pending_customers',
      {'last_error': error},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updatePendingOrderPayload(String localId, String payloadJson, {String? orderNo}) async {
    final db = await database;
    final data = <String, Object?>{
      'payload_json': payloadJson,
      'sync_status': 'pending',
      'last_error': null,
    };
    if (orderNo != null) data['order_no'] = orderNo;
    await db.update(
      'pending_orders',
      data,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }
}
