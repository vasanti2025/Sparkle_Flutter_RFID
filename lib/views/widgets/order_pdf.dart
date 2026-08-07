import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/customer.dart';
import '../../utils/pdf_open_util.dart';

const _tableRowsPerPage = 6;

/// Deep-converts decoded JSON maps so nested Customer fields are readable.
Map<String, dynamic> normalizeOrderMap(Map source) {
  final out = <String, dynamic>{};
  source.forEach((key, value) {
    final k = key.toString();
    if (value is Map) {
      out[k] = normalizeOrderMap(value);
    } else if (value is List) {
      out[k] = value.map((entry) {
        if (entry is Map) return normalizeOrderMap(entry);
        return entry;
      }).toList();
    } else {
      out[k] = value;
    }
  });
  return out;
}

/// Fills missing customer fields (city, email, mobile, etc.) from customer list API cache.
/// Matches strictly by [CustomerId] — never by name alone.
Map<String, dynamic> enrichOrderForPdf(
  Map<String, dynamic> orderRes,
  List<CustomerModel> customers,
) {
  orderRes = normalizeOrderMap(orderRes);
  if (customers.isEmpty) return orderRes;

  var customerId = resolveOrderCustomerId(orderRes);
  CustomerModel? match = customerId == null
      ? null
      : findCustomerById(customers, customerId);

  if (match == null) {
    final byName = findCustomerByName(customers, _customerName(orderRes));
    if (byName != null) {
      match = byName;
      customerId = byName.id;
      debugPrint(
        'Order PDF: CustomerId missing — matched "${byName.firstName ?? ''}" by name (Id=${byName.id}).',
      );
    }
  }

  if (match == null || customerId == null) {
    debugPrint('Order PDF: no customer match for order CustomerId=$customerId');
    return orderRes;
  }

  if (!_customerIdentityConsistent(orderRes, match, customerId)) {
    debugPrint(
      'Order PDF: CustomerId=$customerId name mismatch — using customer list record '
      '"${match.firstName ?? ''} ${match.lastName ?? ''}".',
    );
  }

  final enriched = Map<String, dynamic>.from(orderRes);
  enriched['CustomerId'] = customerId.toString();

  final existing = enriched['Customer'];
  final merged = existing is Map
      ? Map<String, dynamic>.from(existing)
      : <String, dynamic>{};

  merged['Id'] = match.id;

  void setFromCustomerList(String key, String? value) {
    if (value == null || value.trim().isEmpty) return;
    merged[key] = value.trim();
  }

  setFromCustomerList('Mobile', match.mobile);
  setFromCustomerList('Email', match.email);
  setFromCustomerList('CurrAddState', match.currAddState);
  setFromCustomerList('City', match.city);
  setFromCustomerList('CustomerLoginId', match.customerLoginId ?? match.email);
  setFromCustomerList('FirstName', match.firstName);
  setFromCustomerList('LastName', match.lastName);
  setFromCustomerList('CurrAddTown', match.currAddTown);
  setFromCustomerList('Area', match.area);
  setFromCustomerList('Country', match.country);

  enriched['Customer'] = merged;
  enriched['Mobile'] = match.mobile ?? merged['Mobile']?.toString() ?? '';
  enriched['Email'] = match.email ?? merged['Email']?.toString() ?? '';
  enriched['CurrAddState'] =
      match.currAddState ?? merged['CurrAddState']?.toString() ?? '';
  enriched['City'] = match.city ?? merged['City']?.toString() ?? '';

  final name = '${match.firstName ?? ''} ${match.lastName ?? ''}'.trim();
  if (name.isNotEmpty) {
    enriched['CustomerName'] = name;
  }

  return enriched;
}

