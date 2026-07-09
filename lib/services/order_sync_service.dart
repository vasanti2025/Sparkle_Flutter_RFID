import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'order_sync_runner.dart';
import 'pref_service.dart';

const String kOrderSyncWorker = 'order_sync_data_worker';

/// Syncs pending customers and orders when internet is available.
class OrderSyncService {
  static Future<void> initializeIfEnabled() async {
    final pref = await PrefService.init();
    if (pref.isLoggedIn()) {
      await applySettings(true);
    }
  }

  static Future<void> applySettings(bool enabled) async {
    if (enabled) {
      await Workmanager().registerPeriodicTask(
        kOrderSyncWorker,
        kOrderSyncWorker,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      await Workmanager().cancelByUniqueName(kOrderSyncWorker);
    }
  }

  static Future<int> syncNow() async {
    try {
      return await OrderSyncRunner.runOnce();
    } catch (e, st) {
      debugPrint('OrderSyncService error: $e\n$st');
      return 0;
    }
  }
}
