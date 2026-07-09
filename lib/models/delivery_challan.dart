class DeliveryChallanModel {
  final int id;
  final String? createdOn;
  final String? lastUpdated;
  final bool? statusType;
  final int customerId;
  final int vendorId;
  final int branchId;
  final String? totalAmount;
  final String? paymentMode;
  final String? offer;
  final String? qty;
  final String? gst;
  final String? receivedAmount;
  final String? challanStatus;
  final String? visibility;
  final String? mrp;
  final String? grossWt;
  final String? netWt;
  final String? stoneWt;
  final String? totalNetAmount;
  final String? totalGSTAmount;
  final String? totalPurchaseAmount;
  final String? purchaseStatus;
  final String? gstApplied;
  final String? discount;
  final String? totalBalanceMetal;
  final String? balanceAmount;
  final String? totalFineMetal;
  final String? courierCharge;
  final String? tds;
  final String? urdNo;
  final String? gstCheckboxConfirm;
  final String? additionTaxApplied;
  final int? categoryId;
  final String? invoiceNo;
  final String? deliveryAddress;
  final String? billType;
  final String? urdPurchaseAmt;
  final String? billedBy;
  final String? soldBy;
  final String? totalAdvanceAmount;
  final String? totalAdvancePaid;
  final String? creditSilver;
  final String? creditGold;
  final String? creditAmount;
  final String? balanceAmt;
  final String? balanceSilver;
  final String? balanceGold;
  final String? totalSaleGold;
  final String? totalSaleSilver;
  final String? totalSaleUrdGold;
  final String? totalSaleUrdSilver;
  final String? saleType;
  final String? financialYear;
  final String? baseCurrency;
  final String? totalStoneWeight;
  final String? totalStoneAmount;
  final String? totalStonePieces;
  final String? totalDiamondWeight;
  final String? totalDiamondPieces;
  final String? totalDiamondAmount;
  final String clientCode;
  final String? challanNo;
  final String? invoiceCount;
  final String? fineSilver;
  final String? fineGold;
  final String? debitSilver;
  final String? debitGold;
  final String? totalPaidMetal;
  final String? totalPaidAmount;
  final String? urdWt;
  final String? urdAmt;
  final String? transactionAmtType;
  final String? transactionMetalType;
  final String? description;
  final String? metalType;
  final List<ChallanDetailsModel> challanDetails;
  final List<PaymentModel> payments;
  final String? customerName;

  DeliveryChallanModel({
    required this.id,
    this.createdOn,
    this.lastUpdated,
    this.statusType,
    required this.customerId,
    required this.vendorId,
    required this.branchId,
    this.totalAmount,
    this.paymentMode,
    this.offer,
    this.qty,
    this.gst,
    this.receivedAmount,
    this.challanStatus,
    this.visibility,
    this.mrp,
    this.grossWt,
    this.netWt,
    this.stoneWt,
    this.totalNetAmount,
    this.totalGSTAmount,
    this.totalPurchaseAmount,
    this.purchaseStatus,
    this.gstApplied,
    this.discount,
    this.totalBalanceMetal,
    this.balanceAmount,
    this.totalFineMetal,
    this.courierCharge,
    this.tds,
    this.urdNo,
    this.gstCheckboxConfirm,
    this.additionTaxApplied,
    this.categoryId,
    this.invoiceNo,
    this.deliveryAddress,
    this.billType,
    this.urdPurchaseAmt,
    this.billedBy,
    this.soldBy,
    this.totalAdvanceAmount,
    this.totalAdvancePaid,
    this.creditSilver,
    this.creditGold,
    this.creditAmount,
    this.balanceAmt,
    this.balanceSilver,
    this.balanceGold,
    this.totalSaleGold,
    this.totalSaleSilver,
    this.totalSaleUrdGold,
    this.totalSaleUrdSilver,
    this.saleType,
    this.financialYear,
    this.baseCurrency,
    this.totalStoneWeight,
    this.totalStoneAmount,
    this.totalStonePieces,
    this.totalDiamondWeight,
    this.totalDiamondPieces,
    this.totalDiamondAmount,
    required this.clientCode,
    this.challanNo,
    this.invoiceCount,
    this.fineSilver,
    this.fineGold,
    this.debitSilver,
    this.debitGold,
    this.totalPaidMetal,
    this.totalPaidAmount,
    this.urdWt,
    this.urdAmt,
    this.transactionAmtType,
    this.transactionMetalType,
    this.description,
    this.metalType,
    required this.challanDetails,
    required this.payments,
    this.customerName,
  });

  factory DeliveryChallanModel.fromJson(Map<String, dynamic> json) {
    var detailsList = json['ChallanDetails'] as List? ?? [];
    var details = detailsList.map((d) => ChallanDetailsModel.fromJson(d as Map<String, dynamic>)).toList();

    var pmtsList = json['Payments'] as List? ?? [];
    var pmts = pmtsList.map((p) => PaymentModel.fromJson(p as Map<String, dynamic>)).toList();

    return DeliveryChallanModel(
      id: json['Id'] as int? ?? 0,
      createdOn: json['CreatedOn'] as String?,
      lastUpdated: json['LastUpdated'] as String?,
      statusType: json['StatusType'] as bool?,
      customerId: json['CustomerId'] as int? ?? 0,
      vendorId: json['VendorId'] as int? ?? 0,
      branchId: json['BranchId'] as int? ?? 0,
      totalAmount: json['TotalAmount']?.toString(),
      paymentMode: json['PaymentMode'] as String?,
      offer: json['Offer']?.toString(),
      qty: json['Qty']?.toString(),
      gst: json['GST']?.toString(),
      receivedAmount: json['ReceivedAmount']?.toString(),
      challanStatus: json['ChallanStatus'] as String?,
      visibility: json['Visibility'] as String?,
      mrp: json['MRP']?.toString(),
      grossWt: json['GrossWt']?.toString(),
      netWt: json['NetWt']?.toString(),
      stoneWt: json['StoneWt']?.toString(),
      totalNetAmount: json['TotalNetAmount']?.toString(),
      totalGSTAmount: json['TotalGSTAmount']?.toString(),
      totalPurchaseAmount: json['TotalPurchaseAmount']?.toString(),
      purchaseStatus: json['PurchaseStatus'] as String?,
      gstApplied: json['GSTApplied']?.toString(),
      discount: json['Discount']?.toString(),
      totalBalanceMetal: json['TotalBalanceMetal']?.toString(),
      balanceAmount: json['BalanceAmount']?.toString(),
      totalFineMetal: json['TotalFineMetal']?.toString(),
      courierCharge: json['CourierCharge']?.toString(),
      tds: json['TDS']?.toString(),
      urdNo: json['URDNo'] as String?,
      gstCheckboxConfirm: json['gstCheckboxConfirm']?.toString(),
      additionTaxApplied: json['AdditionTaxApplied']?.toString(),
      categoryId: json['CategoryId'] as int?,
      invoiceNo: json['InvoiceNo'] as String?,
      deliveryAddress: json['DeliveryAddress'] as String?,
      billType: json['BillType'] as String?,
      urdPurchaseAmt: json['UrdPurchaseAmt']?.toString(),
      billedBy: json['BilledBy'] as String?,
      soldBy: json['SoldBy'] as String?,
      totalAdvanceAmount: json['TotalAdvanceAmount']?.toString(),
      totalAdvancePaid: json['TotalAdvancePaid']?.toString(),
      creditSilver: json['CreditSilver']?.toString(),
      creditGold: json['CreditGold']?.toString(),
      creditAmount: json['CreditAmount']?.toString(),
      balanceAmt: json['BalanceAmt']?.toString(),
      balanceSilver: json['BalanceSilver']?.toString(),
      balanceGold: json['BalanceGold']?.toString(),
      totalSaleGold: json['TotalSaleGold']?.toString(),
      totalSaleSilver: json['TotalSaleSilver']?.toString(),
      totalSaleUrdGold: json['TotalSaleUrdGold']?.toString(),
      totalSaleUrdSilver: json['TotalSaleUrdSilver']?.toString(),
      saleType: json['SaleType'] as String?,
      financialYear: json['FinancialYear'] as String?,
      baseCurrency: json['BaseCurrency'] as String?,
      totalStoneWeight: json['TotalStoneWeight']?.toString(),
      totalStoneAmount: json['TotalStoneAmount']?.toString(),
      totalStonePieces: json['TotalStonePieces']?.toString(),
      totalDiamondWeight: json['TotalDiamondWeight']?.toString(),
      totalDiamondPieces: json['TotalDiamondPieces']?.toString(),
      totalDiamondAmount: json['TotalDiamondAmount']?.toString(),
      clientCode: json['ClientCode'] as String? ?? '',
      challanNo: json['ChallanNo'] as String?,
      invoiceCount: json['InvoiceCount']?.toString(),
      fineSilver: json['FineSilver']?.toString(),
      fineGold: json['FineGold']?.toString(),
      debitSilver: json['DebitSilver']?.toString(),
      debitGold: json['DebitGold']?.toString(),
      totalPaidMetal: json['TotalPaidMetal']?.toString(),
      totalPaidAmount: json['TotalPaidAmount']?.toString(),
      urdWt: json['UrdWt']?.toString(),
      urdAmt: json['URDAmt']?.toString() ?? json['UrdAmt']?.toString(),
      transactionAmtType: json['TransactionAmtType'] as String?,
      transactionMetalType: json['TransactionMetalType'] as String?,
      description: json['Description'] as String?,
      metalType: json['MetalType'] as String?,
      challanDetails: details,
      payments: pmts,
      customerName: json['CustomerName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'CreatedOn': createdOn,
      'LastUpdated': lastUpdated,
      'StatusType': statusType,
      'CustomerId': customerId,
      'VendorId': vendorId,
      'BranchId': branchId,
      'TotalAmount': totalAmount,
      'PaymentMode': paymentMode,
      'Offer': offer,
      'Qty': qty,
      'GST': gst,
      'ReceivedAmount': receivedAmount,
      'ChallanStatus': challanStatus,
      'Visibility': visibility,
      'MRP': mrp,
      'GrossWt': grossWt,
      'NetWt': netWt,
      'StoneWt': stoneWt,
      'TotalNetAmount': totalNetAmount,
      'TotalGSTAmount': totalGSTAmount,
      'TotalPurchaseAmount': totalPurchaseAmount,
      'PurchaseStatus': purchaseStatus,
      'GSTApplied': gstApplied,
      'Discount': discount,
      'TotalBalanceMetal': totalBalanceMetal,
      'BalanceAmount': balanceAmount,
      'TotalFineMetal': totalFineMetal,
      'CourierCharge': courierCharge,
      'TDS': tds,
      'URDNo': urdNo,
      'gstCheckboxConfirm': gstCheckboxConfirm,
      'AdditionTaxApplied': additionTaxApplied,
      'CategoryId': categoryId,
      'InvoiceNo': invoiceNo,
      'DeliveryAddress': deliveryAddress,
      'BillType': billType,
      'UrdPurchaseAmt': urdPurchaseAmt,
      'BilledBy': billedBy,
      'SoldBy': soldBy,
      'TotalAdvanceAmount': totalAdvanceAmount,
      'TotalAdvancePaid': totalAdvancePaid,
      'CreditSilver': creditSilver,
      'CreditGold': creditGold,
      'CreditAmount': creditAmount,
      'BalanceAmt': balanceAmt,
      'BalanceSilver': balanceSilver,
      'BalanceGold': balanceGold,
      'TotalSaleGold': totalSaleGold,
      'TotalSaleSilver': totalSaleSilver,
      'TotalSaleUrdGold': totalSaleUrdGold,
      'TotalSaleUrdSilver': totalSaleUrdSilver,
      'SaleType': saleType,
      'FinancialYear': financialYear,
      'BaseCurrency': baseCurrency,
      'TotalStoneWeight': totalStoneWeight,
      'TotalStoneAmount': totalStoneAmount,
      'TotalStonePieces': totalStonePieces,
      'TotalDiamondWeight': totalDiamondWeight,
      'TotalDiamondPieces': totalDiamondPieces,
      'TotalDiamondAmount': totalDiamondAmount,
      'ClientCode': clientCode,
      'ChallanNo': challanNo,
      'InvoiceCount': invoiceCount,
      'FineSilver': fineSilver,
      'FineGold': fineGold,
      'DebitSilver': debitSilver,
      'DebitGold': debitGold,
      'TotalPaidMetal': totalPaidMetal,
      'TotalPaidAmount': totalPaidAmount,
      'UrdWt': urdWt,
      'UrdAmt': urdAmt,
      'TransactionAmtType': transactionAmtType,
      'TransactionMetalType': transactionMetalType,
      'Description': description,
      'MetalType': metalType,
      'ChallanDetails': challanDetails.map((x) => x.toJson()).toList(),
      'Payments': payments.map((x) => x.toJson()).toList(),
      'CustomerName': customerName,
    };
  }
}

class ChallanDetailsModel {
  final int challanId;
  final String mrp;
  final String categoryName;
  final String challanStatus;
  final String productName;
  final String quantity;
  final String hsnCode;
  final String itemCode;
  final String grossWt;
  final String netWt;
  final int productId;
  int customerId;
  final String metalRate;
  final String makingCharg;
  final String price;
  final String huidCode;
  final String productCode;
  final String productNo;
  final String size;
  final String stoneAmount;
  final String totalWt;
  final String packingWeight;
  final String metalAmount;
  final bool oldGoldPurchase;
  final String ratePerGram;
  final String amount;
  final String challanType;
  final String finePercentage;
  final String purchaseInvoiceNo;
  final String hallmarkAmount;
  final String hallmarkNo;
  final String makingFixedAmt;
  final String makingFixedWastage;
  final String makingPerGram;
  final String makingPercentage;
  final String description;
  final String cuttingGrossWt;
  final String cuttingNetWt;
  final String baseCurrency;
  final int categoryId;
  final int purityId;
  final String totalStoneWeight;
  final String totalStoneAmount;
  final String totalStonePieces;
  final String totalDiamondWeight;
  final String totalDiamondPieces;
  final String totalDiamondAmount;
  final int skuId;
  final String sku;
  final String fineWastageWt;
  final String totalItemAmount;
  final String itemAmount;
  final String itemGSTAmount;
  final String clientCode;
  final String diamondSize;
  final String diamondWeight;
  final String diamondPurchaseRate;
  final String diamondSellRate;
  final String diamondClarity;
  final String diamondColour;
  final String diamondShape;
  final String diamondCut;
  final String diamondName;
  final String diamondSettingType;
  final String diamondCertificate;
  final String diamondPieces;
  final String diamondPurchaseAmount;
  final String diamondSellAmount;
  final String diamondDescription;
  final String metalName;
  final String netAmount;
  final String gstAmount;
  final String totalAmount;
  final String purity;
  final String designName;
  final int companyId;
  final int branchId;
  final int counterId;
  final int employeeId;
  final int labelledStockId;
  final String fineSilver;
  final String fineGold;
  final String debitSilver;
  final String debitGold;
  final String balanceSilver;
  final String balanceGold;
  final String convertAmt;
  final String pieces;
  final String stoneLessPercent;
  final int designId;
  final int packetId;
  final String rfidCode;
  final String image;
  final String diamondWt;
  final String stoneAmt;
  final String diamondAmt;
  final String finePer;
  final String fineWt;
  final int qty;
  final String tid;
  final String totayRate;
  final String makingPercent;
  final String fixMaking;
  final String fixWastage;
  final String tidNumber;
  String customerName;
  final int pcs;

  ChallanDetailsModel({
    required this.challanId,
    required this.mrp,
    required this.categoryName,
    required this.challanStatus,
    required this.productName,
    required this.quantity,
    required this.hsnCode,
    required this.itemCode,
    required this.grossWt,
    required this.netWt,
    required this.productId,
    required this.customerId,
    required this.metalRate,
    required this.makingCharg,
    required this.price,
    required this.huidCode,
    required this.productCode,
    required this.productNo,
    required this.size,
    required this.stoneAmount,
    required this.totalWt,
    required this.packingWeight,
    required this.metalAmount,
    required this.oldGoldPurchase,
    required this.ratePerGram,
    required this.amount,
    required this.challanType,
    required this.finePercentage,
    required this.purchaseInvoiceNo,
    required this.hallmarkAmount,
    required this.hallmarkNo,
    required this.makingFixedAmt,
    required this.makingFixedWastage,
    required this.makingPerGram,
    required this.makingPercentage,
    required this.description,
    required this.cuttingGrossWt,
    required this.cuttingNetWt,
    required this.baseCurrency,
    required this.categoryId,
    required this.purityId,
    required this.totalStoneWeight,
    required this.totalStoneAmount,
    required this.totalStonePieces,
    required this.totalDiamondWeight,
    required this.totalDiamondPieces,
    required this.totalDiamondAmount,
    required this.skuId,
    required this.sku,
    required this.fineWastageWt,
    required this.totalItemAmount,
    required this.itemAmount,
    required this.itemGSTAmount,
    required this.clientCode,
    required this.diamondSize,
    required this.diamondWeight,
    required this.diamondPurchaseRate,
    required this.diamondSellRate,
    required this.diamondClarity,
    required this.diamondColour,
    required this.diamondShape,
    required this.diamondCut,
    required this.diamondName,
    required this.diamondSettingType,
    required this.diamondCertificate,
    required this.diamondPieces,
    required this.diamondPurchaseAmount,
    required this.diamondSellAmount,
    required this.diamondDescription,
    required this.metalName,
    required this.netAmount,
    required this.gstAmount,
    required this.totalAmount,
    required this.purity,
    required this.designName,
    required this.companyId,
    required this.branchId,
    required this.counterId,
    required this.employeeId,
    required this.labelledStockId,
    required this.fineSilver,
    required this.fineGold,
    required this.debitSilver,
    required this.debitGold,
    required this.balanceSilver,
    required this.balanceGold,
    required this.convertAmt,
    required this.pieces,
    required this.stoneLessPercent,
    required this.designId,
    required this.packetId,
    required this.rfidCode,
    required this.image,
    required this.diamondWt,
    required this.stoneAmt,
    required this.diamondAmt,
    required this.finePer,
    required this.fineWt,
    required this.qty,
    required this.tid,
    required this.totayRate,
    required this.makingPercent,
    required this.fixMaking,
    required this.fixWastage,
    required this.tidNumber,
    required this.customerName,
    required this.pcs,
  });

  factory ChallanDetailsModel.fromJson(Map<String, dynamic> json) {
    return ChallanDetailsModel(
      challanId: json['ChallanId'] as int? ?? 0,
      mrp: json['MRP']?.toString() ?? '0.0',
      categoryName: json['CategoryName'] as String? ?? '',
      challanStatus: json['ChallanStatus'] as String? ?? '',
      productName: json['ProductName'] as String? ?? '',
      quantity: json['Quantity']?.toString() ?? '0',
      hsnCode: json['HSNCode'] as String? ?? '',
      itemCode: json['ItemCode'] as String? ?? '',
      grossWt: json['GrossWt']?.toString() ?? '0.0',
      netWt: json['NetWt']?.toString() ?? '0.0',
      productId: json['ProductId'] as int? ?? 0,
      customerId: json['CustomerId'] as int? ?? 0,
      metalRate: json['MetalRate']?.toString() ?? '0.0',
      makingCharg: json['MakingCharg']?.toString() ?? '0.0',
      price: json['Price']?.toString() ?? '0.0',
      huidCode: json['HUIDCode'] as String? ?? '',
      productCode: json['ProductCode'] as String? ?? '',
      productNo: json['ProductNo'] as String? ?? '',
      size: json['Size']?.toString() ?? '',
      stoneAmount: json['StoneAmount']?.toString() ?? '0.0',
      totalWt: json['TotalWt']?.toString() ?? '0.0',
      packingWeight: json['PackingWeight']?.toString() ?? '0.0',
      metalAmount: json['MetalAmount']?.toString() ?? '0.0',
      oldGoldPurchase: json['OldGoldPurchase'] as bool? ?? false,
      ratePerGram: json['RatePerGram']?.toString() ?? '0.0',
      amount: json['Amount']?.toString() ?? '0.0',
      challanType: json['ChallanType'] as String? ?? '',
      finePercentage: json['FinePercentage']?.toString() ?? '0.0',
      purchaseInvoiceNo: json['PurchaseInvoiceNo'] as String? ?? '',
      hallmarkAmount: json['HallmarkAmount']?.toString() ?? '0.0',
      hallmarkNo: json['HallmarkNo'] as String? ?? '',
      makingFixedAmt: json['MakingFixedAmt']?.toString() ?? '0.0',
      makingFixedWastage: json['MakingFixedWastage']?.toString() ?? '0.0',
      makingPerGram: json['MakingPerGram']?.toString() ?? '0.0',
      makingPercentage: json['MakingPercentage']?.toString() ?? '0.0',
      description: json['Description'] as String? ?? '',
      cuttingGrossWt: json['CuttingGrossWt']?.toString() ?? '0.0',
      cuttingNetWt: json['CuttingNetWt']?.toString() ?? '0.0',
      baseCurrency: json['BaseCurrency'] as String? ?? '',
      categoryId: json['CategoryId'] as int? ?? 0,
      purityId: json['PurityId'] as int? ?? 0,
      totalStoneWeight: json['TotalStoneWeight']?.toString() ?? '0.0',
      totalStoneAmount: json['TotalStoneAmount']?.toString() ?? '0.0',
      totalStonePieces: json['TotalStonePieces']?.toString() ?? '0',
      totalDiamondWeight: json['TotalDiamondWeight']?.toString() ?? '0.0',
      totalDiamondPieces: json['TotalDiamondPieces']?.toString() ?? '0',
      totalDiamondAmount: json['TotalDiamondAmount']?.toString() ?? '0.0',
      skuId: json['SKUId'] as int? ?? 0,
      sku: json['SKU'] as String? ?? '',
      fineWastageWt: json['FineWastageWt']?.toString() ?? '0.0',
      totalItemAmount: json['TotalItemAmount']?.toString() ?? '0.0',
      itemAmount: json['ItemAmount']?.toString() ?? '0.0',
      itemGSTAmount: json['ItemGSTAmount']?.toString() ?? '0.0',
      clientCode: json['ClientCode'] as String? ?? '',
      diamondSize: json['DiamondSize'] as String? ?? '',
      diamondWeight: json['DiamondWeight']?.toString() ?? '0.0',
      diamondPurchaseRate: json['DiamondPurchaseRate']?.toString() ?? '0.0',
      diamondSellRate: json['DiamondSellRate']?.toString() ?? '0.0',
      diamondClarity: json['DiamondClarity'] as String? ?? '',
      diamondColour: json['DiamondColour'] as String? ?? '',
      diamondShape: json['DiamondShape'] as String? ?? '',
      diamondCut: json['DiamondCut'] as String? ?? '',
      diamondName: json['DiamondName'] as String? ?? '',
      diamondSettingType: json['DiamondSettingType'] as String? ?? '',
      diamondCertificate: json['DiamondCertificate'] as String? ?? '',
      diamondPieces: json['DiamondPieces']?.toString() ?? '0',
      diamondPurchaseAmount: json['DiamondPurchaseAmount']?.toString() ?? '0.0',
      diamondSellAmount: json['DiamondSellAmount']?.toString() ?? '0.0',
      diamondDescription: json['DiamondDescription'] as String? ?? '',
      metalName: json['MetalName'] as String? ?? '',
      netAmount: json['NetAmount']?.toString() ?? '0.0',
      gstAmount: json['GSTAmount']?.toString() ?? '0.0',
      totalAmount: json['TotalAmount']?.toString() ?? '0.0',
      purity: json['Purity'] as String? ?? '',
      designName: json['DesignName'] as String? ?? '',
      companyId: json['CompanyId'] as int? ?? 0,
      branchId: json['BranchId'] as int? ?? 0,
      counterId: json['CounterId'] as int? ?? 0,
      employeeId: json['EmployeeId'] as int? ?? 0,
      labelledStockId: json['LabelledStockId'] as int? ?? 0,
      fineSilver: json['FineSilver']?.toString() ?? '0.0',
      fineGold: json['FineGold']?.toString() ?? '0.0',
      debitSilver: json['DebitSilver']?.toString() ?? '0.0',
      debitGold: json['DebitGold']?.toString() ?? '0.0',
      balanceSilver: json['BalanceSilver']?.toString() ?? '0.0',
      balanceGold: json['BalanceGold']?.toString() ?? '0.0',
      convertAmt: json['ConvertAmt']?.toString() ?? '0.0',
      pieces: json['Pieces']?.toString() ?? '1',
      stoneLessPercent: json['StoneLessPercent']?.toString() ?? '0.0',
      designId: json['DesignId'] as int? ?? 0,
      packetId: json['PacketId'] as int? ?? 0,
      rfidCode: json['RFIDCode'] as String? ?? '',
      image: json['Image'] as String? ?? '',
      diamondWt: json['DiamondWt']?.toString() ?? '',
      stoneAmt: json['StoneAmt']?.toString() ?? '',
      diamondAmt: json['DiamondAmt']?.toString() ?? '',
      finePer: json['FinePer']?.toString() ?? '',
      fineWt: json['FineWt']?.toString() ?? '',
      qty: json['qty'] as int? ?? 0,
      tid: json['tid'] as String? ?? '',
      totayRate: json['totayRate']?.toString() ?? '',
      makingPercent: json['makingPercent']?.toString() ?? '',
      fixMaking: json['fixMaking']?.toString() ?? '',
      fixWastage: json['fixWastage']?.toString() ?? '',
      tidNumber: json['TIDNumber'] as String? ?? '',
      customerName: json['CustomerName'] as String? ?? '',
      pcs: json['Pcs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ChallanId': challanId,
      'MRP': mrp,
      'CategoryName': categoryName,
      'ChallanStatus': challanStatus,
      'ProductName': productName,
      'Quantity': quantity,
      'HSNCode': hsnCode,
      'ItemCode': itemCode,
      'GrossWt': grossWt,
      'NetWt': netWt,
      'ProductId': productId,
      'CustomerId': customerId,
      'MetalRate': metalRate,
      'MakingCharg': makingCharg,
      'Price': price,
      'HUIDCode': huidCode,
      'ProductCode': productCode,
      'ProductNo': productNo,
      'Size': size,
      'StoneAmount': stoneAmount,
      'TotalWt': totalWt,
      'PackingWeight': packingWeight,
      'MetalAmount': metalAmount,
      'OldGoldPurchase': oldGoldPurchase,
      'RatePerGram': ratePerGram,
      'Amount': amount,
      'ChallanType': challanType,
      'FinePercentage': finePercentage,
      'PurchaseInvoiceNo': purchaseInvoiceNo,
      'HallmarkAmount': hallmarkAmount,
      'HallmarkNo': hallmarkNo,
      'MakingFixedAmt': makingFixedAmt,
      'MakingFixedWastage': makingFixedWastage,
      'MakingPerGram': makingPerGram,
      'MakingPercentage': makingPercentage,
      'Description': description,
      'CuttingGrossWt': cuttingGrossWt,
      'CuttingNetWt': cuttingNetWt,
      'BaseCurrency': baseCurrency,
      'CategoryId': categoryId,
      'PurityId': purityId,
      'TotalStoneWeight': totalStoneWeight,
      'TotalStoneAmount': totalStoneAmount,
      'TotalStonePieces': totalStonePieces,
      'TotalDiamondWeight': totalDiamondWeight,
      'TotalDiamondPieces': totalDiamondPieces,
      'TotalDiamondAmount': totalDiamondAmount,
      'SKUId': skuId,
      'SKU': sku,
      'FineWastageWt': fineWastageWt,
      'TotalItemAmount': totalItemAmount,
      'ItemAmount': itemAmount,
      'ItemGSTAmount': itemGSTAmount,
      'ClientCode': clientCode,
      'DiamondSize': diamondSize,
      'DiamondWeight': diamondWeight,
      'DiamondPurchaseRate': diamondPurchaseRate,
      'DiamondSellRate': diamondSellRate,
      'DiamondClarity': diamondClarity,
      'DiamondColour': diamondColour,
      'DiamondShape': diamondShape,
      'DiamondCut': diamondCut,
      'DiamondName': diamondName,
      'DiamondSettingType': diamondSettingType,
      'DiamondCertificate': diamondCertificate,
      'DiamondPieces': diamondPieces,
      'DiamondPurchaseAmount': diamondPurchaseAmount,
      'DiamondSellAmount': diamondSellAmount,
      'DiamondDescription': diamondDescription,
      'MetalName': metalName,
      'NetAmount': netAmount,
      'GSTAmount': gstAmount,
      'TotalAmount': totalAmount,
      'Purity': purity,
      'DesignName': designName,
      'CompanyId': companyId,
      'BranchId': branchId,
      'CounterId': counterId,
      'EmployeeId': employeeId,
      'LabelledStockId': labelledStockId,
      'FineSilver': fineSilver,
      'FineGold': fineGold,
      'DebitSilver': debitSilver,
      'DebitGold': debitGold,
      'BalanceSilver': balanceSilver,
      'BalanceGold': balanceGold,
      'ConvertAmt': convertAmt,
      'Pieces': pieces,
      'StoneLessPercent': stoneLessPercent,
      'DesignId': designId,
      'PacketId': packetId,
      'RFIDCode': rfidCode,
      'Image': image,
      'DiamondWt': diamondWt,
      'StoneAmt': stoneAmt,
      'DiamondAmt': diamondAmt,
      'FinePer': finePer,
      'FineWt': fineWt,
      'qty': qty,
      'tid': tid,
      'totayRate': totayRate,
      'makingPercent': makingPercent,
      'fixMaking': fixMaking,
      'fixWastage': fixWastage,
      'TIDNumber': tidNumber,
      'CustomerName': customerName,
      'Pcs': pcs,
    };
  }

  ChallanDetailsModel copyWith({
    int? challanId,
    String? mrp,
    String? categoryName,
    String? challanStatus,
    String? productName,
    String? quantity,
    String? hsnCode,
    String? itemCode,
    String? grossWt,
    String? netWt,
    int? productId,
    int? customerId,
    String? metalRate,
    String? makingCharg,
    String? price,
    String? huidCode,
    String? productCode,
    String? productNo,
    String? size,
    String? stoneAmount,
    String? totalWt,
    String? packingWeight,
    String? metalAmount,
    bool? oldGoldPurchase,
    String? ratePerGram,
    String? amount,
    String? challanType,
    String? finePercentage,
    String? purchaseInvoiceNo,
    String? hallmarkAmount,
    String? hallmarkNo,
    String? makingFixedAmt,
    String? makingFixedWastage,
    String? makingPerGram,
    String? makingPercentage,
    String? description,
    String? cuttingGrossWt,
    String? cuttingNetWt,
    String? baseCurrency,
    int? categoryId,
    int? purityId,
    String? totalStoneWeight,
    String? totalStoneAmount,
    String? totalStonePieces,
    String? totalDiamondWeight,
    String? totalDiamondPieces,
    String? totalDiamondAmount,
    int? skuId,
    String? sku,
    String? fineWastageWt,
    String? totalItemAmount,
    String? itemAmount,
    String? itemGSTAmount,
    String? clientCode,
    String? diamondSize,
    String? diamondWeight,
    String? diamondPurchaseRate,
    String? diamondSellRate,
    String? diamondClarity,
    String? diamondColour,
    String? diamondShape,
    String? diamondCut,
    String? diamondName,
    String? diamondSettingType,
    String? diamondCertificate,
    String? diamondPieces,
    String? diamondPurchaseAmount,
    String? diamondSellAmount,
    String? diamondDescription,
    String? metalName,
    String? netAmount,
    String? gstAmount,
    String? totalAmount,
    String? purity,
    String? designName,
    int? companyId,
    int? branchId,
    int? counterId,
    int? employeeId,
    int? labelledStockId,
    String? fineSilver,
    String? fineGold,
    String? debitSilver,
    String? debitGold,
    String? balanceSilver,
    String? balanceGold,
    String? convertAmt,
    String? pieces,
    String? stoneLessPercent,
    int? designId,
    int? packetId,
    String? rfidCode,
    String? image,
    String? diamondWt,
    String? stoneAmt,
    String? diamondAmt,
    String? finePer,
    String? fineWt,
    int? qty,
    String? tid,
    String? totayRate,
    String? makingPercent,
    String? fixMaking,
    String? fixWastage,
    String? tidNumber,
    String? customerName,
    int? pcs,
  }) {
    return ChallanDetailsModel(
      challanId: challanId ?? this.challanId,
      mrp: mrp ?? this.mrp,
      categoryName: categoryName ?? this.categoryName,
      challanStatus: challanStatus ?? this.challanStatus,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      hsnCode: hsnCode ?? this.hsnCode,
      itemCode: itemCode ?? this.itemCode,
      grossWt: grossWt ?? this.grossWt,
      netWt: netWt ?? this.netWt,
      productId: productId ?? this.productId,
      customerId: customerId ?? this.customerId,
      metalRate: metalRate ?? this.metalRate,
      makingCharg: makingCharg ?? this.makingCharg,
      price: price ?? this.price,
      huidCode: huidCode ?? this.huidCode,
      productCode: productCode ?? this.productCode,
      productNo: productNo ?? this.productNo,
      size: size ?? this.size,
      stoneAmount: stoneAmount ?? this.stoneAmount,
      totalWt: totalWt ?? this.totalWt,
      packingWeight: packingWeight ?? this.packingWeight,
      metalAmount: metalAmount ?? this.metalAmount,
      oldGoldPurchase: oldGoldPurchase ?? this.oldGoldPurchase,
      ratePerGram: ratePerGram ?? this.ratePerGram,
      amount: amount ?? this.amount,
      challanType: challanType ?? this.challanType,
      finePercentage: finePercentage ?? this.finePercentage,
      purchaseInvoiceNo: purchaseInvoiceNo ?? this.purchaseInvoiceNo,
      hallmarkAmount: hallmarkAmount ?? this.hallmarkAmount,
      hallmarkNo: hallmarkNo ?? this.hallmarkNo,
      makingFixedAmt: makingFixedAmt ?? this.makingFixedAmt,
      makingFixedWastage: makingFixedWastage ?? this.makingFixedWastage,
      makingPerGram: makingPerGram ?? this.makingPerGram,
      makingPercentage: makingPercentage ?? this.makingPercentage,
      description: description ?? this.description,
      cuttingGrossWt: cuttingGrossWt ?? this.cuttingGrossWt,
      cuttingNetWt: cuttingNetWt ?? this.cuttingNetWt,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      categoryId: categoryId ?? this.categoryId,
      purityId: purityId ?? this.purityId,
      totalStoneWeight: totalStoneWeight ?? this.totalStoneWeight,
      totalStoneAmount: totalStoneAmount ?? this.totalStoneAmount,
      totalStonePieces: totalStonePieces ?? this.totalStonePieces,
      totalDiamondWeight: totalDiamondWeight ?? this.totalDiamondWeight,
      totalDiamondPieces: totalDiamondPieces ?? this.totalDiamondPieces,
      totalDiamondAmount: totalDiamondAmount ?? this.totalDiamondAmount,
      skuId: skuId ?? this.skuId,
      sku: sku ?? this.sku,
      fineWastageWt: fineWastageWt ?? this.fineWastageWt,
      totalItemAmount: totalItemAmount ?? this.totalItemAmount,
      itemAmount: itemAmount ?? this.itemAmount,
      itemGSTAmount: itemGSTAmount ?? this.itemGSTAmount,
      clientCode: clientCode ?? this.clientCode,
      diamondSize: diamondSize ?? this.diamondSize,
      diamondWeight: diamondWeight ?? this.diamondWeight,
      diamondPurchaseRate: diamondPurchaseRate ?? this.diamondPurchaseRate,
      diamondSellRate: diamondSellRate ?? this.diamondSellRate,
      diamondClarity: diamondClarity ?? this.diamondClarity,
      diamondColour: diamondColour ?? this.diamondColour,
      diamondShape: diamondShape ?? this.diamondShape,
      diamondCut: diamondCut ?? this.diamondCut,
      diamondName: diamondName ?? this.diamondName,
      diamondSettingType: diamondSettingType ?? this.diamondSettingType,
      diamondCertificate: diamondCertificate ?? this.diamondCertificate,
      diamondPieces: diamondPieces ?? this.diamondPieces,
      diamondPurchaseAmount: diamondPurchaseAmount ?? this.diamondPurchaseAmount,
      diamondSellAmount: diamondSellAmount ?? this.diamondSellAmount,
      diamondDescription: diamondDescription ?? this.diamondDescription,
      metalName: metalName ?? this.metalName,
      netAmount: netAmount ?? this.netAmount,
      gstAmount: gstAmount ?? this.gstAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      purity: purity ?? this.purity,
      designName: designName ?? this.designName,
      companyId: companyId ?? this.companyId,
      branchId: branchId ?? this.branchId,
      counterId: counterId ?? this.counterId,
      employeeId: employeeId ?? this.employeeId,
      labelledStockId: labelledStockId ?? this.labelledStockId,
      fineSilver: fineSilver ?? this.fineSilver,
      fineGold: fineGold ?? this.fineGold,
      debitSilver: debitSilver ?? this.debitSilver,
      debitGold: debitGold ?? this.debitGold,
      balanceSilver: balanceSilver ?? this.balanceSilver,
      balanceGold: balanceGold ?? this.balanceGold,
      convertAmt: convertAmt ?? this.convertAmt,
      pieces: pieces ?? this.pieces,
      stoneLessPercent: stoneLessPercent ?? this.stoneLessPercent,
      designId: designId ?? this.designId,
      packetId: packetId ?? this.packetId,
      rfidCode: rfidCode ?? this.rfidCode,
      image: image ?? this.image,
      diamondWt: diamondWt ?? this.diamondWt,
      stoneAmt: stoneAmt ?? this.stoneAmt,
      diamondAmt: diamondAmt ?? this.diamondAmt,
      finePer: finePer ?? this.finePer,
      fineWt: fineWt ?? this.fineWt,
      qty: qty ?? this.qty,
      tid: tid ?? this.tid,
      totayRate: totayRate ?? this.totayRate,
      makingPercent: makingPercent ?? this.makingPercent,
      fixMaking: fixMaking ?? this.fixMaking,
      fixWastage: fixWastage ?? this.fixWastage,
      tidNumber: tidNumber ?? this.tidNumber,
      customerName: customerName ?? this.customerName,
      pcs: pcs ?? this.pcs,
    );
  }
}

class PaymentModel {
  final int? id;
  final String? mode;
  final String? amount;

  PaymentModel({
    this.id,
    this.mode,
    this.amount,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['Id'] as int?,
      mode: json['Mode'] as String?,
      amount: json['Amount']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Id': id,
      'Mode': mode,
      'Amount': amount,
    };
  }
}
