class VendorModel {
  final int id;
  final String name;

  VendorModel({required this.id, required this.name});

  factory VendorModel.fromJson(Map<String, dynamic> json) {
    return VendorModel(
      id: json['Id'] as int? ?? 0,
      name: json['VendorName']?.toString() ?? json['Name']?.toString() ?? '',
    );
  }
}

class SkuModel {
  final int id;
  final String sku;
  final int categoryId;
  final int productId;
  final int designId;
  final int purityId;
  final int branchId;
  final String clientCode;
  final int employeeId;
  final String? vendorName;
  final List<String> vendorNames;

  SkuModel({
    required this.id,
    required this.sku,
    required this.categoryId,
    required this.productId,
    required this.designId,
    required this.purityId,
    required this.branchId,
    required this.clientCode,
    required this.employeeId,
    this.vendorName,
    this.vendorNames = const [],
  });

  factory SkuModel.fromJson(Map<String, dynamic> json) {
    final vendorNames = <String>[];
    final vendorsRaw = json['SKUVendor'];
    if (vendorsRaw is List) {
      for (final entry in vendorsRaw) {
        if (entry is Map) {
          final name = entry['VendorName']?.toString().trim();
          if (name != null && name.isNotEmpty) vendorNames.add(name);
        }
      }
    }
    final vendor = json['SKUVendor'];
    String? singleVendor;
    if (vendor is Map) {
      singleVendor = vendor['VendorName']?.toString();
    }

    return SkuModel(
      id: json['Id'] as int? ?? 0,
      sku: json['SKU']?.toString() ?? json['StockKeepingUnit']?.toString() ?? '',
      categoryId: json['CategoryId'] as int? ?? 0,
      productId: json['ProductId'] as int? ?? 0,
      designId: json['DesignId'] as int? ?? 0,
      purityId: json['PurityId'] as int? ?? 0,
      branchId: json['BranchId'] as int? ?? 0,
      clientCode: json['ClientCode']?.toString() ?? '',
      employeeId: json['EmployeeId'] as int? ?? 0,
      vendorName: singleVendor ?? (vendorNames.isNotEmpty ? vendorNames.first : null),
      vendorNames: vendorNames,
    );
  }
}

class CategoryModel {
  final int id;
  final String name;

  CategoryModel({required this.id, required this.name});

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['Id'] as int? ?? 0,
      name: json['CategoryName']?.toString() ?? '',
    );
  }
}

class ProductMasterModel {
  final int id;
  final String name;
  final int categoryId;

  ProductMasterModel({required this.id, required this.name, required this.categoryId});

  factory ProductMasterModel.fromJson(Map<String, dynamic> json) {
    return ProductMasterModel(
      id: json['Id'] as int? ?? 0,
      name: json['ProductName']?.toString() ?? '',
      categoryId: json['CategoryId'] as int? ?? 0,
    );
  }
}

class DesignModel {
  final int id;
  final String name;
  final int productId;

  DesignModel({required this.id, required this.name, required this.productId});

  factory DesignModel.fromJson(Map<String, dynamic> json) {
    return DesignModel(
      id: json['Id'] as int? ?? 0,
      name: json['DesignName']?.toString() ?? '',
      productId: json['ProductId'] as int? ?? 0,
    );
  }
}

class PurityModel {
  final int id;
  final String name;
  final int categoryId;

  PurityModel({required this.id, required this.name, required this.categoryId});

  factory PurityModel.fromJson(Map<String, dynamic> json) {
    return PurityModel(
      id: json['Id'] as int? ?? 0,
      name: json['PurityName']?.toString() ?? '',
      categoryId: json['CategoryId'] as int? ?? 0,
    );
  }
}

Map<String, dynamic> buildInsertProductPayload({
  required int categoryId,
  required int productId,
  required int designId,
  required int vendorId,
  required int purityId,
  required String rfidCode,
  required String epc,
  required String grossWt,
  required String stoneWt,
  required String netWt,
  required String diamondWt,
  required String makingPerc,
  required String makingGm,
  required String fixMaking,
  required String fixWastage,
  required String stoneAmt,
  required String diamondAmt,
  required int branchId,
  required String clientCode,
  required int employeeCode,
}) {
  return {
    'CategoryId': categoryId,
    'ProductId': productId,
    'DesignId': designId,
    'VendorId': vendorId,
    'PurityId': purityId,
    'RFIDCode': rfidCode,
    'HUIDCode': '',
    'HSNCode': '',
    'Quantity': '1',
    'TotalWeight': 0.0,
    'PackingWeight': 0.0,
    'GrossWt': grossWt,
    'TotalStoneWeight': stoneWt,
    'NetWt': netWt,
    'Pieces': '',
    'MakingPercentage': makingPerc,
    'MakingPerGram': makingGm,
    'MakingFixedAmt': fixMaking,
    'MakingFixedWastage': fixWastage,
    'MRP': '',
    'ClipWeight': '',
    'ClipQuantity': '',
    'ProductCode': '',
    'Featured': '',
    'ProductTitle': '',
    'Description': '',
    'Gender': '',
    'DiamondId': '',
    'DiamondName': '',
    'DiamondShape': '',
    'DiamondShapeName': '',
    'DiamondClarity': '',
    'DiamondClarityName': '',
    'DiamondColour': '',
    'DiamondColourName': '',
    'DiamondSleve': '',
    'DiamondSize': '',
    'DiamondSellRate': '',
    'DiamondWeight': diamondWt,
    'DiamondCut': '',
    'DiamondCutName': '',
    'DiamondSettingType': '',
    'DiamondSettingTypeName': '',
    'DiamondCertificate': '',
    'DiamondDescription': '',
    'DiamondPacket': '',
    'DiamondBox': '',
    'DiamondPieces': '',
    'Stones': <dynamic>[],
    'DButton': '',
    'StoneName': '',
    'StoneShape': '',
    'StoneSize': '',
    'StoneWeight': stoneWt,
    'StonePieces': '',
    'StoneRatePiece': '',
    'StoneRateKarate': '',
    'StoneAmount': stoneAmt,
    'StoneDescription': '',
    'StoneCertificate': '',
    'StoneSettingType': '',
    'BranchName': '',
    'BranchId': branchId,
    'PurityName': '',
    'TotalStoneAmount': stoneAmt,
    'TotalStonePieces': '',
    'ClientCode': clientCode,
    'EmployeeCode': employeeCode,
    'StoneColour': '',
    'CompanyId': 0,
    'MetalId': 0,
    'WarehouseId': 0,
    'TIDNumber': epc,
    'TotalDiamondWeight': diamondWt,
    'TotalDiamondAmount': diamondAmt,
    'Status': 'Active',
  };
}
