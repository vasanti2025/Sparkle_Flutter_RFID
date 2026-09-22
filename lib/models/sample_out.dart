import 'delivery_challan.dart';

/// Header/list model for Sample Out transactions (mirrors Kotlin SampleOutListResponse).
class SampleOutModel {
  final int id;
  final String sampleStatus;
  final String sampleOutNo;
  final bool statusType;
  final String createdOn;
  final String lastUpdated;
  final int customerId;
  final int quantity;
  final String totalWt;
  final String totalGrossWt;
  final String totalNetWt;
  final String totalStoneWeight;
  final String totalDiamondWeight;
  final String returnDate;
  final String description;
  final String date;
  final String clientCode;
  final int branchId;
  final List<Map<String, dynamic>> issueItems;
  /// Active API rows before de-dupe. Used on Update to inactivate leftover Ids.
  final List<Map<String, dynamic>> allActiveIssueItems;
  final String? customerFirstName;

  SampleOutModel({
    required this.id,
    required this.sampleStatus,
    required this.sampleOutNo,
    required this.statusType,
    required this.createdOn,
    required this.lastUpdated,
    required this.customerId,
    required this.quantity,
    required this.totalWt,
    required this.totalGrossWt,
    required this.totalNetWt,
    required this.totalStoneWeight,
    required this.totalDiamondWeight,
    required this.returnDate,
    required this.description,
    required this.date,
    required this.clientCode,
    required this.branchId,
    required this.issueItems,
    List<Map<String, dynamic>>? allActiveIssueItems,
    this.customerFirstName,
  }) : allActiveIssueItems = allActiveIssueItems ?? issueItems;

