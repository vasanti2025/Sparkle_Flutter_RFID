import 'package:workmanager/workmanager.dart';
import 'location_sync_runner.dart';
import 'pref_service.dart';

const String kLocationSyncWorker = 'location_sync_data_worker';

class LocationSyncService {
  static Future<void> initializeIfEnabled() async {
    final pref = await PrefService.init();
    if (pref.isLocationSyncEnabled()) {
      await applySettings(true);
    }
  }

  static Future<void> applySettings(bool enabled) async {
    if (enabled) {
      await Workmanager().registerPeriodicTask(
        kLocationSyncWorker,
        kLocationSyncWorker,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      await Workmanager().cancelByUniqueName(kLocationSyncWorker);
    }
  }

  static Future<void> syncNow() async {
    await LocationSyncRunner.runOnce();
  }
}
