/// Normalizes item/RFID codes for matching (same as Kotlin `norm`).
String normSampleCode(String? value) {
  if (value == null) return '';
  return value.trim().toUpperCase().replaceAll(' ', '').replaceAll('-', '');
}

/// Flat list row from `GetAllIssueItemDetails` (SampleStatus = SampleIn).
class SampleInModel {
  final int id;
  final String itemCode;
  final String sampleOutNo;
  final String sampleStatus;
  final String createdOn;
  final String sampleInDate;
  final String description;
  final String productName;
  final String totalWt;
  final String grossWt;
  final String stoneWeight;
  final String diamondWeight;
  final int quantity;
  final int customerId;
  final String? customerFirstName;
  final String clientCode;
  final int branchId;

  SampleInModel({
    required this.id,
    required this.itemCode,
    required this.sampleOutNo,
    required this.sampleStatus,
    required this.createdOn,
    required this.sampleInDate,
    required this.description,
    required this.productName,
    required this.totalWt,
    required this.grossWt,
    required this.stoneWeight,
    required this.diamondWeight,
    required this.quantity,
    required this.customerId,
    this.customerFirstName,
    required this.clientCode,
    required this.branchId,
  });

  factory SampleInModel.fromJson(Map<String, dynamic> json) {
    final customer = json['Customer'] as Map<String, dynamic>?;
    return SampleInModel(
      id: json['Id'] as int? ?? 0,
      itemCode: json['ItemCode']?.toString() ?? '',
      sampleOutNo: json['SampleOutNo']?.toString() ?? '',
      sampleStatus: json['SampleStatus']?.toString() ?? '',
      createdOn: json['CreatedOn']?.toString() ?? '',
      sampleInDate: json['SampleInDate']?.toString() ?? '',
      description: json['Description']?.toString() ?? '',
      productName: json['ProductName']?.toString() ?? '',
      totalWt: json['TotalWt']?.toString() ?? '0',
      grossWt: json['GrossWt']?.toString() ?? '0',
      stoneWeight: json['StoneWeight']?.toString() ?? '0',
      diamondWeight: json['DiamondWeight']?.toString() ?? '0',
      quantity: json['Quantity'] as int? ?? 0,
      customerId: json['CustomerId'] as int? ?? 0,
      customerFirstName: customer?['FirstName']?.toString() ?? json['CustomerName']?.toString(),
      clientCode: json['ClientCode']?.toString() ?? '',
      branchId: json['BranchId'] as int? ?? 0,
    );
  }

  String get customerName => customerFirstName ?? '';
}

/// Builds IssueItems entry for Sample In update API.
Map<String, dynamic> issueMapToIssueItemPayload({
  required Map<String, dynamic> issue,
  required String parentSampleOutNo,
  required int customerId,
  required String clientCode,
  required int branchId,
  required String customerName,
  required String sampleInDate,
  required String itemStatus,
}) {
  int safeInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  return {
    'ItemCode': issue['ItemCode']?.toString() ?? '',
    'SKU': issue['SKU']?.toString() ?? '',
    'SKUId': safeInt(issue['SKUId']),
    'CategoryId': safeInt(issue['CategoryId']),
    'ProductId': safeInt(issue['ProductId']),
    'DesignId': safeInt(issue['DesignId']),
    'PurityId': safeInt(issue['PurityId']),
    'Quantity': safeInt(issue['Quantity']) <= 0 ? 1 : safeInt(issue['Quantity']),
    'GrossWt': issue['GrossWt']?.toString() ?? '0',
    'NetWt': issue['NetWt']?.toString() ?? '0',
    'TotalWt': issue['TotalWt']?.toString() ?? issue['NetWt']?.toString() ?? '0',
    'FinePercentage': issue['FinePercentage']?.toString(),
    'WastegePercentage': issue['WastegePercentage']?.toString(),
    'StoneWeight': issue['StoneWeight']?.toString() ?? '0.000',
    'DiamondWeight': issue['DiamondWeight']?.toString() ?? '0.000',
    'FineWastageWt': issue['FineWastageWt']?.toString() ?? '0.000',
    'RatePerGram': issue['RatePerGram']?.toString(),
    'MetalAmount': issue['MetalAmount']?.toString(),
    'Description': issue['Description']?.toString() ?? '',
    'SampleStatus': itemStatus,
    'ClientCode': clientCode,
    'StoneAmount': issue['StoneAmount']?.toString() ?? '0.00',
    'SampleOutNo': parentSampleOutNo,
    'DiamondAmount': issue['DiamondAmount']?.toString() ?? '0.00',
    'Pieces': issue['Pieces']?.toString() ?? '0',
    'CategoryName': issue['CategoryName']?.toString() ?? '',
    'ProductName': issue['ProductName']?.toString() ?? '',
    'PurityName': issue['PurityName']?.toString() ?? '',
    'DesignName': issue['DesignName']?.toString() ?? '',
    'Id': safeInt(issue['Id']),
    'CustomerId': customerId,
    'VendorId': 0,
    'BranchId': branchId,
    'LabelledStockId': safeInt(issue['LabelledStockId']),
    'CustomerName': customerName,
    'SampleInDate': sampleInDate,
    'CreatedOn': sampleInDate,
    'Customer': null,
    'RFIDCode': issue['RFIDCode']?.toString() ?? '',
    'TIDNumber': issue['TIDNumber']?.toString() ?? '',
  };
}
