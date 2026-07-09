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
    return ReportSessionItem(
      sessionNumber: json['SessionNumber'] as int? ?? 0,
      sessionId: json['SessionId']?.toString() ?? '',
      scanBatchId: json['ScanBatchId']?.toString() ?? '',
      batchName: json['BatchName']?.toString() ?? '',
      branchId: json['BranchId'] as int?,
      branchName: json['BranchName']?.toString(),
      startedOn: json['StartedOn']?.toString() ?? '',
      endedOn: json['EndedOn']?.toString() ?? '',
      totalQty: json['TotalQty'] as int? ?? 0,
      matchQty: json['MatchQty'] as int? ?? 0,
      unmatchQty: json['UnmatchQty'] as int? ?? 0,
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
    final raw = json['Sessions'] as List? ?? [];
    return SessionListResponse(
      message: json['Message']?.toString() ?? '',
      clientCode: json['ClientCode']?.toString() ?? '',
      totalSessions: json['TotalSessions'] as int? ?? 0,
      sessions: raw.map((e) => ReportSessionItem.fromJson(e as Map<String, dynamic>)).toList(),
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

  factory ReportDesign.fromJson(Map<String, dynamic> json) {
    final raw = json['Items'] as List? ?? [];
    return ReportDesign(
      designId: json['DesignId'] as int?,
      designName: json['DesignName']?.toString(),
      totalInventoryItems: json['TotalInventoryItems'] as int?,
      totalScannedItems: json['TotalScannedItems'] as int?,
      notScannedItems: json['NotScannedItems'] as int?,
      items: raw.map((e) => ReportItem.fromJson(e as Map<String, dynamic>)).toList(),
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

  factory ReportProduct.fromJson(Map<String, dynamic> json) {
    final raw = json['Designs'] as List? ?? [];
    return ReportProduct(
      productId: json['ProductId'] as int?,
      productName: json['ProductName']?.toString(),
      totalInventoryItems: json['TotalInventoryItems'] as int?,
      totalScannedItems: json['TotalScannedItems'] as int?,
      notScannedItems: json['NotScannedItems'] as int?,
      designs: raw.map((e) => ReportDesign.fromJson(e as Map<String, dynamic>)).toList(),
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

  factory ReportCategory.fromJson(Map<String, dynamic> json) {
    final raw = json['Products'] as List? ?? [];
    return ReportCategory(
      categoryId: json['CategoryId'] as int?,
      categoryName: json['CategoryName']?.toString(),
      totalInventoryItems: json['TotalInventoryItems'] as int?,
      totalScannedItems: json['TotalScannedItems'] as int?,
      notScannedItems: json['NotScannedItems'] as int?,
      products: raw.map((e) => ReportProduct.fromJson(e as Map<String, dynamic>)).toList(),
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

  factory ReportBranch.fromJson(Map<String, dynamic> json) {
    final raw = json['Categories'] as List? ?? [];
    return ReportBranch(
      branchId: json['BranchId'] as int?,
      branchName: json['BranchName']?.toString(),
      totalInventoryItems: json['TotalInventoryItems'] as int?,
      totalScannedItems: json['TotalScannedItems'] as int?,
      notScannedItems: json['NotScannedItems'] as int?,
      categories: raw.map((e) => ReportCategory.fromJson(e as Map<String, dynamic>)).toList(),
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

  factory StockVerificationReportResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['Branches'] as List? ?? [];
    return StockVerificationReportResponse(
      message: json['Message']?.toString(),
      reportDate: json['ReportDate']?.toString(),
      totalRecordsFetched: json['TotalRecordsFetched'] as int?,
      branches: raw.map((e) => ReportBranch.fromJson(e as Map<String, dynamic>)).toList(),
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
    final matched = json['MatchedList'] as List? ?? [];
    final unmatched = json['UnmatchedList'] as List? ?? [];
    return BatchDetailsResponse(
      message: json['Message']?.toString(),
      scanBatchId: json['ScanBatchId']?.toString(),
      batchName: json['BatchName']?.toString(),
      matchedList: matched.map((e) => BatchReportItem.fromJson(e as Map<String, dynamic>)).toList(),
      unmatchedList: unmatched.map((e) => BatchReportItem.fromJson(e as Map<String, dynamic>)).toList(),
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
