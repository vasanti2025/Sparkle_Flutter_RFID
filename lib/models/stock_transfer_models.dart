class TransferType {
  final int id;
  final String transferType;
  final String clientCode;

  TransferType({
    required this.id,
    required this.transferType,
    required this.clientCode,
  });

  factory TransferType.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return TransferType(
      id: asInt(json['Id'] ?? json['id']),
      transferType: json['TransferType']?.toString() ?? json['transferType']?.toString() ?? '',
      clientCode: json['ClientCode']?.toString() ?? json['clientCode']?.toString() ?? '',
    );
  }
}

class StockTransferItemPayload {
  final int stockId;

  StockTransferItemPayload({required this.stockId});

  // Exact Sparkle Gson field name.
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

  Map<String, dynamic> toJson() {
    // Match Sparkle Gson: omit null TransferType entirely (do NOT send "TransferType":null).
    // ASP.NET often binds null as 0 and returns an empty Out/In list.
    final map = <String, dynamic>{
      'ClientCode': clientCode,
      'StockType': stockType,
      'BranchId': branchId,
      'UserID': userId,
      'RequestType': requestType,
    };
    if (transferType != null) {
      map['TransferType'] = transferType;
    }
    return map;
  }
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

dynamic _jsonPick(Map<dynamic, dynamic> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key) && json[key] != null) return json[key];
  }
  final lower = <String, dynamic>{};
  for (final entry in json.entries) {
    lower[entry.key.toString().toLowerCase()] = entry.value;
  }
  for (final key in keys) {
    final v = lower[key.toLowerCase()];
    if (v != null) return v;
  }
  return null;
}

String _jsonStr(Map<dynamic, dynamic> json, List<String> keys) {
  final v = _jsonPick(json, keys);
  if (v == null) return '';
  final s = v.toString().trim();
  if (s.isEmpty || s.toLowerCase() == 'null') return '';
  return s;
}

