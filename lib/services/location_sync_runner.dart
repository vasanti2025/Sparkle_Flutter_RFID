import 'package:flutter/foundation.dart';

import '../models/location_item.dart';
import 'api_service.dart';
import 'db_service.dart';
import 'location_service.dart';
import 'pref_service.dart';

class LocationSyncResult {
  final bool uploaded;
  final int serverCount;
  final String? error;

  const LocationSyncResult({
    required this.uploaded,
    required this.serverCount,
    this.error,
  });
}

class LocationSyncRunner {
  /// Match Sparkle: use employee.defaultBranchId for location APIs.
  static int _branchId(PrefService pref, {required int defaultBranchId}) {
    // Prefer employee default (Sparkle). Fall back to selected branch if default missing.
    if (defaultBranchId > 0) return defaultBranchId;
    final fromPref = pref.getBranchId();
    return fromPref > 0 ? fromPref : 0;
  }

  static int _userId({
    required int id,
    int? userId,
    int? employeeId,
  }) {
    if (id > 0) return id;
    if (userId != null && userId > 0) return userId;
    if (employeeId != null && employeeId > 0) return employeeId;
    return 0;
  }

  /// Upload current GPS then refresh local cache from server.
  static Future<LocationSyncResult> runOnce() async {
    final prefService = await PrefService.init();
    if (!prefService.isLoggedIn()) {
      return const LocationSyncResult(uploaded: false, serverCount: 0, error: 'Not logged in');
    }
    if (!prefService.isLocationSyncEnabled()) {
      return const LocationSyncResult(uploaded: false, serverCount: 0, error: 'Location sync disabled');
    }

    final employee = prefService.getEmployee();
    if (employee == null) {
      return const LocationSyncResult(uploaded: false, serverCount: 0, error: 'Employee not found');
    }

    final clientCode = (employee.clientCode ?? '').trim();
    final userId = _userId(id: employee.id, userId: employee.userId, employeeId: employee.employeeId);
    final branchId = _branchId(prefService, defaultBranchId: employee.defaultBranchId);
    if (clientCode.isEmpty || userId <= 0 || branchId <= 0) {
      final msg = 'Invalid ClientCode/UserId/BranchId: $clientCode / $userId / $branchId';
      debugPrint('LocationSync: $msg');
      return LocationSyncResult(uploaded: false, serverCount: 0, error: msg);
    }

    final reading = await LocationService.getCurrentLocation();
    if (reading == null) {
      debugPrint('LocationSync: GPS unavailable');
      // Still try to refresh list from server so older points remain visible.
      final count = await _refreshFromServer(
        prefService: prefService,
        clientCode: clientCode,
        userId: userId,
        branchId: branchId,
      );
      return LocationSyncResult(uploaded: false, serverCount: count, error: 'GPS unavailable');
    }

    final api = ApiService(prefService);
    final addError = await api.addClientLocation(
      clientCode: clientCode,
      userId: userId,
      branchId: branchId,
      latitude: reading.latitude,
      longitude: reading.longitude,
      address: reading.address,
    );
    final uploaded = addError == null;
    debugPrint('LocationSync: AddClientLocation => $uploaded (${reading.latitude},${reading.longitude}) err=$addError');

    // Brief delay so server can commit before Get.
    if (uploaded) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    var locations = await api.getClientLocations(
      clientCode: clientCode,
      userId: userId,
      branchId: branchId,
    );
    debugPrint('LocationSync: GetClientLocations => ${locations.length} rows');

    final db = DbService();
    if (locations.isNotEmpty) {
      await db.replaceAllLocations(locations);
    } else if (uploaded) {
      // Server accepted add but Get returned empty — keep today's point visible locally.
      final now = DateTime.now().toIso8601String();
      final local = LocationItem(
        id: DateTime.now().millisecondsSinceEpoch,
        clientCode: clientCode,
        userId: userId,
        branchId: branchId,
        latitude: reading.latitude,
        longitude: reading.longitude,
        address: reading.address,
        createdOn: now,
        lastUpdated: now,
        statusType: true,
      );
      final existing = await db.getAllLocations();
      await db.replaceAllLocations([local, ...existing]);
      locations = await db.getAllLocations();
    }
    // If get failed/empty and upload failed, leave existing DB rows alone (do not wipe).

    return LocationSyncResult(
      uploaded: uploaded,
      serverCount: locations.length,
      error: uploaded ? null : addError,
    );
  }

  /// Pull server locations into local DB without uploading GPS.
  static Future<List<LocationItem>> fetchFromServer() async {
    final prefService = await PrefService.init();
    final employee = prefService.getEmployee();
    if (employee == null) return [];

    final clientCode = (employee.clientCode ?? '').trim();
    final userId = _userId(id: employee.id, userId: employee.userId, employeeId: employee.employeeId);
    final branchId = _branchId(prefService, defaultBranchId: employee.defaultBranchId);
    if (clientCode.isEmpty || userId <= 0 || branchId <= 0) return [];

    return _loadAndMaybeReplace(
      prefService: prefService,
      clientCode: clientCode,
      userId: userId,
      branchId: branchId,
    );
  }

  static Future<int> _refreshFromServer({
    required PrefService prefService,
    required String clientCode,
    required int userId,
    required int branchId,
  }) async {
    final list = await _loadAndMaybeReplace(
      prefService: prefService,
      clientCode: clientCode,
      userId: userId,
      branchId: branchId,
    );
    return list.length;
  }

  static Future<List<LocationItem>> _loadAndMaybeReplace({
    required PrefService prefService,
    required String clientCode,
    required int userId,
    required int branchId,
  }) async {
    final api = ApiService(prefService);
    final locations = await api.getClientLocations(
      clientCode: clientCode,
      userId: userId,
      branchId: branchId,
    );
    final db = DbService();
    // Never wipe local history with an empty/failed response.
    if (locations.isNotEmpty) {
      await db.replaceAllLocations(locations);
      return locations;
    }
    return db.getAllLocations();
  }
}
