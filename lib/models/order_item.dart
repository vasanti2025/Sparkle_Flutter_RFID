class OrderItem {
  final String rfidCode;
  final String branchId;
  final String branchName;
  final String exhibition;
  final String remark;
  final String purity;
  final String size;
  final String length;
  final String typeOfColor;
  final String screwType;
  final String polishType;
  final String finePer;
  final String wastage;
  final String orderDate;
  final String deliverDate;
  final String productName;
  final String itemCode;
  final String? grWt;
  final String? nWt;
  final String? stoneAmt;
  final String? finePlusWt;
  final String? itemAmt;
  final String packingWt;
  final String totalWt;
  final String stoneWt;
  final String dimondWt;
  final String sku;
  final String qty;
  final String hallmarkAmt;
  final String mrp;
  final String image;
  final String netAmt;
  final String diamondAmt;
  final int? categoryId;
  final String categoryName;
  final int productId;
  final String productCode;
  final int skuId;
  final int designid;
  final String designName;
  final int purityid;
  final int counterId;
  final String counterName;
  final int companyId;
  final String epc;
  final String tid;
  final String todaysRate;
  final String makingPercentage;
  final String makingFixedAmt;
  final String makingFixedWastage;
  final String makingPerGram;
  final String categoryWt;

  OrderItem({
    required this.rfidCode,
    required this.branchId,
    required this.branchName,
    required this.exhibition,
    required this.remark,
    required this.purity,
    required this.size,
    required this.length,
    required this.typeOfColor,
    required this.screwType,
    required this.polishType,
    required this.finePer,
    required this.wastage,
    required this.orderDate,
    required this.deliverDate,
    required this.productName,
    required this.itemCode,
    this.grWt,
    this.nWt,
    this.stoneAmt,
    this.finePlusWt,
    this.itemAmt,
    required this.packingWt,
    required this.totalWt,
    required this.stoneWt,
    required this.dimondWt,
    required this.sku,
    required this.qty,
    required this.hallmarkAmt,
    required this.mrp,
    required this.image,
    required this.netAmt,
    required this.diamondAmt,
    this.categoryId,
    required this.categoryName,
    required this.productId,
    required this.productCode,
    required this.skuId,
    required this.designid,
    required this.designName,
    required this.purityid,
    required this.counterId,
    required this.counterName,
    required this.companyId,
    required this.epc,
    required this.tid,
    required this.todaysRate,
    required this.makingPercentage,
    required this.makingFixedAmt,
    required this.makingFixedWastage,
    required this.makingPerGram,
    required this.categoryWt,
  });

  OrderItem copyWith({
    String? rfidCode,
    String? branchId,
    String? branchName,
    String? exhibition,
    String? remark,
    String? purity,
    String? size,
    String? length,
    String? typeOfColor,
    String? screwType,
    String? polishType,
    String? finePer,
    String? wastage,
    String? orderDate,
    String? deliverDate,
    String? productName,
    String? itemCode,
    String? grWt,
    String? nWt,
    String? stoneAmt,
    String? finePlusWt,
    String? itemAmt,
    String? packingWt,
    String? totalWt,
    String? stoneWt,
    String? dimondWt,
    String? sku,
    String? qty,
    String? hallmarkAmt,
    String? mrp,
    String? image,
    String? netAmt,
    String? diamondAmt,
    int? categoryId,
    String? categoryName,
    int? productId,
    String? productCode,
    int? skuId,
    int? designid,
    String? designName,
    int? purityid,
    int? counterId,
    String? counterName,
    int? companyId,
    String? epc,
    String? tid,
    String? todaysRate,
    String? makingPercentage,
    String? makingFixedAmt,
    String? makingFixedWastage,
    String? makingPerGram,
    String? categoryWt,
  }) {
    return OrderItem(
      rfidCode: rfidCode ?? this.rfidCode,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      exhibition: exhibition ?? this.exhibition,
      remark: remark ?? this.remark,
      purity: purity ?? this.purity,
      size: size ?? this.size,
      length: length ?? this.length,
      typeOfColor: typeOfColor ?? this.typeOfColor,
      screwType: screwType ?? this.screwType,
      polishType: polishType ?? this.polishType,
      finePer: finePer ?? this.finePer,
      wastage: wastage ?? this.wastage,
      orderDate: orderDate ?? this.orderDate,
      deliverDate: deliverDate ?? this.deliverDate,
      productName: productName ?? this.productName,
      itemCode: itemCode ?? this.itemCode,
      grWt: grWt ?? this.grWt,
      nWt: nWt ?? this.nWt,
      stoneAmt: stoneAmt ?? this.stoneAmt,
      finePlusWt: finePlusWt ?? this.finePlusWt,
      itemAmt: itemAmt ?? this.itemAmt,
      packingWt: packingWt ?? this.packingWt,
      totalWt: totalWt ?? this.totalWt,
      stoneWt: stoneWt ?? this.stoneWt,
      dimondWt: dimondWt ?? this.dimondWt,
      sku: sku ?? this.sku,
      qty: qty ?? this.qty,
      hallmarkAmt: hallmarkAmt ?? this.hallmarkAmt,
      mrp: mrp ?? this.mrp,
      image: image ?? this.image,
      netAmt: netAmt ?? this.netAmt,
      diamondAmt: diamondAmt ?? this.diamondAmt,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      productId: productId ?? this.productId,
      productCode: productCode ?? this.productCode,
      skuId: skuId ?? this.skuId,
      designid: designid ?? this.designid,
      designName: designName ?? this.designName,
      purityid: purityid ?? this.purityid,
      counterId: counterId ?? this.counterId,
      counterName: counterName ?? this.counterName,
      companyId: companyId ?? this.companyId,
      epc: epc ?? this.epc,
      tid: tid ?? this.tid,
      todaysRate: todaysRate ?? this.todaysRate,
      makingPercentage: makingPercentage ?? this.makingPercentage,
      makingFixedAmt: makingFixedAmt ?? this.makingFixedAmt,
      makingFixedWastage: makingFixedWastage ?? this.makingFixedWastage,
      makingPerGram: makingPerGram ?? this.makingPerGram,
      categoryWt: categoryWt ?? this.categoryWt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'CustomOrderId': 0, // Filled during API mapping
      'RFIDCode': rfidCode,
      'OrderDate': orderDate,
      'DeliverDate': deliverDate,
      'SKUId': skuId,
      'SKU': sku,
      'CategoryId': categoryId,
      'VendorId': 0, // Default or mapped
      'CategoryName': categoryName,
      'CustomerName': '',
      'VendorName': '',
      'ProductId': productId,
      'ProductName': productName,
      'DesignId': designid,
      'DesignName': designName,
      'PurityId': purityid,
      'PurityName': purity,
      'GrossWt': grWt,
      'StoneWt': stoneWt,
      'DiamondWt': dimondWt,
      'NetWt': nWt,
      'Size': size,
      'Length': length,
      'TypesOdColors': typeOfColor,
      'Quantity': qty,
      'RatePerGram': todaysRate,
      'MakingPerGram': makingPerGram,
      'MakingFixed': makingFixedAmt,
      'FixedWt': makingFixedWastage,
      'MakingPercentage': makingPercentage,
      'DiamondPieces': '0',
      'DiamondRate': '0.0',
      'DiamondAmount': diamondAmt,
      'StoneAmount': stoneAmt,
      'ScrewType': screwType,
      'Polish': polishType,
      'Rhodium': '',
      'SampleWt': '',
      'Image': image,
      'ItemCode': itemCode,
      'CustomerId': 0, // Filled on parent submit
      'MRP': mrp,
      'HSNCode': '',
      'UnlProductId': 0,
      'OrderBy': '',
      'StoneLessPercent': '0.0',
      'ProductCode': productCode,
      'TotalWt': totalWt,
      'BillType': 'SampleOut',
      'FinePercentage': finePer,
      'ClientCode': '',
      'OrderId': null,
      'StatusType': true,
      'PackingWeight': packingWt,
      'MetalAmount': '0.0',
      'OldGoldPurchase': false,
      'Amount': itemAmt,
      'totalGstAmount': '0.0',
      'finalPrice': itemAmt,
      'MakingFixedWastage': makingFixedWastage,
      'Description': remark,
      'CompanyId': companyId,
      'LabelledStockId': 0,
      'TotalStoneWeight': stoneWt,
      'BranchId': int.tryParse(branchId) ?? 0,
      'BranchName': branchName,
      'Exhibition': exhibition,
      'CounterId': counterId.toString(),
      'EmployeeId': 0,
      'OrderNo': '',
      'OrderStatus': 'Order Received',
      'DueDate': null,
      'Remark': remark,
      'PurchaseInvoiceNo': null,
      'Purity': purity,
      'Status': null,
      'URDNo': null,
      'HallmarkAmount': hallmarkAmt,
      'WeightCategories': categoryWt,
      'TIDNumber': tid,
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      rfidCode: json['RFIDCode']?.toString() ?? '',
      branchId: (json['BranchId'] ?? 0).toString(),
      branchName: json['BranchName']?.toString() ?? '',
      exhibition: json['Exhibition']?.toString() ?? '',
      remark: json['Remark']?.toString() ?? json['Description']?.toString() ?? '',
      purity: json['PurityName']?.toString() ?? json['Purity']?.toString() ?? '',
      size: json['Size']?.toString() ?? '1',
      length: json['Length']?.toString() ?? '',
      typeOfColor: json['TypesOdColors']?.toString() ?? '',
      screwType: json['ScrewType']?.toString() ?? '',
      polishType: json['Polish']?.toString() ?? '',
      finePer: json['FinePercentage']?.toString() ?? '0',
      wastage: json['MakingPercentage']?.toString() ?? '0',
      orderDate: json['OrderDate']?.toString() ?? '',
      deliverDate: json['DeliverDate']?.toString() ?? '',
      productName: json['ProductName']?.toString() ?? '',
      itemCode: json['ItemCode']?.toString() ?? '',
      grWt: json['GrossWt']?.toString() ?? '0.000',
      nWt: json['NetWt']?.toString() ?? '0.000',
      stoneAmt: json['StoneAmount']?.toString() ?? '0.00',
      finePlusWt: json['FixedWt']?.toString() ?? '0.000',
      itemAmt: json['Amount']?.toString() ?? json['finalPrice']?.toString() ?? '0.00',
      packingWt: json['PackingWeight']?.toString() ?? '0.000',
      totalWt: json['TotalWt']?.toString() ?? '0.000',
      stoneWt: json['StoneWt']?.toString() ?? '0.000',
      dimondWt: json['DiamondWt']?.toString() ?? '0.000',
      sku: json['SKU']?.toString() ?? '',
      qty: json['Quantity']?.toString() ?? '1',
      hallmarkAmt: json['HallmarkAmount']?.toString() ?? '0.00',
      mrp: json['MRP']?.toString() ?? '0.00',
      image: json['Image']?.toString() ?? '',
      netAmt: json['Amount']?.toString() ?? '0.00',
      diamondAmt: json['DiamondAmount']?.toString() ?? '0.00',
      categoryId: json['CategoryId'] as int?,
      categoryName: json['CategoryName']?.toString() ?? '',
      productId: json['ProductId'] as int? ?? 0,
      productCode: json['ProductCode']?.toString() ?? '',
      skuId: json['SKUId'] as int? ?? 0,
      designid: json['DesignId'] as int? ?? 0,
      designName: json['DesignName']?.toString() ?? '',
      purityid: json['PurityId'] as int? ?? 0,
      counterId: int.tryParse(json['CounterId']?.toString() ?? '0') ?? 0,
      counterName: json['CounterName']?.toString() ?? '',
      companyId: json['CompanyId'] as int? ?? 0,
      epc: json['RfidCode']?.toString() ?? '',
      tid: json['TIDNumber']?.toString() ?? '',
      todaysRate: json['RatePerGram']?.toString() ?? '0.0',
      makingPercentage: json['MakingPercentage']?.toString() ?? '0.0',
      makingFixedAmt: json['MakingFixed']?.toString() ?? '0.0',
      makingFixedWastage: json['MakingFixedWastage']?.toString() ?? '0.0',
      makingPerGram: json['MakingPerGram']?.toString() ?? '0.0',
      categoryWt: json['WeightCategories']?.toString() ?? '',
    );
  }
}
