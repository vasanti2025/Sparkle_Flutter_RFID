import 'package:intl/intl.dart';

import '../models/employee.dart';

/// Builds/enriches CustomOrder API payloads to match the native Android app.
class OrderPayloadBuilder {
  static String financialYear([DateTime? now]) {
    final d = now ?? DateTime.now();
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    final endShort = (startYear + 1).toString().substring(2);
    return '$startYear-$endShort';
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

  static Map<String, dynamic>? _firstItem(List? items) {
    if (items == null || items.isEmpty) return null;
    final first = items.first;
    return first is Map<String, dynamic> ? first : null;
  }

  /// Ensures offline/synced orders include all root fields the web API expects.
  static Map<String, dynamic> enrichForApi(
    Map<String, dynamic> payload, {
    required String clientCode,
    Employee? employee,
  }) {
    final order = Map<String, dynamic>.from(payload);
    final items = (order['CustomOrderItem'] as List?) ?? const [];
    final first = _firstItem(items);
    final customer = order['Customer'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(order['Customer'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final totalAmount = order['TotalAmount']?.toString() ??
        _sumItems(items, 'Amount').toStringAsFixed(2);
    final totalNet = order['TotalNetAmount']?.toString() ?? totalAmount;
    final totalGst = order['TotalGSTAmount']?.toString() ?? '0';
    final gstApplied = order['GSTApplied']?.toString() ?? 'False';
    final isGst = gstApplied.toLowerCase() == 'true';
    final gstValue = order['GST']?.toString() ?? (isGst ? '3.0' : '0.0');
    final gstAmount = isGst ? totalGst : '0';
    final gstCheck = isGst ? 'true' : 'false';

    final customerId = customer['Id']?.toString() ?? '0';
    final categoryId = first?['CategoryId'] as int? ?? 0;
    final categoryName = first?['CategoryName']?.toString() ?? '';
    final qty = items.length.toString();
    final orderDate = order['OrderDate']?.toString().trim().isNotEmpty == true
        ? order['OrderDate'].toString()
        : DateFormat('yyyy-MM-dd').format(DateTime.now());
    final employeeName = employee?.firstName ?? employee?.userName ?? '';

    final totalStoneWt = _sumItems(items, 'StoneWt').toStringAsFixed(3);
    final totalStoneAmt = _sumItems(items, 'StoneAmount').toStringAsFixed(2);
    final totalDiamondWt = _sumItems(items, 'DiamondWt').toStringAsFixed(3);
    final totalDiamondAmt = _sumItems(items, 'DiamondAmount').toStringAsFixed(2);

    order['CustomOrderId'] = order['CustomOrderId'] ?? 0;
    order['ClientCode'] = clientCode;
    order['CustomerId'] = customerId;
    order['OrderId'] = order['OrderId'] ?? 0;
    order['Qty'] = qty;
    order['OrderCount'] = qty;
    order['OrderStatus'] = order['OrderStatus']?.toString() ?? 'Order Received';
    order['BillType'] = order['BillType']?.toString() ?? 'SampleOut';
    order['CategoryId'] = categoryId;
    order['Category'] = categoryName;
    order['StatusType'] = order['StatusType'] ?? true;
    order['PaymentMode'] = order['PaymentMode']?.toString() ?? '';
    order['Discount'] = order['Discount']?.toString() ?? '0';
    order['TotalAmount'] = totalAmount;
    order['TotalNetAmount'] = totalNet;
    order['TotalGSTAmount'] = totalGst;
    order['TotalPurchaseAmount'] = order['TotalPurchaseAmount']?.toString() ?? totalAmount;
    order['ReceivedAmount'] = order['ReceivedAmount']?.toString() ?? '0';
    order['TotalBalanceMetal'] = order['TotalBalanceMetal']?.toString() ?? '0';
    order['BalanceAmount'] = order['BalanceAmount']?.toString() ?? totalAmount;
    order['TotalFineMetal'] = order['TotalFineMetal']?.toString() ?? '0';
    order['BalanceAmt'] = order['BalanceAmt']?.toString() ?? totalAmount;
    order['AdditionTaxApplied'] = order['AdditionTaxApplied']?.toString() ?? 'false';
    order['BilledBy'] = order['BilledBy']?.toString() ?? employeeName;
    order['SoldBy'] = order['SoldBy']?.toString() ?? employeeName;
    order['FinancialYear'] = order['FinancialYear']?.toString() ?? financialYear();
    order['BaseCurrency'] = order['BaseCurrency']?.toString() ?? 'INR';
    order['TotalStoneWeight'] = order['TotalStoneWeight']?.toString() ?? totalStoneWt;
    order['TotalStoneAmount'] = order['TotalStoneAmount']?.toString() ?? totalStoneAmt;
    order['TotalStonePieces'] = order['TotalStonePieces']?.toString() ?? '0';
    order['TotalDiamondWeight'] = order['TotalDiamondWeight']?.toString() ?? totalDiamondWt;
    order['TotalDiamondPieces'] = order['TotalDiamondPieces']?.toString() ?? '0';
    order['TotalDiamondAmount'] = order['TotalDiamondAmount']?.toString() ?? totalDiamondAmt;
    order['FineSilver'] = order['FineSilver']?.toString() ?? '0';
    order['FineGold'] = order['FineGold']?.toString() ?? '0';
    order['PaidMetal'] = order['PaidMetal']?.toString() ?? '0';
    order['PaidAmount'] = order['PaidAmount']?.toString() ?? '0';
    order['TaxableAmount'] = order['TaxableAmount']?.toString() ?? totalNet;
    order['TaxableAmt'] = order['TaxableAmt']?.toString() ?? totalNet;
    order['GstAmount'] = order['GstAmount']?.toString() ?? gstAmount;
    order['GstCheck'] = order['GstCheck']?.toString() ?? gstCheck;
    order['FineMetal'] = order['FineMetal']?.toString() ?? '0';
    order['BalanceMetal'] = order['BalanceMetal']?.toString() ?? '0';
    order['AdvanceAmt'] = order['AdvanceAmt']?.toString() ?? '0';
    order['PaidAmt'] = order['PaidAmt']?.toString() ?? '0';
    order['TDSCheck'] = order['TDSCheck']?.toString() ?? 'false';
    order['GSTApplied'] = gstApplied;
    order['GST'] = gstValue;
    order['OrderDate'] = orderDate;
    order['CreatedOn'] = order['CreatedOn']?.toString() ?? orderDate;
    order['syncStatus'] = false;
    order['RfidCode'] = order['RfidCode']?.toString() ?? '';
    order['TidNumber'] = order['TidNumber']?.toString() ?? '';
    order['Payments'] = order['Payments'] ?? [];
    order['uRDPurchases'] = order['uRDPurchases'] ?? [];

    customer['ClientCode'] = customer['ClientCode']?.toString() ?? clientCode;
    customer['StatusType'] = customer['StatusType'] ?? true;
    order['Customer'] = customer;

    final enrichedItems = <Map<String, dynamic>>[];
    for (final it in items) {
      if (it is! Map) continue;
      final item = Map<String, dynamic>.from(it);
      item['ClientCode'] = clientCode;
      item['CustomerId'] = int.tryParse(customerId) ?? item['CustomerId'] ?? 0;
      item['EmployeeId'] = item['EmployeeId'] ?? employee?.id ?? 0;
      item['OrderNo'] = order['OrderNo']?.toString() ?? item['OrderNo']?.toString() ?? '';
      item['OrderDate'] = item['OrderDate']?.toString().isNotEmpty == true
          ? item['OrderDate']
          : orderDate;
      item['CustomerName'] = item['CustomerName']?.toString().isNotEmpty == true
          ? item['CustomerName']
          : employeeName;
      item['StatusType'] = item['StatusType'] ?? true;
      item['BillType'] = item['BillType']?.toString() ?? 'SampleOut';
      item['Stones'] = item['Stones'] ?? [];
      item['Diamond'] = item['Diamond'] ?? [];
      enrichedItems.add(item);
    }
    order['CustomOrderItem'] = enrichedItems;

    order.remove('IsPendingSync');
    order.remove('LocalOrderId');
    order.remove('LocalCustomerId');

    return order;
  }
}