/// Parses a positive customer id from order root, nested Customer, or line items.
int? resolveOrderCustomerId(Map<String, dynamic> orderRes) {
  int? parsePositiveId(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw > 0 ? raw : null;
    final parsed = int.tryParse(raw.toString().trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  final fromRoot = parsePositiveId(orderRes['CustomerId']);
  final customer = orderRes['Customer'];
  final fromCustomer = customer is Map ? parsePositiveId(customer['Id']) : null;

  int? fromItems;
  final items = orderRes['CustomOrderItem'];
  if (items is List) {
    for (final raw in items) {
      if (raw is! Map) continue;
      final itemId = parsePositiveId(raw['CustomerId']);
      if (itemId == null) continue;
      if (fromItems == null) {
        fromItems = itemId;
      } else if (fromItems != itemId) {
        debugPrint(
          'Order PDF: mixed CustomerId on items ($fromItems vs $itemId) — using order header id.',
        );
        break;
      }
    }
  }

  final ids = <int>{};
  if (fromRoot != null) ids.add(fromRoot);
  if (fromCustomer != null) ids.add(fromCustomer);
  if (fromItems != null) ids.add(fromItems);
  if (ids.isEmpty) return null;
  if (ids.length > 1) {
    debugPrint('Order PDF: conflicting CustomerId values $ids — preferring order header.');
  }

  return fromRoot ?? fromCustomer ?? fromItems;
}

CustomerModel? findCustomerById(List<CustomerModel> customers, int customerId) {
  for (final customer in customers) {
    if (customer.id == customerId) return customer;
  }
  return null;
}

CustomerModel? findCustomerByName(List<CustomerModel> customers, String customerName) {
  final target = _normalizePersonName(customerName);
  if (target.isEmpty) return null;

  for (final customer in customers) {
    final listName = _normalizePersonName(
      '${customer.firstName ?? ''} ${customer.lastName ?? ''}',
    );
    if (listName.isNotEmpty && listName == target) return customer;
  }
  return null;
}

bool _customerIdentityConsistent(
  Map<String, dynamic> orderRes,
  CustomerModel match,
  int customerId,
) {
  final nested = orderRes['Customer'];
  if (nested is Map) {
    final nestedId = int.tryParse(nested['Id']?.toString() ?? '');
    if (nestedId != null && nestedId > 0 && nestedId != customerId) {
      return false;
    }
  }

  final orderName = _normalizePersonName(_customerName(orderRes));
  final listName = _normalizePersonName(
    '${match.firstName ?? ''} ${match.lastName ?? ''}',
  );
  if (orderName.isEmpty || listName.isEmpty) return true;
  return orderName == listName;
}

String _normalizePersonName(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Customer order PDF — summary table + per-item detail pages.
/// Used from Order save and Order list print.
Future<void> printCustomOrderPdf({
  required BuildContext context,
  required Map<String, dynamic> orderRes,
  required String baseUrl,
}) async {
  await openOrdersPdf(
    context: context,
    orders: [orderRes],
    baseUrl: baseUrl,
    fileName: _singleOrderPdfFileName(orderRes),
  );
}

String _singleOrderPdfFileName(Map<String, dynamic> orderRes) {
  final orderNo = _orderNo(orderRes);
  final custName = _customerName(orderRes);
  return 'Order_${orderNo.isNotEmpty ? orderNo : (custName.isNotEmpty ? custName : 'Customer')}';
}

/// Opens one combined PDF for multiple orders (filtered list download).
Future<void> openOrdersPdf({
  required BuildContext context,
  required List<Map<String, dynamic>> orders,
  required String baseUrl,
  required String fileName,
}) async {
  if (!context.mounted || orders.isEmpty) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final bytes = await buildOrdersPdfBytes(orders: orders, baseUrl: baseUrl);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    final ok = await PdfOpenUtil.openPdfBytes(
      bytes: bytes,
      fileName: fileName,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PDF viewer installed')),
      );
    }
  } catch (e, st) {
    debugPrint('Order PDF failed: $e\n$st');
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate PDF: $e')),
      );
    }
  }
}

Future<Uint8List> buildOrdersPdfBytes({
  required List<Map<String, dynamic>> orders,
  required String baseUrl,
}) async {
  final pdf = pw.Document();
  for (final orderRes in orders) {
    await _appendOrderPagesToPdf(
      pdf: pdf,
      orderRes: orderRes,
      baseUrl: baseUrl,
    );
  }
  return pdf.save();
}

