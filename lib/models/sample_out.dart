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
    this.customerFirstName,
  });

  factory SampleOutModel.fromJson(Map<String, dynamic> json) {
    final customer = json['Customer'] as Map<String, dynamic>?;
    final items = (json['IssueItems'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    return SampleOutModel(
      id: json['Id'] as int? ?? 0,
      sampleStatus: json['SampleStatus']?.toString() ?? '',
      sampleOutNo: json['SampleOutNo']?.toString() ?? '',
      statusType: json['StatusType'] as bool? ?? false,
      createdOn: json['CreatedOn']?.toString() ?? '',
      lastUpdated: json['LastUpdated']?.toString() ?? '',
      customerId: json['CustomerId'] as int? ?? 0,
      quantity: json['Quantity'] as int? ?? 0,
      totalWt: json['TotalWt']?.toString() ?? '0',
      totalGrossWt: json['TotalGrossWt']?.toString() ?? '0',
      totalNetWt: json['TotalNetWt']?.toString() ?? '0',
      totalStoneWeight: json['TotalStoneWeight']?.toString() ?? '0',
      totalDiamondWeight: json['TotalDiamondWeight']?.toString() ?? '0',
      returnDate: json['ReturnDate']?.toString() ?? '',
      description: json['Description']?.toString() ?? '',
      date: json['Date']?.toString() ?? '',
      clientCode: json['ClientCode']?.toString() ?? '',
      branchId: json['BranchId'] as int? ?? 0,
      issueItems: items,
      customerFirstName: customer?['FirstName']?.toString(),
    );
  }

  String get customerName => customerFirstName ?? '';

  /// Maps API issue item to line-item model used in the create/edit screen.
  static ChallanDetailsModel issueItemToDetails(Map<String, dynamic> json) {
    return ChallanDetailsModel(
      challanId: json['Id'] as int? ?? 0,
      mrp: '0.0',
      categoryName: json['CategoryName']?.toString() ?? '',
      challanStatus: json['SampleStatus']?.toString() ?? 'SampleOut',
      productName: json['ProductName']?.toString() ?? '',
      quantity: (json['Quantity'] ?? 1).toString(),
      hsnCode: '',
      itemCode: json['ItemCode']?.toString() ?? '',
      grossWt: json['GrossWt']?.toString() ?? '0.0',
      netWt: json['NetWt']?.toString() ?? '0.0',
      productId: json['ProductId'] as int? ?? 0,
      customerId: json['CustomerId'] as int? ?? 0,
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
      categoryId: json['CategoryId'] as int? ?? 0,
      purityId: json['PurityId'] as int? ?? 0,
      totalStoneWeight: json['StoneWeight']?.toString() ?? '0.0',
      totalStoneAmount: json['StoneAmount']?.toString() ?? '0.0',
      totalStonePieces: '0',
      totalDiamondWeight: json['DiamondWeight']?.toString() ?? '0.0',
      totalDiamondPieces: '0',
      totalDiamondAmount: json['DiamondAmount']?.toString() ?? '0.0',
      skuId: json['SKUId'] as int? ?? 0,
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
      branchId: json['BranchId'] as int? ?? 0,
      counterId: 0,
      employeeId: 0,
      labelledStockId: json['LabelledStockId'] as int? ?? 0,
      fineSilver: '0.0',
      fineGold: '0.0',
      debitSilver: '0.0',
      debitGold: '0.0',
      balanceSilver: '0.0',
      balanceGold: '0.0',
      convertAmt: '0.0',
      pieces: json['Pieces']?.toString() ?? '1',
      stoneLessPercent: json['WastegePercentage']?.toString() ?? '0.0',
      designId: json['DesignId'] as int? ?? 0,
      packetId: 0,
      rfidCode: json['RFIDCode']?.toString() ?? '',
      image: '',
      diamondWt: json['DiamondWeight']?.toString() ?? '0.0',
      stoneAmt: json['StoneAmount']?.toString() ?? '0.0',
      diamondAmt: json['DiamondAmount']?.toString() ?? '0.0',
      finePer: json['FinePercentage']?.toString() ?? '0.0',
      fineWt: json['FineWastageWt']?.toString() ?? '0.0',
      qty: json['Quantity'] as int? ?? 1,
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
      'SampleStatus': 'SampleOut',
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
