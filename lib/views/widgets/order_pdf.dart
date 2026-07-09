import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;

Future<void> printCustomOrderPdf({
  required BuildContext context,
  required Map<String, dynamic> orderRes,
  required String baseUrl,
}) async {
  final pdf = pw.Document();
  
  final custMap = orderRes['Customer'] as Map<String, dynamic>? ?? {};
  final custName = '${custMap['FirstName'] ?? ''} ${custMap['LastName'] ?? ''}'.trim();
  
  final itemsList = orderRes['CustomOrderItem'] as List? ?? [];

  // Helper to resolve image URL
  String resolveImageUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final imgList = path.split(',');
    final lastImg = imgList.isNotEmpty ? imgList.last.trim() : '';
    return '$baseUrl$lastImg';
  }

  // Pre-cache item images
  final List<pw.MemoryImage?> cachedImages = [];
  for (final itemRaw in itemsList) {
    final item = itemRaw as Map<String, dynamic>;
    final rawImage = item['Image'] as String? ?? '';
    if (rawImage.isNotEmpty) {
      try {
        final resolvedUrl = resolveImageUrl(rawImage);
        final res = await http.get(Uri.parse(resolvedUrl));
        if (res.statusCode == 200) {
          cachedImages.add(pw.MemoryImage(res.bodyBytes));
        } else {
          cachedImages.add(null);
        }
      } catch (_) {
        cachedImages.add(null);
      }
    } else {
      cachedImages.add(null);
    }
  }

  for (int i = 0; i < itemsList.length; i++) {
    final item = itemsList[i] as Map<String, dynamic>;
    final img = cachedImages[i];

    final leftText = '''
Name     : $custName
Order No : ${item['OrderNo'] ?? '-'}
Design   : ${item['DesignName'] ?? '-'}
RFID No  : ${item['RFIDCode'] ?? '-'}
Quantity : ${item['Quantity'] ?? '-'}
'''.trim();

    final rightText = '''
Gross Wt : ${item['GrossWt'] ?? '-'}
Stone Wt : ${item['StoneWt'] ?? '-'}
Net Wt   : ${item['NetWt'] ?? '-'}
Remark   : ${item['Remark'] ?? '-'}
'''.trim();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context pContext) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'Customer Order',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 15),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(leftText, style: const pw.TextStyle(lineSpacing: 4)),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Text(rightText, style: const pw.TextStyle(lineSpacing: 4)),
                  ),
                ],
              ),
              pw.SizedBox(height: 25),
              if (img != null)
                pw.Container(
                  height: 300,
                  width: double.infinity,
                  child: pw.Image(img, fit: pw.BoxFit.contain),
                )
              else
                pw.Text('Image not available', style: pw.TextStyle(fontStyle: pw.FontStyle.italic)),
            ],
          );
        },
      ),
    );
  }

  // Display printer / preview dialog
  await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
}
