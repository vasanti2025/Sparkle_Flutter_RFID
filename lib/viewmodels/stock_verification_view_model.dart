import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/stock_verification_report.dart';
import '../services/api_service.dart';
import '../services/batch_report_export_service.dart';
import '../services/consolidated_report_export_service.dart';
import '../services/pref_service.dart';

enum ReportLoadState { idle, loading, success, error }

Map<String, dynamic> _decodeJsonObject(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  throw const FormatException('Expected a JSON object');
}

/// Hierarchy + counts only (no item rows) so the tree can paint like the web report.
StockVerificationReportResponse parseConsolidatedTreeIsolate(String body) {
  return StockVerificationReportResponse.fromJson(
    _decodeJsonObject(body),
    includeItems: false,
  );
}

SessionListResponse parseSessionsIsolate(String body) {
  final decoded = jsonDecode(body);
  if (decoded is List) {
    return SessionListResponse.fromJson({'Sessions': decoded, 'TotalSessions': decoded.length});
  }
  if (decoded is Map<String, dynamic>) return SessionListResponse.fromJson(decoded);
  if (decoded is Map) return SessionListResponse.fromJson(Map<String, dynamic>.from(decoded));
  throw const FormatException('Expected a JSON object');
}

List<Map<String, dynamic>> extractConsolidatedItemsIsolate(Map<String, dynamic> args) {
  final json = _decodeJsonObject(args['body'] as String);
  final branchId = args['branchId'] as int;
  final type = (args['type'] as String? ?? 'TOTAL').toUpperCase();
  final categoryId = args['categoryId'] as int?;
  final productId = args['productId'] as int?;
  final designId = args['designId'] as int?;

  final branches = json['Branches'] ?? json['branches'];
  if (branches is! List) return const [];

  Map<String, dynamic>? asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  int asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic>? branchMap;
  for (final e in branches) {
    final map = asMap(e);
    if (map != null && asInt(map['BranchId'] ?? map['branchId']) == branchId) {
      branchMap = map;
      break;
    }
  }
  if (branchMap == null) return const [];

  final items = <Map<String, dynamic>>[];
  final categories = branchMap['Categories'] ?? branchMap['categories'];
  if (categories is! List) return const [];

  for (final c in categories) {
    final cat = asMap(c);
    if (cat == null) continue;
    if (categoryId != null && asInt(cat['CategoryId'] ?? cat['categoryId']) != categoryId) {
      continue;
    }
    final products = cat['Products'] ?? cat['products'];
    if (products is! List) continue;
    for (final p in products) {
      final prod = asMap(p);
      if (prod == null) continue;
      if (productId != null && asInt(prod['ProductId'] ?? prod['productId']) != productId) {
        continue;
      }
      final designs = prod['Designs'] ?? prod['designs'];
      if (designs is! List) continue;
      for (final d in designs) {
        final des = asMap(d);
        if (des == null) continue;
        if (designId != null && asInt(des['DesignId'] ?? des['designId']) != designId) {
          continue;
        }
        final rawItems = des['Items'] ?? des['items'];
        if (rawItems is! List) continue;
        for (final it in rawItems) {
          final item = asMap(it);
          if (item == null) continue;
          final status = item['Status']?.toString() ?? item['status']?.toString() ?? '';
          if (type == 'MATCHED' && status.toLowerCase() != 'matched') continue;
          if (type == 'UNMATCHED' && status.toLowerCase() != 'unmatched') continue;
          items.add(item);
        }
      }
    }
  }
  return items;
}

StockVerificationReportResponse parseConsolidatedFullIsolate(String body) {
  return StockVerificationReportResponse.fromJson(
    _decodeJsonObject(body),
    includeItems: true,
  );
}

