import 'dart:async';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'pref_service.dart';
import 'sync_isolate.dart';

/// Runs product sync from WorkManager background (no UI progress).
class BackgroundSyncRunner {
  static Future<void> runOnce() async {
    final prefService = await PrefService.init();
    if (!prefService.isLoggedIn()) return;

    final employee = prefService.getEmployee();
    if (employee == null) return;

    final dbPath = p.join(await getDatabasesPath(), 'sparkle_rfid.db');
    final receivePort = ReceivePort();
    final completer = Completer<void>();

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final status = message['status'] as String? ?? '';
        if (status == 'completed' || status == 'error') {
          if (!completer.isCompleted) completer.complete();
          receivePort.close();
        }
      }
    });

    SyncIsolate.run({
      'token': null,
      'sendPort': receivePort.sendPort,
      'baseUrl': prefService.getCustomApi() ?? 'https://rrgold.loyalstring.co.in/',
      'clientCode': employee.clientCode ?? '',
      'roleId': employee.roleId ?? 0,
      'branchIds': prefService.getBranchIds(),
      'tokenStr': prefService.getToken() ?? '',
      'dbPath': dbPath,
      'tagType': prefService.getRfidType(),
      'allowSingleAndWebReusable': prefService.isWebReusableTagEnabled(),
    });

    await completer.future.timeout(
      const Duration(minutes: 30),
      onTimeout: () {
        if (!completer.isCompleted) completer.complete();
        receivePort.close();
      },
    );
  }
}
