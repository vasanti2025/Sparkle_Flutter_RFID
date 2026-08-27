import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../services/auto_sync_service.dart' deferred as autosync;

class DashboardViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final DbService? _dbService;
  Employee? _employee;

  DashboardViewModel({
    required PrefService prefService,
    DbService? dbService,
  })  : _prefService = prefService,
        _dbService = dbService {
    _employee = _prefService.getEmployee();
  }

  Employee? get employee => _employee;

  void loadUser() {
    _employee = _prefService.getEmployee();
    notifyListeners();
  }

  /// Full logout like Sparkle: clear prefs + local stock, then UI must reset VMs + navigate.
  Future<void> logout() async {
    try {
      await autosync.loadLibrary();
      await autosync.AutoSyncService.cancelPeriodicSync();
    } catch (_) {}
    try {
      await _dbService?.clearAllItems();
      await _dbService?.clearAllRFID();
      _dbService?.invalidateBulkCache();
      await _dbService?.resetConnection();
    } catch (_) {}
    await _prefService.logout();
    _employee = null;
    notifyListeners();
  }
}
