Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      return {
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
  }
  return null;
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

List<ReportItem> _parseReportItems(dynamic raw) {
  if (raw is! List) return const [];
  final out = <ReportItem>[];
  for (final e in raw) {
    final map = _asStringKeyedMap(e);
    if (map != null) out.add(ReportItem.fromJson(map));
  }
  return out;
}

dynamic _unwrapDotNetList(dynamic value) {
  final map = _asStringKeyedMap(value);
  if (map == null) return value;
  return map[r'$values'] ?? map[r'$Values'] ?? map['Values'] ?? value;
}

bool _isSkippedSessionSearchKey(String lower) {
  return lower == 'matchedlist' ||
      lower == 'unmatchedlist' ||
      lower == 'items' ||
      lower == 'branches' ||
      lower == 'categories' ||
      lower == 'products' ||
      lower == 'designs' ||
      lower == 'images';
}

bool _isSessionRow(dynamic value) {
  final map = _asStringKeyedMap(_unwrapDotNetList(value));
  if (map == null) return false;
  for (final key in map.keys) {
    final lower = key.toString().toLowerCase().replaceAll('_', '');
    if (lower == 'scanbatchid' ||
        lower == 'sessionid' ||
        lower == 'sessionnumber' ||
        lower == 'batchname') {
      return true;
    }
  }
  return false;
}

List<dynamic>? _asSessionRows(dynamic value) {
  final unwrapped = _unwrapDotNetList(value);
  if (unwrapped is! List) return null;
  if (unwrapped.isEmpty) return unwrapped;
  for (final item in unwrapped) {
    if (_isSessionRow(item)) return unwrapped;
  }
  return null;
}

List<dynamic>? _findSessionsList(dynamic node, [int depth = 0]) {
  if (depth > 6 || node == null) return null;

  final unwrapped = _unwrapDotNetList(node);
  final direct = _asSessionRows(unwrapped);
  if (direct != null && direct.isNotEmpty) return direct;

  final json = _asStringKeyedMap(unwrapped);
  if (json == null) {
    if (unwrapped is List) {
      for (final item in unwrapped) {
        final found = _findSessionsList(item, depth + 1);
        if (found != null && found.isNotEmpty) return found;
      }
    }
    return direct;
  }

  List<dynamic>? emptyHit;

  List<dynamic>? fromExactKey(String lowerKey) {
    for (final key in json.keys) {
      if (key.toString().trim().toLowerCase() != lowerKey) continue;
      final unwrapped = _unwrapDotNetList(json[key]);
      if (unwrapped is List) {
        if (unwrapped.isNotEmpty) return unwrapped;
        emptyHit ??= unwrapped;
      }
      final nested = _findSessionsList(json[key], depth + 1);
      if (nested != null && nested.isNotEmpty) return nested;
    }
    return null;
  }

  for (final key in const ['sessions', 'sessionlist', 'session', 'scanbatches', 'batches']) {
    final found = fromExactKey(key);
    if (found != null && found.isNotEmpty) return found;
  }

  for (final entry in json.entries) {
    final lower = entry.key.toString().trim().toLowerCase();
    if (_isSkippedSessionSearchKey(lower)) continue;
    final found = _asSessionRows(entry.value);
    if (found != null && found.isNotEmpty) return found;
  }

  for (final entry in json.entries) {
    final lower = entry.key.toString().trim().toLowerCase();
    if (_isSkippedSessionSearchKey(lower)) continue;
    final nested = _asStringKeyedMap(_unwrapDotNetList(entry.value));
    if (nested == null) continue;
    final found = _findSessionsList(nested, depth + 1);
    if (found != null && found.isNotEmpty) return found;
    if (found != null) emptyHit ??= found;
  }

  final hasWrapperKeys = json.keys.any((key) {
    final lower = key.toString().trim().toLowerCase();
    return lower == 'sessions' ||
        lower == 'sessionlist' ||
        lower == 'totalsessions' ||
        lower == 'message';
  });
  if (!hasWrapperKeys && _isSessionRow(json)) {
    return [json];
  }

  return emptyHit;
}

class ReportSessionItem {
  final int sessionNumber;
  final String sessionId;
  final String scanBatchId;
  final String batchName;
  final int? branchId;
  final String? branchName;
  final String startedOn;
  final String endedOn;
  final int totalQty;
  final int matchQty;
  final int unmatchQty;

  ReportSessionItem({
    required this.sessionNumber,
    required this.sessionId,
    required this.scanBatchId,
    required this.batchName,
    this.branchId,
    this.branchName,
    required this.startedOn,
    required this.endedOn,
    required this.totalQty,
    required this.matchQty,
    required this.unmatchQty,
  });

