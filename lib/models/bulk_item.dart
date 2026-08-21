class BulkItem {
  final int? id;
  final int bulkItemId;
  final String productName;
  final String itemCode;
  final String rfid;
  final String grossWeight;
  final String stoneWeight;
  final String diamondWeight;
  final String netWeight;
  final String category;
  final String design;
  final String purity;
  final String makingPerGram;
  final String makingPercent;
  final String fixMaking;
  final String fixWastage;
  final String stoneAmount;
  final String diamondAmount;
  final String sku;
  String epc;
  final String vendor;
  String tid;
  final String box;
  final String designCode;
  final String productCode;
  String imageUrl;
  final int totalQty;
  final int pcs;
  final int matchedPcs;
  final double totalGwt;
  final double matchGwt;
  final double totalStoneWt;
  final double matchStoneWt;
  final double totalNetWt;
  final double matchNetWt;
  final int unmatchedQty;
  final int matchedQty;
  final double unmatchedGrossWt;
  final double mrp;
  final String counterName;
  final int counterId;
  final int boxId;
  final String boxName;
  final int branchId;
  final String branchName;
  final int packetId;
  final String packetName;
  final String scannedStatus;
  final int categoryId;
  final int productId;
  final String branchType;
  final int designId;
  int isScanned; // 0 = false, 1 = true (SQLite handles booleans as integers)
  final double totalWt;
  final String categoryWt;
  final int skuId;
  final int purityId;
  final String status;

  BulkItem({
    this.id,
    required this.bulkItemId,
    required this.productName,
    required this.itemCode,
    required this.rfid,
    required this.grossWeight,
    required this.stoneWeight,
    required this.diamondWeight,
    required this.netWeight,
    required this.category,
    required this.design,
    required this.purity,
    required this.makingPerGram,
    required this.makingPercent,
    required this.fixMaking,
    required this.fixWastage,
    required this.stoneAmount,
    required this.diamondAmount,
    required this.sku,
    required this.epc,
    required this.vendor,
    required this.tid,
    required this.box,
    required this.designCode,
    required this.productCode,
    required this.imageUrl,
    required this.totalQty,
    required this.pcs,
    required this.matchedPcs,
    required this.totalGwt,
    required this.matchGwt,
    required this.totalStoneWt,
    required this.matchStoneWt,
    required this.totalNetWt,
    required this.matchNetWt,
    required this.unmatchedQty,
    required this.matchedQty,
    required this.unmatchedGrossWt,
    required this.mrp,
    required this.counterName,
    required this.counterId,
    required this.boxId,
    required this.boxName,
    required this.branchId,
    required this.branchName,
    required this.packetId,
    required this.packetName,
    required this.scannedStatus,
    required this.categoryId,
    required this.productId,
    required this.branchType,
    required this.designId,
    required this.isScanned,
    required this.totalWt,
    required this.categoryWt,
    required this.skuId,
    required this.purityId,
    required this.status,
  });

  // Map representation to store in SQLite
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'bulkItemId': bulkItemId,
      'productName': productName,
      'itemCode': itemCode,
      'rfid': rfid,
      'grossWeight': grossWeight,
      'stoneWeight': stoneWeight,
      'diamondWeight': diamondWeight,
      'netWeight': netWeight,
      'category': category,
      'design': design,
      'purity': purity,
      'makingPerGram': makingPerGram,
      'makingPercent': makingPercent,
      'fixMaking': fixMaking,
      'fixWastage': fixWastage,
      'stoneAmount': stoneAmount,
      'diamondAmount': diamondAmount,
      'sku': sku,
      // Empty string breaks UNIQUE(epc) — only one '' row can insert; use NULL like Room.
      'epc': epc.trim().isEmpty ? null : epc.trim(),
      'vendor': vendor,
      'tid': tid.trim().isEmpty ? null : tid.trim(),
      'box': box,
      'designCode': designCode,
      'productCode': productCode,
      'imageUrl': imageUrl,
      'totalQty': totalQty,
      'pcs': pcs,
      'matchedPcs': matchedPcs,
      'totalGwt': totalGwt,
      'matchGwt': matchGwt,
      'totalStoneWt': totalStoneWt,
      'matchStoneWt': matchStoneWt,
      'totalNetWt': totalNetWt,
      'matchNetWt': matchNetWt,
      'unmatchedQty': unmatchedQty,
      'matchedQty': matchedQty,
      'unmatchedGrossWt': unmatchedGrossWt,
      'mrp': mrp,
      'counterName': counterName,
      'counterId': counterId,
      'boxId': boxId,
      'boxName': boxName,
      'branchId': branchId,
      'branchName': branchName,
      'packetId': packetId,
      'packetName': packetName,
      'scannedStatus': scannedStatus,
      'categoryId': categoryId,
      'productId': productId,
      'branchType': branchType,
      'designId': designId,
      'isScanned': isScanned,
      'totalWt': totalWt,
      'categoryWt': categoryWt,
      'skuId': skuId,
      'purityId': purityId,
      'status': status,
    };
  }

  // Load from SQLite Map
  factory BulkItem.fromMap(Map<String, dynamic> map) {
    return BulkItem(
      id: map['id'] as int?,
      bulkItemId: (map['bulkItemId'] as num?)?.toInt() ?? 0,
      productName: map['productName'] as String? ?? '',
      itemCode: map['itemCode'] as String? ?? '',
      rfid: map['rfid']?.toString() ?? '',
      grossWeight: map['grossWeight'] as String? ?? '',
      stoneWeight: map['stoneWeight'] as String? ?? '',
      diamondWeight: map['diamondWeight'] as String? ?? '',
      netWeight: map['netWeight'] as String? ?? '',
      category: map['category'] as String? ?? '',
      design: map['design'] as String? ?? '',
      purity: map['purity'] as String? ?? '',
      makingPerGram: map['makingPerGram'] as String? ?? '',
      makingPercent: map['makingPercent'] as String? ?? '',
      fixMaking: map['fixMaking'] as String? ?? '',
      fixWastage: map['fixWastage'] as String? ?? '',
      stoneAmount: map['stoneAmount'] as String? ?? '',
      diamondAmount: map['diamondAmount'] as String? ?? '',
      sku: map['sku'] as String? ?? '',
      epc: map['epc']?.toString() ?? '',
      vendor: map['vendor'] as String? ?? '',
      tid: map['tid']?.toString() ?? '',
      box: map['box'] as String? ?? '',
      designCode: map['designCode'] as String? ?? '',
      productCode: map['productCode'] as String? ?? '',
      imageUrl: map['imageUrl'] as String? ?? '',
      totalQty: map['totalQty'] as int? ?? 0,
      pcs: map['pcs'] as int? ?? 0,
      matchedPcs: map['matchedPcs'] as int? ?? 0,
      totalGwt: (map['totalGwt'] as num?)?.toDouble() ?? 0.0,
      matchGwt: (map['matchGwt'] as num?)?.toDouble() ?? 0.0,
      totalStoneWt: (map['totalStoneWt'] as num?)?.toDouble() ?? 0.0,
      matchStoneWt: (map['matchStoneWt'] as num?)?.toDouble() ?? 0.0,
      totalNetWt: (map['totalNetWt'] as num?)?.toDouble() ?? 0.0,
      matchNetWt: (map['matchNetWt'] as num?)?.toDouble() ?? 0.0,
      unmatchedQty: map['unmatchedQty'] as int? ?? 0,
      matchedQty: map['matchedQty'] as int? ?? 0,
      unmatchedGrossWt: (map['unmatchedGrossWt'] as num?)?.toDouble() ?? 0.0,
      mrp: (map['mrp'] as num?)?.toDouble() ?? 0.0,
      counterName: map['counterName'] as String? ?? '',
      counterId: map['counterId'] as int? ?? 0,
      boxId: map['boxId'] as int? ?? 0,
      boxName: map['boxName'] as String? ?? '',
      branchId: map['branchId'] as int? ?? 0,
      branchName: map['branchName'] as String? ?? '',
      packetId: map['packetId'] as int? ?? 0,
      packetName: map['packetName'] as String? ?? '',
      scannedStatus: map['scannedStatus'] as String? ?? '',
      categoryId: map['categoryId'] as int? ?? 0,
      productId: map['productId'] as int? ?? 0,
      branchType: map['branchType'] as String? ?? '',
      designId: map['designId'] as int? ?? 0,
      isScanned: map['isScanned'] as int? ?? 0,
      totalWt: (map['totalWt'] as num?)?.toDouble() ?? 0.0,
      categoryWt: map['categoryWt'] as String? ?? '',
      skuId: map['skuId'] as int? ?? 0,
      purityId: map['purityId'] as int? ?? 0,
      status: map['status'] as String? ?? '',
    );
  }

  /// Safe API string read — case-insensitive keys, non-string values OK
  /// (ASP.NET may send PascalCase or camelCase; Gson SerializedName is exact).
  static String apiString(Map<String, dynamic> json, List<String> keys) {
    String? pick(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty || s.toLowerCase() == 'null') return null;
      return s;
    }

    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      final s = pick(json[key]);
      if (s != null) return s;
    }

    // Case-insensitive fallback (e.g. rfidCode / tidNumber / RFIDCODE).
    final lower = <String, dynamic>{
      for (final e in json.entries) e.key.toLowerCase(): e.value,
    };
    for (final key in keys) {
      final s = pick(lower[key.toLowerCase()]);
      if (s != null) return s;
    }
    return '';
  }

  // Map API Response item to BulkItem model
  // Mirrors Sparkle [LabelItemsMapper.toBulkItem].
  factory BulkItem.fromApi(Map<String, dynamic> json) {
    final itemCode = apiString(json, ['ItemCode', 'itemCode']);
    // Exact RFID from API (never invent / never blank when server sent it).
    final rfidCode = apiString(json, [
      'RFIDCode',
      'RfidCode',
      'rfidCode',
      'RFID',
      'rfid',
      'RfidBarcode',
      'rfidBarcode',
    ]);
    // TID/EPC from API only — do NOT copy RFID into epc (causes UNIQUE collisions at 10k scale).
    final tidNumber = apiString(json, [
      'TIDNumber',
      'TidNumber',
      'tidNumber',
      'TidValue',
      'tidValue',
      'TID',
      'tid',
      'EPC',
      'Epc',
      'epc',
      'EpcValue',
      'epcValue',
    ]);
    final epc = tidNumber;

    return BulkItem(
      bulkItemId: int.tryParse(json['Id']?.toString() ?? json['id']?.toString() ?? '') ?? 0,
      productName: apiString(json, ['ProductName', 'productName']),
      itemCode: itemCode,
      rfid: rfidCode,
      grossWeight: apiString(json, ['GrossWt', 'grossWt']),
      stoneWeight: apiString(json, ['TotalStoneWeight', 'totalStoneWeight']),
      diamondWeight: apiString(json, ['TotalDiamondWeight', 'totalDiamondWeight']),
      netWeight: apiString(json, ['NetWt', 'netWt']),
      category: apiString(json, ['CategoryName', 'categoryName']),
      design: apiString(json, ['DesignName', 'designName']),
      purity: apiString(json, ['PurityName', 'purityName']),
      makingPerGram: apiString(json, ['MakingPerGram', 'makingPerGram']),
      makingPercent: apiString(json, ['MakingPercentage', 'makingPercentage']),
      fixMaking: apiString(json, ['MakingFixedAmt', 'makingFixedAmt']),
      fixWastage: apiString(json, ['MakingFixedWastage', 'makingFixedWastage']),
      stoneAmount: apiString(json, ['TotalStoneAmount', 'totalStoneAmount']),
      diamondAmount: apiString(json, ['TotalDiamondAmount', 'totalDiamondAmount']),
      sku: apiString(json, ['SKU', 'sku']),
      epc: epc,
      vendor: apiString(json, ['VendorName', 'vendorName']),
      tid: tidNumber,
      box: '',
      designCode: '',
      productCode: apiString(json, ['ProductCode', 'productCode']),
      imageUrl: apiString(json, ['Images', 'image', 'Image', 'images']),
      totalQty: int.tryParse(json['Quantity']?.toString() ?? '') ?? 0,
      pcs: int.tryParse(json['Pieces']?.toString() ?? '') ?? 0,
      matchedPcs: 0,
      totalGwt: 0.0,
      matchGwt: 0.0,
      totalStoneWt: double.tryParse(json['TotalStoneWeight']?.toString() ?? '') ?? 0.0,
      matchStoneWt: 0.0,
      totalNetWt: double.tryParse(json['NetWt']?.toString() ?? '') ?? 0.0,
      matchNetWt: 0.0,
      unmatchedQty: 0,
      matchedQty: 0,
      unmatchedGrossWt: 0.0,
      mrp: double.tryParse(json['MRP']?.toString() ?? '') ?? 0.0,
      counterName: apiString(json, ['CounterName', 'counterName']),
      counterId: int.tryParse(json['CounterId']?.toString() ?? '') ?? 0,
      boxId: int.tryParse(json['BoxId']?.toString() ?? '') ?? 0,
      boxName: apiString(json, ['BoxName', 'boxName']),
      branchId: int.tryParse(json['BranchId']?.toString() ?? '') ?? 0,
      branchName: apiString(json, ['BranchName', 'branchName']),
      packetId: int.tryParse(json['PacketId']?.toString() ?? '') ?? 0,
      packetName: apiString(json, ['PacketName', 'packetName']),
      scannedStatus: '',
      categoryId: int.tryParse(json['CategoryId']?.toString() ?? '') ?? 0,
      productId: int.tryParse(json['ProductId']?.toString() ?? '') ?? 0,
      branchType: apiString(json, ['BranchType', 'branchType']),
      designId: int.tryParse(json['DesignId']?.toString() ?? '') ?? 0,
      isScanned: 0,
      totalWt: double.tryParse(json['TotalWeight']?.toString() ?? '') ?? 0.0,
      categoryWt: apiString(json, ['WeightCategory', 'weightCategory']),
      skuId: int.tryParse(json['SKUId']?.toString() ?? '') ?? 0,
      purityId: int.tryParse(json['PurityId']?.toString() ?? '') ?? 0,
      status: apiString(json, ['Status', 'status']),
    );
  }

  /// Local-only row for bulk add / excel import (matches Kotlin defaults).
  factory BulkItem.local({
    required String category,
    required String productName,
    required String design,
    required String itemCode,
    String rfid = '',
    String epc = '',
    String tid = '',
    String grossWeight = '',
    String stoneWeight = '',
    String diamondWeight = '',
    String netWeight = '',
    String purity = '',
    String makingPerGram = '',
    String makingPercent = '',
    String fixMaking = '',
    String fixWastage = '',
    String stoneAmount = '',
    String diamondAmount = '',
    String sku = '',
    String vendor = '',
    String counterName = '',
    String branchName = '',
    String boxName = '',
  }) {
    final normalizedEpc = epc.trim().isNotEmpty ? epc.trim() : (rfid.trim().isNotEmpty ? rfid.trim() : tid.trim());
    return BulkItem(
      bulkItemId: 0,
      productName: productName,
      itemCode: itemCode,
      rfid: rfid,
      grossWeight: grossWeight,
      stoneWeight: stoneWeight,
      diamondWeight: diamondWeight,
      netWeight: netWeight,
      category: category,
      design: design,
      purity: purity,
      makingPerGram: makingPerGram,
      makingPercent: makingPercent,
      fixMaking: fixMaking,
      fixWastage: fixWastage,
      stoneAmount: stoneAmount,
      diamondAmount: diamondAmount,
      sku: sku,
      epc: normalizedEpc,
      vendor: vendor,
      tid: tid.isNotEmpty ? tid : normalizedEpc,
      box: '',
      designCode: '',
      productCode: '',
      imageUrl: '',
      totalQty: 0,
      pcs: 0,
      matchedPcs: 0,
      totalGwt: 0.0,
      matchGwt: 0.0,
      totalStoneWt: 0.0,
      matchStoneWt: 0.0,
      totalNetWt: 0.0,
      matchNetWt: 0.0,
      unmatchedQty: 0,
      matchedQty: 0,
      unmatchedGrossWt: 0.0,
      mrp: 0.0,
      counterName: counterName,
      counterId: 0,
      boxId: 0,
      boxName: boxName,
      branchId: 0,
      branchName: branchName,
      packetId: 0,
      packetName: '',
      scannedStatus: '',
      categoryId: 0,
      productId: 0,
      branchType: '',
      designId: 0,
      isScanned: 0,
      totalWt: 0.0,
      categoryWt: '',
      skuId: 0,
      purityId: 0,
      status: '',
    );
  }
}
