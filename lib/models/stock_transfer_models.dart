class TransferType {
  final int id;
  final String transferType;
  final String clientCode;

  TransferType({
    required this.id,
    required this.transferType,
    required this.clientCode,
  });

  factory TransferType.fromJson(Map<String, dynamic> json) => TransferType(
        id: (json['Id'] as num?)?.toInt() ?? 0,
        transferType: json['TransferType']?.toString() ?? '',
        clientCode: json['ClientCode']?.toString() ?? '',
      );
}

class StockTransferItemPayload {
  final int stockId;

  StockTransferItemPayload({required this.stockId});

  Map<String, dynamic> toJson() => {'stockId': stockId};
}

class StockTransferRequest {
  final String clientCode;
  final List<StockTransferItemPayload> stockTransferItems;
  final String stockType;
  final String stockTransferTypeName;
  final int transferTypeId;
  final String transferByEmployee;
  final String transferedToBranch;
  final String transferToEmployee;
  final String transferedBranch;
  final int source;
  final int destination;
  final String remarks;
  final String stockTransferDate;
  final String receivedByEmployee;

  StockTransferRequest({
    required this.clientCode,
    required this.stockTransferItems,
    required this.stockType,
    required this.stockTransferTypeName,
    required this.transferTypeId,
    required this.transferByEmployee,
    required this.transferedToBranch,
    required this.transferToEmployee,
    required this.transferedBranch,
    required this.source,
    required this.destination,
    required this.remarks,
    required this.stockTransferDate,
    required this.receivedByEmployee,
  });

  Map<String, dynamic> toJson() => {
        'ClientCode': clientCode,
        'StockTransferItems': stockTransferItems.map((e) => e.toJson()).toList(),
        'StockType': stockType,
        'StockTransferTypeName': stockTransferTypeName,
        'TransferTypeId': transferTypeId,
        'TransferByEmployee': transferByEmployee,
        'TransferedToBranch': transferedToBranch,
        'TransferToEmployee': transferToEmployee,
        'TransferedBranch': transferedBranch,
        'Source': source,
        'Destination': destination,
        'Remarks': remarks,
        'StockTransferDate': stockTransferDate,
        'ReceivedByEmployee': receivedByEmployee,
      };
}

class StockInOutRequest {
  final String clientCode;
  final String stockType;
  final int? transferType;
  final dynamic branchId;
  final int userId;
  final String requestType;

  StockInOutRequest({
    required this.clientCode,
    this.stockType = 'labelled',
    this.transferType,
    required this.branchId,
    required this.userId,
    required this.requestType,
  });

  Map<String, dynamic> toJson() => {
        'ClientCode': clientCode,
        'StockType': stockType,
        'TransferType': transferType,
        'BranchId': branchId,
        'UserID': userId,
        'RequestType': requestType,
      };
}

/// RequestStatus: 0 pending, 1 approved, 2 rejected, 3 lost (same as Sparkle).
int? parseTransferRequestStatus(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toInt();
  final s = raw.toString().trim().toLowerCase();
  if (s.isEmpty || s == 'null') return null;
  final asInt = int.tryParse(s);
  if (asInt != null) return asInt;
  if (s.contains('approv')) return 1;
  if (s.contains('reject')) return 2;
  if (s.contains('lost')) return 3;
  if (s.contains('pending')) return 0;
  return null;
}

String transferStatusLabel(int? status, {String pending = 'Pending'}) {
  return switch (status) {
    1 => 'Approved',
    2 => 'Rejected',
    3 => 'Lost',
    _ => pending,
  };
}

class LabelledStockItem {
  final int? id;
  final int? transferItemId;
  final String? itemCode;
  final String? rfidCode;
  final int? requestStatus;
  final String? productName;
  final String? grossWeight;
  final String? netWeight;

  LabelledStockItem({
    this.id,
    this.transferItemId,
    this.itemCode,
    this.rfidCode,
    this.requestStatus,
    this.productName,
    this.grossWeight,
    this.netWeight,
  });

  factory LabelledStockItem.fromJson(Map<String, dynamic> json) => LabelledStockItem(
        id: (json['Id'] as num?)?.toInt() ?? (json['LabelledStockId'] as num?)?.toInt(),
        transferItemId: (json['TransferItemId'] as num?)?.toInt() ??
            (json['Id'] as num?)?.toInt(),
        itemCode: json['ItemCode']?.toString(),
        rfidCode: json['RFIDCode']?.toString() ?? json['RFID']?.toString(),
        requestStatus: parseTransferRequestStatus(
          json['RequestStatus'] ?? json['Status'],
        ),
        productName: json['ProductTitle']?.toString() ??
            json['ProductName']?.toString(),
        grossWeight: json['GrossWeight']?.toString() ?? json['GrossWt']?.toString(),
        netWeight: json['NetWeight']?.toString() ?? json['NetWt']?.toString(),
      );

