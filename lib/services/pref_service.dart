import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../models/clients.dart';

class PrefService {
  static const String _keyToken = 'token';
  static const String _keyEmployee = 'employee';
  static const String _keyUsername = 'remember_username';
  static const String _keyPassword = 'remember_password';
  static const String _keyRememberMe = 'remember_me';
  static const String _keyLoggedIn = 'logged_in';
  static const String _keyCustomApiUrl = 'custom_api_url';
  static const String _keyUserId = 'user_id';
  static const String _keyBranchId = 'branch_id';
  static const String _keyOrg = 'organisation_name';
  static const String _keyRfidType = 'remember_rfidType';

  // RFID power keys — match Kotlin UserPreferences
  static const String keyProductCount = 'product_count';
  static const String keyInventoryCount = 'inventory_count';
  static const String keySearchCount = 'search_count';
  static const String keyOrderCount = 'orders_count';
  static const String keyStockTransferCount = 'stock_transfer_count';

  static const String keyAutosyncEnabled = 'autosync_enabled';
  static const String keyAutosyncIntervalMin = 'autosync_interval_min';
  static const String keySheetUrl = 'sheet_url';
  static const String keyStockTransferUrl = 'stock_transfer_url';
  static const String keyBackupEmail = 'backup_email';
  static const String keyWebReusableTag = 'web_reusable_tag';
  static const String keyBranchIds = 'branch_ids';
  static const String keyNotificationsEnabled = 'notifications_enabled';
  static const String keyAppLanguage = 'app_language';
  static const String keyLocationSync = 'location_sync';

  static const Map<String, int> powerDefaults = {
    keyProductCount: 5,
    keyInventoryCount: 30,
    keySearchCount: 30,
    keyOrderCount: 10,
    keyStockTransferCount: 10,
  };

  final SharedPreferences _prefs;

  PrefService(this._prefs);

  static Future<PrefService> init() async {
    final prefs = await SharedPreferences.getInstance();
    final service = PrefService(prefs);
    await service.ensureDefaultCounters();
    return service;
  }

  Future<void> ensureDefaultCounters() async {
    for (final entry in powerDefaults.entries) {
      if (!_prefs.containsKey(entry.key)) {
        await _prefs.setInt(entry.key, entry.value);
      }
    }
    if (!_prefs.containsKey(keyAutosyncIntervalMin)) {
      await _prefs.setInt(keyAutosyncIntervalMin, 15);
    }
    if (!_prefs.containsKey(keyAutosyncEnabled)) {
      await _prefs.setBool(keyAutosyncEnabled, false);
    }
  }

  int getPower(String key) {
    return _prefs.getInt(key) ?? powerDefaults[key] ?? 5;
  }

  int get productPower => getPower(keyProductCount);
  int get inventoryPower => getPower(keyInventoryCount);
  int get searchPower => getPower(keySearchCount);
  int get orderPower => getPower(keyOrderCount);
  int get stockTransferPower => getPower(keyStockTransferCount);

  Future<void> savePower(String key, int value) async {
    await _prefs.setInt(key, value.clamp(1, 30));
  }

  Future<void> saveToken(String token) async => _prefs.setString(_keyToken, token);
  String? getToken() => _prefs.getString(_keyToken);

  Future<void> saveEmployee(Employee employee) async {
    await _prefs.setString(_keyEmployee, jsonEncode(employee.toJson()));
  }

  String getEmployeeRawJson() => _prefs.getString(_keyEmployee) ?? '';

  static const String keyFaceEmbedding = 'registered_face_embedding';
  Future<void> saveRegisteredFaceEmbedding(String val) async => _prefs.setString(keyFaceEmbedding, val);
  String getRegisteredFaceEmbedding() => _prefs.getString(keyFaceEmbedding) ?? '';

  static const String keyFaceUsername = 'registered_face_username';
  Future<void> saveRegisteredFaceUsername(String val) async => _prefs.setString(keyFaceUsername, val);
  String getRegisteredFaceUsername() => _prefs.getString(keyFaceUsername) ?? '';

