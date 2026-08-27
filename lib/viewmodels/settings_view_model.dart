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
        _apiService = apiService;

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

  bool get r6ModeEnabled => _prefService.isR6ModeEnabled();
  String get r6DeviceName => _prefService.getR6DeviceName();
  String get r6DeviceAddress => _prefService.getR6DeviceAddress();
  bool get r6Connected => RfidService().r6Connected;

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
      await RfidService().waitForBleConnection(isR6: false);
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
      await RfidService().waitForBleConnection(isR6: false);
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
      await RfidService().waitForBleConnection(isR6: true);
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
      await RfidService().waitForBleConnection(isR6: true);
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

  List<WholesaleCounter> countersForBranch(int? branchId) {
    if (branchId == null || branchId <= 0) return _wholesaleCounters;
    final filtered = _wholesaleCounters
        .where((c) => c.branchId == 0 || c.branchId == branchId)
        .toList();
    return filtered.isNotEmpty ? filtered : _wholesaleCounters;
  }

  List<WholesaleBranch> get scanPopupBranches {
    final fromAssign = <int, WholesaleBranch>{};
    for (final assignment in _wholesaleAssignments) {
      if (assignment.branchId <= 0) continue;
      fromAssign[assignment.branchId] = WholesaleBranch(
        id: assignment.branchId,
        name: assignment.branchName,
      );
    }
    if (fromAssign.isNotEmpty) return fromAssign.values.toList();
    return _wholesaleBranches;
  }

  List<WholesaleCounter> scanPopupCountersFor(int? branchId) {
    final fromAssign = <int, WholesaleCounter>{};
    for (final assignment in _wholesaleAssignments) {
      if (assignment.counterId <= 0) continue;
      if (branchId != null &&
          branchId > 0 &&
          assignment.branchId > 0 &&
          assignment.branchId != branchId) {
        continue;
      }
      fromAssign[assignment.counterId] = WholesaleCounter(
        id: assignment.counterId,
        name: assignment.counterName,
        branchId: assignment.branchId,
      );
    }
    if (fromAssign.isNotEmpty) return fromAssign.values.toList();
    return countersForBranch(branchId);
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

  Object? _rfidApiDeviceId;
  Object? get rfidApiDeviceId => _rfidApiDeviceId;

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
      final deviceId = await ensureDeviceId();
      final results = await Future.wait([
        _apiService.getWholesaleBranches(clientCode),
        _apiService.getAllCounters(clientCode),
        _loadDeviceAndAssignments(clientCode, deviceId),
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
    return device.deviceId.trim().toLowerCase() == stored ||
        device.deviceCode.trim().toLowerCase() == stored ||
        device.id.toString() == storedId.trim();
  }

  Future<List<RfidDeviceAssignment>> _loadDeviceAndAssignments(
    String clientCode,
    String storedDeviceCode,
  ) async {
    final deviceCode = storedDeviceCode.trim();
    _rfidApiDeviceId = deviceCode;
    var assignments = <RfidDeviceAssignment>[];

    assignments = await _apiService.getRFIDDeviceAssignments(
      clientCode: clientCode,
      deviceCode: deviceCode,
      deviceId: int.tryParse(deviceCode) ?? 0,
    );

    if (assignments.isEmpty) {
      final devices = await _apiService.getAllRFIDDevices(clientCode);
      RfidDeviceInfo? matched;
      for (final device in devices) {
        if (_deviceMatches(device, deviceCode)) {
          matched = device;
          break;
        }
      }
      if (matched != null) {
        assignments = matched.assignments;
        final matchedCode = matched.deviceCode.trim().isNotEmpty
            ? matched.deviceCode.trim()
            : deviceCode;
        _rfidApiDeviceId = matchedCode;
        if (assignments.isEmpty) {
          assignments = await _apiService.getRFIDDeviceAssignments(
            clientCode: clientCode,
            deviceCode: matchedCode,
            deviceId: matched.id,
          );
        }
      }
    }

    if (assignments.isEmpty) {
      assignments = _prefService.getWholesaleAssignments();
    }
    _wholesaleAssignments = assignments;
    return assignments;
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
    if (clientCode.isEmpty || deviceId.trim().isEmpty) return false;

    final rows = (assignments ?? const <RfidDeviceAssignment>[]).where((a) => a.isValid).toList();
    if (rows.isEmpty) {
      rows.add(RfidDeviceAssignment(
        branchId: branchId,
        branchName: branchName,
        counterId: counterId,
        counterName: counterName,
      ));
    }
    if (rows.every((a) => !a.isValid)) return false;

    _savingWholesale = true;
    notifyListeners();
    try {
      final numericDeviceId = _rfidApiDeviceId is int
          ? _rfidApiDeviceId as int
          : int.tryParse('${_rfidApiDeviceId ?? ''}') ?? 0;
      final ok = await _apiService.assignRFIDDeviceToBranchCounter(
        clientCode: clientCode,
        deviceCode: deviceId.trim(),
        deviceId: numericDeviceId,
        replaceAll: false,
        assignments: rows,
      );
      if (!ok) return false;
      final first = rows.first;
      await _prefService.saveWholesaleOption(
        branchId: first.branchId,
        branchName: first.branchName,
        counterId: first.counterId,
        counterName: first.counterName,
        deviceId: deviceId.trim(),
        assignments: rows,
      );
      _wholesaleAssignments = rows;
      notifyListeners();
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