  factory SampleOutModel.fromJson(Map<String, dynamic> json) {
    final customer = json['Customer'] as Map<String, dynamic>?;
    final allActive = (json['IssueItems'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where(_isCurrentSampleOutLine)
        .toList();
    final items = _dedupeIssueItems(allActive);

    return SampleOutModel(
      id: _jsonInt(json['Id']),
      sampleStatus: json['SampleStatus']?.toString() ?? '',
      sampleOutNo: json['SampleOutNo']?.toString() ?? '',
      statusType: json['StatusType'] == true || json['StatusType'] == 1,
      createdOn: json['CreatedOn']?.toString() ?? '',
      lastUpdated: json['LastUpdated']?.toString() ?? '',
      customerId: _jsonInt(json['CustomerId']),
      quantity: items.length,
      totalWt: json['TotalWt']?.toString() ?? '0',
      totalGrossWt: json['TotalGrossWt']?.toString() ?? '0',
      totalNetWt: json['TotalNetWt']?.toString() ?? '0',
      totalStoneWeight: json['TotalStoneWeight']?.toString() ?? '0',
      totalDiamondWeight: json['TotalDiamondWeight']?.toString() ?? '0',
      returnDate: json['ReturnDate']?.toString() ?? '',
      description: json['Description']?.toString() ?? '',
      date: json['Date']?.toString() ?? '',
      clientCode: json['ClientCode']?.toString() ?? '',
      branchId: _jsonInt(json['BranchId']),
      issueItems: items,
      allActiveIssueItems: allActive,
      customerFirstName: customer?['FirstName']?.toString(),
    );
  }

  SampleOutModel copyWith({
    int? quantity,
    String? totalWt,
    String? totalGrossWt,
    String? totalNetWt,
    String? totalStoneWeight,
    String? totalDiamondWeight,
    String? returnDate,
    String? description,
    String? date,
    List<Map<String, dynamic>>? issueItems,
    List<Map<String, dynamic>>? allActiveIssueItems,
  }) {
    return SampleOutModel(
      id: id,
      sampleStatus: sampleStatus,
      sampleOutNo: sampleOutNo,
      statusType: statusType,
      createdOn: createdOn,
      lastUpdated: lastUpdated,
      customerId: customerId,
      quantity: quantity ?? this.quantity,
      totalWt: totalWt ?? this.totalWt,
      totalGrossWt: totalGrossWt ?? this.totalGrossWt,
      totalNetWt: totalNetWt ?? this.totalNetWt,
      totalStoneWeight: totalStoneWeight ?? this.totalStoneWeight,
      totalDiamondWeight: totalDiamondWeight ?? this.totalDiamondWeight,
      returnDate: returnDate ?? this.returnDate,
      description: description ?? this.description,
      date: date ?? this.date,
      clientCode: clientCode,
      branchId: branchId,
      issueItems: issueItems ?? this.issueItems,
      allActiveIssueItems: allActiveIssueItems ?? this.allActiveIssueItems,
      customerFirstName: customerFirstName,
    );
  }

  String get customerName => customerFirstName ?? '';

  static int _jsonInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _issueItemIsActive(Map<String, dynamic> item) {
    final status = item['StatusType'];
    if (status == false || status == 0 || status == 'false' || status == '0') {
      return false;
    }
    return true;
  }

  static bool _isCurrentSampleOutLine(Map<String, dynamic> item) {
    if (!_issueItemIsActive(item)) return false;
    final status = (item['SampleStatus']?.toString() ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(' ', '');
    if (status == 'samplein' || status == 'deleted' || status == 'cancelled') {
      return false;
    }
    return true;
  }

  static String _issueItemDedupeKey(Map<String, dynamic> item) {
    final stockId = _jsonInt(item['LabelledStockId']);
    if (stockId > 0) return 'sid:$stockId';
    final rfid = item['RFIDCode']?.toString().trim().toUpperCase() ?? '';
    if (rfid.isNotEmpty) return 'rfid:$rfid';
    final tid = item['TIDNumber']?.toString().trim().toUpperCase() ?? '';
    if (tid.isNotEmpty) return 'tid:$tid';
    final code = item['ItemCode']?.toString().trim().toUpperCase() ?? '';
    if (code.isNotEmpty) return 'code:$code';
    final id = _jsonInt(item['Id']);
    if (id > 0) return 'id:$id';
    return 'row:${identityHashCode(item)}';
  }

  static List<Map<String, dynamic>> _dedupeIssueItems(
    List<Map<String, dynamic>> items,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final key = _issueItemDedupeKey(item);
      final existing = byKey[key];
      if (existing == null || _jsonInt(item['Id']) >= _jsonInt(existing['Id'])) {
        byKey[key] = item;
      }
    }
    return byKey.values.toList();
  }

  /// Maps API issue item to line-item model used in the create/edit screen.
  static ChallanDetailsModel issueItemToDetails(Map<String, dynamic> json) {
    return ChallanDetailsModel(
      challanId: _jsonInt(json['Id']),
      mrp: '0.0',
      categoryName: json['CategoryName']?.toString() ?? '',
      challanStatus: json['SampleStatus']?.toString() ?? 'SampleOut',
      productName: json['ProductName']?.toString() ?? '',
      quantity: (json['Quantity'] ?? 1).toString(),
      hsnCode: '',
      itemCode: json['ItemCode']?.toString() ?? '',
      grossWt: json['GrossWt']?.toString() ?? '0.0',
      netWt: json['NetWt']?.toString() ?? '0.0',
      productId: _jsonInt(json['ProductId']),
      customerId: _jsonInt(json['CustomerId']),
      metalRate: json['RatePerGram']?.toString() ?? '0.0',
      makingCharg: json['MetalAmount']?.toString() ?? '0.0',
      price: json['MetalAmount']?.toString() ?? '0.0',
      huidCode: '',
      productCode: '',
      productNo: '',
      size: '1',
      stoneAmount: json['StoneAmount']?.toString() ?? '0.0',
      totalWt: json['TotalWt']?.toString() ?? json['NetWt']?.toString() ?? '0.0',
      packingWeight: '0.0',
      metalAmount: json['MetalAmount']?.toString() ?? '0.0',
      oldGoldPurchase: false,
      ratePerGram: json['RatePerGram']?.toString() ?? '0.0',
      amount: json['MetalAmount']?.toString() ?? '0.0',
      challanType: 'SampleOut',
      finePercentage: json['FinePercentage']?.toString() ?? '0.0',
      purchaseInvoiceNo: '',
      hallmarkAmount: '0.0',
      hallmarkNo: '',
      makingFixedAmt: '0.0',
      makingFixedWastage: '0.0',
      makingPerGram: '0.0',
      makingPercentage: '0.0',
      description: json['Description']?.toString() ?? '',
      cuttingGrossWt: json['GrossWt']?.toString() ?? '0.0',
      cuttingNetWt: json['NetWt']?.toString() ?? '0.0',
      baseCurrency: 'INR',
      categoryId: _jsonInt(json['CategoryId']),
      purityId: _jsonInt(json['PurityId']),
      totalStoneWeight: json['StoneWeight']?.toString() ?? '0.0',
      totalStoneAmount: json['StoneAmount']?.toString() ?? '0.0',
      totalStonePieces: '0',
      totalDiamondWeight: json['DiamondWeight']?.toString() ?? '0.0',
      totalDiamondPieces: '0',
      totalDiamondAmount: json['DiamondAmount']?.toString() ?? '0.0',
      skuId: _jsonInt(json['SKUId']),
      sku: json['SKU']?.toString() ?? '',
      fineWastageWt: json['FineWastageWt']?.toString() ?? '0.0',
      totalItemAmount: json['MetalAmount']?.toString() ?? '0.0',
      itemAmount: json['MetalAmount']?.toString() ?? '0.0',
      itemGSTAmount: '0.0',
      clientCode: json['ClientCode']?.toString() ?? '',
      diamondSize: '',
      diamondWeight: json['DiamondWeight']?.toString() ?? '0.0',
      diamondPurchaseRate: '0.0',
      diamondSellRate: '0.0',
      diamondClarity: '',
      diamondColour: '',
      diamondShape: '',
      diamondCut: '',
      diamondName: '',
      diamondSettingType: '',
      diamondCertificate: '',
      diamondPieces: '0',
      diamondPurchaseAmount: '0.0',
      diamondSellAmount: json['DiamondAmount']?.toString() ?? '0.0',
      diamondDescription: '',
      metalName: '',
      netAmount: json['MetalAmount']?.toString() ?? '0.0',
      gstAmount: '0.0',
      totalAmount: json['MetalAmount']?.toString() ?? '0.0',
      purity: json['PurityName']?.toString() ?? '',
      designName: json['DesignName']?.toString() ?? '',
      companyId: 0,
      branchId: _jsonInt(json['BranchId']),
      counterId: 0,
      employeeId: 0,
      labelledStockId: _jsonInt(json['LabelledStockId']),
      fineSilver: '0.0',
      fineGold: '0.0',
      debitSilver: '0.0',
      debitGold: '0.0',
      balanceSilver: '0.0',
      balanceGold: '0.0',
      convertAmt: '0.0',
      pieces: json['Pieces']?.toString() ?? '1',
      stoneLessPercent: json['WastegePercentage']?.toString() ?? '0.0',
      designId: _jsonInt(json['DesignId']),
      packetId: 0,
      rfidCode: json['RFIDCode']?.toString() ?? '',
      image: '',
      diamondWt: json['DiamondWeight']?.toString() ?? '0.0',
      stoneAmt: json['StoneAmount']?.toString() ?? '0.0',
      diamondAmt: json['DiamondAmount']?.toString() ?? '0.0',
      finePer: json['FinePercentage']?.toString() ?? '0.0',
      fineWt: json['FineWastageWt']?.toString() ?? '0.0',
      qty: _jsonInt(json['Quantity']) <= 0 ? 1 : _jsonInt(json['Quantity']),
      tid: json['TIDNumber']?.toString() ?? '',
      totayRate: json['RatePerGram']?.toString() ?? '0.0',
      makingPercent: '0.0',
      fixMaking: '0.0',
      fixWastage: '0.0',
      tidNumber: json['TIDNumber']?.toString() ?? '',
      customerName: json['CustomerName']?.toString() ?? '',
      pcs: int.tryParse(json['Pieces']?.toString() ?? '1') ?? 1,
    );
  }

  /// Builds IssueItems payload entry for add/update API.
  static Map<String, dynamic> detailsToIssueItem({
    required ChallanDetailsModel item,
    required String sampleOutNo,
    required int customerId,
    required String clientCode,
    required int branchId,
    required String customerName,
    required String sampleInDate,
    bool statusType = true,
  }) {
    return {
      'ItemCode': item.itemCode,
      'SKU': item.sku,
      'SKUId': item.skuId,
      'CategoryId': item.categoryId,
      'ProductId': item.productId,
      'DesignId': item.designId,
      'PurityId': item.purityId,
      'Quantity': item.qty <= 0 ? 1 : item.qty,
      'GrossWt': item.grossWt,
      'NetWt': item.netWt,
      'TotalWt': item.totalWt.isNotEmpty ? item.totalWt : item.netWt,
      'FinePercentage': item.finePer.isNotEmpty ? item.finePer : item.finePercentage,
      'WastegePercentage': item.stoneLessPercent,
      'StoneWeight': item.totalStoneWeight.isNotEmpty ? item.totalStoneWeight : '0.000',
      'DiamondWeight': item.diamondWt.isNotEmpty ? item.diamondWt : item.totalDiamondWeight,
      'FineWastageWt': item.fineWastageWt,
      'RatePerGram': item.metalRate,
      'MetalAmount': item.metalAmount,
      'Description': item.description,
      'SampleStatus': item.challanStatus.isNotEmpty ? item.challanStatus : 'SampleOut',
      'ClientCode': clientCode,
      'StoneAmount': item.stoneAmt.isNotEmpty ? item.stoneAmt : item.stoneAmount,
      'SampleOutNo': sampleOutNo,
      'DiamondAmount': item.diamondAmt.isNotEmpty ? item.diamondAmt : item.totalDiamondAmount,
      'Pieces': item.pieces,
      'CategoryName': item.categoryName,
      'ProductName': item.productName,
      'PurityName': item.purity,
      'DesignName': item.designName,
      'Id': item.challanId,
      'CustomerId': customerId,
      'VendorId': 0,
      'BranchId': branchId,
      'LabelledStockId': item.labelledStockId,
      'CustomerName': customerName,
      'SampleInDate': sampleInDate,
      'CreatedOn': sampleInDate,
      'Customer': null,
      'RFIDCode': item.rfidCode,
      'TIDNumber': item.tid.isNotEmpty ? item.tid : item.tidNumber,
      'StatusType': statusType,
    };
  }
}

/// Generates next Sample Out number (e.g. C14 → C15).
String getNextSampleOutNo(String? lastNo) {
  if (lastNo == null || lastNo.trim().isEmpty) return 'C1';
  final trimmed = lastNo.trim();
  final match = RegExp(r'^(\D*)(\d+)$').firstMatch(trimmed);
  if (match == null) return '${trimmed}1';
  final prefix = match.group(1)!;
  final current = int.tryParse(match.group(2)!) ?? 0;
  return '$prefix${current + 1}';
}
