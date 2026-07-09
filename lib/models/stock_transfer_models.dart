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

class LabelledStockItem {
  final int? transferItemId;
  final String? itemCode;
  final String? rfidCode;
  final String? requestStatus;
  final String? productName;
  final String? grossWeight;
  final String? netWeight;

  LabelledStockItem({
    this.transferItemId,
    this.itemCode,
    this.rfidCode,
    this.requestStatus,
    this.productName,
    this.grossWeight,
    this.netWeight,
  });

  factory LabelledStockItem.fromJson(Map<String, dynamic> json) => LabelledStockItem(
        transferItemId: (json['TransferItemId'] as num?)?.toInt(),
        itemCode: json['ItemCode']?.toString(),
        rfidCode: json['RFIDCode']?.toString() ?? json['RFID']?.toString(),
        requestStatus: json['RequestStatus']?.toString(),
        productName: json['ProductName']?.toString(),
        grossWeight: json['GrossWeight']?.toString() ?? json['GrossWt']?.toString(),
        netWeight: json['NetWeight']?.toString() ?? json['NetWt']?.toString(),
      );
}

class StockTransferInOutItem {
  final int id;
  final int transferTypeId;
  final String sourceName;
  final String destinationName;
  final String transferByEmployee;
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
    required this.sourceName,
    required this.destinationName,
    required this.transferByEmployee,
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
    final rawItems = json['LabelledStockItems'];
    final items = <LabelledStockItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map<String, dynamic>) items.add(LabelledStockItem.fromJson(e));
      }
    }
    return StockTransferInOutItem(
      id: (json['Id'] as num?)?.toInt() ?? 0,
      transferTypeId: (json['TransferTypeId'] as num?)?.toInt() ?? 0,
      sourceName: json['SourceName']?.toString() ?? '',
      destinationName: json['DestinationName']?.toString() ?? '',
      transferByEmployee: json['TransferByEmployee']?.toString() ?? '',
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
}

class CancelStockTransferRequest {
  final int id;
  final String clientCode;

  CancelStockTransferRequest({required this.id, required this.clientCode});

  Map<String, dynamic> toJson() => {'Id': id, 'ClientCode': clientCode};
}

class StApproveRejectRequest {
  final List<Map<String, String>> stockTransferItems;
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
        'StockTransferItems': stockTransferItems,
        'ClientCode': clientCode,
        'UserID': userId,
        'RequestTyp': requestTyp,
      };
}
