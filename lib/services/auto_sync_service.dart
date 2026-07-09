import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'background_sync_runner.dart';
import 'location_sync_runner.dart';
import 'location_sync_service.dart';
import 'order_sync_runner.dart';
import 'order_sync_service.dart';
import 'pref_service.dart';

const String kSyncDataWorker = 'sync_data_worker';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (task == kSyncDataWorker) {
        await BackgroundSyncRunner.runOnce();
      } else if (task == kLocationSyncWorker) {
        await LocationSyncRunner.runOnce();
      } else if (task == kOrderSyncWorker) {
        await OrderSyncRunner.runOnce();
      }
    } catch (e) {
      debugPrint('Background task failed ($task): $e');
    }
    return true;
  });
}

class AutoSyncService {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
    final pref = await PrefService.init();
    if (pref.isAutosyncEnabled()) {
      await schedulePeriodicSync(pref.getAutosyncIntervalMin());
    }
  }

  static Future<void> schedulePeriodicSync(int intervalMinutes) async {
    final minutes = intervalMinutes.clamp(15, 1440);
    await Workmanager().registerPeriodicTask(
      kSyncDataWorker,
      kSyncDataWorker,
      frequency: Duration(minutes: minutes),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> cancelPeriodicSync() async {
    await Workmanager().cancelByUniqueName(kSyncDataWorker);
  }

  static Future<void> applySettings({required bool enabled, required int intervalMinutes}) async {
    if (enabled) {
      await schedulePeriodicSync(intervalMinutes);
    } else {
      await cancelPeriodicSync();
    }
  }
}