Future<void> _appendOrderPagesToPdf({
  required pw.Document pdf,
  required Map<String, dynamic> orderRes,
  required String baseUrl,
}) async {
  final custName = _customerName(orderRes);
  final orderNo = _orderNo(orderRes);
  final itemsList = orderRes['CustomOrderItem'];

  final tableRows = <_OrderPdfRow>[];
  final detailItems = <Map<String, dynamic>>[];

  if (itemsList is List) {
    for (var i = 0; i < itemsList.length; i++) {
      final raw = itemsList[i];
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      detailItems.add(item);

      final image = await _loadPdfThumbnail(
        _orderImagePath(item),
        baseUrl,
        large: false,
      );

      tableRows.add(
        _OrderPdfRow(
          srNo: '${i + 1}',
          barCode: _orderBarCode(item),
          item: _orderItemName(item),
          image: image,
          colour: _orderColour(item),
          pt: _orderPt(item, orderRes),
          dwt: _orderDwt(item, orderRes),
          size: _orderSize(item, orderRes),
          netWt: _displayWt(item['NetWt']),
          remarks: _orderRemark(item, orderRes),
        ),
      );
    }
  }

  if (tableRows.isEmpty) {
    tableRows.add(
      const _OrderPdfRow(
        srNo: '-',
        barCode: '-',
        item: '-',
        image: null,
        colour: '-',
        pt: '-',
        dwt: '-',
        size: '-',
        netWt: '-',
        remarks: '-',
      ),
    );
  }

  _addTablePages(
    pdf: pdf,
    orderRes: orderRes,
    custName: custName,
    orderNo: orderNo,
    detailItems: detailItems,
    rows: tableRows,
  );

  for (var i = 0; i < detailItems.length; i++) {
    final item = detailItems[i];
    final largeImage = await _loadPdfThumbnail(
      _orderImagePath(item),
      baseUrl,
      large: true,
    );
    _addItemDetailPage(
      pdf: pdf,
      orderRes: orderRes,
      custName: custName,
      orderNo: _itemOrderNo(orderRes, item),
      item: item,
      image: largeImage,
      itemIndex: i + 1,
      totalItems: detailItems.length,
    );
  }
}

void _addTablePages({
  required pw.Document pdf,
  required Map<String, dynamic> orderRes,
  required String custName,
  required String orderNo,
  required List<Map<String, dynamic>> detailItems,
  required List<_OrderPdfRow> rows,
}) {
  for (var pageStart = 0; pageStart < rows.length; pageStart += _tableRowsPerPage) {
    final end = (pageStart + _tableRowsPerPage).clamp(0, rows.length);
    final pageRows = rows.sublist(pageStart, end);
    final isFirstPage = pageStart == 0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(18),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  isFirstPage ? 'Customer Order' : 'Customer Order (continued)',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 8),
              if (isFirstPage) ...[
                _buildOrderSummaryHeader(
                  orderRes: orderRes,
                  custName: custName,
                  orderNo: orderNo,
                  detailItems: detailItems,
                ),
                pw.SizedBox(height: 10),
              ],
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
                columnWidths: const {
                  0: pw.FlexColumnWidth(0.55),
                  1: pw.FlexColumnWidth(1.15),
                  2: pw.FlexColumnWidth(1.45),
                  3: pw.FlexColumnWidth(0.95),
                  4: pw.FlexColumnWidth(0.65),
                  5: pw.FlexColumnWidth(0.65),
                  6: pw.FlexColumnWidth(0.75),
                  7: pw.FlexColumnWidth(0.95),
                  8: pw.FlexColumnWidth(0.75),
                  9: pw.FlexColumnWidth(0.95),
                },
                children: [
                  _orderHeaderRow(),
                  ...pageRows.map(_orderDataRow),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

pw.Widget _buildOrderSummaryHeader({
  required Map<String, dynamic> orderRes,
  required String custName,
  required String orderNo,
  required List<Map<String, dynamic>> detailItems,
}) {
  final totals = _orderWeightTotals(detailItems);
  final remarks = _orderHeaderRemark(orderRes, detailItems);
  final email = _customerEmail(orderRes);
  final mobile = _customerMobile(orderRes);
  final date = _orderDateFormatted(orderRes);
  final totalWtGms = totals.netWtGms;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      _headerGridRow(
        left: _detailLine('PURCHASE ORDER NO', orderNo),
        right: _detailLine('REMARKS', remarks),
      ),
      _headerGridRow(
        left: _detailLine('CLIENT / COMPANY NAME', custName),
      ),
      _headerGridRow(
        left: _detailLine('CITY / PLACE', _customerCity(orderRes)),
      ),
      _headerGridRow(
        left: _detailLine('CONTACT PERSON', _contactPerson(orderRes)),
      ),
      _headerGridRow(
        left: _detailLine('MOBILE NO :', mobile),
        right: _detailLine('EMAIL', email),
      ),
      _headerGridRow(
        left: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _detailLine('TOTAL ORDER WT', ''),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                'Number of pcs as per DESIGN CODE / Total $totalWtGms GMS',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        right: _detailLine('DATE', date),
      ),
    ],
  );
}