  factory ReportSessionItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    String str(dynamic value) {
      if (value == null) return '';
      final text = value.toString().trim();
      return text == 'null' ? '' : text;
    }

    return ReportSessionItem(
      sessionNumber: asInt(json['SessionNumber'] ?? json['sessionNumber']),
      sessionId: str(json['SessionId'] ?? json['sessionId']),
      scanBatchId: str(
        json['ScanBatchId'] ?? json['scanBatchId'] ?? json['ScanBatchID'],
      ),
      batchName: str(json['BatchName'] ?? json['batchName']),
      branchId: json['BranchId'] is int
          ? json['BranchId'] as int
          : int.tryParse('${json['BranchId'] ?? json['branchId'] ?? ''}'),
      branchName: json['BranchName']?.toString() ?? json['branchName']?.toString(),
      startedOn: str(json['StartedOn'] ?? json['startedOn']),
      endedOn: str(json['EndedOn'] ?? json['endedOn']),
      totalQty: asInt(json['TotalQty'] ?? json['totalQty']),
      matchQty: asInt(json['MatchQty'] ?? json['matchQty'] ?? json['MatchedQty']),
      unmatchQty: asInt(json['UnmatchQty'] ?? json['unmatchQty'] ?? json['UnmatchedQty']),
    );
  }
}

class SessionListResponse {
  final String message;
  final String clientCode;
  final int totalSessions;
  final List<ReportSessionItem> sessions;

  SessionListResponse({
    required this.message,
    required this.clientCode,
    required this.totalSessions,
    required this.sessions,
  });

  factory SessionListResponse.fromJson(Map<String, dynamic> json) {
    var raw = _findSessionsList(json);
    if (raw == null || raw.isEmpty) {
      final fallback = _unwrapDotNetList(json['Sessions'] ?? json['sessions']);
      if (fallback is List && fallback.isNotEmpty) {
        raw = fallback;
      }
    }
    final sessions = <ReportSessionItem>[];
    if (raw != null) {
      for (final e in raw) {
        final map = _asStringKeyedMap(_unwrapDotNetList(e));
        if (map != null) sessions.add(ReportSessionItem.fromJson(map));
      }
    }
    return SessionListResponse(
      message: json['Message']?.toString() ?? json['message']?.toString() ?? '',
      clientCode: json['ClientCode']?.toString() ?? json['clientCode']?.toString() ?? '',
      totalSessions: _asInt(json['TotalSessions'] ?? json['totalSessions'] ?? sessions.length),
      sessions: sessions,
    );
  }

  SessionListResponse copyWith({List<ReportSessionItem>? sessions}) {
    return SessionListResponse(
      message: message,
      clientCode: clientCode,
      totalSessions: totalSessions,
      sessions: sessions ?? this.sessions,
    );
  }
}

class ReportItem {
  final String? itemCode;
  final String? rfidCode;
  final String? tidNumber;
  final String? status;
  final double? grossWeight;
  final double? netWeight;
  final String? categoryName;
  final String? productName;
  final String? designName;

  ReportItem({
    this.itemCode,
    this.rfidCode,
    this.tidNumber,
    this.status,
    this.grossWeight,
    this.netWeight,
    this.categoryName,
    this.productName,
    this.designName,
  });

  factory ReportItem.fromJson(Map<String, dynamic> json) {
    double? d(dynamic v) => v == null ? null : double.tryParse(v.toString());
    return ReportItem(
      itemCode: json['ItemCode']?.toString(),
      rfidCode: json['RFIDCode']?.toString(),
      tidNumber: json['TIDNumber']?.toString(),
      status: json['Status']?.toString(),
      grossWeight: d(json['GrossWeight']),
      netWeight: d(json['NetWeight']),
      categoryName: json['CategoryName']?.toString(),
      productName: json['ProductName']?.toString(),
      designName: json['DesignName']?.toString(),
    );
  }
}

class ReportDesign {
  final int? designId;
  final String? designName;
  final int? totalInventoryItems;
  final int? totalScannedItems;
  final int? notScannedItems;
  final List<ReportItem> items;

  ReportDesign({
    this.designId,
    this.designName,
    this.totalInventoryItems,
    this.totalScannedItems,
    this.notScannedItems,
    required this.items,
  });