  /// Approve API needs TransferItemId (or line Id), not ItemCode/RFID.
  int get approveId =>
      (transferItemId != null && transferItemId! > 0) ? transferItemId! : (id ?? 0);
}

class StockTransferInOutItem {
  final int id;
  final int transferTypeId;
  final int? source;
  final int? destination;
  final String sourceName;
  final String destinationName;
  final String transferByEmployee;
  final String transferToEmployee;
  final String transferedToBranch;
  final String receivedByEmployee;
  final String stockTransferTypeName;
  final int pending;
  final int approved;
  final int rejected;
  final int lost;
  final String requestType;
  final List<LabelledStockItem> labelledStockItems;

  StockTransferInOutItem({
    required this.id,
    required this.transferTypeId,
    this.source,
    this.destination,
    required this.sourceName,
    required this.destinationName,
    required this.transferByEmployee,
    required this.transferToEmployee,
    required this.transferedToBranch,
    required this.receivedByEmployee,
    required this.stockTransferTypeName,
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.lost,
    required this.requestType,
    this.labelledStockItems = const [],
  });

  factory StockTransferInOutItem.fromJson(Map<String, dynamic> json) {
    final items = <LabelledStockItem>[];
    final labelled = json['LabelledStockItems'];
    if (labelled is List && labelled.isNotEmpty) {
      for (final e in labelled) {
        if (e is Map<String, dynamic>) items.add(LabelledStockItem.fromJson(e));
      }
    } else {
      final lines = json['StockTransferItems'];
      if (lines is List) {
        for (final e in lines) {
          if (e is Map<String, dynamic>) items.add(LabelledStockItem.fromJson(e));
        }
      }
    }

    return StockTransferInOutItem(
      id: (json['Id'] as num?)?.toInt() ?? 0,
      transferTypeId: (json['TransferTypeId'] as num?)?.toInt() ?? 0,
      source: (json['Source'] as num?)?.toInt(),
      destination: (json['Destination'] as num?)?.toInt(),
      sourceName: json['SourceName']?.toString() ?? '',
      destinationName: json['DestinationName']?.toString() ?? '',
      transferByEmployee: json['TransferByEmployee']?.toString() ?? '',
      transferToEmployee: json['TransferToEmployee']?.toString() ?? '',
      transferedToBranch: json['TransferedToBranch']?.toString() ?? '',
      receivedByEmployee: json['ReceivedByEmployee']?.toString() ?? '',
      stockTransferTypeName: json['StockTransferTypeName']?.toString() ?? '',
      pending: (json['Pending'] as num?)?.toInt() ?? 0,
      approved: (json['Approved'] as num?)?.toInt() ?? 0,
      rejected: (json['Rejected'] as num?)?.toInt() ?? 0,
      lost: (json['Lost'] as num?)?.toInt() ?? 0,
      requestType: json['RequestType']?.toString() ?? '',
      labelledStockItems: items,
    );
  }

  double get totalGrossWt => labelledStockItems.fold(0.0, (s, i) => s + (double.tryParse(i.grossWeight ?? '') ?? 0));
  double get totalNetWt => labelledStockItems.fold(0.0, (s, i) => s + (double.tryParse(i.netWeight ?? '') ?? 0));

  /// Same as Sparkle: branch-to-branch (15) is self only when by==to; other types always self.
  bool get isSelfApproval {
    const branchToBranchId = 15;
    final by = transferByEmployee.trim();
    final to = transferToEmployee.trim();
    if (transferTypeId == branchToBranchId) {
      return by.isNotEmpty && by == to;
    }
    return true;
  }

  String get transferToDisplay =>
      transferToEmployee.trim().isNotEmpty ? transferToEmployee : transferedToBranch;
}

class CancelStockTransferRequest {
  final int id;
  final String clientCode;

  CancelStockTransferRequest({required this.id, required this.clientCode});

  Map<String, dynamic> toJson() => {'Id': id, 'ClientCode': clientCode};
}

class StApproveRejectItem {
  final int id;
  final bool approved;
  final int status;

  StApproveRejectItem({
    required this.id,
    required this.approved,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'Id': id,
        'Approved': approved,
        'Status': status,
      };
}

class StApproveRejectRequest {
  final List<StApproveRejectItem> stockTransferItems;
  final String clientCode;
  final String userId;
  final String requestTyp;

  StApproveRejectRequest({
    required this.stockTransferItems,
    required this.clientCode,
    required this.userId,
    required this.requestTyp,
  });

  Map<String, dynamic> toJson() => {
        'StockTransferItems': stockTransferItems.map((e) => e.toJson()).toList(),
        'ClientCode': clientCode,
        'UserID': userId,
        'RequestTyp': requestTyp,
      };
}
