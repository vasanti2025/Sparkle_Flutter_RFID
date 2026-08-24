import 'package:flutter_test/flutter_test.dart';
import 'package:rfid_flutter/models/bulk_item.dart';
import 'package:rfid_flutter/services/db_service.dart';
import 'package:rfid_flutter/utils/tray_scan_auto_stop.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

BulkItem _sampleItem(int id, {String? epc, String? rfid, String category = 'Gold'}) {
  return BulkItem(
    bulkItemId: id,
    productName: 'Product ${id % 10}',
    itemCode: 'IC$id',
    rfid: rfid ?? 'RFID$id',
    grossWeight: '10.500',
    stoneWeight: '0.000',
    diamondWeight: '0.000',
    netWeight: '10.000',
    category: category,
    design: 'Design ${id % 5}',
    purity: '22K',
    makingPerGram: '',
    makingPercent: '',
    fixMaking: '',
    fixWastage: '',
    stoneAmount: '',
    diamondAmount: '',
    sku: '',
    epc: epc ?? 'EPC${id.toString().padLeft(12, '0')}',
    vendor: '',
    tid: '',
    box: '',
    designCode: '',
    productCode: '',
    imageUrl: '',
    totalQty: 1,
    pcs: 1,
    matchedPcs: 0,
    totalGwt: 10.5,
    matchGwt: 0,
    totalStoneWt: 0,
    matchStoneWt: 0,
    totalNetWt: 10,
    matchNetWt: 0,
    unmatchedQty: 1,
    matchedQty: 0,
    unmatchedGrossWt: 10.5,
    mrp: 0,
    counterName: 'Counter A',
    counterId: 1,
    boxId: 1,
    boxName: 'Box 1',
    branchId: 1,
    branchName: 'Main Branch',
    packetId: 0,
    packetName: '',
    scannedStatus: 'Unmatched',
    categoryId: 1,
    productId: id % 10,
    branchType: 'store',
    designId: id % 5,
    isScanned: 0,
    totalWt: 10.5,
    categoryWt: '',
    skuId: 0,
    purityId: 0,
    status: '',
  );
}

Future<void> _resetDb(DbService db) async {
  await db.resetConnection();
  db.invalidateBulkCache();
  final handle = await db.database;
  await handle.delete('bulk_items');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Inventory scan DB (large catalog)', () {
    late DbService db;

    setUp(() async {
      db = DbService();
      await _resetDb(db);
    });

    tearDown(() async {
      await db.resetConnection();
    });

    test('findBulkItemInScanScope matches epc/rfid with counter filter', () async {
      await db.insertBulkItemsInBatch([
        _sampleItem(1, epc: 'EPC000000000001', category: 'Gold'),
        _sampleItem(2, epc: 'EPC000000000002', category: 'Silver'),
      ]);

      final byEpc = await db.findBulkItemInScanScope(
        'EPC000000000001',
        filterType: 'Counter',
        filterValue: 'Counter A',
      );
      expect(byEpc, isNotNull);
      expect(byEpc!.bulkItemId, 1);

      final wrongCounter = await db.findBulkItemInScanScope(
        'EPC000000000002',
        filterType: 'Counter',
        filterValue: 'Other Counter',
      );
      expect(wrongCounter, isNull);

      final byRfid = await db.findBulkItemInScanScope('RFID2');
      expect(byRfid?.bulkItemId, 2);
    });

    test('markBulkItemScanned updates counts and aggregates', () async {
      await db.insertBulkItemsInBatch([
        _sampleItem(1, category: 'Gold'),
        _sampleItem(2, category: 'Gold'),
        _sampleItem(3, category: 'Silver'),
      ]);

      await db.markBulkItemScanned(1);
      await db.markBulkItemScanned(2);

      final matched = await db.countScannedInInventoryScope();
      expect(matched, 2);

      final goldAgg = await db.getInventoryGroupAggregates(groupColumn: 'category');
      final gold = goldAgg.firstWhere((g) => g.name == 'Gold');
      expect(gold.totalQty, 2);
      expect(gold.matchedQty, 2);
      expect(gold.fullyMatched, isTrue);

      final silver = goldAgg.firstWhere((g) => g.name == 'Silver');
      expect(silver.matchedQty, 0);
      expect(silver.fullyMatched, isFalse);
    });

    test('resetScannedFlagsInScope clears session matches', () async {
      await db.insertBulkItemsInBatch([_sampleItem(1), _sampleItem(2)]);
      await db.markBulkItemScanned(1);
      expect(await db.countScannedInInventoryScope(), 1);

      await db.resetScannedFlagsInScope();
      expect(await db.countScannedInInventoryScope(), 0);
    });

    test('forEachBulkItemInInventoryScope iterates all rows in chunks', () async {
      final items = List.generate(4500, (i) => _sampleItem(i + 1));
      await db.insertBulkItemsInBatch(items, chunkSize: 1000);

      var seen = 0;
      await db.forEachBulkItemInInventoryScope(
        chunkSize: 2000,
        onChunk: (chunk) async {
          seen += chunk.length;
        },
      );
      expect(seen, 4500);
    });

    test('isLargeInventoryCatalog true at 25k+ rows', () async {
      // Seed enough rows to cross threshold without storing all in RAM.
      final handle = await db.database;
      final batch = handle.batch();
      for (var i = 1; i <= kLargeInventoryCatalogThreshold; i++) {
        batch.insert('bulk_items', _sampleItem(i).toMap());
      }
      await batch.commit(noResult: true);
      db.invalidateBulkCache();

      final total = await db.getTotalItemCount();
      expect(total, kLargeInventoryCatalogThreshold);
      expect(await db.isLargeInventoryCatalog(), isTrue);

      // Must not build full scan-key index on large catalogs — SQL fallback still works.
      await db.warmScanKeyIndex();
      expect(await db.findBulkItemByScanKey('EPC000000025000'), isNotNull);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('paged scope query respects matched filter', () async {
      await db.insertBulkItemsInBatch([_sampleItem(1), _sampleItem(2), _sampleItem(3)]);
      await db.markBulkItemScanned(1);

      final matchedPage = await db.getInventoryScopeItemsPaged(
        50,
        0,
        scanStatus: 'matched',
      );
      expect(matchedPage.length, 1);
      expect(matchedPage.first.bulkItemId, 1);
    });
  });

  group('TrayInventoryScanSession', () {
    test('recordInScopeTag tracks tray tags without scope set', () {
      final session = TrayInventoryScanSession();
      session.recordInScopeTag('ABC');
      session.recordInScopeTag('ABC');
      expect(session.seenInScope.length, 1);

      session.recordInScope('XYZ', {'ABC'});
      expect(session.seenInScope.contains('XYZ'), isFalse);

      expect(session.shouldStop({'ABC'}), isFalse);
    });
  });
}
