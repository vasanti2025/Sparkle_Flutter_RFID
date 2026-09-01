import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/location_item.dart';
import '../models/wholesale_master.dart';
import '../services/api_service.dart';
import '../services/auto_sync_service.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';
import '../services/location_sync_service.dart';
import '../services/location_service.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';

class SettingsViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final DbService _dbService;
  final ApiService _apiService;

  SettingsViewModel({
    required PrefService prefService,
    required DbService dbService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _dbService = dbService,
        _apiService = apiService {
    RfidService().addConnectionListener(_onRfidConnectionChanged);
  }

  void _onRfidConnectionChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    RfidService().removeConnectionListener(_onRfidConnectionChanged);
    super.dispose();
  }

  PrefService get pref => _prefService;

  List<LocationItem> _locations = [];
  List<LocationItem> get locations => _locations;

  bool _loadingLocations = false;
  bool get loadingLocations => _loadingLocations;

  int getPower(String key) => _prefService.getPower(key);

  bool get locationSyncEnabled => _prefService.isLocationSyncEnabled();

  Future<void> savePower(String key, int value) async {
    await _prefService.savePower(key, value);
    notifyListeners();
  }

  Future<void> saveSheetUrl(String url) async {
    await _prefService.saveSheetUrl(url);
    notifyListeners();
  }

  Future<void> saveStockTransferUrl(String url) async {
    await _prefService.saveStockTransferUrl(url);
    notifyListeners();
  }

  Future<void> saveCustomApi(String url) async {
    await _prefService.saveCustomApi(url);
    notifyListeners();
  }

  Future<void> saveBackupEmail(String email) async {
    await _prefService.saveBackupEmail(email);
    notifyListeners();
  }

  Future<void> setAutosync(bool enabled, int intervalMin) async {
    await _prefService.setAutosyncEnabled(enabled);
    await _prefService.setAutosyncIntervalMin(intervalMin);
    await AutoSyncService.applySettings(enabled: enabled, intervalMinutes: intervalMin);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _prefService.setNotificationsEnabled(value);
    notifyListeners();
  }

  Future<bool> setLocationSyncEnabled(bool enabled) async {
    await _prefService.setLocationSyncEnabled(enabled);
    await LocationSyncService.applySettings(enabled);
    notifyListeners();
    if (!enabled) return true;

    // Don't block Settings UI on GPS/network — sync in background.
    Future<void>(() async {
      final reading = await LocationService.getCurrentLocation();
      if (reading == null) {
        await _prefService.setLocationSyncEnabled(false);
        await LocationSyncService.applySettings(false);
        notifyListeners();
        return;
      }
      await LocationSyncService.syncNow();
      await fetchLocationsFromDb();
    });
    return true;
  }

  Future<void> fetchLocationsFromDb() async {
    _loadingLocations = true;
    notifyListeners();
    _locations = await _dbService.getAllLocations();
    _loadingLocations = false;
    notifyListeners();
  }

  int _resolveBranchId(int defaultBranchId) {
    // Same as Sparkle location APIs: employee default branch first.
    if (defaultBranchId > 0) return defaultBranchId;
    final fromPref = _prefService.getBranchId();
    return fromPref > 0 ? fromPref : 0;
  }

  /// Upload current location (if sync enabled), then load server list into UI.
  Future<String?> syncAndRefreshLocations() async {
    _loadingLocations = true;
    notifyListeners();
    String? error;
    try {
      if (_prefService.isLocationSyncEnabled()) {
        final result = await LocationSyncService.syncNow();
        error = result.error;
      } else {
        final employee = _prefService.getEmployee();
        if (employee != null) {
          final branchId = _resolveBranchId(employee.defaultBranchId);
          final list = await _apiService.getClientLocations(
            clientCode: employee.clientCode ?? '',
            userId: employee.id > 0 ? employee.id : (employee.userId ?? 0),
            branchId: branchId,
          );
          if (list.isNotEmpty) {
            await _dbService.replaceAllLocations(list);
          }
        }
      }
      _locations = await _dbService.getAllLocations();
    } finally {
      _loadingLocations = false;
      notifyListeners();
    }
    return error;
  }

  /// Loads location history from the server into local DB, then updates the list UI.
  /// Does not clear local rows when the server returns an empty list.
  Future<void> refreshLocationsFromServer() async {
    final employee = _prefService.getEmployee();
    if (employee == null) return;
    _loadingLocations = true;
    notifyListeners();
    try {
      final branchId = _resolveBranchId(employee.defaultBranchId);
      final userId = employee.id > 0 ? employee.id : (employee.userId ?? 0);
      final list = await _apiService.getClientLocations(
        clientCode: employee.clientCode ?? '',
        userId: userId,
        branchId: branchId,
      );
      if (list.isNotEmpty) {
        await _dbService.replaceAllLocations(list);
      }
      _locations = await _dbService.getAllLocations();
    } finally {
      _loadingLocations = false;
      notifyListeners();
    }
  }

  Future<FileInfo> saveBackupToDevice() async {
    final file = await BackupService.saveToDevice();
    return FileInfo(file.path);
  }

  Future<void> sendBackupEmail(String email) async {
    await _prefService.saveBackupEmail(email);
    await BackupService.sendViaEmail(email);
  }

  Future<void> restoreBackup() async {
    final picked = await BackupService.pickRestoreFile();
    if (picked == null) return;
    await _dbService.resetConnection();
    await BackupService.restoreFromFile(picked);
    await _dbService.resetConnection();
  }

  Future<bool> clearAllData(String password) async {
    if (password != _prefService.getSavedPassword()) return false;
    await _dbService.clearAllLocalData();
    await _prefService.clearAll();
    await AutoSyncService.cancelPeriodicSync();
    await LocationSyncService.applySettings(false);
    return true;
  }

  bool get webReusableTagEnabled => _prefService.isWebReusableTagEnabled();
  bool get localWifiModeEnabled => _prefService.isLocalWifiModeEnabled();

  Future<void> setWebReusableTagEnabled(bool value) async {
    await _prefService.setWebReusableTagEnabled(value);
    notifyListeners();
  }

  Future<void> setLocalWifiModeEnabled(bool value) async {
    await _prefService.setLocalWifiModeEnabled(value);
    notifyListeners();
  }

  bool get trayModeEnabled => _prefService.isTrayModeEnabled();
  String get trayDeviceName => _prefService.getTrayDeviceName();
  String get trayDeviceAddress => _prefService.getTrayDeviceAddress();
  bool get trayConnected => RfidService().trayConnected;
  bool get trayConnecting => RfidService().trayConnecting;

  bool get r6ModeEnabled => _prefService.isR6ModeEnabled();
  String get r6DeviceName => _prefService.getR6DeviceName();
  String get r6DeviceAddress => _prefService.getR6DeviceAddress();
  bool get r6Connected => RfidService().r6Connected;
  bool get r6Connecting => RfidService().r6Connecting;

  Future<List<Map<String, String>>> listBondedTrayDevices() {
    return RfidService().listBondedBluetoothDevices();
  }

  Future<bool> setTrayModeEnabled(bool value) async {
    await _prefService.setTrayModeEnabled(value);
    if (value) {
      await RfidService().applyR6Mode(enabled: false);
    }
    final address = value ? _prefService.getTrayDeviceAddress() : '';
    await RfidService().applyTrayMode(enabled: value, address: address);
    if (value && address.isNotEmpty) {
      await RfidService().waitForBleConnection(
        isR6: false,
        timeout: const Duration(seconds: 20),
      );
    }
    notifyListeners();
    return RfidService().trayConnected || !value || address.isEmpty;
  }

  Future<void> selectTrayDevice({
    required String name,
    required String address,
  }) async {
    await _prefService.saveTrayDevice(name: name, address: address);
    if (_prefService.isTrayModeEnabled()) {
      await RfidService().applyTrayMode(enabled: true, address: address);
      await RfidService().waitForBleConnection(
        isR6: false,
        timeout: const Duration(seconds: 20),
      );
    }
    notifyListeners();
  }

  Future<void> refreshTrayStatus() async {
    await RfidService().getTrayStatus();
    notifyListeners();
  }

  Future<bool> setR6ModeEnabled(bool value) async {
    await _prefService.setR6ModeEnabled(value);
    if (value) {
      await RfidService().applyTrayMode(enabled: false);
    }
    final address = value ? _prefService.getR6DeviceAddress() : '';
    await RfidService().applyR6Mode(enabled: value, address: address);
    if (value && address.isNotEmpty) {
      await RfidService().waitForBleConnection(
        isR6: true,
        timeout: const Duration(seconds: 20),
      );
    }
    notifyListeners();
    return RfidService().r6Connected || !value || address.isEmpty;
  }

  Future<void> selectR6Device({
    required String name,
    required String address,
  }) async {
    await _prefService.saveR6Device(name: name, address: address);
    if (_prefService.isR6ModeEnabled()) {
      await RfidService().applyR6Mode(enabled: true, address: address);
      await RfidService().waitForBleConnection(
        isR6: true,
        timeout: const Duration(seconds: 20),
      );
    }
    notifyListeners();
  }

  Future<void> refreshR6Status() async {
    await RfidService().getR6Status();
    notifyListeners();
  }

  List<WholesaleBranch> _wholesaleBranches = [];
  List<WholesaleBranch> get wholesaleBranches => _wholesaleBranches;

  List<WholesaleCounter> _wholesaleCounters = [];
  List<WholesaleCounter> get wholesaleCounters => _wholesaleCounters;

  bool _loadingWholesale = false;
  bool get loadingWholesale => _loadingWholesale;

  bool _savingWholesale = false;
  bool get savingWholesale => _savingWholesale;

  String? _wholesaleError;
  String? get wholesaleError => _wholesaleError;

  /// Master counters for a branch from GetAllCounters (BranchId match).
  List<WholesaleCounter> countersForBranch(int? branchId, {String branchName = ''}) {
    if (branchId == null || branchId <= 0) {
      return List<WholesaleCounter>.from(_wholesaleCounters);
    }
    // Strict: only counters belonging to this BranchId (e.g. Counter1/2/3 for Branch 1).
    final filtered = _wholesaleCounters.where((c) => c.branchId == branchId).toList();
    if (filtered.isNotEmpty) {
      filtered.sort((a, b) => a.name.compareTo(b.name));
      return filtered;
    }
    // Fallback: counters with no BranchId set.
    final unscoped = _wholesaleCounters.where((c) => c.branchId <= 0).toList();
    return unscoped.isNotEmpty ? unscoped : const [];
  }

  /// True when GetRFID returned data for this handset's stable DeviceId.
  bool get hasDeviceAssignments =>
      _stableDeviceId.isNotEmpty && _wholesaleAssignments.isNotEmpty;

  /// Branches registered for THIS DeviceId only (Scan + Wholesale view).
  List<WholesaleBranch> get assignedBranchesForDevice {
    final fromAssign = <String, WholesaleBranch>{};
    for (final assignment in _wholesaleAssignments) {
      if (!assignment.hasBranch) continue;
      final branch = _resolvedBranch(assignment);
      final key = branch.id > 0 ? 'id:${branch.id}' : 'name:${branch.name.toLowerCase()}';
      fromAssign[key] = branch;
    }
    return fromAssign.values.toList();
  }

  /// Counters registered for THIS DeviceId + selected branch only.
  List<WholesaleCounter> assignedCountersForBranch(int? branchId, {String branchName = ''}) {
    final fromAssign = <String, WholesaleCounter>{};
    for (final assignment in _wholesaleAssignments) {
      if (!assignment.hasCounter) continue;
      if (!_assignmentMatchesBranch(assignment, branchId, branchName: branchName)) {
        continue;
      }
      final counter = _resolvedCounter(assignment);
      final key = counter.id > 0
          ? 'id:${counter.branchId}:${counter.id}'
          : 'name:${counter.branchId}:${counter.name.toLowerCase()}';
      fromAssign[key] = counter;
    }
    return fromAssign.values.toList();
  }

  List<RfidDeviceAssignment> assignmentsForBranch(int? branchId, {String branchName = ''}) {
    return _wholesaleAssignments
        .where((a) => _assignmentMatchesBranch(a, branchId, branchName: branchName))
        .toList();
  }

  WholesaleBranch _resolvedBranch(RfidDeviceAssignment assignment) {
    // Prefer assignment name/id from DeviceCode API — master list can rename
    // (e.g. BranchId 2 → "Main Branch" while assignment says "1007").
    var id = assignment.branchId;
    var name = assignment.branchName.trim();
    if (id > 0) {
      for (final branch in _wholesaleBranches) {
        if (branch.id != id) continue;
        if (name.isEmpty) name = branch.name;
        break;
      }
    } else if (name.isNotEmpty) {
      for (final branch in _wholesaleBranches) {
        if (branch.name.trim().toLowerCase() != name.toLowerCase()) continue;
        id = branch.id;
        break;
      }
    }
    return WholesaleBranch(id: id, name: name);
  }

  WholesaleCounter _resolvedCounter(RfidDeviceAssignment assignment) {
    final branch = _resolvedBranch(assignment);
    var id = assignment.counterId;
    var name = assignment.counterName.trim();
    if (id > 0) {
      for (final counter in _wholesaleCounters) {
        if (counter.id != id) continue;
        if (name.isEmpty) name = counter.name;
        break;
      }
    } else if (name.isNotEmpty) {
      for (final counter in _wholesaleCounters) {
        if (counter.name.trim().toLowerCase() != name.toLowerCase()) continue;
        if (branch.id > 0 && counter.branchId > 0 && counter.branchId != branch.id) {
          continue;
        }
        id = counter.id;
        break;
      }
    }
    return WholesaleCounter(id: id, name: name, branchId: branch.id);
  }

  bool _assignmentMatchesBranch(RfidDeviceAssignment assignment, int? branchId, {String branchName = ''}) {
    if (branchId == null || branchId <= 0) {
      final name = branchName.trim().toLowerCase();
      if (name.isEmpty) return true;
      return assignment.branchName.trim().toLowerCase() == name;
    }
    final resolved = _resolvedBranch(assignment);
    if (resolved.id > 0) return resolved.id == branchId;
    return assignment.branchId == branchId;
  }

  /// Scan Display: only branches for matching DeviceId.
  List<WholesaleBranch> get scanPopupBranches => assignedBranchesForDevice;

  /// Scan Display: only counters for that branch on matching DeviceId.
  List<WholesaleCounter> scanPopupCountersFor(int? branchId, {String branchName = ''}) {
    if (_stableDeviceId.isEmpty) return const [];
    return assignedCountersForBranch(branchId, branchName: branchName);
  }

  Future<String> ensureDeviceId() async {
    var id = _prefService.getDeviceId().trim();
    if (id.isEmpty) {
      final fromEmployee = _prefService.getEmployee()?.deviceId?.trim() ?? '';
      if (fromEmployee.isNotEmpty) {
        id = fromEmployee;
      } else {
        final rand = Random.secure();
        final values = List<int>.generate(16, (i) => rand.nextInt(256));
        id = values.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
      }
      await _prefService.saveDeviceId(id);
    }
    return id;
  }

  List<RfidDeviceAssignment> _wholesaleAssignments = [];
  List<RfidDeviceAssignment> get wholesaleAssignments => _wholesaleAssignments;

  /// Stable handset id for API `DeviceId` — never regenerated once saved.
  String _stableDeviceId = '';
  String get stableDeviceId => _stableDeviceId;

  /// API `DeviceCode` for this handset — short codes like "1", "2", ...
  String _rfidDeviceCode = '';
  String get rfidDeviceCode => _rfidDeviceCode;

  Object? get rfidApiDeviceId => _stableDeviceId.isNotEmpty ? _stableDeviceId : null;

  Future<void> loadWholesaleMasters() async {
    _loadingWholesale = true;
    _wholesaleError = null;
    notifyListeners();
    try {
      final clientCode = _prefService.getEmployee()?.clientCode ?? '';
      if (clientCode.isEmpty) {
        _wholesaleBranches = [];
        _wholesaleCounters = [];
        _wholesaleAssignments = _prefService.getWholesaleAssignments();
        _wholesaleError = 'deviceConfigNotFound';
        return;
      }
      final stableId = await ensureDeviceId();
      final results = await Future.wait([
        _apiService.getWholesaleBranches(clientCode),
        _apiService.getAllCounters(clientCode),
        _loadDeviceAndAssignments(clientCode, stableId),
      ]);
      _wholesaleBranches = results[0] as List<WholesaleBranch>;
      _wholesaleCounters = results[1] as List<WholesaleCounter>;
    } catch (e) {
      _wholesaleError = e.toString();
    } finally {
      _loadingWholesale = false;
      notifyListeners();
    }
  }

  bool _deviceMatches(RfidDeviceInfo device, String storedId) {
    final stored = storedId.trim().toLowerCase();
    if (stored.isEmpty) return false;
    final ids = <String>[
      device.deviceId.trim().toLowerCase(),
      device.deviceCode.trim().toLowerCase(),
      if (device.id > 0) device.id.toString(),
    ].where((id) => id.isNotEmpty).toList();
    for (final id in ids) {
      if (id == stored) return true;
      if (id.length >= 4 &&
          stored.length >= 4 &&
          (stored.endsWith(id) || id.endsWith(stored))) {
        return true;
      }
    }
    if (stored.length >= 2) {
      final short = 'a${stored.substring(stored.length - 2)}';
      if (ids.contains(short)) return true;
    }
    return false;
  }

  List<RfidDeviceAssignment> _uniqueAssignments(Iterable<RfidDeviceAssignment> items) {
    final seen = <String>{};
    final out = <RfidDeviceAssignment>[];
    for (final item in items) {
      if (!item.isValid) continue;
      final key =
          '${item.branchId}|${item.counterId}|${item.branchName.toLowerCase()}|${item.counterName.toLowerCase()}';
      if (seen.add(key)) out.add(item);
    }
    return out;
  }

  String _deviceCodeFromMatch(RfidDeviceInfo device) {
    final code = device.deviceCode.trim();
    if (code.isNotEmpty) return code;
    if (device.id > 0) return '${device.id}';
    final asInt = int.tryParse(device.deviceId.trim());
    if (asInt != null && asInt > 0) return '$asInt';
    return '';
  }

  Future<List<RfidDeviceAssignment>> _loadDeviceAndAssignments(
    String clientCode,
    String stableDeviceId,
  ) async {
    // DeviceId = stable handset id (never changes). All branch/counters key off this.
    final stableId = stableDeviceId.trim();
    _stableDeviceId = stableId;
    var resolvedCode = _rfidDeviceCode;

    final devices = await _apiService.getAllRFIDDevices(
      clientCode,
      deviceCode: stableId,
    );
    RfidDeviceInfo? matched;
    for (final device in devices) {
      if (_deviceMatches(device, stableId)) {
        matched = device;
        break;
      }
    }
    if (matched == null && stableId.isNotEmpty) {
      matched = await _apiService.getRFIDDeviceById(
        clientCode: clientCode,
        deviceId: stableId,
      );
    }
    if (matched != null) {
      final code = _deviceCodeFromMatch(matched);
      if (code.isNotEmpty) resolvedCode = code;
    }
    _rfidDeviceCode = resolvedCode;

    debugPrint(
      'GetRFIDDeviceAssignments DeviceCode=$stableId (device stable id)',
    );

    // Swagger: DeviceCode = this device's id — all branch/counters for it.
    var assignments = await _apiService.getRFIDDeviceAssignments(
      clientCode: clientCode,
      deviceCode: stableId,
    );
    if (assignments.isEmpty && matched != null && matched.assignments.isNotEmpty) {
      assignments = matched.assignments;
    }

    // Prefs only if saved for the SAME DeviceId — never another device's data.
    if (assignments.isEmpty) {
      final prefsDeviceId = _prefService.getDeviceId().trim();
      if (prefsDeviceId.isNotEmpty &&
          prefsDeviceId.toLowerCase() == stableId.toLowerCase()) {
        assignments = _prefService.getWholesaleAssignments();
      }
    }

    assignments = _uniqueAssignments(assignments);
    _wholesaleAssignments = assignments;
    debugPrint(
      'DeviceId=$stableId assignments=${assignments.length} '
      'branches=${assignedBranchesForDevice.length}',
    );
    return assignments;
  }

  int _resolveWholesaleBranchId(int branchId, String branchName) {
    if (branchId > 0) return branchId;
    final name = branchName.trim().toLowerCase();
    if (name.isEmpty) return 0;
    for (final b in _wholesaleBranches) {
      if (b.name.trim().toLowerCase() == name) return b.id;
    }
    return 0;
  }

  Future<bool> saveWholesaleOption({
    required int branchId,
    required String branchName,
    required int counterId,
    required String counterName,
    required String deviceId,
    List<RfidDeviceAssignment>? assignments,
  }) async {
    final employee = _prefService.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    debugPrint('========== Wholesale SAVE start ==========');
    debugPrint('clientCode=$clientCode deviceId=$deviceId');
    debugPrint('branchId=$branchId branchName=$branchName');
    debugPrint(
      'incomingAssignments=${assignments?.map((a) => '${a.branchId}/${a.counterId}:${a.counterName}').toList()}',
    );

    if (clientCode.isEmpty || deviceId.trim().isEmpty) {
      debugPrint('Wholesale SAVE aborted: missing clientCode or deviceId');
      return false;
    }

    final resolvedBranchId = _resolveWholesaleBranchId(branchId, branchName);
    final rows = <RfidDeviceAssignment>[];
    for (final a in (assignments ?? const <RfidDeviceAssignment>[])) {
      if (!a.hasCounter) continue;
      final bid = _resolveWholesaleBranchId(
        a.branchId,
        a.branchName.isNotEmpty ? a.branchName : branchName,
      );
      final bname = a.branchName.trim().isNotEmpty ? a.branchName.trim() : branchName.trim();
      final cid = a.counterId > 0 ? a.counterId : 0;
      if (bid <= 0 || cid <= 0) {
        debugPrint(
          'Wholesale SAVE skip row: need BranchId>0 and CounterId>0 '
          '(got branchId=$bid counterId=$cid name=${a.counterName})',
        );
        continue;
      }
      rows.add(RfidDeviceAssignment(
        branchId: bid,
        branchName: bname,
        counterId: cid,
        counterName: a.counterName,
      ));
    }
    if (rows.isEmpty && resolvedBranchId > 0 && counterId > 0) {
      rows.add(RfidDeviceAssignment(
        branchId: resolvedBranchId,
        branchName: branchName,
        counterId: counterId,
        counterName: counterName,
      ));
    }
    if (rows.isEmpty) {
      debugPrint(
        'Wholesale SAVE aborted: no valid rows (BranchId + CounterId required). '
        'resolvedBranchId=$resolvedBranchId',
      );
      return false;
    }

    _savingWholesale = true;
    notifyListeners();
    try {
      final stableId = deviceId.trim().isNotEmpty ? deviceId.trim() : await ensureDeviceId();
      if (_stableDeviceId != stableId) {
        await _loadDeviceAndAssignments(clientCode, stableId);
      }

      // Keep other branches for this DeviceId; replace only the edited branch rows.
      final editedBranchId = rows.first.branchId;
      final editedBranchName = rows.first.branchName.trim().toLowerCase();
      final others = _wholesaleAssignments.where((a) {
        if (editedBranchId > 0 && a.branchId > 0) {
          return a.branchId != editedBranchId;
        }
        return a.branchName.trim().toLowerCase() != editedBranchName;
      }).toList();
      final merged = _uniqueAssignments([...others, ...rows]);

      // Send ALL branches/counters for this DeviceCode so none are dropped.
      // Swagger: { BranchId: 1, CounterId: [3,4,5] } with ReplaceAll true.
      // ignore: avoid_print
      print(
        'Wholesale SAVE calling Assign DeviceCode=$stableId '
        'rows=${rows.length} merged=${merged.length} replaceAll=true',
      );
      for (final r in merged) {
        // ignore: avoid_print
        print('  -> BranchId=${r.branchId} CounterId=${r.counterId} (${r.counterName})');
      }

      final ok = await _apiService.assignRFIDDeviceToBranchCounter(
        clientCode: clientCode,
        deviceCode: stableId,
        deviceId: stableId,
        replaceAll: true,
        assignments: merged,
      );
      // ignore: avoid_print
      print('Wholesale SAVE Assign result=$ok');
      if (!ok) return false;

      final first = rows.first;
      await _prefService.saveWholesaleOption(
        branchId: first.branchId,
        branchName: first.branchName,
        counterId: first.counterId,
        counterName: first.counterName,
        deviceId: stableId,
        assignments: merged,
      );

      // Reload GetRFID for this DeviceId so Scan/Wholesale see all counters.
      await _loadDeviceAndAssignments(clientCode, stableId);
      notifyListeners();
      return true;
    } finally {
      _savingWholesale = false;
      notifyListeners();
    }
  }

  Future<bool> deleteWholesaleBranch(int branchId) async {
    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    if (clientCode.isEmpty || branchId <= 0) return false;
    _savingWholesale = true;
    notifyListeners();
    try {
      final ok = await _apiService.deleteBranch(
        clientCode: clientCode,
        id: branchId,
      );
      if (!ok) return false;
      await loadWholesaleMasters();
      return true;
    } finally {
      _savingWholesale = false;
      notifyListeners();
    }
  }

  Future<bool> deleteWholesaleCounter(int counterId) async {
    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    if (clientCode.isEmpty || counterId <= 0) return false;
    _savingWholesale = true;
    notifyListeners();
    try {
      final ok = await _apiService.deleteCounter(
        clientCode: clientCode,
        id: counterId,
      );
      if (!ok) return false;
      await loadWholesaleMasters();
      return true;
    } finally {
      _savingWholesale = false;
      notifyListeners();
    }
  }
}

class FileInfo {
  final String path;
  FileInfo(this.path);
}
