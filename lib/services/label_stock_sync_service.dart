import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'db_service.dart';
import 'pref_service.dart';
import 'sync_isolate.dart';

/// Refreshes local LabelStock (`bulk_items`) after Delivery Challan / Sample Out /
/// Sample In — same idea as Sparkle `BulkViewModel.syncItems`.
class LabelStockSyncService {
  LabelStockSyncService._();

  static bool _syncing = false;

  /// Drop sold / sample-out rows immediately so they cannot be scanned again
  /// while the full server sync is still running.
  static Future<void> removeLocalByLabelledStockIds(
    DbService db,
    Iterable<int> labelledStockIds,
  ) async {
    final ids = labelledStockIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) return;
    for (final id in ids) {
      try {
        await db.deleteItemLocally(id);
      } catch (e, st) {
        debugPrint('LabelStock local delete failed id=$id: $e\n$st');
      }
    }
  }

  /// Full wipe + re-download of Active/ApiActive labelled stock (Sparkle syncItems).
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
    } catch (e, st) {
      debugPrint('LabelStock sync failed: $e\n$st');
      try {
        await dbService.resetConnection();
      } catch (_) {}
    } finally {
      _syncing = false;
    }
  }

  /// Delivery Challan / Sample Out create — Sparkle: remove from stock + syncItems.
  static void afterStockOut({
    required PrefService prefService,
    required DbService dbService,
    required Iterable<int> labelledStockIds,
  }) {
    unawaited(() async {
      await removeLocalByLabelledStockIds(dbService, labelledStockIds);
      await syncFromServer(prefService: prefService, dbService: dbService);
    }());
  }

  /// Sample In — returned items become Active again on server; refresh local DB.
  static void afterStockIn({
    required PrefService prefService,
    required DbService dbService,
  }) {
    unawaited(syncFromServer(prefService: prefService, dbService: dbService));
  }
}
