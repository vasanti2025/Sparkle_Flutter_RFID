import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../models/clients.dart';
import '../models/wholesale_master.dart';
import 'pref_store.dart';

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
  /// Absolute login session clock (ms since epoch). Cleared on logout.
  static const String _keySessionStartedAt = 'session_started_at';
  /// In-session credentials for silent JWT refresh (cleared on logout).
  static const String _keySessionUsername = 'session_username';
  static const String _keySessionPassword = 'session_password';

  /// Client-side login session length. Server JWT is refreshed within this window.
  static const Duration sessionDuration = Duration(hours: 1);

  // RFID power keys — match Kotlin UserPreferences
  static const String keyProductCount = 'product_count';
  static const String keyInventoryCount = 'inventory_count';
  static const String keySearchCount = 'search_count';
  static const String keyOrderCount = 'orders_count';
  static const String keyStockTransferCount = 'stock_transfer_count';

  static const String keyAutosyncEnabled = 'autosync_enabled';
  static const String keyAutosyncIntervalMin = 'autosync_interval_min';
  static const String keySheetUrl = 'sheet_url';
  static const String keyImportMappingTemplates = 'import_column_mapping_templates';
  static const String keyImportMappingLastTemplate = 'import_column_mapping_last_template';
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

  PrefStore _store;

  PrefService._(this._store);

  PrefStore get store => _store;

  static Future<PrefService>? _initFuture;
  static PrefService? _cached;

  /// Instant boot from Android entrypoint args — no SharedPreferences wait.
  static PrefService bootstrapQuick({
    required bool loggedIn,
    String username = '',
    String password = '',
  }) {
    if (_cached != null) return _cached!;
    final seed = <String, Object?>{
      _keyLoggedIn: loggedIn,
      keyAppLanguage: 'en',
    };
    if (username.isNotEmpty) {
      seed[_keyRememberMe] = true;
      seed[_keyUsername] = username;
      if (password.isNotEmpty) seed[_keyPassword] = password;
    }
    final service = PrefService._(MemoryPrefStore(seed));
    _cached = service;
    return service;
  }

  void applyNativeSnapshot(Map<String, dynamic> snapshot) {
    final mem = _store;
    if (mem is! MemoryPrefStore) return;

    final sanitized = Map<String, dynamic>.from(snapshot);
    // Never downgrade an already-restored session from a partial/error snapshot.
    if (sanitized['logged_in'] == false && (mem.getBool(_keyLoggedIn) ?? false)) {
      sanitized.remove('logged_in');
    }
    final snapshotToken = sanitized['token']?.toString() ?? '';
    if (snapshotToken.isEmpty) {
      final existingToken = mem.getString(_keyToken) ?? '';
      if (existingToken.isNotEmpty) sanitized.remove('token');
    }
    final snapshotEmployee = sanitized['employee']?.toString() ?? '';
    if (snapshotEmployee.isEmpty) {
      final existingEmployee = mem.getString(_keyEmployee) ?? '';
      if (existingEmployee.isNotEmpty) sanitized.remove('employee');
    }

    mem.applySnapshot(sanitized);
  }

  /// True when the user should stay on dashboard without re-entering credentials.
  bool hasValidSession() {
    if (!isLoggedIn() || getEmployee() == null) return false;
    final token = getToken();
    if (token == null || token.isEmpty) return false;
    if (isSessionTimedOut()) return false;
    return true;
  }

  Future<void> markSessionStarted([DateTime? at]) async {
    final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
    await _store.setInt(_keySessionStartedAt, ms);
  }

  int? getSessionStartedAtMs() => _store.getInt(_keySessionStartedAt);

  bool isSessionTimedOut() {
    final started = getSessionStartedAtMs();
    if (started == null || started <= 0) {
      // Legacy sessions without a clock: treat as still valid until next login
      // stamps a start time. Do not force-logout mid-shift for old installs.
      return false;
    }
    final age = DateTime.now().millisecondsSinceEpoch - started;
    return age >= sessionDuration.inMilliseconds;
  }

  Duration? sessionTimeRemaining() {
    final started = getSessionStartedAtMs();
    if (started == null || started <= 0) return null;
    final left = sessionDuration.inMilliseconds -
        (DateTime.now().millisecondsSinceEpoch - started);
    if (left <= 0) return Duration.zero;
    return Duration(milliseconds: left);
  }

  Future<void> saveSessionCredentials({
    required String username,
    required String password,
  }) async {
    await _store.setString(_keySessionUsername, username);
    await _store.setString(_keySessionPassword, password);
  }

  String getSessionUsername() {
    final session = _store.getString(_keySessionUsername) ?? '';
    if (session.isNotEmpty) return session;
    return getSavedUsername();
  }

  String getSessionPassword() {
    final session = _store.getString(_keySessionPassword) ?? '';
    if (session.isNotEmpty) return session;
    return getSavedPassword();
  }

  Future<void> upgradeToSharedPreferences(SharedPreferences prefs) async {
    if (_store is MemoryPrefStore) {
      final mem = _store as MemoryPrefStore;
      // Capture any in-memory session written during bootstrap (login race).
      final memToken = mem.getString(_keyToken) ?? '';
      final memEmployee = mem.getString(_keyEmployee) ?? '';
      final memClient = mem.getString('client') ?? '';
      final memLoggedIn = mem.getBool(_keyLoggedIn) ?? false;
      final memSessionAt = mem.getInt(_keySessionStartedAt);
      final memSessionUser = mem.getString(_keySessionUsername) ?? '';
      final memSessionPass = mem.getString(_keySessionPassword) ?? '';

      // Disk is source of truth for cold start, then restore richer memory session.
      mem.importFromSharedPreferences(prefs);
      if (memToken.isNotEmpty) mem.put(_keyToken, memToken);
      if (memEmployee.isNotEmpty) mem.put(_keyEmployee, memEmployee);
      if (memClient.isNotEmpty) mem.put('client', memClient);
      if (memLoggedIn) mem.put(_keyLoggedIn, true);
      if (memSessionAt != null && memSessionAt > 0) {
        mem.put(_keySessionStartedAt, memSessionAt);
      }
      if (memSessionUser.isNotEmpty) mem.put(_keySessionUsername, memSessionUser);
      if (memSessionPass.isNotEmpty) mem.put(_keySessionPassword, memSessionPass);

      await mem.mergeSessionSafeInto(prefs);
    }
    _store = SharedPrefStore(prefs);
    _initFuture = Future.value(this);
    unawaited(ensureDefaultCounters());
  }

  /// Cached — cold start and later callers share one load.
  static Future<PrefService> init() {
    return _initFuture ??= _initOnce();
  }

  /// Available after [init] or [bootstrapQuick] completes.
  static PrefService? get instanceOrNull => _cached;

  /// After a timed-out init attempt, allow a fresh [SharedPreferences] load.
  static void resetInitForRetry() {
    _initFuture = null;
    _cached = null;
  }

  static Future<PrefService> _initOnce() async {
    if (_cached != null && _cached!._store is SharedPrefStore) {
      return _cached!;
    }
    final prefs = await SharedPreferences.getInstance();
    if (_cached != null) {
      await _cached!.upgradeToSharedPreferences(prefs);
      return _cached!;
    }
    final service = PrefService._(SharedPrefStore(prefs));
    _cached = service;
    unawaited(service.ensureDefaultCounters());
    return service;
  }

  Future<void> ensureDefaultCounters() async {
    for (final entry in powerDefaults.entries) {
      if (!_store.containsKey(entry.key)) {
        await _store.setInt(entry.key, entry.value);
      }
    }
    if (!_store.containsKey(keyAutosyncIntervalMin)) {
      await _store.setInt(keyAutosyncIntervalMin, 15);
    }
    if (!_store.containsKey(keyAutosyncEnabled)) {
      await _store.setBool(keyAutosyncEnabled, false);
    }
  }

  int getPower(String key) {
    return _store.getInt(key) ?? powerDefaults[key] ?? 5;
  }

  int get productPower => getPower(keyProductCount);
  int get inventoryPower => getPower(keyInventoryCount);
  int get searchPower => getPower(keySearchCount);
  int get orderPower => getPower(keyOrderCount);
  int get stockTransferPower => getPower(keyStockTransferCount);

  Future<void> savePower(String key, int value) async {
    await _store.setInt(key, value.clamp(1, 30));
  }

  Future<void> saveToken(String token) async => _store.setString(_keyToken, token);
  String? getToken() => _store.getString(_keyToken);

  Future<void> saveEmployee(Employee employee) async {
    await _store.setString(_keyEmployee, jsonEncode(employee.toJson()));
  }

  String getEmployeeRawJson() => _store.getString(_keyEmployee) ?? '';

  static const String keyFaceEmbedding = 'registered_face_embedding';
  Future<void> saveRegisteredFaceEmbedding(String val) async => _store.setString(keyFaceEmbedding, val);
  String getRegisteredFaceEmbedding() => _store.getString(keyFaceEmbedding) ?? '';

  static const String keyFaceUsername = 'registered_face_username';
  Future<void> saveRegisteredFaceUsername(String val) async => _store.setString(keyFaceUsername, val);
  String getRegisteredFaceUsername() => _store.getString(keyFaceUsername) ?? '';

  Employee? getEmployee() {
    final jsonStr = _store.getString(_keyEmployee);
    if (jsonStr == null || jsonStr.trim().isEmpty) return null;
    try {
      return Employee.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('getEmployee parse failed: $e');
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
    await _store.setBool(_keyRememberMe, rememberMe);
    if (rememberMe) {
      await _store.setString(_keyUsername, username);
      await _store.setString(_keyPassword, password);
      await _store.setString(_keyRfidType, rfidType);
      await _store.setInt(_keyUserId, userId);
      await _store.setInt(_keyBranchId, branchId);
      await _store.setString(_keyOrg, organisationName);
    } else {
      await _store.remove(_keyUsername);
      await _store.remove(_keyPassword);
      await _store.remove(_keyRfidType);
      await _store.remove(_keyUserId);
      await _store.remove(_keyBranchId);
      await _store.remove(_keyOrg);
    }
  }

  bool isRememberMe() => _store.getBool(_keyRememberMe) ?? false;
  String getSavedUsername() => _store.getString(_keyUsername) ?? '';
  String getSavedPassword() => _store.getString(_keyPassword) ?? '';

  /// Wholesale + Scan Display branch/counter flow is only for this ClientCode.
  static const String wholesaleClientCode = 'LS000641';

  bool isWholesaleLoginUser() {
    bool matches(String? value) =>
        (value ?? '').trim().toUpperCase() == wholesaleClientCode;
    final emp = getEmployee();
    return matches(emp?.clientCode) ||
        matches(emp?.clients?.clientCode) ||
        matches(getClient()?.clientCode);
  }

  Future<void> setLoggedIn(bool loggedIn) async => _store.setBool(_keyLoggedIn, loggedIn);
  bool isLoggedIn() => _store.getBool(_keyLoggedIn) ?? false;

  Future<void> saveCustomApi(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      // No custom URL → use default rrgold server (same as Sparkle)
      await _store.remove(_keyCustomApiUrl);
      return;
    }
    var finalUrl = trimmed;
    if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
      finalUrl = 'http://$finalUrl';
    }
    if (!finalUrl.endsWith('/')) {
      finalUrl = '$finalUrl/';
    }
    await _store.setString(_keyCustomApiUrl, finalUrl);
  }

  /// Raw saved custom API (null/empty means use default rrgold).
  String? getCustomApi() {
    final v = _store.getString(_keyCustomApiUrl)?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static const String defaultApiBaseUrl = 'https://rrgold.loyalstring.co.in/';

  /// Effective API base URL — custom if set, otherwise rrgold default.
  String getEffectiveApiBaseUrl() {
    var url = getCustomApi() ?? '';
    if (url.isEmpty) {
      url = defaultApiBaseUrl;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (!url.endsWith('/')) {
      url = '$url/';
    }
    return url;
  }

  Future<void> setUserId(int userId) async => _store.setInt(_keyUserId, userId);
  Future<void> saveBranchId(int branchId) async => _store.setInt(_keyBranchId, branchId);

  /// Login-time / selected branch (same as Sparkle `getBranchID()`).
  int getBranchId() => _store.getInt(_keyBranchId) ?? 0;

  Future<void> saveClient(Clients client) async {
    await _store.setString('client', jsonEncode(client.toJson()));
  }

  Clients? getClient() {
    final jsonStr = _store.getString('client');
    if (jsonStr == null) return null;
    try {
      return Clients.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Organisation / company name for PDFs and Bluetooth print headers.
  String? getOrganisationName() {
    final saved = _store.getString(_keyOrg);
    if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    final fromClient = getClient()?.organisationName?.trim();
    if (fromClient != null && fromClient.isNotEmpty) return fromClient;
    return null;
  }

  String getRfidType() {
    final clientType = getClient()?.rfidType;
    if (clientType != null && clientType.trim().isNotEmpty) {
      return clientType.trim().toLowerCase();
    }
    return (_store.getString(_keyRfidType) ?? 'webreusable').trim().toLowerCase();
  }

  static const String keyLocalWifiMode = 'local_wifi_mode';
  static const String keyTrayModeEnabled = 'tray_mode_enabled';
  static const String keyTrayDeviceAddress = 'tray_device_address';
  static const String keyTrayDeviceName = 'tray_device_name';
  static const String keyR6ModeEnabled = 'r6_mode_enabled';
  static const String keyR6DeviceAddress = 'r6_device_address';
  static const String keyR6DeviceName = 'r6_device_name';

  bool isWebReusableTagEnabled() => _store.getBool(keyWebReusableTag) ?? true;
  Future<void> setWebReusableTagEnabled(bool value) async => _store.setBool(keyWebReusableTag, value);

  bool isLocalWifiModeEnabled() => _store.getBool(keyLocalWifiMode) ?? false;
  Future<void> setLocalWifiModeEnabled(bool value) async => _store.setBool(keyLocalWifiMode, value);

  bool isTrayModeEnabled() => _store.getBool(keyTrayModeEnabled) ?? false;
  Future<void> setTrayModeEnabled(bool value) async {
    await _store.setBool(keyTrayModeEnabled, value);
    if (value) await _store.setBool(keyR6ModeEnabled, false);
  }

  String getTrayDeviceAddress() => _store.getString(keyTrayDeviceAddress) ?? '';
  String getTrayDeviceName() => _store.getString(keyTrayDeviceName) ?? '';

  Future<void> saveTrayDevice({required String name, required String address}) async {
    await _store.setString(keyTrayDeviceName, name);
    await _store.setString(keyTrayDeviceAddress, address);
  }

  bool isR6ModeEnabled() => _store.getBool(keyR6ModeEnabled) ?? false;
  Future<void> setR6ModeEnabled(bool value) async {
    await _store.setBool(keyR6ModeEnabled, value);
    if (value) await _store.setBool(keyTrayModeEnabled, false);
  }

  String getR6DeviceAddress() => _store.getString(keyR6DeviceAddress) ?? '';
  String getR6DeviceName() => _store.getString(keyR6DeviceName) ?? '';

  Future<void> saveR6Device({required String name, required String address}) async {
    await _store.setString(keyR6DeviceName, name);
    await _store.setString(keyR6DeviceAddress, address);
  }

  Future<void> saveBranchIds(List<int> branchIds) async {
    await _store.setString(keyBranchIds, jsonEncode(branchIds));
  }

  List<int> getBranchIds() {
    final jsonStr = _store.getString(keyBranchIds);
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

  String getSheetUrl() => _store.getString(keySheetUrl) ?? '';
  Future<void> saveSheetUrl(String url) async => _store.setString(keySheetUrl, url);

  /// Saved Excel / Google Sheet column maps: template name → {fieldKey: columnName}.
  Map<String, Map<String, String>> getImportMappingTemplates() {
    final raw = _store.getString(keyImportMappingTemplates);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, Map<String, String>>{};
      decoded.forEach((key, value) {
        if (value is! Map) return;
        final name = key.toString().trim();
        if (name.isEmpty) return;
        out[name] = {
          for (final e in value.entries)
            e.key.toString(): e.value.toString(),
        };
      });
      return out;
    } catch (e) {
      debugPrint('getImportMappingTemplates parse failed: $e');
      return {};
    }
  }

  Future<void> saveImportMappingTemplate(String name, Map<String, String> mapping) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final all = getImportMappingTemplates();
    all[trimmed] = Map<String, String>.from(mapping);
    await _store.setString(keyImportMappingTemplates, jsonEncode(all));
    await _store.setString(keyImportMappingLastTemplate, trimmed);
  }

  String? getLastImportMappingTemplateName() {
    final name = _store.getString(keyImportMappingLastTemplate)?.trim();
    if (name == null || name.isEmpty) return null;
    if (!getImportMappingTemplates().containsKey(name)) return null;
    return name;
  }

  Future<void> setLastImportMappingTemplateName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _store.setString(keyImportMappingLastTemplate, trimmed);
  }

  String getStockTransferUrl() => _store.getString(keyStockTransferUrl) ?? '';
  Future<void> saveStockTransferUrl(String url) async => _store.setString(keyStockTransferUrl, url);

  String getBackupEmail() => _store.getString(keyBackupEmail) ?? '';
  Future<void> saveBackupEmail(String email) async => _store.setString(keyBackupEmail, email);

  bool isAutosyncEnabled() => _store.getBool(keyAutosyncEnabled) ?? false;
  Future<void> setAutosyncEnabled(bool value) async => _store.setBool(keyAutosyncEnabled, value);

  int getAutosyncIntervalMin() => _store.getInt(keyAutosyncIntervalMin) ?? 15;
  Future<void> setAutosyncIntervalMin(int minutes) async => _store.setInt(keyAutosyncIntervalMin, minutes);

  bool areNotificationsEnabled() => _store.getBool(keyNotificationsEnabled) ?? true;
  Future<void> setNotificationsEnabled(bool value) async => _store.setBool(keyNotificationsEnabled, value);

  String getAppLanguage() => _store.getString(keyAppLanguage) ?? 'en';
  Future<void> saveAppLanguage(String code) async => _store.setString(keyAppLanguage, code);

  bool isLocationSyncEnabled() => _store.getBool(keyLocationSync) ?? true;
  Future<void> setLocationSyncEnabled(bool value) async => _store.setBool(keyLocationSync, value);

  static const String keyDeviceId = 'stable_device_id';
  Future<void> saveDeviceId(String val) async => _store.setString(keyDeviceId, val);
  String getDeviceId() => _store.getString(keyDeviceId) ?? '';

  static const String keyWholesaleBranchId = 'wholesale_branch_id';
  static const String keyWholesaleBranchName = 'wholesale_branch_name';
  static const String keyWholesaleCounterId = 'wholesale_counter_id';
  static const String keyWholesaleCounterName = 'wholesale_counter_name';

  static const String keyWholesaleAssignments = 'wholesale_assignments';

  int getWholesaleBranchId() => _store.getInt(keyWholesaleBranchId) ?? 0;
  String getWholesaleBranchName() => _store.getString(keyWholesaleBranchName) ?? '';
  int getWholesaleCounterId() => _store.getInt(keyWholesaleCounterId) ?? 0;
  String getWholesaleCounterName() => _store.getString(keyWholesaleCounterName) ?? '';

  List<RfidDeviceAssignment> getWholesaleAssignments() {
    final raw = _store.getString(keyWholesaleAssignments);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((e) => RfidDeviceAssignment.fromJson(Map<String, dynamic>.from(e)))
              .where((a) => a.isValid)
              .toList();
        }
      } catch (_) {}
    }
    final branchId = getWholesaleBranchId();
    final branchName = getWholesaleBranchName();
    final counterId = getWholesaleCounterId();
    final counterName = getWholesaleCounterName();
    if (branchId > 0 || branchName.isNotEmpty || counterId > 0 || counterName.isNotEmpty) {
      return [
        RfidDeviceAssignment(
          branchId: branchId,
          branchName: branchName,
          counterId: counterId,
          counterName: counterName,
        ),
      ];
    }
    return [];
  }

  Future<void> saveWholesaleOption({
    required int branchId,
    required String branchName,
    required int counterId,
    required String counterName,
    required String deviceId,
    List<RfidDeviceAssignment>? assignments,
  }) async {
    await _store.setInt(keyWholesaleBranchId, branchId);
    await _store.setString(keyWholesaleBranchName, branchName);
    await _store.setInt(keyWholesaleCounterId, counterId);
    await _store.setString(keyWholesaleCounterName, counterName);
    await saveDeviceId(deviceId);
    final rows = assignments ??
        [
          RfidDeviceAssignment(
            branchId: branchId,
            branchName: branchName,
            counterId: counterId,
            counterName: counterName,
          ),
        ];
    await _store.setString(
      keyWholesaleAssignments,
      jsonEncode(rows.map((a) => a.toPrefJson()).toList()),
    );
  }

  Future<void> logout() async {
    // Clear login flag first so a killed mid-logout process cannot autologin.
    await _store.remove(_keyLoggedIn);
    await _store.remove(_keyToken);
    await _store.remove(_keyEmployee);
    await _store.remove('client');
    await _store.remove(_keyBranchId);
    await _store.remove(keyBranchIds);
    await _store.remove(_keyUserId);
    await _store.remove(_keySessionStartedAt);
    await _store.remove(_keySessionUsername);
    await _store.remove(_keySessionPassword);
    if (!isRememberMe()) {
      await _store.remove(_keyUsername);
      await _store.remove(_keyPassword);
      await _store.remove(_keyRfidType);
      await _store.remove(_keyOrg);
    }
    // Custom API URL is a persistent setting and should not be removed on logout
  }

  Future<void> clearAll() async {
    await _store.clear();
    await ensureDefaultCounters();
  }
}