int? _jsonInt(Map<dynamic, dynamic> json, List<String> keys) {
  final v = _jsonPick(json, keys);
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

Map<String, dynamic>? _asStringMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

/// Sparkle parseTransferEndpointTypes: "Counter to Box" → (counter, box).
(String?, String?) parseTransferEndpointTypes(String? typeName) {
  final normalized = typeName?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
  if (normalized.isEmpty) return (null, null);
  final parts = normalized.split(RegExp(r'\s+to\s+', caseSensitive: false));
  if (parts.length < 2) return (null, null);
  return (parts[0].trim().toLowerCase(), parts[1].trim().toLowerCase());
}

String? cleanTransferLocationName(String? value) {
  final s = value?.trim() ?? '';
  if (s.isEmpty || s == '-' || s.toLowerCase() == 'null') return null;
  if (RegExp(r'^\d+$').hasMatch(s)) return null;
  return s;
}

class LabelledStockItem {
  final int? id;
  final int? transferItemId;
  final String? itemCode;
  final String? rfidCode;
  final int? requestStatus;
  final String? productName;
  final String? categoryName;
  final String? branchName;
  final String? grossWeight;
  final String? netWeight;
  final String? sourceName;
  final String? destinationName;
  final String? counterName;
  final String? boxName;
  final String? packetName;
  final int? counterId;
  final int? boxId;
  final int? packetId;
  final int? branchId;

  LabelledStockItem({
    this.id,
    this.transferItemId,
    this.itemCode,
    this.rfidCode,
    this.requestStatus,
    this.productName,
    this.categoryName,
    this.branchName,
    this.grossWeight,
    this.netWeight,
    this.sourceName,
    this.destinationName,
    this.counterName,
    this.boxName,
    this.packetName,
    this.counterId,
    this.boxId,
    this.packetId,
    this.branchId,
  });

  factory LabelledStockItem.fromJson(Map<String, dynamic> json) {
    // Sparkle lineItemToLabelledStock:
    //   Id = LabelledStockId/StockId
    //   TransferItemId = TransferItemId ?: line.Id
    final lineId = _jsonInt(json, const ['Id']);
    final transferItemId = _jsonInt(json, const ['TransferItemId']) ?? lineId;
    final stockId = _jsonInt(json, const ['LabelledStockId', 'StockId']) ?? lineId;

    return LabelledStockItem(
      id: stockId,
      transferItemId: transferItemId,
      itemCode: _jsonStr(json, const ['ItemCode']),
      rfidCode: _jsonStr(json, const ['RFIDCode', 'RFID']),
      requestStatus: parseTransferRequestStatus(
        _jsonPick(json, const ['RequestStatus', 'Status']),
      ),
      productName: _jsonStr(json, const ['ProductTitle', 'ProductName']),
      categoryName: _jsonStr(json, const ['CategoryName', 'Category']),
      branchName: _jsonStr(json, const ['BranchName', 'Branch']),
      grossWeight: _jsonStr(json, const ['GrossWeight', 'GrossWt']),
      netWeight: _jsonStr(json, const ['NetWeight', 'NetWt']),
      sourceName: _jsonStr(json, const ['SourceName']),
      destinationName: _jsonStr(json, const ['DestinationName']),
      counterName: _jsonStr(json, const ['CounterName']),
      boxName: _jsonStr(json, const ['BoxName']),
      packetName: _jsonStr(json, const ['PacketName']),
      counterId: _jsonInt(json, const ['CounterId']),
      boxId: _jsonInt(json, const ['BoxId']),
      packetId: _jsonInt(json, const ['PacketId']),
      branchId: _jsonInt(json, const ['BranchId']),
    );
  }

  String? locationNameForType(String? type) {
    return switch (type?.toLowerCase()) {
      'counter' => cleanTransferLocationName(counterName),
      'box' => cleanTransferLocationName(boxName),
      'packet' => cleanTransferLocationName(packetName),
      'branch' => cleanTransferLocationName(branchName),
      _ => null,
    };
  }

  int? locationIdForType(String? type) {
    return switch (type?.toLowerCase()) {
      'counter' => counterId,
      'box' => boxId,
      'packet' => packetId,
      'branch' => branchId,
      _ => null,
    };
  }

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
    void addRows(dynamic raw) {
      if (raw is! List) return;
      for (final e in raw) {
        final map = _asStringMap(e);
        if (map != null) items.add(LabelledStockItem.fromJson(map));
      }
    }

    addRows(_jsonPick(json, const ['LabelledStockItems', 'labelledStockItems']));
    if (items.isEmpty) {
      addRows(_jsonPick(json, const ['StockTransferItems', 'stockTransferItems']));
    }

    return StockTransferInOutItem(
      id: _jsonInt(json, const ['Id']) ?? 0,
      transferTypeId: _jsonInt(json, const ['TransferTypeId']) ?? 0,
      source: _jsonInt(json, const ['Source']),
      destination: _jsonInt(json, const ['Destination']),
      sourceName: _jsonStr(json, const ['SourceName']),
      destinationName: _jsonStr(json, const ['DestinationName']),
      transferByEmployee: _jsonStr(json, const ['TransferByEmployee']),
      transferToEmployee: _jsonStr(json, const ['TransferToEmployee']),
      transferedToBranch: _jsonStr(json, const ['TransferedToBranch']),
      receivedByEmployee: _jsonStr(json, const ['ReceivedByEmployee']),
      stockTransferTypeName: _jsonStr(json, const ['StockTransferTypeName']),
      pending: _jsonInt(json, const ['Pending']) ?? 0,
      approved: _jsonInt(json, const ['Approved']) ?? 0,
      rejected: _jsonInt(json, const ['Rejected']) ?? 0,
      lost: _jsonInt(json, const ['Lost']) ?? 0,
      requestType: _jsonStr(json, const ['RequestType']),
      labelledStockItems: items,
    );
  }

  StockTransferInOutItem withFromTo(String from, String to) {
    return StockTransferInOutItem(
      id: id,
      transferTypeId: transferTypeId,
      source: source,
      destination: destination,
      sourceName: from,
      destinationName: to,
      transferByEmployee: transferByEmployee,
      transferToEmployee: transferToEmployee,
      transferedToBranch: transferedToBranch,
      receivedByEmployee: receivedByEmployee,
      stockTransferTypeName: stockTransferTypeName,
      pending: pending,
      approved: approved,
      rejected: rejected,
      lost: lost,
      requestType: requestType,
      labelledStockItems: labelledStockItems,
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
