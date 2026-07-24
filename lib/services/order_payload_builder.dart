import '../models/employee.dart';

/// Builds CustomOrder payloads to match Sparkle `CustomOrderRequest` 1:1.
/// Reference: Sparkle_Optimised `CustomOrderRequest.kt` + `OrderScreen.kt` buildCustomOrderRequest.
class OrderPayloadBuilder {
  static String financialYear([DateTime? now]) {
    final d = now ?? DateTime.now();
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    final endShort = (startYear + 1).toString().substring(2);
    return '$startYear-$endShort';
  }

  static String _s(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    final t = v.toString().trim();
    if (t.isEmpty || t.toLowerCase() == 'null') return fallback;
    return t;
  }

  static String _s0(dynamic v) => _s(v, '0');

  static String _s00(dynamic v) => _s(v, '0.0');

  static int _i(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? fallback;
  }

  static double _sumItems(List items, String key) {
    var total = 0.0;
    for (final it in items) {
      if (it is Map) {
        total += double.tryParse(it[key]?.toString() ?? '') ?? 0.0;
      }
    }
    return total;
  }

  static String? _decimalOrNull(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    final d = double.tryParse(s);
    return d?.toString();
  }

  /// Sparkle: `OffsetDateTime.now(IST).format(ISO_OFFSET_DATE_TIME)`
  static String isoOffsetNow() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final oh = offset.inHours.abs().toString().padLeft(2, '0');
    final om = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$y-$m-${d}T$h:$min:$s$sign$oh:$om';
  }

  static String nowDateOnly() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static String toIsoOffsetDateTime(String? input) {
    final raw = input?.trim() ?? '';
    if (raw.isEmpty || raw.toLowerCase() == 'null') return isoOffsetNow();
    if (raw.contains('T') &&
        (raw.endsWith('Z') ||
            RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw) ||
            RegExp(r'[+-]\d{4}$').hasMatch(raw))) {
      return raw;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      final offset = DateTime.now().timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final oh = offset.inHours.abs().toString().padLeft(2, '0');
      final om = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      return '${raw}T00:00:00$sign$oh:$om';
    }
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(raw);
    if (m != null) {
      final dd = m.group(1)!.padLeft(2, '0');
      final mm = m.group(2)!.padLeft(2, '0');
      final yyyy = m.group(3)!;
      final offset = DateTime.now().timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final oh = offset.inHours.abs().toString().padLeft(2, '0');
      final om = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      return '$yyyy-$mm-${dd}T00:00:00$sign$oh:$om';
    }
    return isoOffsetNow();
  }

  static String toIsoLocalDate(String? input) {
    final raw = input?.trim() ?? '';
    if (raw.isEmpty || raw.toLowerCase() == 'null') return nowDateOnly();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    if (raw.contains('T')) return raw.split('T').first;
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(raw);
    if (m != null) {
      return '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
    }
    return nowDateOnly();
  }

  /// Exact Sparkle `CustomOrderRequest` JSON (Gson includes nulls).
  ///
  /// [forceCreateDefaults] — when true (AddCustomOrder / CREATE sync), force
  /// GST fields to match Sparkle `buildCustomOrderRequest` (GST="0", GSTApplied="false").
  static Map<String, dynamic> toSparkleApiPayload(
    Map<String, dynamic> source, {
    required String clientCode,
    Employee? employee,
    int? customOrderId,
    String? orderNo,
    int? customerId,
    bool forceCreateDefaults = false,
  }) {
    final rawItems = (source['CustomOrderItem'] as List?) ?? const [];
    final srcItems = rawItems
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final first = srcItems.isNotEmpty ? srcItems.first : null;
    final srcCust = source['Customer'] is Map
        ? Map<String, dynamic>.from(source['Customer'] as Map)
        : <String, dynamic>{};

    final resolvedCid = () {
      final forced = customerId ?? 0;
      if (forced > 0) return forced;
      final root = _i(source['CustomerId']);
      if (root > 0) return root;
      final nested = _i(srcCust['Id']);
      return nested > 0 ? nested : 0;
    }();

    final baseTotal = _s(
      source['TotalNetAmount'],
      _s(source['TotalAmount'], _sumItems(srcItems, 'Amount').toStringAsFixed(2)),
    );

    // Sparkle CREATE always sends GST off. UPDATE may keep GST from source.
    final wantGst = !forceCreateDefaults &&
        _s(source['GSTApplied'], 'false').toLowerCase() == 'true';
    final gstApplied = wantGst ? 'true' : 'false';
    final gstValue = wantGst ? 'true' : '0';
    final totalGst = wantGst ? _s(source['TotalGSTAmount'], '0') : '0';
    final gstAmountField = wantGst ? _s(source['GstAmount'], totalGst) : '0';
    final totalAmount = wantGst
        ? _s(source['TotalAmount'], baseTotal)
        : baseTotal;
    final totalNet = baseTotal;

    var orderStatus = _s(source['OrderStatus'], 'Order Received');
    if (orderStatus.toUpperCase().contains('PENDING') ||
        orderStatus.toUpperCase().contains('OFFLINE')) {
      orderStatus = 'Order Received';
    }

    final resolvedOrderNo = _s(orderNo ?? source['OrderNo'], '0');
    final resolvedCustomId = customOrderId ?? _i(source['CustomOrderId']);
    final categoryId = _i(first?['CategoryId']);
    final categoryName = _s(first?['CategoryName']);
    final qty = srcItems.isEmpty ? '0' : srcItems.length.toString();
    final employeeName = employee?.firstName ?? employee?.userName ?? '';
    final fallbackBranchId = (employee?.defaultBranchId ?? 0) > 0
        ? employee!.defaultBranchId
        : 1;
    final orderDate = toIsoOffsetDateTime(source['OrderDate']?.toString());

    final items = <Map<String, dynamic>>[];
    for (final it in srcItems) {
      var branchId = _i(it['BranchId']);
      if (branchId <= 0) branchId = fallbackBranchId;

      items.add({
        'CustomOrderId': resolvedCustomId,
        'RFIDCode': _s(it['RFIDCode']),
        'OrderDate': toIsoOffsetDateTime(it['OrderDate']?.toString() ?? orderDate),
        'DeliverDate': toIsoLocalDate(it['DeliverDate']?.toString()),
        'SKUId': _i(it['SKUId']),
        'SKU': _s(it['SKU']),
        'CategoryId': _i(it['CategoryId']),
        'VendorId': _i(it['VendorId']),
        'CategoryName': _s(it['CategoryName']),
        'CustomerName': _s(
          it['CustomerName'],
          employeeName.isNotEmpty
              ? employeeName
              : '${_s(srcCust['FirstName'])} ${_s(srcCust['LastName'])}'.trim(),
        ),
        'VendorName': _s(it['VendorName']),
        'ProductId': _i(it['ProductId']),
        'ProductName': _s(it['ProductName']),
        'DesignId': _i(it['DesignId']),
        'DesignName': _s(it['DesignName']),
        'PurityId': _i(it['PurityId']),
        'PurityName': _s(it['PurityName'], _s(it['Purity'])),
        'GrossWt': _s00(it['GrossWt']),
        'StoneWt': _s00(it['StoneWt']),
        'DiamondWt': _s00(it['DiamondWt']),
        'NetWt': _s00(it['NetWt']),
        'Size': _s(it['Size']),
        'Length': _s(it['Length']),
        'TypesOdColors': _s(it['TypesOdColors']),
        'Quantity': () {
          final q = _s(it['Quantity'], '1');
          final n = double.tryParse(q)?.toInt() ?? 0;
          return n <= 0 ? '1' : n.toString();
        }(),
        'RatePerGram': _s00(it['RatePerGram']),
        'MakingPerGram': _s00(it['MakingPerGram']),
        'MakingFixed': _s00(it['MakingFixed']),
        'FixedWt': _s00(it['FixedWt']),
        'MakingPercentage': _s00(it['MakingPercentage']),
        'DiamondPieces': _s0(it['DiamondPieces']),
        'DiamondRate': _s0(it['DiamondRate']),
        'DiamondAmount': _s00(it['DiamondAmount']),
        'StoneAmount': _s00(it['StoneAmount']),
        'ScrewType': _s(it['ScrewType']),
        'Polish': _s(it['Polish']),
        'Rhodium': _s(it['Rhodium']),
        'SampleWt': _s(it['SampleWt']),
        'Image': _s(it['Image']),
        'ItemCode': _s(it['ItemCode']),
        'CustomerId': resolvedCid,
        'MRP': _s00(it['MRP']),
        'HSNCode': _s(it['HSNCode']),
        'UnlProductId': _i(it['UnlProductId']),
        'OrderBy': _s(it['OrderBy']),
        'StoneLessPercent': _s0(it['StoneLessPercent']),
        'ProductCode': _s(it['ProductCode']),
        'TotalWt': _s(it['TotalWt']).isNotEmpty ? _s00(it['TotalWt']) : _s00(it['NetWt']),
        'BillType': 'SampleOut',
        'FinePercentage': _s00(it['FinePercentage']),
        'ClientCode': clientCode,
        'OrderId': null, // Sparkle sends null
        'StatusType': true,
        'PackingWeight': _s00(it['PackingWeight']),
        'MetalAmount': _s00(it['MetalAmount']),
        'OldGoldPurchase': false,
        'Amount': _s00(it['Amount']),
        'totalGstAmount': wantGst
            ? (_s(it['totalGstAmount']).isNotEmpty ? _s00(it['totalGstAmount']) : _s00(totalGst))
            : '0.0',
        'finalPrice': _s(it['finalPrice']).isNotEmpty
            ? _s00(it['finalPrice'])
            : _s00(it['Amount']),
        'MakingFixedWastage': _s00(it['MakingFixedWastage']),
        'Description': _s(it['Description']).isNotEmpty
            ? _s(it['Description'])
            : _s(it['Remark']),
        'CompanyId': _i(it['CompanyId']),
        'LabelledStockId': _i(it['LabelledStockId']),
        'TotalStoneWeight': _s(it['TotalStoneWeight']).isNotEmpty
            ? _s00(it['TotalStoneWeight'])
            : _s00(it['StoneWt']),
        'BranchId': branchId,
        'BranchName': _s(it['BranchName']),
        'Exhibition': _s(it['Exhibition']),
        'CounterId': _s(it['CounterId'], '0'),
        'EmployeeId': _i(it['EmployeeId'], employee?.id ?? 0),
        'OrderNo': resolvedOrderNo,
        'OrderStatus': orderStatus,
        'DueDate': null,
        'Remark': it['Remark'] == null ? null : _s(it['Remark']),
        'PurchaseInvoiceNo': null,
        'Purity': _s(it['Purity'], _s(it['PurityName'])),
        'Status': null,
        'URDNo': null,
        'HallmarkAmount': _decimalOrNull(it['HallmarkAmount']),
        'WeightCategories': _decimalOrNull(it['WeightCategories']),
        'Stones': <dynamic>[],
        'Diamond': <dynamic>[],
        'TIDNumber': it['TIDNumber']?.toString(),
      });
    }

    final customer = <String, dynamic>{
      'FirstName': _s(srcCust['FirstName']),
      'LastName': _s(srcCust['LastName']),
      'PerAddStreet': _s(srcCust['PerAddStreet']),
      'CurrAddStreet': _s(srcCust['CurrAddStreet']),
      'Mobile': _s(srcCust['Mobile']),
      'Email': _s(srcCust['Email']),
      'Password': '',
      'CustomerLoginId': _s(srcCust['CustomerLoginId'], _s(srcCust['Email'])),
      'DateOfBirth': _s(srcCust['DateOfBirth']),
      'MiddleName': _s(srcCust['MiddleName']),
      'PerAddPincode': _s(srcCust['PerAddPincode']),
      'Gender': _s(srcCust['Gender']),
      'OnlineStatus': _s(srcCust['OnlineStatus']),
      'CurrAddTown': _s(srcCust['CurrAddTown']),
      'CurrAddPincode': _s(srcCust['CurrAddPincode']),
      'CurrAddState': _s(srcCust['CurrAddState']),
      'PerAddTown': _s(srcCust['PerAddTown']),
      'PerAddState': _s(srcCust['PerAddState']),
      'GstNo': _s(srcCust['GstNo']),
      'PanNo': _s(srcCust['PanNo']),
      'AadharNo': _s(srcCust['AadharNo']),
      'BalanceAmount': _s0(srcCust['BalanceAmount']),
      'AdvanceAmount': _s0(srcCust['AdvanceAmount']),
      'Discount': _s0(srcCust['Discount']),
      'CreditPeriod': _s(srcCust['CreditPeriod']),
      'FineGold': _s0(srcCust['FineGold']),
      'FineSilver': _s0(srcCust['FineSilver']),
      'ClientCode': _s(srcCust['ClientCode'], clientCode),
      'VendorId': 0,
      'AddToVendor': false,
      'CustomerSlabId': 0,
      'CreditPeriodId': 0,
      'RateOfInterestId': 0,
      'Remark': '',
      'Area': _s(srcCust['Area']),
      'City': _s(srcCust['City']),
      'Country': _s(srcCust['Country']),
      'Id': resolvedCid,
      'CreatedOn': nowDateOnly(),
      'LastUpdated': nowDateOnly(),
      'StatusType': true,
    };

    // Build Sparkle CustomOrderRequest, then omit nulls (Gson default).
    final body = <String, dynamic>{
      'Id': 0,
      'CustomOrderId': resolvedCustomId,
      'CustomerId': resolvedCid.toString(),
      'ClientCode': clientCode,
      'OrderId': 0,
      'TotalAmount': totalAmount,
      'PaymentMode': '',
      'Offer': null,
      'Qty': qty,
      'GST': gstValue,
      'OrderStatus': orderStatus,
      'MRP': null,
      'VendorId': null,
      'TDS': null,
      'PurchaseStatus': null,
      'GSTApplied': gstApplied,
      'Discount': '0',
      'TotalNetAmount': totalNet,
      'TotalGSTAmount': totalGst,
      'TotalPurchaseAmount': totalAmount,
      'ReceivedAmount': '0',
      'TotalBalanceMetal': '0',
      'BalanceAmount': totalAmount,
      'TotalFineMetal': '0',
      'CourierCharge': null,
      'SaleType': null,
      'OrderDate': orderDate,
      'OrderCount': qty,
      'AdditionTaxApplied': wantGst ? 'true' : 'false',
      'CategoryId': categoryId,
      'OrderNo': resolvedOrderNo,
      'DeliveryAddress': null,
      'BillType': 'SampleOut',
      'UrdPurchaseAmt': null,
      'BilledBy': employeeName,
      'SoldBy': employeeName,
      'CreditSilver': null,
      'CreditGold': null,
      'CreditAmount': null,
      'BalanceAmt': totalAmount,
      'BalanceSilver': null,
      'BalanceGold': null,
      'TotalSaleGold': null,
      'TotalSaleSilver': null,
      'TotalSaleUrdGold': null,
      'TotalSaleUrdSilver': null,
      'FinancialYear': financialYear(),
      'BaseCurrency': 'INR',
      'TotalStoneWeight': _sumItems(srcItems, 'StoneWt').toString(),
      'TotalStoneAmount': _sumItems(srcItems, 'StoneAmount').toString(),
      'TotalStonePieces': '0',
      'TotalDiamondWeight': _sumItems(srcItems, 'DiamondWt').toString(),
      'TotalDiamondPieces': '0',
      'TotalDiamondAmount': _sumItems(srcItems, 'DiamondAmount').toString(),
      'FineSilver': '0',
      'FineGold': '0',
      'DebitSilver': null,
      'DebitGold': null,
      'PaidMetal': '0',
      'PaidAmount': '0',
      'TotalAdvanceAmt': null,
      'TaxableAmount': totalNet,
      'TDSAmount': null,
      // Current date/time like Sparkle OrderDate (ISO offset) — never null (ASP.NET DateTime 400).
      'CreatedOn': orderDate,
      'StatusType': true,
      'FineMetal': '0',
      'BalanceMetal': '0',
      'AdvanceAmt': '0',
      'PaidAmt': '0',
      'TaxableAmt': totalNet,
      'GstAmount': gstAmountField,
      'GstCheck': gstApplied,
      'Category': categoryName,
      'TDSCheck': 'false',
      'Remark': null,
      'OrderItemId': null,
      'StoneStatus': null,
      'DiamondStatus': null,
      'BulkOrderId': null,
      'CustomOrderItem': items,
      'Payments': <dynamic>[],
      'uRDPurchases': <dynamic>[],
      'Customer': customer,
      'syncStatus': false,
      'LastUpdated': null,
      'HallmarkAmount': null,
      'WeightCatogories': null, // Sparkle spelling (typo kept on purpose)
      'SKUId': 0,
      'RfidCode': '',
      'TidNumber': '',
    };

    // Match Gson default: do NOT serialize null fields.
    return omitNulls(body);
  }

  /// Deep-omit nulls (same as default Gson — Sparkle Retrofit).
  static Map<String, dynamic> omitNulls(Map<String, dynamic> input) {
    dynamic clean(dynamic v) {
      if (v == null) return null;
      if (v is Map) {
        final out = <String, dynamic>{};
        v.forEach((k, val) {
          final c = clean(val);
          if (c != null) out[k.toString()] = c;
        });
        return out;
      }
      if (v is List) {
        return v.map(clean).where((e) => e != null).toList();
      }
      return v;
    }

    return Map<String, dynamic>.from(clean(input) as Map);
  }

  static Map<String, dynamic> enrichForApi(
    Map<String, dynamic> payload, {
    required String clientCode,
    Employee? employee,
  }) {
    return toSparkleApiPayload(
      payload,
      clientCode: clientCode,
      employee: employee,
      forceCreateDefaults: true,
    );
  }

  static Map<String, dynamic> sanitizeForApi(Map<String, dynamic> input) {
    final out = Map<String, dynamic>.from(input);
    out.remove('IsPendingSync');
    out.remove('LocalOrderId');
    out.remove('LocalCustomerId');
    out.remove('operation');
    out.remove('PendingOperation');
    out.remove('SyncStatus');
    var status = _s(out['OrderStatus'], 'Order Received');
    if (status.toUpperCase().contains('PENDING') ||
        status.toUpperCase().contains('OFFLINE')) {
      status = 'Order Received';
    }
    out['OrderStatus'] = status;
    return out;
  }
}
