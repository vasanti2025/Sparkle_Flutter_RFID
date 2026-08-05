import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../utils/pdf_open_util.dart';

const _tableRowsPerPage = 6;

/// Customer order PDF — summary table + per-item detail pages.
/// Used from Order save and Order list print.
Future<void> printCustomOrderPdf({
  required BuildContext context,
  required Map<String, dynamic> orderRes,
  required String baseUrl,
}) async {
  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final bytes = await _buildOrderPdfBytes(orderRes: orderRes, baseUrl: baseUrl);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    final orderNo = _orderNo(orderRes);
    final custName = _customerName(orderRes);
    final ok = await PdfOpenUtil.openPdfBytes(
      bytes: bytes,
      fileName: 'Order_${orderNo.isNotEmpty ? orderNo : (custName.isNotEmpty ? custName : 'Customer')}.pdf',
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

Future<Uint8List> _buildOrderPdfBytes({
  required Map<String, dynamic> orderRes,
  required String baseUrl,
}) async {
  final pdf = pw.Document();
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

  return pdf.save();
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
  final firstItem = detailItems.isNotEmpty ? detailItems.first : <String, dynamic>{};
  final totals = _orderWeightTotals(detailItems);

  final leftLines = [
    _detailLine('Name', custName),
    _detailLine('Order No', orderNo),
    _detailLine('Design', _orderDesign(orderRes, firstItem)),
    _detailLine('RFID No', _orderHeaderRfid(orderRes, detailItems)),
    _detailLine('Quantity', _orderTotalQuantity(orderRes, detailItems)),
  ];

  final rightLines = [
    _detailLine('Gross Wt', totals.grossWt),
    _detailLine('Stone Wt', totals.stoneWt),
    _detailLine('Net Wt', totals.netWt),
    _detailLine('Remark', _orderHeaderRemark(orderRes, detailItems)),
  ];

  return pw.Row(
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
  );
}

class _OrderWeightTotals {
  final String grossWt;
  final String stoneWt;
  final String netWt;

  const _OrderWeightTotals({
    required this.grossWt,
    required this.stoneWt,
    required this.netWt,
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
  );
}

String _orderDesign(Map<String, dynamic> orderRes, Map<String, dynamic> firstItem) {
  return _displayText(_firstNonEmpty([
    orderRes['DesignName']?.toString(),
    orderRes['CategoryName']?.toString(),
    firstItem['CategoryName']?.toString(),
    firstItem['DesignName']?.toString(),
  ]));
}

String _orderHeaderRfid(
  Map<String, dynamic> orderRes,
  List<Map<String, dynamic>> items,
) {
  final orderRfid = _displayRfid(orderRes);
  if (orderRfid != '-') return orderRfid;
  if (items.length == 1) return _displayRfid(items.first);
  return '-';
}

String _orderTotalQuantity(
  Map<String, dynamic> orderRes,
  List<Map<String, dynamic>> items,
) {
  final orderQty = orderRes['Quantity']?.toString().trim() ?? '';
  if (orderQty.isNotEmpty && orderQty.toLowerCase() != 'null') {
    return orderQty;
  }

  var total = 0;
  var hasQty = false;
  for (final item in items) {
    final q = int.tryParse(item['Quantity']?.toString() ?? '') ??
        int.tryParse(item['Qty']?.toString() ?? '');
    if (q != null) {
      total += q;
      hasQty = true;
    }
  }
  if (hasQty) return total.toString();
  if (items.isNotEmpty) return items.length.toString();
  return '-';
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
