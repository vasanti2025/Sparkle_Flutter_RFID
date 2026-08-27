import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_navigator.dart';
import '../models/login_request.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/login_view_model.dart';
import '../session_vm_hooks.dart' deferred as vm_hooks;
import 'api_service.dart';
import 'pref_service.dart';

/// Keeps the login session alive for [PrefService.sessionDuration] (1 hour),
/// refreshes short-lived JWT tokens silently, and sends the user to Login
/// when the session ends or becomes invalid.
class SessionLifecycle {
  SessionLifecycle._();
  static final SessionLifecycle instance = SessionLifecycle._();

  PrefService? _prefs;
  ApiService? _api;
  Timer? _timer;
  bool _forcingLogout = false;
  bool _refreshing = false;
  bool _monitoring = false;
  DateTime? _lastSilentRefreshAt;

  void attach({required PrefService prefs, required ApiService api}) {
    _prefs = prefs;
    _api = api;
  }

  /// Start periodic checks (safe to call multiple times).
  Future<void> startMonitoring() async {
    final prefs = _prefs;
    if (prefs == null) return;

    // Migrate older installs that logged in before session clocks existed.
    if (prefs.isLoggedIn() &&
        (prefs.getSessionStartedAtMs() == null ||
            (prefs.getSessionStartedAtMs() ?? 0) <= 0)) {
      await prefs.markSessionStarted();
    }

    // Avoid an immediate re-login right after opening the dashboard.
    _lastSilentRefreshAt ??= DateTime.now();

    _monitoring = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(checkAndEnforce());
    });
    unawaited(checkAndEnforce());
  }

  void stopMonitoring() {
    _monitoring = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Call on app resume / dashboard open.
  Future<void> checkAndEnforce() async {
    final prefs = _prefs;
    if (prefs == null || _forcingLogout) return;
    if (!prefs.isLoggedIn()) return;

    if (prefs.isSessionTimedOut()) {
      debugPrint('SessionLifecycle: 1hr session expired → login');
      await forceLogoutToLogin();
      return;
    }

    if (prefs.getEmployee() == null) {
      final refreshed = await trySilentRefresh();
      if (!refreshed || prefs.getEmployee() == null) {
        debugPrint('SessionLifecycle: missing employee → login');
        await forceLogoutToLogin();
      }
      return;
    }

    // Proactively refresh JWT before typical ~20min server expiry.
    final last = _lastSilentRefreshAt;
    final due = last == null ||
        DateTime.now().difference(last) >= const Duration(minutes: 20);
    if (due) {
      await trySilentRefresh();
    }
  }

  /// Dio 401 handler: refresh token once; if that fails, go to Login.
  Future<bool> handleUnauthorized() async {
    final prefs = _prefs;
    if (prefs == null) return false;
    if (prefs.isSessionTimedOut()) {
      await forceLogoutToLogin();
      return false;
    }
    final ok = await trySilentRefresh();
    if (!ok) {
      await forceLogoutToLogin();
      return false;
    }
    return true;
  }

  Future<bool> trySilentRefresh() async {
    final prefs = _prefs;
    final api = _api;
    if (prefs == null || api == null) return false;
    if (prefs.isSessionTimedOut()) return false;

    if (_refreshing) {
      for (var i = 0; i < 40 && _refreshing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final token = prefs.getToken();
      return token != null && token.isNotEmpty && prefs.getEmployee() != null;
    }

    final user = prefs.getSessionUsername();
    final pass = prefs.getSessionPassword();
    if (user.isEmpty || pass.isEmpty) return false;

    _refreshing = true;
    try {
      final response = await api.login(
        LoginRequest(username: user, password: pass),
      );
      final employee = response.employee;
      if (employee == null) return false;

      await prefs.saveToken(response.token ?? '');
      await prefs.saveEmployee(employee);
      await prefs.setUserId(employee.id);
      await prefs.saveBranchId(employee.defaultBranchId);
      if (employee.clients != null) {
        await prefs.saveClient(employee.clients!);
      }
      // Keep original session_started_at — absolute 1hr window from first login.
      await prefs.setLoggedIn(true);
      _lastSilentRefreshAt = DateTime.now();

      final ctx = appNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        try {
          ctx.read<DashboardViewModel>().loadUser();
        } catch (_) {}
      }
      return true;
    } catch (e) {
      debugPrint('SessionLifecycle silent refresh failed: $e');
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> forceLogoutToLogin() async {
    if (_forcingLogout) return;
    _forcingLogout = true;
    stopMonitoring();
    try {
      final prefs = _prefs;
      final ctx = appNavigatorKey.currentContext;

      DashboardViewModel? dashVm;
      LoginViewModel? loginVm;
      if (ctx != null && ctx.mounted) {
        try {
          dashVm = ctx.read<DashboardViewModel>();
        } catch (_) {}
        try {
          loginVm = ctx.read<LoginViewModel>();
        } catch (_) {}
        try {
          await vm_hooks.loadLibrary();
          if (ctx.mounted) {
            await vm_hooks.resetProductAndStockForLogout(ctx);
          }
        } catch (_) {}
      }

      try {
        if (dashVm != null) {
          await dashVm.logout();
        } else {
          await prefs?.logout();
        }
      } catch (_) {
        await prefs?.logout();
      }
      try {
        loginVm?.reloadRememberMe();
      } catch (_) {}

      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        nav.pushNamedAndRemoveUntil('/login', (_) => false);
      }
    } finally {
      _forcingLogout = false;
      _lastSilentRefreshAt = null;
      _monitoring = false;
    }
  }

  bool get isMonitoring => _monitoring;
}