  factory ReportDesign.fromJson(Map<String, dynamic> json, {bool includeItems = true}) {
    final raw = includeItems ? (json['Items'] ?? json['items']) : null;
    return ReportDesign(
      designId: json['DesignId'] as int? ?? json['designId'] as int?,
      designName: json['DesignName']?.toString() ?? json['designName']?.toString(),
      totalInventoryItems: json['TotalInventoryItems'] as int? ?? json['totalInventoryItems'] as int?,
      totalScannedItems: json['TotalScannedItems'] as int? ?? json['totalScannedItems'] as int?,
      notScannedItems: json['NotScannedItems'] as int? ?? json['notScannedItems'] as int?,
      items: _parseReportItems(raw),
    );
  }
}

class ReportProduct {
  final int? productId;
  final String? productName;
  final int? totalInventoryItems;
  final int? totalScannedItems;
  final int? notScannedItems;
  final List<ReportDesign> designs;

  ReportProduct({
    this.productId,
    this.productName,
    this.totalInventoryItems,
    this.totalScannedItems,
    this.notScannedItems,
    required this.designs,
  });

  factory ReportProduct.fromJson(Map<String, dynamic> json, {bool includeItems = true}) {
    final raw = json['Designs'] ?? json['designs'];
    final designs = <ReportDesign>[];
    if (raw is List) {
      for (final e in raw) {
        final map = _asStringKeyedMap(e);
        if (map != null) designs.add(ReportDesign.fromJson(map, includeItems: includeItems));
      }
    }
    return ReportProduct(
      productId: json['ProductId'] as int? ?? json['productId'] as int?,
      productName: json['ProductName']?.toString() ?? json['productName']?.toString(),
      totalInventoryItems: json['TotalInventoryItems'] as int? ?? json['totalInventoryItems'] as int?,
      totalScannedItems: json['TotalScannedItems'] as int? ?? json['totalScannedItems'] as int?,
      notScannedItems: json['NotScannedItems'] as int? ?? json['notScannedItems'] as int?,
      designs: designs,
    );
  }
}

class ReportCategory {
  final int? categoryId;
  final String? categoryName;
  final int? totalInventoryItems;
  final int? totalScannedItems;
  final int? notScannedItems;
  final List<ReportProduct> products;

  ReportCategory({
    this.categoryId,
    this.categoryName,
    this.totalInventoryItems,
    this.totalScannedItems,
    this.notScannedItems,
    required this.products,
  });

  factory ReportCategory.fromJson(Map<String, dynamic> json, {bool includeItems = true}) {
    final raw = json['Products'] ?? json['products'];
    final products = <ReportProduct>[];
    if (raw is List) {
      for (final e in raw) {
        final map = _asStringKeyedMap(e);
        if (map != null) products.add(ReportProduct.fromJson(map, includeItems: includeItems));
      }
    }
    return ReportCategory(
      categoryId: json['CategoryId'] as int? ?? json['categoryId'] as int?,
      categoryName: json['CategoryName']?.toString() ?? json['categoryName']?.toString(),
      totalInventoryItems: json['TotalInventoryItems'] as int? ?? json['totalInventoryItems'] as int?,
      totalScannedItems: json['TotalScannedItems'] as int? ?? json['totalScannedItems'] as int?,
      notScannedItems: json['NotScannedItems'] as int? ?? json['notScannedItems'] as int?,
      products: products,
    );
  }
}

class ReportBranch {
  final int? branchId;
  final String? branchName;
  final int? totalInventoryItems;
  final int? totalScannedItems;
  final int? notScannedItems;
  final List<ReportCategory> categories;

  ReportBranch({
    this.branchId,
    this.branchName,
    this.totalInventoryItems,
    this.totalScannedItems,
    this.notScannedItems,
    required this.categories,
  });

  factory ReportBranch.fromJson(Map<String, dynamic> json, {bool includeItems = true}) {
    final raw = json['Categories'] ?? json['categories'];
    final categories = <ReportCategory>[];
    if (raw is List) {
      for (final e in raw) {
        final map = _asStringKeyedMap(e);
        if (map != null) categories.add(ReportCategory.fromJson(map, includeItems: includeItems));
      }
    }
    return ReportBranch(
      branchId: json['BranchId'] as int? ?? json['branchId'] as int?,
      branchName: json['BranchName']?.toString() ?? json['branchName']?.toString(),
      totalInventoryItems: json['TotalInventoryItems'] as int? ?? json['totalInventoryItems'] as int?,
      totalScannedItems: json['TotalScannedItems'] as int? ?? json['totalScannedItems'] as int?,
      notScannedItems: json['NotScannedItems'] as int? ?? json['notScannedItems'] as int?,
      categories: categories,
    );
  }
}

class StockVerificationReportResponse {
  final String? message;
  final String? reportDate;
  final int? totalRecordsFetched;
  final List<ReportBranch> branches;

