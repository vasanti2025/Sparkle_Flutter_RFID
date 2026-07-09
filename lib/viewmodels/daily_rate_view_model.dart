import 'package:flutter/foundation.dart';
import '../models/daily_rate.dart';
import '../services/api_service.dart';
import '../services/pref_service.dart';

enum RateUpdateStatus { idle, loading, success, failure }

/// Backs the Today's Rate (Edit Daily Rates) screen. Loads the purity master
/// list and merges current daily rates onto it, recalculates sibling purities
/// in the same category when a rate is edited, and pushes updates to the API.
class DailyRateViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final ApiService _apiService;

  DailyRateViewModel({
    required PrefService prefService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _apiService = apiService;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<DailyRate> _rates = [];
  List<DailyRate> get rates => _rates;

  RateUpdateStatus _updateStatus = RateUpdateStatus.idle;
  RateUpdateStatus get updateStatus => _updateStatus;

  String? _updateMessage;
  String? get updateMessage => _updateMessage;

  /// Fetch purity master + daily rates and merge them into editable rows.
  Future<void> loadRates() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final employee = _prefService.getEmployee();
      final code = employee?.clientCode ?? '';
      final empCode = employee?.employeeCode ?? '';

      final results = await Future.wait([
        _apiService.getAllPurity(code),
        _apiService.getDailyRates(code),
      ]);
      final purityList = results[0];
      final rateList = results[1];

      final List<DailyRate> rows = [];

      if (purityList.isNotEmpty) {
        // Build rows from purity master, merging the matching rate by PurityId.
        for (final p in purityList) {
          final pm = p as Map<String, dynamic>;
          final pid = pm['Id'] as int? ?? 0;

          Map<String, dynamic>? match;
          for (final r in rateList) {
            final rm = r as Map<String, dynamic>;
            if ((rm['PurityId'] as int?) == pid) {
              match = rm;
              break;
            }
          }

          rows.add(DailyRate(
            categoryId: pm['CategoryId'] as int? ?? 0,
            categoryName: (pm['CategoryName'] as String?) ?? '',
            clientCode: (match?['ClientCode'] as String?) ?? code,
            employeeCode: (match?['EmployeeCode'] as String?) ?? empCode,
            finePercentage: pm['FinePercentage']?.toString() ?? '0',
            purityId: pid,
            purityName: (pm['PurityName'] as String?) ?? '',
            rate: match?['Rate']?.toString() ?? '0.00',
          ));
        }
      } else {
        // Fallback: build directly from the daily-rate list if purity is empty.
        for (final r in rateList) {
          final rm = r as Map<String, dynamic>;
          rows.add(DailyRate(
            categoryId: rm['CategoryId'] as int? ?? 0,
            categoryName: (rm['CategoryName'] as String?) ?? '',
            clientCode: (rm['ClientCode'] as String?) ?? code,
            employeeCode: (rm['EmployeeCode'] as String?) ?? empCode,
            finePercentage: rm['FinePercentage']?.toString() ?? '0',
            purityId: rm['PurityId'] as int? ?? 0,
            purityName: (rm['PurityName'] as String?) ?? '',
            rate: rm['Rate']?.toString() ?? '0.00',
          ));
        }
      }

      _rates = rows;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates the rate at [index] and recalculates every other purity in the
  /// same category from the implied 100%-fine base rate (matches Kotlin).
  void updateRateAt(int index, String newRate) {
    if (index < 0 || index >= _rates.length) return;

    final edited = _rates[index];
    edited.rate = newRate;

    final baseFine = double.tryParse(edited.finePercentage);
    final newRateVal = double.tryParse(newRate);

    if (baseFine != null && baseFine != 0 && newRateVal != null) {
      final basePureRate = newRateVal / (baseFine / 100.0);
      for (int i = 0; i < _rates.length; i++) {
        if (i == index) continue;
        final other = _rates[i];
        if (other.categoryName.toLowerCase() == edited.categoryName.toLowerCase() &&
            other.purityId != edited.purityId) {
          final finePct = double.tryParse(other.finePercentage);
          if (finePct != null) {
            other.rate = (basePureRate * (finePct / 100.0)).toStringAsFixed(2);
          }
        }
      }
    }

    notifyListeners();
  }

  /// Push all rows to the UpdateDailyRates API.
  Future<bool> submitUpdate() async {
    _updateStatus = RateUpdateStatus.loading;
    _updateMessage = null;
    notifyListeners();

    try {
      final payload = _rates.map((r) => r.toUpdateJson()).toList();
      final ok = await _apiService.updateDailyRates(payload);
      if (ok) {
        _updateStatus = RateUpdateStatus.success;
        _updateMessage = 'Rates updated successfully';
        notifyListeners();
        return true;
      }
      _updateStatus = RateUpdateStatus.failure;
      _updateMessage = 'Failed to update rates';
      notifyListeners();
      return false;
    } catch (e) {
      _updateStatus = RateUpdateStatus.failure;
      _updateMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void resetUpdateState() {
    _updateStatus = RateUpdateStatus.idle;
    _updateMessage = null;
  }
}
