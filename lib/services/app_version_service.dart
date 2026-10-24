import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_version_info.dart';
import 'api_service.dart';
import 'pref_service.dart';

enum AppVersionStatus { unknown, checking, allowed, updateRequired }

class AppVersionService extends ChangeNotifier {
  AppVersionService({
    required ApiService apiService,
    required PrefService prefService,
  })  : _api = apiService,
        _pref = prefService;

  static const playStoreId = 'com.loyalstring.rfid';
  static const defaultPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=$playStoreId';

  /// Debug-only: always show the force-update popup so it can be tested.
  /// Set back to `false` after testing.
  static const bool debugForceShowPopup = true;

  final ApiService _api;
  final PrefService _pref;

  AppVersionStatus _status = AppVersionStatus.unknown;
  String _installedVersion = '';
  String _requiredVersion = '';
  String _storeUrl = defaultPlayStoreUrl;
  bool _checkedWithClientCode = false;
  Future<AppVersionStatus>? _inFlight;

  AppVersionStatus get status => _status;
  bool get isChecking =>
      _status == AppVersionStatus.checking || _status == AppVersionStatus.unknown;
  bool get needsUpdate => _status == AppVersionStatus.updateRequired;
  bool get isAllowed => _status == AppVersionStatus.allowed;
  String get storeUrl => _storeUrl;
  String get installedVersion => _installedVersion;
  String get requiredVersion => _requiredVersion;

  /// Single-flight check used by splash and auto-login.
  Future<AppVersionStatus> check({bool forceRefresh = false}) {
    if (!forceRefresh && _inFlight != null) return _inFlight!;
    if (!forceRefresh && _status == AppVersionStatus.updateRequired) {
      return Future.value(_status);
    }
    final hasClient = _pref.getClientCode().isNotEmpty;
    if (!forceRefresh &&
        _status == AppVersionStatus.allowed &&
        !(kDebugMode && debugForceShowPopup) &&
        (_checkedWithClientCode || !hasClient)) {
      return Future.value(_status);
    }
    final future = _runCheck();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  Future<bool> ensureAllowed({bool forceRefresh = false}) async {
    final result = await check(forceRefresh: forceRefresh);
    return result == AppVersionStatus.allowed;
  }

  Future<void> openStore() async {
    final web = Uri.parse(
      _storeUrl.trim().isEmpty ? defaultPlayStoreUrl : _storeUrl.trim(),
    );
    if (Platform.isAndroid) {
      final market = Uri.parse('market://details?id=$playStoreId');
      try {
        if (await canLaunchUrl(market)) {
          final opened =
              await launchUrl(market, mode: LaunchMode.externalApplication);
          if (opened) return;
        }
      } catch (_) {}
    }
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  Future<AppVersionStatus> _runCheck() async {
    _status = AppVersionStatus.checking;
    notifyListeners();

    try {
      final info = await PackageInfo.fromPlatform();
      _installedVersion = info.version.trim();
    } catch (e) {
      debugPrint('App version package info failed: $e');
    }

    final ios = Platform.isIOS;
    final clientCode = _pref.getClientCode();
    AppVersionInfo? remote;

    if (clientCode.isEmpty) {
      _checkedWithClientCode = false;
      remote = _fromCache();
    } else {
      try {
        remote = await _api.getAppVersionConfig(
          clientCode: clientCode,
          ios: ios,
        );
        _checkedWithClientCode = true;
        if (remote.hasVersion) {
          await _pref.saveAppVersionCheck(
            version: remote.expectedVersion,
            forceUpdate: remote.forceUpdate,
            storeUrl: remote.storeUrl,
          );
        }
      } catch (e) {
        debugPrint('GetAppVersionConfig failed: $e');
        remote = _fromCache();
        _checkedWithClientCode = remote != null;
      }
    }

    final next = _evaluate(
      installedVersion: _installedVersion,
      remote: remote,
    );
    _status = next;
    notifyListeners();
    return next;
  }

  AppVersionInfo? _fromCache() {
    final version = _pref.getCachedRequiredAppVersion();
    if (version.isEmpty) return null;
    final url = _pref.getCachedForceUpdateStoreUrl();
    return AppVersionInfo(
      currentVersion: version,
      forceUpdate: _pref.isCachedForceUpdateRequired(),
      storeUrl: url.isEmpty ? null : url,
    );
  }

  AppVersionStatus _evaluate({
    required String installedVersion,
    required AppVersionInfo? remote,
  }) {
    if (kDebugMode && debugForceShowPopup) {
      debugPrint('╔════════════════════════════════════════');
      debugPrint('║ 🧪 Force-update popup forced for testing');
      debugPrint('╚════════════════════════════════════════');
      return AppVersionStatus.updateRequired;
    }
    if (remote == null || !remote.hasVersion) {
      return AppVersionStatus.allowed;
    }

    _requiredVersion = remote.expectedVersion;
    if (remote.storeUrl != null && remote.storeUrl!.trim().isNotEmpty) {
      _storeUrl = remote.storeUrl!.trim();
    }

    if (installedVersion.isEmpty) {
      return _pref.isCachedForceUpdateRequired()
          ? AppVersionStatus.updateRequired
          : AppVersionStatus.allowed;
    }

    final min = remote.minimumSupportedVersion.trim();
    if (min.isNotEmpty && compareVersions(installedVersion, min) < 0) {
      return AppVersionStatus.updateRequired;
    }

    // Any mismatch vs currentVersion (higher or lower) requires update.
    if (compareVersions(installedVersion, remote.expectedVersion) != 0) {
      return AppVersionStatus.updateRequired;
    }
    return AppVersionStatus.allowed;
  }

  /// Numeric dotted comparison: `1.9.0` vs `1.10.0`.
  static int compareVersions(String a, String b) {
    List<int> parts(String raw) {
      final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final numbers = <int>[];
      for (final piece in cleaned.split(RegExp(r'[^0-9]+'))) {
        if (piece.isEmpty) continue;
        numbers.add(int.tryParse(piece) ?? 0);
      }
      return numbers;
    }

    final left = parts(a);
    final right = parts(b);
    final n = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < n; i++) {
      final lv = i < left.length ? left[i] : 0;
      final rv = i < right.length ? right[i] : 0;
      if (lv != rv) return lv.compareTo(rv);
    }
    return 0;
  }
}