pw.Widget _headerGridRow({
  required pw.Widget left,
  pw.Widget? right,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(flex: 3, child: left),
        if (right != null) ...[
          pw.SizedBox(width: 16),
          pw.Expanded(flex: 2, child: right),
        ],
      ],
    ),
  );
}

class _OrderWeightTotals {
  final String grossWt;
  final String stoneWt;
  final String netWt;
  final String netWtGms;

  const _OrderWeightTotals({
    required this.grossWt,
    required this.stoneWt,
    required this.netWt,
    required this.netWtGms,
  });
}

_OrderWeightTotals _orderWeightTotals(List<Map<String, dynamic>> items) {
  var gross = 0.0;
  var stone = 0.0;
  var net = 0.0;
  var hasGross = false;
  var hasStone = false;
  var hasNet = false;

  for (final item in items) {
    final g = double.tryParse(item['GrossWt']?.toString() ?? '');
    if (g != null) {
      gross += g;
      hasGross = true;
    }
    final s = double.tryParse(
      _firstNonEmpty([
        item['StoneWt']?.toString(),
        item['TotalStoneWeight']?.toString(),
      ]),
    );
    if (s != null) {
      stone += s;
      hasStone = true;
    }
    final n = double.tryParse(item['NetWt']?.toString() ?? '');
    if (n != null) {
      net += n;
      hasNet = true;
    }
  }

  return _OrderWeightTotals(
    grossWt: hasGross ? gross.toStringAsFixed(3) : '-',
    stoneWt: hasStone ? stone.toStringAsFixed(3) : '-',
    netWt: hasNet ? net.toStringAsFixed(2) : '-',
    netWtGms: hasNet ? net.toStringAsFixed(3) : '0.000',
  );
}

Map<String, dynamic>? _customerMap(Map<String, dynamic> orderRes) {
  final customer = orderRes['Customer'];
  if (customer is Map) return Map<String, dynamic>.from(customer);
  return null;
}

