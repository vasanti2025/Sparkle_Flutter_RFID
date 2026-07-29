import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/login_request.dart';
import '../models/login_response.dart';
import '../models/user_permission.dart';
import '../services/api_service.dart';
import '../services/location_sync_service.dart';
import '../services/pref_service.dart';

class LoginViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final PrefService _prefService;

  LoginViewModel({
    required ApiService apiService,
    required PrefService prefService,
  })  : _apiService = apiService,
        _prefService = prefService {
    // Load remember me options on init
    _rememberMe = _prefService.isRememberMe();
    if (_rememberMe) {
      _username = _prefService.getSavedUsername();
      _password = _prefService.getSavedPassword();
    }
  }

  String _selectedLoginMode = 'password'; // 'password' or 'face'
  String _username = '';
  String _password = '';
  bool _passwordVisible = false;
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Subscription Expiry Warning variables
  bool _showExpiryWarning = false;
  String _expiryWarningMessage = '';
  LoginResponse? _pendingLoginResponse;

  // Getters
  String get selectedLoginMode => _selectedLoginMode;
  String get username => _username;
  String get password => _password;
  bool get passwordVisible => _passwordVisible;
  bool get rememberMe => _rememberMe;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get showExpiryWarning => _showExpiryWarning;
  String get expiryWarningMessage => _expiryWarningMessage;

  // Setters / Actions
  void setLoginMode(String mode) {
    _selectedLoginMode = mode;
    _errorMessage = null;
    notifyListeners();
  }

  void setUsername(String value) {
    _username = value;
  }

  void setPassword(String value) {
    _password = value;
  }

  void togglePasswordVisibility() {
    _passwordVisible = !_passwordVisible;
    notifyListeners();
  }

  void setRememberMe(bool value) {
    _rememberMe = value;
    notifyListeners();
  }

  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Called after native prefs snapshot hydrates memory store at startup.
  void reloadRememberMe() {
    _rememberMe = _prefService.isRememberMe();
    if (_rememberMe) {
      _username = _prefService.getSavedUsername();
      _password = _prefService.getSavedPassword();
    }
    notifyListeners();
  }

  // Custom API configuration
  String getCustomApiUrl() {
    return _prefService.getCustomApi() ?? '';
  }

  Future<void> saveCustomApiUrl(String url) async {
    await _prefService.saveCustomApi(url);
    notifyListeners();
  }

  // Calculate subscription remaining days
  int? _getDaysRemaining(String? expiryDateStr) {
    if (expiryDateStr == null || expiryDateStr.trim().isEmpty) return null;
    try {
      final cleanDateStr = expiryDateStr.trim().substring(0, 10);
      final expiryDate = DateTime.parse(cleanDateStr);
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final expiryStart = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
      return expiryStart.difference(todayStart).inDays;
    } catch (e) {
      return null;
    }
  }

  Future<bool> login(BuildContext context) async {
    if (_username.trim().isEmpty || _password.trim().isEmpty) {
      _errorMessage = 'Please enter username and password';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.login(
        LoginRequest(username: _username.trim(), password: _password),
      );

      final employee = response.employee;
      if (employee == null) {
        throw Exception('Login failed: Employee data missing');
      }

      final planExpiryDate = employee.clients?.planExpiryDate;
      final daysRemaining = _getDaysRemaining(planExpiryDate);

      if (daysRemaining != null) {
        if (daysRemaining < 0) {
          throw Exception(
            'Your subscription has expired. Please contact support.',
          );
        } else if (daysRemaining >= 0 && daysRemaining <= 15) {
          // Store response and show popup
          _pendingLoginResponse = response;
          _expiryWarningMessage =
              'Your subscription will expire in $daysRemaining day(s). Please renew soon.';
          _showExpiryWarning = true;
          _isLoading = false;
          notifyListeners();
          return false; // Return false to indicate login did not complete yet (requires dialog confirmation)
        }
      }

      // Standard login flow
      await _completeLogin(response);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> confirmExpiryAndLogin() async {
    if (_pendingLoginResponse != null) {
      _showExpiryWarning = false;
      await _completeLogin(_pendingLoginResponse!);
      _pendingLoginResponse = null;
    }
  }

  void cancelExpiryLogin() {
    _showExpiryWarning = false;
    _pendingLoginResponse = null;
    notifyListeners();
  }

  Future<void> _completeLogin(LoginResponse response) async {
    final employee = response.employee!;
    final client = employee.clients;

    await _prefService.saveToken(response.token ?? '');
    await _prefService.saveEmployee(employee);
    await _prefService.setUserId(employee.id);
    await _prefService.setLoggedIn(true);
    // Exact Sparkle MainActivity: saveBranchId(defaultBranchId) — used by AddStockTransfer.
    await _prefService.saveBranchId(employee.defaultBranchId);
    if (client != null) {
      await _prefService.saveClient(client);
    }

    // Fallback branches immediately — do not block login on permissions API.
    await _prefService.saveBranchIds(_fallbackBranchIds(employee));

    await _prefService.saveLoginCredentials(
      username: _username.trim(),
      password: _password,
      rememberMe: _rememberMe,
      rfidType: client?.rfidType ?? '',
      userId: employee.id,
      branchId: employee.defaultBranchId,
      organisationName: client?.organisationName ?? '',
    );

    _isLoading = false;
    _errorMessage = null;
    notifyListeners();

    // Permissions + location sync run after UI navigates (handheld was freezing here).
    unawaited(_saveBranchIdsForEmployee(employee));

    if (_prefService.isLocationSyncEnabled()) {
      unawaited(LocationSyncService.applySettings(true));
      Future<void>.delayed(const Duration(seconds: 8), () {
        unawaited(LocationSyncService.syncNow().then((_) {}));
      });
    }
  }

  List<int> _fallbackBranchIds(Employee employee) {
    final ids = <int>[
      if (employee.defaultBranchId > 0) employee.defaultBranchId,
      if ((employee.branchNo ?? 0) > 0) employee.branchNo!,
    ].toSet().toList();
    return ids.isEmpty ? [employee.defaultBranchId] : ids;
  }

  Future<void> _saveBranchIdsForEmployee(Employee employee) async {
    final clientCode = employee.clientCode ?? '';
    final fallback = <int>[
      if (employee.defaultBranchId > 0) employee.defaultBranchId,
      if ((employee.branchNo ?? 0) > 0) employee.branchNo!,
    ].toSet().toList();
    if (clientCode.isEmpty) {
      await _prefService.saveBranchIds(fallback.isEmpty ? [1] : fallback);
      return;
    }
    try {
      final permissions = await _apiService.getAllUserPermissionsAll(clientCode);
      UserPermission? current;
      for (final p in permissions) {
        if (p.userId == employee.id || p.employeeId == (employee.employeeId ?? -1)) {
          current = p;
          break;
        }
      }
      final fromPerm = parseBranchSelectionJson(current?.branchSelectionJson)
          .map((b) => b.id)
          .where((id) => id > 0)
          .toList();
      final ids = fromPerm.isNotEmpty ? fromPerm : fallback;
      await _prefService.saveBranchIds(ids.isEmpty ? [employee.defaultBranchId] : ids);
    } catch (e) {
      debugPrint('_saveBranchIdsForEmployee: $e');
      await _prefService.saveBranchIds(fallback.isEmpty ? [employee.defaultBranchId] : fallback);
    }
  }
}
