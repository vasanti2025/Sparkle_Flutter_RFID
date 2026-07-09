import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/pref_service.dart';

class DashboardViewModel extends ChangeNotifier {
  final PrefService _prefService;
  Employee? _employee;

  DashboardViewModel({required PrefService prefService})
      : _prefService = prefService {
    _employee = _prefService.getEmployee();
  }

  Employee? get employee => _employee;

  void loadUser() {
    _employee = _prefService.getEmployee();
    notifyListeners();
  }

  Future<void> logout() async {
    await _prefService.logout();
    _employee = null;
    notifyListeners();
  }
}
