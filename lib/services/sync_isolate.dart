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
    final String tagType =
        (params['tagType'] as String? ?? 'webreusable').trim().toLowerCase();
    final bool allowSingleAndWebReusable =
        params['allowSingleAndWebReusable'] as bool? ?? true;

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

      // Kotlin clears only bulk_items before streaming stock data.
      sendPort.send({'status': 'init', 'message': 'Clearing old stock data...'});
      await db.delete('bulk_items');

      httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 60);
      httpClient.idleTimeout = const Duration(minutes: 10);

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

          final mapped = await _mapServerItem(
            db: db!,
            rfidLookup: rfidLookup,
            itemJson: itemJson,
            tagType: tagType,
            allowSingleAndWebReusable: allowSingleAndWebReusable,
            skippedItemCodes: skippedItemCodes,
          );
          if (mapped != null) {
            queue.add(mapped);
            syncedCount++;
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
      batch.insert(
        'bulk_items',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<BulkItem?> _mapServerItem({
    required Database db,
    required _RfidLookupCache rfidLookup,
    required Map<String, dynamic> itemJson,
    required String tagType,
    required bool allowSingleAndWebReusable,
    required List<String> skippedItemCodes,
  }) async {
    final status = itemJson['Status'] as String? ?? '';
    final itemCode = itemJson['ItemCode'] as String? ?? '';
    final categoryId = itemJson['CategoryId'] as int?;
    final categoryName = itemJson['CategoryName'] as String? ?? '';
    final productId = itemJson['ProductId'] as int?;
    final productName = itemJson['ProductName'] as String? ?? '';

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

    if (tagType == 'webreusable') {
      final hasItemCode = bulkItem.itemCode.isNotEmpty;
      final hasRfid = bulkItem.rfid.isNotEmpty;
      final hasEpcOrTid = bulkItem.epc.isNotEmpty || bulkItem.tid.isNotEmpty;

      if (!hasItemCode ||
          (!allowSingleAndWebReusable && !hasRfid) ||
          (allowSingleAndWebReusable && !hasRfid && !hasEpcOrTid)) {
        addSkipped('No RFID/EPC/TID');
        return null;
      }

      if (bulkItem.rfid.isNotEmpty && bulkItem.epc.isEmpty) {
        final lookupEpc = await rfidLookup.lookup(db, bulkItem.rfid);
        if (lookupEpc != null && lookupEpc.isNotEmpty) {
          bulkItem.epc = lookupEpc;
        }
      }
    } else {
      if (bulkItem.itemCode.isNotEmpty) {
        final hexValue = utf8
            .encode(bulkItem.itemCode)
            .map((c) => c.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase();
        return BulkItem(
          id: bulkItem.id,
          bulkItemId: bulkItem.bulkItemId,
          productName: bulkItem.productName,
          itemCode: bulkItem.itemCode,
          rfid: bulkItem.itemCode,
          grossWeight: bulkItem.grossWeight,
          stoneWeight: bulkItem.stoneWeight,
          diamondWeight: bulkItem.diamondWeight,
          netWeight: bulkItem.netWeight,
          category: bulkItem.category,
          design: bulkItem.design,
          purity: bulkItem.purity,
          makingPerGram: bulkItem.makingPerGram,
          makingPercent: bulkItem.makingPercent,
          fixMaking: bulkItem.fixMaking,
          fixWastage: bulkItem.fixWastage,
          stoneAmount: bulkItem.stoneAmount,
          diamondAmount: bulkItem.diamondAmount,
          sku: bulkItem.sku,
          epc: hexValue,
          vendor: bulkItem.vendor,
          tid: hexValue,
          box: bulkItem.box,
          designCode: bulkItem.designCode,
          productCode: bulkItem.productCode,
          imageUrl: bulkItem.imageUrl,
          totalQty: bulkItem.totalQty,
          pcs: bulkItem.pcs,
          matchedPcs: bulkItem.matchedPcs,
          totalGwt: bulkItem.totalGwt,
          matchGwt: bulkItem.matchGwt,
          totalStoneWt: bulkItem.totalStoneWt,
          matchStoneWt: bulkItem.matchStoneWt,
          totalNetWt: bulkItem.totalNetWt,
          matchNetWt: bulkItem.matchNetWt,
          unmatchedQty: bulkItem.unmatchedQty,
          matchedQty: bulkItem.matchedQty,
          unmatchedGrossWt: bulkItem.unmatchedGrossWt,
          mrp: bulkItem.mrp,
          counterName: bulkItem.counterName,
          counterId: bulkItem.counterId,
          boxId: bulkItem.boxId,
          boxName: bulkItem.boxName,
          branchId: bulkItem.branchId,
          branchName: bulkItem.branchName,
          packetId: bulkItem.packetId,
          packetName: bulkItem.packetName,
          scannedStatus: bulkItem.scannedStatus,
          categoryId: bulkItem.categoryId,
          productId: bulkItem.productId,
          branchType: bulkItem.branchType,
          designId: bulkItem.designId,
          isScanned: bulkItem.isScanned,
          totalWt: bulkItem.totalWt,
          categoryWt: bulkItem.categoryWt,
          skuId: bulkItem.skuId,
          purityId: bulkItem.purityId,
          status: bulkItem.status,
        );
      }
      addSkipped('ItemCode blank for single-use tag');
      return null;
    }

    return bulkItem;
  }
}

/// LRU cache for RFID barcode -> TID lookups (avoids loading all RFID into RAM).
class _RfidLookupCache {
  _RfidLookupCache({required int maxEntries}) : _maxEntries = maxEntries;

  final int _maxEntries;
  final Map<String, String> _cache = {};

  Future<String?> lookup(Database db, String rfid) async {
    final key = rfid.trim().toUpperCase();
    if (key.isEmpty) return null;

    final cached = _cache[key];
    if (cached != null) return cached;

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

    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = tid;
    return tid.isEmpty ? null : tid;
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

      final itemsIndex = _headerBuffer.indexOf(RegExp(r'"Items"\s*:\s*\['));
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