  Employee? getEmployee() {
    final jsonStr = _prefs.getString(_keyEmployee);
    if (jsonStr == null) return null;
    try {
      return Employee.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLoginCredentials({
    required String username,
    required String password,
    required bool rememberMe,
    required String rfidType,
    required int userId,
    required int branchId,
    required String organisationName,
  }) async {
    await _prefs.setBool(_keyRememberMe, rememberMe);
    if (rememberMe) {
      await _prefs.setString(_keyUsername, username);
      await _prefs.setString(_keyPassword, password);
      await _prefs.setString(_keyRfidType, rfidType);
      await _prefs.setInt(_keyUserId, userId);
      await _prefs.setInt(_keyBranchId, branchId);
      await _prefs.setString(_keyOrg, organisationName);
    } else {
      await _prefs.remove(_keyUsername);
      await _prefs.remove(_keyPassword);
      await _prefs.remove(_keyRfidType);
      await _prefs.remove(_keyUserId);
      await _prefs.remove(_keyBranchId);
      await _prefs.remove(_keyOrg);
    }
  }

  bool isRememberMe() => _prefs.getBool(_keyRememberMe) ?? false;
  String getSavedUsername() => _prefs.getString(_keyUsername) ?? '';
  String getSavedPassword() => _prefs.getString(_keyPassword) ?? '';

  Future<void> setLoggedIn(bool loggedIn) async => _prefs.setBool(_keyLoggedIn, loggedIn);
  bool isLoggedIn() => _prefs.getBool(_keyLoggedIn) ?? false;

  Future<void> saveCustomApi(String url) async => _prefs.setString(_keyCustomApiUrl, url);
  String? getCustomApi() => _prefs.getString(_keyCustomApiUrl);

  Future<void> setUserId(int userId) async => _prefs.setInt(_keyUserId, userId);
  Future<void> saveBranchId(int branchId) async => _prefs.setInt(_keyBranchId, branchId);

  Future<void> saveClient(Clients client) async {
    await _prefs.setString('client', jsonEncode(client.toJson()));
  }

  Clients? getClient() {
    final jsonStr = _prefs.getString('client');
    if (jsonStr == null) return null;
    try {
      return Clients.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String getRfidType() {
    final clientType = getClient()?.rfidType;
    if (clientType != null && clientType.trim().isNotEmpty) {
      return clientType.trim().toLowerCase();
    }
    return (_prefs.getString(_keyRfidType) ?? 'webreusable').trim().toLowerCase();
  }

  static const String keyLocalWifiMode = 'local_wifi_mode';
  static const String keyTrayModeEnabled = 'tray_mode_enabled';
  static const String keyTrayDeviceAddress = 'tray_device_address';
  static const String keyTrayDeviceName = 'tray_device_name';
  static const String keyR6ModeEnabled = 'r6_mode_enabled';
  static const String keyR6DeviceAddress = 'r6_device_address';
  static const String keyR6DeviceName = 'r6_device_name';

  bool isWebReusableTagEnabled() => _prefs.getBool(keyWebReusableTag) ?? true;
  Future<void> setWebReusableTagEnabled(bool value) async => _prefs.setBool(keyWebReusableTag, value);

  bool isLocalWifiModeEnabled() => _prefs.getBool(keyLocalWifiMode) ?? false;
  Future<void> setLocalWifiModeEnabled(bool value) async => _prefs.setBool(keyLocalWifiMode, value);

  bool isTrayModeEnabled() => _prefs.getBool(keyTrayModeEnabled) ?? false;
  Future<void> setTrayModeEnabled(bool value) async {
    await _prefs.setBool(keyTrayModeEnabled, value);
    if (value) await _prefs.setBool(keyR6ModeEnabled, false);
  }

  String getTrayDeviceAddress() => _prefs.getString(keyTrayDeviceAddress) ?? '';
  String getTrayDeviceName() => _prefs.getString(keyTrayDeviceName) ?? '';

  Future<void> saveTrayDevice({required String name, required String address}) async {
    await _prefs.setString(keyTrayDeviceName, name);
    await _prefs.setString(keyTrayDeviceAddress, address);
  }

  bool isR6ModeEnabled() => _prefs.getBool(keyR6ModeEnabled) ?? false;
  Future<void> setR6ModeEnabled(bool value) async {
    await _prefs.setBool(keyR6ModeEnabled, value);
    if (value) await _prefs.setBool(keyTrayModeEnabled, false);
  }

  String getR6DeviceAddress() => _prefs.getString(keyR6DeviceAddress) ?? '';
  String getR6DeviceName() => _prefs.getString(keyR6DeviceName) ?? '';

  Future<void> saveR6Device({required String name, required String address}) async {
    await _prefs.setString(keyR6DeviceName, name);
    await _prefs.setString(keyR6DeviceAddress, address);
  }

  Future<void> saveBranchIds(List<int> branchIds) async {
    await _prefs.setString(keyBranchIds, jsonEncode(branchIds));
  }

  List<int> getBranchIds() {
    final jsonStr = _prefs.getString(keyBranchIds);
    if (jsonStr == null) {
      final emp = getEmployee();
      if (emp != null) return [emp.defaultBranchId];
      return [1];
    }
    try {
      return (jsonDecode(jsonStr) as List).cast<int>();
    } catch (_) {
      return [1];
    }
  }

  String getSheetUrl() => _prefs.getString(keySheetUrl) ?? '';
  Future<void> saveSheetUrl(String url) async => _prefs.setString(keySheetUrl, url);

  String getStockTransferUrl() => _prefs.getString(keyStockTransferUrl) ?? '';
  Future<void> saveStockTransferUrl(String url) async => _prefs.setString(keyStockTransferUrl, url);

  String getBackupEmail() => _prefs.getString(keyBackupEmail) ?? '';
  Future<void> saveBackupEmail(String email) async => _prefs.setString(keyBackupEmail, email);

  bool isAutosyncEnabled() => _prefs.getBool(keyAutosyncEnabled) ?? false;
  Future<void> setAutosyncEnabled(bool value) async => _prefs.setBool(keyAutosyncEnabled, value);

  int getAutosyncIntervalMin() => _prefs.getInt(keyAutosyncIntervalMin) ?? 15;
  Future<void> setAutosyncIntervalMin(int minutes) async => _prefs.setInt(keyAutosyncIntervalMin, minutes);

  bool areNotificationsEnabled() => _prefs.getBool(keyNotificationsEnabled) ?? true;
  Future<void> setNotificationsEnabled(bool value) async => _prefs.setBool(keyNotificationsEnabled, value);

  String getAppLanguage() => _prefs.getString(keyAppLanguage) ?? 'en';
  Future<void> saveAppLanguage(String code) async => _prefs.setString(keyAppLanguage, code);

  bool isLocationSyncEnabled() => _prefs.getBool(keyLocationSync) ?? true;
  Future<void> setLocationSyncEnabled(bool value) async => _prefs.setBool(keyLocationSync, value);

  static const String keyDeviceId = 'stable_device_id';
  Future<void> saveDeviceId(String val) async => _prefs.setString(keyDeviceId, val);
  String getDeviceId() => _prefs.getString(keyDeviceId) ?? '';

  Future<void> logout() async {
    await _prefs.remove(_keyUserId);
    if (!isRememberMe()) {
      await _prefs.remove(_keyUsername);
      await _prefs.remove(_keyPassword);
      await _prefs.remove(_keyRfidType);
      await _prefs.remove(_keyOrg);
    }
    // Custom API URL is a persistent setting and should not be removed on logout
    await _prefs.remove(_keyLoggedIn);
    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyEmployee);
  }

  Future<void> clearAll() async {
    await _prefs.clear();
    await ensureDefaultCounters();
  }
}
