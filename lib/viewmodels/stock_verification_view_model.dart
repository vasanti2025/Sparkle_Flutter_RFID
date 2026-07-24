import 'package:flutter/foundation.dart';

import '../models/stock_verification_report.dart';
import '../services/api_service.dart';
import '../services/batch_report_export_service.dart';
import '../services/consolidated_report_export_service.dart';
import '../services/pref_service.dart';

enum ReportLoadState { idle, loading, success, error }

/// Isolate entry: keep only display fields so large payloads parse off the UI thread.
Map<String, dynamic> parseBatchDetailsIsolate(Map<String, dynamic> json) {
  List<Map<String, String?>> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, String?>>[];
    for (final e in raw) {
      if (e is! Map) continue;
      out.add({
        'itemCode': e['ItemCode']?.toString(),
        'productName': e['ProductName']?.toString(),
        'branchName': e['BranchName']?.toString(),
        'categoryName': e['CategoryName']?.toString(),
        'rfidCode': e['RFIDCode']?.toString(),
      });
    }
    return out;
  }

  return {
    'message': json['Message']?.toString(),
    'scanBatchId': json['ScanBatchId']?.toString(),
    'batchName': json['BatchName']?.toString(),
    'matchedList': parseList(json['MatchedList'] ?? json['matchedList']),
    'unmatchedList': parseList(json['UnmatchedList'] ?? json['unmatchedList']),
  };
}

List<Map<String, String?>> filterBatchItemsIsolate(Map<String, dynamic> args) {
  final q = (args['query'] as String?) ?? '';
  final items = (args['items'] as List?) ?? const [];
  return items.whereType<Map>().where((item) {
    String v(String key) => (item[key]?.toString() ?? '').toLowerCase();
    return v('itemCode').contains(q) ||
        v('productName').contains(q) ||
        v('branchName').contains(q) ||
        v('categoryName').contains(q) ||
        v('rfidCode').contains(q);
  }).map((e) {
    return <String, String?>{
      'itemCode': e['itemCode']?.toString(),
      'productName': e['productName']?.toString(),
      'branchName': e['branchName']?.toString(),
      'categoryName': e['categoryName']?.toString(),
      'rfidCode': e['rfidCode']?.toString(),
    };
  }).toList();
}

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

  int _exportProgress = 0;
  int get exportProgress => _exportProgress;

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
        _originalSessions = List<ReportSessionItem>.from(list.sessions);
        _sessionList = list;
        _sessionState = ReportLoadState.success;
      } else {
        _sessionList = null;
        _originalSessions = [];
        _sessionState = ReportLoadState.error;
        _errorMessage = 'No sessions found';
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
    _batchDetails = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await _apiService.getStockVerificationBatchDetails(
        clientCode: clientCode,
        scanBatchId: scanBatchId,
      );
      if (raw == null) {
        _batchDetails = null;
        _batchDetailsState = ReportLoadState.error;
        _errorMessage = 'No batch details';
        notifyListeners();
        return;
      }

      // Heavy JSON trim + parse off the UI thread
      final compact = await compute(parseBatchDetailsIsolate, Map<String, dynamic>.from(raw));
      _batchDetails = BatchDetailsResponse.fromCompact(compact);
      _batchDetailsState = ReportLoadState.success;
    } catch (e) {
      _batchDetailsState = ReportLoadState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<List<BatchReportItem>> filterBatchItems(
    List<BatchReportItem> items,
    String query,
  ) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    if (items.length < 1500) {
      return items.where((item) {
        return (item.itemCode ?? '').toLowerCase().contains(q) ||
            (item.productName ?? '').toLowerCase().contains(q) ||
            (item.branchName ?? '').toLowerCase().contains(q) ||
            (item.categoryName ?? '').toLowerCase().contains(q) ||
            (item.rfidCode ?? '').toLowerCase().contains(q);
      }).toList();
    }
    final maps = items.map((e) => e.toCompact()).toList();
    final filtered = await compute(filterBatchItemsIsolate, <String, dynamic>{
      'items': maps,
      'query': q,
    });
    return filtered.map(BatchReportItem.fromCompact).toList();
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
    _exportProgress = 0;
    notifyListeners();

    try {
      final file = await ConsolidatedReportExportService.exportToCsv(
        report: _consolidatedReport!,
        onProgress: (c) {
          _exportProgress = c;
          onProgress?.call(c);
        },
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

  Future<String?> exportBatchDetails({
    String? scanBatchId,
    void Function(int count)? onProgress,
  }) async {
    if (_batchDetails == null) return 'No batch details to export';
    if (_isExporting) return 'Export already in progress';
    _isExporting = true;
    _exportProgress = 0;
    notifyListeners();

    try {
      final file = await BatchReportExportService.exportToCsv(
        details: _batchDetails!,
        scanBatchId: scanBatchId,
        onProgress: (c) {
          _exportProgress = c;
          onProgress?.call(c);
        },
      );
      await BatchReportExportService.shareExportedFile(file);
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
    notifyListeners();
  }

  void clearDetailItems() {
    _detailItems = [];
    _detailState = ReportLoadState.idle;
  }
}
