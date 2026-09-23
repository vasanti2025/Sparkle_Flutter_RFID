import 'dart:async';

import 'package:flutter/foundation.dart';

import 'services/auto_sync_service.dart';
import 'services/db_service.dart';
import 'services/location_sync_service.dart';
import 'services/order_sync_service.dart';
import 'services/pref_service.dart';
import 'services/rfid_service.dart';

Future<void> warmAfterFirstFrame(
  PrefService prefService,
  DbService? dbService,
) async {
  if (dbService != null) {
    try {
      await dbService.database;
    } catch (e, st) {
      debugPrint('DB init deferred error: $e\n$st');
    }
  }

  Future<void>.delayed(const Duration(seconds: 3), () async {
    try {
      await AutoSyncService.initialize();
    } catch (e, st) {
      debugPrint('AutoSync init skipped: $e\n$st');
    }
  });

  Future<void>.delayed(const Duration(seconds: 8), () async {
    try {
      await LocationSyncService.initializeIfEnabled();
    } catch (e, st) {
      debugPrint('LocationSync init skipped: $e\n$st');
    }
  });

  Future<void>.delayed(const Duration(seconds: 12), () async {
    try {
      await OrderSyncService.initializeIfEnabled();
    } catch (e, st) {
      debugPrint('OrderSync init skipped: $e\n$st');
    }
  });

  Future<void>.delayed(const Duration(seconds: 2), () async {
    try {
      await RfidService().autoAttachSystemBluetoothReader();
    } catch (e, st) {
      debugPrint('Tray/R6 auto-attach skipped: $e\n$st');
    }
  });
}
