import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/stock_verification_report.dart';
import '../services/api_service.dart';
import '../services/consolidated_report_export_service.dart';
import '../services/pref_service.dart';

enum ReportLoadState { idle, loading, success, error }

class StockVerificationViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final ApiService _apiService;

  StockVerificationViewModel({
    required PrefService prefService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _apiService = apiService;

  ReportLoadState _consolidatedState = ReportLoadState.idle;
  ReportLoadState get consolidatedState => _consolidatedState;

  ReportLoadState _sessionState = ReportLoadState.idle;
  ReportLoadState get sessionState => _sessionState;

  ReportLoadState _batchDetailsState = ReportLoadState.idle;
  ReportLoadState get batchDetailsState => _batchDetailsState;

  ReportLoadState _detailState = ReportLoadState.idle;
  ReportLoadState get detailState => _detailState;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  StockVerificationReportResponse? _consolidatedReport;
  StockVerificationReportResponse? get consolidatedReport => _consolidatedReport;

  SessionListResponse? _sessionList;
  SessionListResponse? get sessionList => _sessionList;

  BatchDetailsResponse? _batchDetails;
  BatchDetailsResponse? get batchDetails => _batchDetails;

  List<ReportItem> _detailItems = [];
  List<ReportItem> get detailItems => _detailItems;

  List<ReportBranchOption> _branches = [];
  List<ReportBranchOption> get branches => _branches;

  List<ReportSessionItem> _originalSessions = [];

  bool _isExporting = false;
  bool get isExporting => _isExporting;

  String get clientCode => _prefService.getEmployee()?.clientCode ?? '';

  Future<void> loadBranches() async {
    try {
      final raw = await _apiService.getAllBranches(clientCode);
      _branches = raw.map((e) => ReportBranchOption.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('loadBranches: $e');
    }
  }

  Future<void> fetchConsolidatedReport(String reportDate) async {
    _consolidatedState = ReportLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await _apiService.getConsolidatedStockVerificationReport(
        clientCode: clientCode,
        reportDate: reportDate,
      );
      if (raw != null) {
        _consolidatedReport = StockVerificationReportResponse.fromJson(raw);
        _consolidatedState = ReportLoadState.success;
      } else {
        _consolidatedReport = null;
        _consolidatedState = ReportLoadState.error;
        _errorMessage = 'No report data';
      }
    } catch (e) {
      _consolidatedState = ReportLoadState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> fetchSessions() async {
    _sessionState = ReportLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await _apiService.getAllStockVerificationSessions(clientCode);
      if (raw != null) {
        final list = SessionListResponse.fromJson(raw);
        _originalSessions = List.from(list.sessions);
        _sessionList = list;
        _sessionState = ReportLoadState.success;
      } else {
        _sessionList = null;
        _sessionState = ReportLoadState.error;
        _errorMessage = 'No session data';
      }
    } catch (e) {
      _sessionState = ReportLoadState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  void filterSessions({int? branchId, required String fromDate, required String toDate}) {
    if (_sessionList == null) return;

    final filtered = _originalSessions.where((session) {
      final branchMatch = branchId == null || session.branchId == branchId;
      final dateStr = session.startedOn.length >= 10 ? session.startedOn.substring(0, 10) : session.startedOn;
      final dateMatch = dateStr.compareTo(fromDate) >= 0 && dateStr.compareTo(toDate) <= 0;
      return branchMatch && dateMatch;
    }).toList();

    _sessionList = _sessionList!.copyWith(sessions: filtered);
    notifyListeners();
  }

  Future<void> fetchBatchDetails(String scanBatchId) async {
    _batchDetailsState = ReportLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await _apiService.getStockVerificationBatchDetails(
        clientCode: clientCode,
        scanBatchId: scanBatchId,
      );
      if (raw != null) {
        _batchDetails = BatchDetailsResponse.fromJson(raw);
        _batchDetailsState = ReportLoadState.success;
      } else {
        _batchDetails = null;
        _batchDetailsState = ReportLoadState.error;
        _errorMessage = 'No batch details';
      }
    } catch (e) {
      _batchDetailsState = ReportLoadState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> fetchDetailItems({
    required int branchId,
    required String type,
    required String date,
    int? categoryId,
    int? productId,
    int? designId,
  }) async {
    _detailState = ReportLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await _apiService.getConsolidatedStockVerificationReport(
        clientCode: clientCode,
        reportDate: date,
      );
      if (raw == null) {
        _detailItems = [];
        _detailState = ReportLoadState.error;
        _errorMessage = 'No data available';
        notifyListeners();
        return;
      }

      final report = StockVerificationReportResponse.fromJson(raw);
      ReportBranch? branch;
      for (final b in report.branches) {
        if (b.branchId == branchId) {
          branch = b;
          break;
        }
      }
      if (branch == null) {
        _detailItems = [];
        _detailState = ReportLoadState.error;
        _errorMessage = 'Branch not found';
        notifyListeners();
        return;
      }

      final categories = branch.categories
          .where((c) => categoryId == null || c.categoryId == categoryId)
          .toList();

      final products = categories
          .expand((c) => c.products)
          .where((p) => productId == null || p.productId == productId)
          .toList();

      final designs = products
          .expand((p) => p.designs)
          .where((d) => designId == null || d.designId == designId)
          .toList();

      var items = designs.expand((d) => d.items).toList();

      switch (type.toUpperCase()) {
        case 'MATCHED':
          items = items.where((i) => i.status?.toLowerCase() == 'matched').toList();
          break;
        case 'UNMATCHED':
          items = items.where((i) => i.status?.toLowerCase() == 'unmatched').toList();
          break;
        default:
          break;
      }

      _detailItems = items;
      _detailState = ReportLoadState.success;
    } catch (e) {
      _detailState = ReportLoadState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<String?> exportConsolidatedReport(void Function(int count)? onProgress) async {
    if (_consolidatedReport == null) return 'No report to export';
    _isExporting = true;
    notifyListeners();

    try {
      final file = await ConsolidatedReportExportService.exportToCsv(
        report: _consolidatedReport!,
        onProgress: onProgress,
      );
      await ConsolidatedReportExportService.shareExportedFile(file);
      _isExporting = false;
      notifyListeners();
      return null;
    } catch (e) {
      _isExporting = false;
      notifyListeners();
      return e.toString();
    }
  }

  void clearBatchDetails() {
    _batchDetails = null;
    _batchDetailsState = ReportLoadState.idle;
  }

  void clearDetailItems() {
    _detailItems = [];
    _detailState = ReportLoadState.idle;
  }
}
