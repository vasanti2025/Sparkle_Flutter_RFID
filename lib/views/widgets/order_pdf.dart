import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../utils/pdf_open_util.dart';

const _rowsPerPage = 6;

/// Customer order PDF — table layout (Barcode, Item, Image, Colour, PT, DWT, Size, Net Wt, Remarks).
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

  final rows = <_OrderPdfRow>[];
  if (itemsList is List) {
    for (var i = 0; i < itemsList.length; i++) {
      final raw = itemsList[i];
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final image = await _loadPdfThumbnail(
        item['Image']?.toString() ?? '',
        baseUrl,
      );

      rows.add(
        _OrderPdfRow(
          srNo: '${i + 1}',
          barCode: _orderBarCode(item),
          item: _orderItemName(item),
          image: image,
          colour: _orderColour(item),
          pt: _formatPt(item['HallmarkAmount']),
          dwt: _formatDwt(item['DiamondWt']),
          size: _orderSize(item),
          netWt: _dash(item['NetWt']?.toString()),
          remarks: _dash(item['Remark']?.toString()),
        ),
      );
    }
  }

  if (rows.isEmpty) {
    rows.add(
      _OrderPdfRow(
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

  for (var pageStart = 0; pageStart < rows.length; pageStart += _rowsPerPage) {
    final end = (pageStart + _rowsPerPage).clamp(0, rows.length);
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
              if (isFirstPage)
                pw.Row(
                  children: [
                    pw.Expanded(child: _headerLine('Customer', custName)),
                    pw.Expanded(child: _headerLine('Order No', orderNo)),
                  ],
                ),
              if (isFirstPage) pw.SizedBox(height: 10),
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

  return pdf.save();
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

Future<pw.MemoryImage?> _loadPdfThumbnail(String rawImage, String baseUrl) async {
  if (rawImage.isEmpty) return null;
  final url = _resolveImageUrl(rawImage, baseUrl);
  if (url.isEmpty) return null;

  try {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

    final decoded = img.decodeImage(res.bodyBytes);
    if (decoded == null) return null;

    final thumb = img.copyResize(
      decoded,
      width: 72,
      height: 72,
      interpolation: img.Interpolation.linear,
    );
    final jpg = Uint8List.fromList(img.encodeJpg(thumb, quality: 70));
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

/// PDF Bar Code ← dashboard Product No. (ProductCode / ProductNo)
String _orderBarCode(Map<String, dynamic> item) {
  return _dash(_firstNonEmpty([
    item['ProductNo']?.toString(),
    item['ProductCode']?.toString(),
    item['ItemCode']?.toString(),
  ]));
}

/// PDF Item ← dashboard Product Code (ProductName / ProductCode)
String _orderItemName(Map<String, dynamic> item) {
  return _dash(_firstNonEmpty([
    item['ProductName']?.toString(),
    item['ProductCode']?.toString(),
  ]));
}

/// PDF COLOUR ← dashboard Design (DesignName)
String _orderColour(Map<String, dynamic> item) {
  return _dash(_firstNonEmpty([
    item['DesignName']?.toString(),
    item['TypesOdColors']?.toString(),
  ]));
}

/// PDF SIZE ← dashboard Description
String _orderSize(Map<String, dynamic> item) {
  return _dash(_firstNonEmpty([
    item['Description']?.toString(),
    item['Size']?.toString(),
  ]));
}

String _formatPt(dynamic value) {
  final t = value?.toString().trim() ?? '';
  if (t.isEmpty || t == '0' || t == '0.0' || t == '0.00') return '-';
  if (t.toUpperCase().endsWith('PT')) return t;
  return '${t}PT';
}

String _formatDwt(dynamic value) {
  final t = value?.toString().trim() ?? '';
  if (t.isEmpty || t == '0' || t == '0.0' || t == '0.000') return '-';
  if (t.toUpperCase().endsWith('CT')) return t;
  return '${t}CT';
}

pw.Widget _headerLine(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: value.isEmpty ? '-' : value,
            style: const pw.TextStyle(fontSize: 10.5),
          ),
        ],
      ),
    ),
  );
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

String _dash(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty || t == '0' || t == '0.0' || t == '0.00' || t == '0.000') return '-';
  return t;
}