String _pickCustomerField(Map<String, dynamic> orderRes, List<String> keys) {
  for (final key in keys) {
    final top = orderRes[key]?.toString().trim() ?? '';
    if (top.isNotEmpty && top.toLowerCase() != 'null') return top;
  }

  final customer = _customerMap(orderRes);
  if (customer != null) {
    for (final key in keys) {
      final text = customer[key]?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
  }
  return '';
}

String _customerCity(Map<String, dynamic> orderRes) {
  return _displayText(_firstNonEmpty([
    _pickCustomerField(orderRes, ['CurrAddState']),
    _pickCustomerField(orderRes, ['City']),
    _pickCustomerField(orderRes, ['PerAddState']),
    _pickCustomerField(orderRes, ['CurrAddTown', 'PerAddTown']),
    _pickCustomerField(orderRes, ['Area']),
  ]));
}

String _contactPerson(Map<String, dynamic> orderRes) {
  return _displayText(_firstNonEmpty([
    _pickCustomerField(orderRes, ['ContactPerson', 'ContactName']),
    '${_pickCustomerField(orderRes, ['FirstName'])} ${_pickCustomerField(orderRes, ['LastName'])}'
        .trim(),
    orderRes['ContactPerson']?.toString(),
  ]));
}

String _customerMobile(Map<String, dynamic> orderRes) {
  return _displayText(_firstNonEmpty([
    _pickCustomerField(orderRes, ['Mobile']),
  ]));
}

String _customerEmail(Map<String, dynamic> orderRes) {
  return _displayText(_firstNonEmpty([
    _pickCustomerField(orderRes, ['Email']),
    _pickCustomerField(orderRes, ['CustomerLoginId']),
  ]));
}

String _orderDateFormatted(Map<String, dynamic> orderRes) {
  final raw = _firstNonEmpty([
    orderRes['OrderDate']?.toString(),
    orderRes['CreatedOn']?.toString(),
  ]);
  if (raw.isEmpty) return _formatPdfDate(DateTime.now());

  final datePart = raw.split('T').first.trim();
  final parsed = DateTime.tryParse(datePart);
  if (parsed != null) return _formatPdfDate(parsed);

  final slashParts = datePart.split('/');
  if (slashParts.length == 3) return datePart;

  final dashParts = datePart.split('-');
  if (dashParts.length == 3) {
    final year = int.tryParse(dashParts[0]);
    final month = int.tryParse(dashParts[1]);
    final day = int.tryParse(dashParts[2]);
    if (year != null && month != null && day != null) {
      return _formatPdfDate(DateTime(year, month, day));
    }
  }

  return datePart;
}

String _formatPdfDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String _orderHeaderRemark(
  Map<String, dynamic> orderRes,
  List<Map<String, dynamic>> items,
) {
  final orderRemark = _pickOrderField(const {}, orderRes, [
    'Remark',
    'Remarks',
    'OrderRemark',
  ]);
  if (orderRemark != null) return orderRemark;
  if (items.length == 1) {
    return _orderRemark(items.first, orderRes);
  }
  return '-';
}

void _addItemDetailPage({
  required pw.Document pdf,
  required Map<String, dynamic> orderRes,
  required String custName,
  required String orderNo,
  required Map<String, dynamic> item,
  required pw.MemoryImage? image,
  required int itemIndex,
  required int totalItems,
}) {
  final leftLines = [
    _detailLine('Name', custName),
    _detailLine('Order No', orderNo),
    _detailLine('Design', _displayText(item['DesignName'] ?? item['CategoryName'])),
    _detailLine('RFID No', _displayRfid(item)),
    _detailLine('Quantity', _displayQty(item['Quantity'])),
    _detailLine('Bar Code', _orderBarCode(item)),
    _detailLine('Item', _orderItemName(item)),
  ];

  final rightLines = [
    _detailLine('Gross Wt', _displayWt(item['GrossWt'])),
    _detailLine('Stone Wt', _displayWt(item['StoneWt'])),
    _detailLine('Net Wt', _displayWt(item['NetWt'])),
    _detailLine('Colour', _orderColour(item)),
    _detailLine('PT', _orderPt(item, orderRes)),
    _detailLine('DWT', _orderDwt(item, orderRes)),
    _detailLine('Size', _orderSize(item, orderRes)),
    _detailLine('Remark', _orderRemark(item, orderRes)),
  ];

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'Customer Order',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'Item $itemIndex of $totalItems',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: leftLines,
                  ),
                ),
                pw.SizedBox(width: 24),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: rightLines,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            if (image != null)
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              )
            else
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 24),
                child: pw.Center(
                  child: pw.Text(
                    'Image not available',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

pw.Widget _detailLine(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label     : ',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: value.isEmpty ? '-' : value,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

String _itemOrderNo(Map<String, dynamic> orderRes, Map<String, dynamic> item) {
  return _firstNonEmpty([
    item['OrderNo']?.toString(),
    orderRes['OrderNo']?.toString(),
  ]);
}

String _displayRfid(Map<String, dynamic> item) {
  return _displayText(
    item['RFIDCode'] ?? item['RfidCode'] ?? item['EPC'] ?? item['TIDNumber'],
  );
}

String _displayQty(dynamic value) {
  final t = value?.toString().trim() ?? '';
  if (t.isEmpty) return '1';
  return t;
}

String _displayWt(dynamic value) {
  final t = value?.toString().trim() ?? '';
  if (t.isEmpty) return '-';
  return t;
}

String _displayText(dynamic value) {
  final t = value?.toString().trim() ?? '';
  if (t.isEmpty || t.toLowerCase() == 'null') return '-';
  return t;
}

String _customerName(Map<String, dynamic> orderRes) {
  final custMap = orderRes['Customer'];
  if (custMap is Map) {
    final map = Map<String, dynamic>.from(custMap);
    return _firstNonEmpty([
      '${map['FirstName'] ?? ''} ${map['LastName'] ?? ''}'.trim(),
      map['CustomerName']?.toString(),
    ]);
  }
  return _firstNonEmpty([orderRes['CustomerName']?.toString()]);
}

String _orderImagePath(Map<String, dynamic> item) {
  return _pickOrderField(item, const {}, ['Image', 'Images']) ?? '';
}

String _orderNo(Map<String, dynamic> orderRes) {
  return _firstNonEmpty([orderRes['OrderNo']?.toString()]);
}

String _resolveImageUrl(String path, String baseUrl) {
  if (path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final imgList = path.split(',');
  final lastImg = imgList.isNotEmpty ? imgList.last.trim() : '';
  if (lastImg.isEmpty) return '';
  var base = baseUrl.trim();
  if (base.isEmpty) return lastImg;
  if (!base.endsWith('/')) base = '$base/';
  if (lastImg.startsWith('/')) return '$base${lastImg.substring(1)}';
  return '$base$lastImg';
}

Future<pw.MemoryImage?> _loadPdfThumbnail(
  String rawImage,
  String baseUrl, {
  required bool large,
}) async {
  if (rawImage.isEmpty) return null;
  final url = _resolveImageUrl(rawImage, baseUrl);
  if (url.isEmpty) return null;

  try {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

    final decoded = img.decodeImage(res.bodyBytes);
    if (decoded == null) return null;

    final target = large ? 480 : 72;
    final thumb = img.copyResize(
      decoded,
      width: target,
      height: target,
      interpolation: img.Interpolation.linear,
    );
    final jpg = Uint8List.fromList(img.encodeJpg(thumb, quality: large ? 82 : 70));
    return pw.MemoryImage(jpg);
  } catch (e) {
    debugPrint('Order PDF image skipped ($url): $e');
    return null;
  }
}

class _OrderPdfRow {
  final String srNo;
  final String barCode;
  final String item;
  final pw.MemoryImage? image;
  final String colour;
  final String pt;
  final String dwt;
  final String size;
  final String netWt;
  final String remarks;

  const _OrderPdfRow({
    required this.srNo,
    required this.barCode,
    required this.item,
    required this.image,
    required this.colour,
    required this.pt,
    required this.dwt,
    required this.size,
    required this.netWt,
    required this.remarks,
  });
}

pw.TableRow _orderHeaderRow() {
  return pw.TableRow(
    children: [
      _orderCell('SR NO', header: true, shaded: true),
      _orderCell('Bar Code', header: true, shaded: true),
      _orderCell('Item', header: true, shaded: true, align: pw.TextAlign.left),
      _orderCell('IMAGE', header: true, shaded: true),
      _orderCell('COLOUR', header: true, shaded: true),
      _orderCell('PT', header: true, shaded: true),
      _orderCell('DWT', header: true, shaded: true),
      _orderCell('SIZE', header: true, shaded: true),
      _orderCell('NET WT', header: true, shaded: true),
      _orderCell('REMARKS', header: true, shaded: true, align: pw.TextAlign.left),
    ],
  );
}

pw.TableRow _orderDataRow(_OrderPdfRow r) {
  return pw.TableRow(
    children: [
      _orderCell(r.srNo),
      _orderCell(r.barCode, align: pw.TextAlign.left),
      _orderCell(r.item, align: pw.TextAlign.left),
      _orderImageCell(r.image),
      _orderCell(r.colour),
      _orderCell(r.pt),
      _orderCell(r.dwt),
      _orderCell(r.size, align: pw.TextAlign.left),
      _orderCell(r.netWt, align: pw.TextAlign.right),
      _orderCell(r.remarks, align: pw.TextAlign.left),
    ],
  );
}

String _orderBarCode(Map<String, dynamic> item) {
  return _displayText(_firstNonEmpty([
    item['ProductNo']?.toString(),
    item['ProductCode']?.toString(),
    item['ItemCode']?.toString(),
  ]));
}

String _orderItemName(Map<String, dynamic> item) {
  return _displayText(_firstNonEmpty([
    item['ProductName']?.toString(),
    item['ProductCode']?.toString(),
  ]));
}

String _orderColour(Map<String, dynamic> item) {
  return _displayText(_firstNonEmpty([
    item['DesignName']?.toString(),
    item['TypesOdColors']?.toString(),
  ]));
}

/// Read a field from CustomOrderItem first, then parent order response.
String? _pickOrderField(
  Map<String, dynamic> item,
  Map<String, dynamic> orderRes,
  List<String> keys,
) {
  for (final key in keys) {
    if (!item.containsKey(key) || item[key] == null) continue;
    final text = item[key].toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  for (final key in keys) {
    if (!orderRes.containsKey(key) || orderRes[key] == null) continue;
    final text = orderRes[key].toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return null;
}

/// PT ← HallmarkAmount (order response / CustomOrderItem)
String _orderPt(Map<String, dynamic> item, Map<String, dynamic> orderRes) {
  final raw = _pickOrderField(item, orderRes, [
    'HallmarkAmount',
    'HallmarkAmt',
    'HallMarkAmount',
    'PT',
  ]);
  if (raw == null) return '-';
  return _formatPt(raw);
}

/// DWT ← DiamondWt / DiamondWeight (order response / CustomOrderItem)
String _orderDwt(Map<String, dynamic> item, Map<String, dynamic> orderRes) {
  final raw = _pickOrderField(item, orderRes, [
    'DiamondWt',
    'DiamondWeight',
    'TotalDiamondWeight',
    'DWT',
  ]);
  if (raw == null) return '-';
  return _formatDwt(raw);
}

/// Size ← Description / Size (order response / CustomOrderItem)
String _orderSize(Map<String, dynamic> item, Map<String, dynamic> orderRes) {
  final raw = _pickOrderField(item, orderRes, [
    'Description',
    'Size',
    'ItemSize',
    'Length',
  ]);
  return raw ?? '-';
}

/// Remark ← Remark (order response / CustomOrderItem)
String _orderRemark(Map<String, dynamic> item, Map<String, dynamic> orderRes) {
  final raw = _pickOrderField(item, orderRes, [
    'Remark',
    'Remarks',
    'OrderRemark',
  ]);
  return raw ?? '-';
}

String _formatPt(dynamic value) {
  final t = value.toString().trim();
  if (t.isEmpty) return '-';
  if (t.toUpperCase().endsWith('PT')) return t;
  return '${t}PT';
}

String _formatDwt(dynamic value) {
  final t = value.toString().trim();
  if (t.isEmpty) return '-';
  if (t.toUpperCase().endsWith('CT')) return t;
  return '${t}CT';
}

pw.Widget _orderCell(
  String text, {
  bool header = false,
  bool shaded = false,
  pw.TextAlign align = pw.TextAlign.center,
}) {
  return pw.Container(
    color: shaded ? const PdfColor.fromInt(0xFFE8E8E8) : null,
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
    child: pw.Text(
      text,
      textAlign: align,
      maxLines: 3,
      style: pw.TextStyle(
        fontSize: header ? 8.5 : 8,
        fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _orderImageCell(pw.MemoryImage? image) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(3),
    height: 46,
    alignment: pw.Alignment.center,
    child: image != null
        ? pw.Image(image, width: 40, height: 40, fit: pw.BoxFit.contain)
        : pw.Text('-', style: const pw.TextStyle(fontSize: 8)),
  );
}

String _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    final t = v?.trim() ?? '';
    if (t.isNotEmpty && t != '0') return t;
  }
  return '';
}