Map<String, dynamic> parseBatchDetailsFromStringIsolate(String body) {
  return parseBatchDetailsIsolate(_decodeJsonObject(body));
}

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

  /// Raw payload kept for detail/export so the tree can skip item rows.
  String? _consolidatedBody;
  String? _consolidatedCacheDate;

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

  Future<void>? _sessionsInFlight;
  Future<void>? _consolidatedInFlight;
  String? _consolidatedInFlightDate;
  int _sessionsFetchId = 0;

  String get clientCode {
    final employee = _prefService.getEmployee();
    final fromEmployee = employee?.clientCode?.trim() ?? '';
    if (fromEmployee.isNotEmpty) return fromEmployee;
    final fromNested = employee?.clients?.clientCode?.trim() ?? '';
    if (fromNested.isNotEmpty) return fromNested;
    return _prefService.getClient()?.clientCode?.trim() ?? '';
  }

  Future<void> loadBranches() async {
    if (_branches.isNotEmpty) return;
    try {
      final raw = await _apiService.getAllBranches(clientCode);
      _branches = raw.map((e) => ReportBranchOption.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('loadBranches: $e');
    }
  }

  Future<void> fetchConsolidatedReport(String reportDate, {bool force = false}) async {
    if (!force &&
        _consolidatedCacheDate == reportDate &&
        _consolidatedReport != null &&
        _consolidatedState == ReportLoadState.success) {
      return;
    }
    if (_consolidatedInFlight != null && _consolidatedInFlightDate == reportDate) {
      await _consolidatedInFlight;
      return;
    }

    _consolidatedState = ReportLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final pending = _doFetchConsolidated(reportDate);
    _consolidatedInFlight = pending;
    _consolidatedInFlightDate = reportDate;
    try {
      await pending;
    } finally {
      if (_consolidatedInFlightDate == reportDate) {
        _consolidatedInFlight = null;
        _consolidatedInFlightDate = null;
      }
    }
  }

  Future<void> _doFetchConsolidated(String reportDate) async {
    try {
      final body = await _apiService.getConsolidatedStockVerificationReportRaw(
        clientCode: clientCode,
        reportDate: reportDate,
      );
      if (body == null || body.isEmpty) {
        _consolidatedReport = null;
        _consolidatedBody = null;
        _consolidatedCacheDate = null;
        _consolidatedState = ReportLoadState.error;
        _errorMessage = 'No report data';
        notifyListeners();
        return;
      }
      // Tree without item rows — same early paint as the web report.
      final tree = await compute(parseConsolidatedTreeIsolate, body);
      _consolidatedBody = body;
      _consolidatedCacheDate = reportDate;
      _consolidatedReport = tree;
      _consolidatedState = ReportLoadState.success;
      notifyListeners();
    } catch (e) {
      _consolidatedState = ReportLoadState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> fetchSessions({bool force = false}) async {
    if (_sessionsInFlight != null) {
      await _sessionsInFlight;
      return;
    }
    final hasSessions = _originalSessions.isNotEmpty && _sessionState == ReportLoadState.success;
    if (!force && hasSessions) {
      return;
    }

    final keepListVisible = _originalSessions.isNotEmpty;
    if (!keepListVisible) {
      _sessionState = ReportLoadState.loading;
      _errorMessage = null;
      notifyListeners();
    }

    final pending = _doFetchSessions();
    _sessionsInFlight = pending;
    try {
      await pending;
    } finally {
      if (identical(_sessionsInFlight, pending)) {
        _sessionsInFlight = null;
      }
    }
  }

  Future<void> _doFetchSessions() async {
    final fetchId = ++_sessionsFetchId;
    final previousOriginal = List<ReportSessionItem>.from(_originalSessions);
    final previousList = _sessionList;
    Object? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      if (fetchId != _sessionsFetchId) return;
      try {
        var code = clientCode;
        if (code.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (fetchId != _sessionsFetchId) return;
          code = clientCode;
        }
        debugPrint('BatchWise fetch attempt=$attempt ClientCode="$code"');
        if (code.isEmpty) {
          lastError = 'No sessions found';
          break;
        }

        final raw = await _apiService.getAllStockVerificationSessions(code);
        if (fetchId != _sessionsFetchId) return;
        if (raw == null) {
          lastError = 'No sessions found';
          if (attempt < 3) {
            await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
            continue;
          }
          break;
        }

        final list = SessionListResponse.fromJson(raw);
        debugPrint(
          'BatchWise sessions=${list.sessions.length} '
          'total=${list.totalSessions} keys=${raw.keys.toList()}',
        );
        if (list.sessions.isNotEmpty) {
          if (fetchId != _sessionsFetchId) return;
          _originalSessions = List<ReportSessionItem>.from(list.sessions);
          _sessionList = list;
          _sessionState = ReportLoadState.success;
          _errorMessage = null;
          notifyListeners();
          return;
        }

        lastError = 'No sessions found';
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      } catch (e) {
        lastError = e;
        debugPrint('BatchWise fetch attempt=$attempt error=$e');
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }

    if (fetchId != _sessionsFetchId) return;
    if (previousOriginal.isNotEmpty) {
      _originalSessions = previousOriginal;
      _sessionList = previousList;
      _sessionState = ReportLoadState.success;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    _sessionList = null;
    _originalSessions = [];
    _sessionState = ReportLoadState.error;
    _errorMessage = lastError?.toString() ?? 'No sessions found';
    notifyListeners();
  }

  void filterSessions({int? branchId, required String fromDate, required String toDate}) {
    if (_sessionList == null) return;
    String dateKey(String startedOn) {
      final s = startedOn.trim();
      if (s.length >= 10 && s[4] == '-') return s.substring(0, 10);
      final match = RegExp(r'^(\d{2})[/-](\d{2})[/-](\d{4})').firstMatch(s);
      if (match != null) return '${match[3]}-${match[2]}-${match[1]}';
      return s.length >= 10 ? s.substring(0, 10) : s;
    }

    final filtered = _originalSessions.where((session) {
      final branchMatch = branchId == null || session.branchId == branchId;
      final dateStr = dateKey(session.startedOn);
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
      final body = await _apiService.getStockVerificationBatchDetailsRaw(
        clientCode: clientCode,
        scanBatchId: scanBatchId,
      );
      if (body == null || body.isEmpty) {
        _batchDetails = null;
        _batchDetailsState = ReportLoadState.error;
        _errorMessage = 'No batch details';
        notifyListeners();
        return;
      }

      final compact = await compute(parseBatchDetailsFromStringIsolate, body);
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
      var body = _consolidatedBody;
      if (body == null || _consolidatedCacheDate != date) {
        body = await _apiService.getConsolidatedStockVerificationReportRaw(
          clientCode: clientCode,
          reportDate: date,
        );
        if (body != null && body.isNotEmpty) {
          _consolidatedBody = body;
          _consolidatedCacheDate = date;
        }
      }
      if (body == null || body.isEmpty) {
        _detailItems = [];
        _detailState = ReportLoadState.error;
        _errorMessage = 'No data available';
        notifyListeners();
        return;
      }

      final rawItems = await compute(extractConsolidatedItemsIsolate, <String, dynamic>{
        'body': body,
        'branchId': branchId,
        'type': type,
        'categoryId': categoryId,
        'productId': productId,
        'designId': designId,
      });
      _detailItems = rawItems.map(ReportItem.fromJson).toList();
      _detailState = ReportLoadState.success;
    } catch (e) {
      _detailState = ReportLoadState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<String?> exportConsolidatedReport(void Function(int count)? onProgress) async {
    if (_consolidatedReport == null && (_consolidatedBody == null || _consolidatedBody!.isEmpty)) {
      return 'No report to export';
    }
    _isExporting = true;
    _exportProgress = 0;
    notifyListeners();

    try {
      var report = _consolidatedReport;
      final hasItems = report?.branches.any(
            (b) => b.categories.any(
              (c) => c.products.any((p) => p.designs.any((d) => d.items.isNotEmpty)),
            ),
          ) ??
          false;
      if (!hasItems && _consolidatedBody != null && _consolidatedBody!.isNotEmpty) {
        report = await compute(parseConsolidatedFullIsolate, _consolidatedBody!);
      }
      if (report == null) return 'No report to export';
      final file = await ConsolidatedReportExportService.exportToCsv(
        report: report,
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
