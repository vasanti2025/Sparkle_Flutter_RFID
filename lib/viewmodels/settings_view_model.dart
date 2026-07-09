import 'package:flutter/foundation.dart';
import '../models/location_item.dart';
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
    if (enabled) {
      final reading = await LocationService.getCurrentLocation();
      if (reading == null) {
        await _prefService.setLocationSyncEnabled(false);
        await LocationSyncService.applySettings(false);
        notifyListeners();
        return false;
      }
      await LocationSyncService.syncNow();
    }
    notifyListeners();
    return true;
  }

  Future<void> fetchLocationsFromDb() async {
    _loadingLocations = true;
    notifyListeners();
    _locations = await _dbService.getAllLocations();
    _loadingLocations = false;
    notifyListeners();
  }

  Future<void> refreshLocationsFromServer() async {
    final employee = _prefService.getEmployee();
    if (employee == null) return;
    final list = await _apiService.getClientLocations(
      clientCode: employee.clientCode ?? '',
      userId: employee.id,
      branchId: employee.defaultBranchId,
    );
    await _dbService.replaceAllLocations(list);
    await fetchLocationsFromDb();
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

  Future<List<Map<String, String>>> listBondedTrayDevices() {
    return RfidService().listBondedBluetoothDevices();
  }

  Future<bool> setTrayModeEnabled(bool value) async {
    await _prefService.setTrayModeEnabled(value);
    final address = value ? _prefService.getTrayDeviceAddress() : '';
    await RfidService().applyTrayMode(enabled: value, address: address);
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
    }
    notifyListeners();
  }

  Future<void> refreshTrayStatus() async {
    await RfidService().getTrayStatus();
    notifyListeners();
  }
}

class FileInfo {
  final String path;
  FileInfo(this.path);
}
