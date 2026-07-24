import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'location_sync_runner.dart';
import 'pref_service.dart';

const String kLocationSyncWorker = 'location_sync_data_worker';

/// Uploads GPS every 15 minutes (foreground timer + background Workmanager)
/// and keeps the location list filled from the server.
class LocationSyncService {
  static Timer? _foregroundTimer;
  static bool _syncInFlight = false;

  static Future<void> initializeIfEnabled() async {
    final pref = await PrefService.init();
    if (!pref.isLocationSyncEnabled()) return;
    await applySettings(true);
    // Delay first GPS upload so cold start / navigation stays responsive.
    if (pref.isLoggedIn()) {
      Future<void>.delayed(const Duration(seconds: 25), () {
        unawaited(syncNow().then((_) {}));
      });
    }
  }

  static Future<void> applySettings(bool enabled) async {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;

    if (enabled) {
      // Reliable while app is open (Workmanager alone is often delayed/killed).
      _foregroundTimer = Timer.periodic(const Duration(minutes: 15), (_) {
        unawaited(syncNow().then((_) {}));
      });

      try {
        await Workmanager().registerPeriodicTask(
          kLocationSyncWorker,
          kLocationSyncWorker,
          frequency: const Duration(minutes: 15),
          // First background run soon; foreground timer + syncNow cover immediate need.
          initialDelay: const Duration(minutes: 1),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        );
      } catch (e) {
        debugPrint('LocationSyncService: Workmanager register failed: $e');
      }
    } else {
      try {
        await Workmanager().cancelByUniqueName(kLocationSyncWorker);
      } catch (e) {
        debugPrint('LocationSyncService: Workmanager cancel failed: $e');
      }
    }
  }

  static Future<LocationSyncResult> syncNow() async {
    if (_syncInFlight) {
      return const LocationSyncResult(uploaded: false, serverCount: 0, error: 'Sync already running');
    }
    _syncInFlight = true;
    try {
      return await LocationSyncRunner.runOnce();
    } catch (e, st) {
      debugPrint('LocationSyncService.syncNow error: $e\n$st');
      return LocationSyncResult(uploaded: false, serverCount: 0, error: e.toString());
    } finally {
      _syncInFlight = false;
    }
  }
}