  StockVerificationReportResponse({
    this.message,
    this.reportDate,
    this.totalRecordsFetched,
    required this.branches,
  });

  factory StockVerificationReportResponse.fromJson(
    Map<String, dynamic> json, {
    bool includeItems = true,
  }) {
    final raw = json['Branches'] ?? json['branches'];
    final branches = <ReportBranch>[];
    if (raw is List) {
      for (final e in raw) {
        final map = _asStringKeyedMap(e);
        if (map != null) {
          branches.add(ReportBranch.fromJson(map, includeItems: includeItems));
        }
      }
    }
    return StockVerificationReportResponse(
      message: json['Message']?.toString() ?? json['message']?.toString(),
      reportDate: json['ReportDate']?.toString() ?? json['reportDate']?.toString(),
      totalRecordsFetched: json['TotalRecordsFetched'] as int? ?? json['totalRecordsFetched'] as int?,
      branches: branches,
    );
  }

  /// Flatten all items from hierarchy — used for export.
  Iterable<ReportItem> iterateAllItems() sync* {
    for (final branch in branches) {
      for (final category in branch.categories) {
        for (final product in category.products) {
          for (final design in product.designs) {
            yield* design.items;
          }
        }
      }
    }
  }
}

class BatchReportItem {
  final String? itemCode;
  final String? productName;
  final String? branchName;
  final String? categoryName;
  final String? rfidCode;

  BatchReportItem({
    this.itemCode,
    this.productName,
    this.branchName,
    this.categoryName,
    this.rfidCode,
  });

  factory BatchReportItem.fromJson(Map<String, dynamic> json) {
    return BatchReportItem(
      itemCode: json['ItemCode']?.toString(),
      productName: json['ProductName']?.toString(),
      branchName: json['BranchName']?.toString(),
      categoryName: json['CategoryName']?.toString(),
      rfidCode: json['RFIDCode']?.toString(),
    );
  }

  factory BatchReportItem.fromCompact(Map<String, String?> json) {
    return BatchReportItem(
      itemCode: json['itemCode'],
      productName: json['productName'],
      branchName: json['branchName'],
      categoryName: json['categoryName'],
      rfidCode: json['rfidCode'],
    );
  }

  Map<String, String?> toCompact() => {
        'itemCode': itemCode,
        'productName': productName,
        'branchName': branchName,
        'categoryName': categoryName,
        'rfidCode': rfidCode,
      };
}

class BatchDetailsResponse {
  final String? message;
  final String? scanBatchId;
  final String? batchName;
  final List<BatchReportItem> matchedList;
  final List<BatchReportItem> unmatchedList;

  BatchDetailsResponse({
    this.message,
    this.scanBatchId,
    this.batchName,
    required this.matchedList,
    required this.unmatchedList,
  });

  factory BatchDetailsResponse.fromJson(Map<String, dynamic> json) {
    List<BatchReportItem> parseList(dynamic raw) {
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => BatchReportItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return BatchDetailsResponse(
      message: json['Message']?.toString(),
      scanBatchId: json['ScanBatchId']?.toString(),
      batchName: json['BatchName']?.toString(),
      matchedList: parseList(json['MatchedList'] ?? json['matchedList']),
      unmatchedList: parseList(json['UnmatchedList'] ?? json['unmatchedList']),
    );
  }

  factory BatchDetailsResponse.fromCompact(Map<String, dynamic> compact) {
    List<BatchReportItem> parseList(dynamic raw) {
      if (raw is! List) return [];
      return raw.map((e) {
        if (e is Map<String, String?>) return BatchReportItem.fromCompact(e);
        if (e is Map) {
          return BatchReportItem.fromCompact({
            'itemCode': e['itemCode']?.toString(),
            'productName': e['productName']?.toString(),
            'branchName': e['branchName']?.toString(),
            'categoryName': e['categoryName']?.toString(),
            'rfidCode': e['rfidCode']?.toString(),
          });
        }
        return BatchReportItem();
      }).toList();
    }

    return BatchDetailsResponse(
      message: compact['message']?.toString(),
      scanBatchId: compact['scanBatchId']?.toString(),
      batchName: compact['batchName']?.toString(),
      matchedList: parseList(compact['matchedList']),
      unmatchedList: parseList(compact['unmatchedList']),
    );
  }
}

class ReportBranchOption {
  final int id;
  final String name;

  ReportBranchOption({required this.id, required this.name});

  factory ReportBranchOption.fromJson(Map<String, dynamic> json) {
    return ReportBranchOption(
      id: json['Id'] as int? ?? 0,
      name: json['BranchName']?.toString() ?? '',
    );
  }
}
