import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db_service.dart';
import 'pref_service.dart';
import 'sync_isolate.dart';

/// Keeps local LabelStock (`bulk_items`) in line with Sample Out / Sample In /
/// Delivery Challan so Product List counts match immediately.
class LabelStockSyncService {
  LabelStockSyncService._();

  static bool _syncing = false;

  /// Called after local stock rows change so Product List drops its stale cache.
  static void Function()? onLocalStockChanged;

  static void _notifyStockChanged() {
    try {
      onLocalStockChanged?.call();
    } catch (_) {}
  }

  /// Drop sold / sample-out rows immediately so they cannot be scanned again
  /// while the full server sync is still running.
  static Future<void> removeLocalByLabelledStockIds(
    DbService db,
    Iterable<int> labelledStockIds,
  ) async {
    await db.holdAndRemoveStock(labelledStockIds: labelledStockIds);
    _notifyStockChanged();
  }

  /// Sample Out / Delivery Challan: hold rows then remove from active stock.
  static Future<void> afterStockOut({
    required PrefService prefService,
    required DbService dbService,
    required Iterable<int> labelledStockIds,
    Iterable<String> itemCodes = const [],
    Iterable<String> rfids = const [],
    Iterable<String> tids = const [],
  }) async {
    try {
      final removed = await dbService.holdAndRemoveStock(
        labelledStockIds: labelledStockIds,
        itemCodes: itemCodes,
        rfids: rfids,
        tids: tids,
      );
      debugPrint('LabelStock afterStockOut removed=$removed');
      _notifyStockChanged();
    } catch (e, st) {
      debugPrint('LabelStock afterStockOut failed: $e\n$st');
    }
  }

  /// Sample In: returned items become Active again locally (from held snapshot).
  static Future<void> afterStockIn({
    required PrefService prefService,
    required DbService dbService,
    Iterable<int> labelledStockIds = const [],
    Iterable<String> itemCodes = const [],
  }) async {
    try {
      final restored = await dbService.restoreHeldStock(
        labelledStockIds: labelledStockIds,
        itemCodes: itemCodes,
      );
      debugPrint('LabelStock afterStockIn restored=$restored');
      _notifyStockChanged();
    } catch (e, st) {
      debugPrint('LabelStock afterStockIn failed: $e\n$st');
    }
  }

  /// Full wipe + re-download of Active/ApiActive labelled stock (manual sync).
  static Future<void> syncFromServer({
    required PrefService prefService,
    required DbService dbService,
  }) async {
    if (_syncing) {
      debugPrint('LabelStock sync already in progress — skip');
      return;
    }
    _syncing = true;
    try {
      final employee = prefService.getEmployee();
      if (employee == null) return;

      final rootToken = RootIsolateToken.instance;
      if (rootToken == null) return;

      final receivePort = ReceivePort();
      final done = Completer<void>();

      late final StreamSubscription sub;
      sub = receivePort.listen((message) {
        if (message is! Map) return;
        final status = message['status']?.toString() ?? '';
        if (status == 'completed' || status == 'error') {
          if (status == 'error') {
            debugPrint('LabelStock sync error: ${message['message']}');
          } else {
            debugPrint(
              'LabelStock sync completed synced=${message['synced']} total=${message['total']}',
            );
          }
          receivePort.close();
          unawaited(sub.cancel());
          if (!done.isCompleted) done.complete();
        }
      });

      final dbPath = p.join(await getDatabasesPath(), 'sparkle_rfid.db');
      try {
        await dbService.resetConnection();
      } catch (_) {}
      await Isolate.spawn(SyncIsolate.run, {
        'token': rootToken,
        'sendPort': receivePort.sendPort,
        'baseUrl': prefService.getEffectiveApiBaseUrl(),
        'clientCode': employee.clientCode ?? '',
        'roleId': employee.roleId ?? 0,
        'branchIds': prefService.getBranchIds(),
        'tokenStr': prefService.getToken() ?? '',
        'dbPath': dbPath,
        'tagType': prefService.getRfidType(),
        'allowSingleAndWebReusable': prefService.isWebReusableTagEnabled(),
      });

      await done.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          debugPrint('LabelStock sync timed out');
          receivePort.close();
          unawaited(sub.cancel());
        },
      );
      await dbService.resetConnection();
      _notifyStockChanged();
    } catch (e, st) {
      debugPrint('LabelStock sync failed: $e\n$st');
      try {
        await dbService.resetConnection();
      } catch (_) {}
    } finally {
      _syncing = false;
    }
  }
}
