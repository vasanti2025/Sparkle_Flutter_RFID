class CustomerTunchModel {
  final int id;
  final int customerId;
  final int categoryId;
  final int productId;
  final int designId;
  final String clientCode;
  final int purityId;
  final String? makingFixedAmt;
  final String? makingPerGram;
  final String? makingFixedWastage;
  final String? makingPercentage;
  final String? stockKeepingUnit;
  final int companyId;
  final int counterId;
  final int branchId;
  final int employeeId;
  final String? productName;
  final String? categoryName;
  final String? purityName;
  final String? designName;
  final String? firstName;
  final String? lastName;
  final String? wastageWt;
  final int? diamondSizeWeightRateTemplateId;
  final String? diamondSizeWeightRateTemplateName;
  final double finePercentage;

  CustomerTunchModel({
    required this.id,
    required this.customerId,
    required this.categoryId,
    required this.productId,
    required this.designId,
    required this.clientCode,
    required this.purityId,
    this.makingFixedAmt,
    this.makingPerGram,
    this.makingFixedWastage,
    this.makingPercentage,
    this.stockKeepingUnit,
    required this.companyId,
    required this.counterId,
    required this.branchId,
    required this.employeeId,
    this.productName,
    this.categoryName,
    this.purityName,
    this.designName,
    this.firstName,
    this.lastName,
    this.wastageWt,
    this.diamondSizeWeightRateTemplateId,
    this.diamondSizeWeightRateTemplateName,
    required this.finePercentage,
  });

  factory CustomerTunchModel.fromJson(Map<String, dynamic> json) {
    return CustomerTunchModel(
      id: json['Id'] as int? ?? 0,
      customerId: json['CustomerId'] as int? ?? 0,
      categoryId: json['CategoryId'] as int? ?? 0,
      productId: json['ProductId'] as int? ?? 0,
      designId: json['DesignId'] as int? ?? 0,
      clientCode: json['ClientCode'] as String? ?? '',
      purityId: json['PurityId'] as int? ?? 0,
      makingFixedAmt: json['MakingFixedAmt']?.toString(),
      makingPerGram: json['MakingPerGram']?.toString(),
      makingFixedWastage: json['MakingFixedWastage']?.toString(),
      makingPercentage: json['MakingPercentage']?.toString(),
      stockKeepingUnit: json['StockKeepingUnit'] as String?,
      companyId: json['CompanyId'] as int? ?? 0,
      counterId: json['CounterId'] as int? ?? 0,
      branchId: json['BranchId'] as int? ?? 0,
      employeeId: json['EmployeeId'] as int? ?? 0,
      productName: json['ProductName'] as String?,
      categoryName: json['CategoryName'] as String?,
      purityName: json['PurityName'] as String?,
      designName: json['DesignName'] as String?,
      firstName: json['FirstName'] as String?,
      lastName: json['LastName'] as String?,
      wastageWt: json['WastageWt']?.toString(),
      diamondSizeWeightRateTemplateId: json['DiamondSizeWeightRateTemplateId'] as int?,
      diamondSizeWeightRateTemplateName: json['DiamondSizeWeightRateTemplateName'] as String?,
      finePercentage: (json['FinePercentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'CustomerId': customerId,
      'CategoryId': categoryId,
      'ProductId': productId,
      'DesignId': designId,
      'ClientCode': clientCode,
      'PurityId': purityId,
      'MakingFixedAmt': makingFixedAmt,
      'MakingPerGram': makingPerGram,
      'MakingFixedWastage': makingFixedWastage,
      'MakingPercentage': makingPercentage,
      'StockKeepingUnit': stockKeepingUnit,
      'CompanyId': companyId,
      'CounterId': counterId,
      'BranchId': branchId,
      'EmployeeId': employeeId,
      'ProductName': productName,
      'CategoryName': categoryName,
      'PurityName': purityName,
      'DesignName': designName,
      'FirstName': firstName,
      'LastName': lastName,
      'WastageWt': wastageWt,
      'DiamondSizeWeightRateTemplateId': diamondSizeWeightRateTemplateId,
      'DiamondSizeWeightRateTemplateName': diamondSizeWeightRateTemplateName,
      'FinePercentage': finePercentage,
    };
  }
}
