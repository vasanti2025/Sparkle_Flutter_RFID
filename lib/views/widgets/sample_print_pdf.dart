import 'package:flutter/material.dart';
import '../../l10n/l10n_extension.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SamplePrintItem {
  final String itemDetails;
  final String grossWt;
  final String stoneWt;
  final String diamondWt;
  final String netWt;
  final String pieces;
  final String status;

  const SamplePrintItem({
    required this.itemDetails,
    required this.grossWt,
    required this.stoneWt,
    required this.diamondWt,
    required this.netWt,
    required this.pieces,
    required this.status,
  });
}

class SamplePrintData {
  final String companyName;
  final String customerName;
  final String addressCity;
  final String contactNo;
  final String sampleOutNo;
  final String date;
  final String returnDate;
  final List<SamplePrintItem> items;
  final bool isSampleIn;

  const SamplePrintData({
    required this.companyName,
    required this.customerName,
    required this.addressCity,
    required this.contactNo,
    required this.sampleOutNo,
    required this.date,
    required this.returnDate,
    required this.items,
    this.isSampleIn = false,
  });
}

String sampleItemDetailsFromIssue(Map<String, dynamic> issue) {
  return [
    issue['CategoryName'],
    issue['ProductName'],
    issue['DesignName'],
    issue['PurityName'],
    issue['SKU'],
  ].where((e) => e != null && e.toString().trim().isNotEmpty).map((e) => e.toString()).join(' - ');
}

Future<void> printSamplePrintPdf({
  required BuildContext context,
  required SamplePrintData data,
}) async {
  try {
    final pdf = pw.Document();
    final title = data.isSampleIn ? 'Sample In  Print' : 'Sample Out Print';
    final filePrefix = data.isSampleIn ? 'SampleIn' : 'SampleOut';

    double n(String? v) => double.tryParse(v ?? '') ?? 0.0;
    String fmt(double d) => d.toStringAsFixed(3);

    var totalGross = 0.0;
    var totalStone = 0.0;
    var totalDiamond = 0.0;
    var totalNet = 0.0;
    var totalPieces = 0.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) {
          return [
            pw.Center(
              child: pw.Text(
                data.companyName.isNotEmpty ? data.companyName : 'SPARKLE RFID',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Customer Name: ${data.customerName}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Address/City: ${data.addressCity}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Contact No: ${data.contactNo}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Sample Out No: ${data.sampleOutNo}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Date: ${data.date}', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('ReturnDate: ${data.returnDate}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.6),
                1: const pw.FlexColumnWidth(2.0),
                2: const pw.FlexColumnWidth(1.0),
                3: const pw.FlexColumnWidth(1.0),
                4: const pw.FlexColumnWidth(1.0),
                5: const pw.FlexColumnWidth(1.0),
                6: const pw.FlexColumnWidth(0.8),
                7: const pw.FlexColumnWidth(1.0),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _hdr('Sr.No'),
                    _hdr('Item Details', alignLeft: true),
                    _hdr('Gross Wt'),
                    _hdr('Stone Wt'),
                    _hdr('Diamond\nWt'),
                    _hdr('Net Wt'),
                    _hdr('Pieces'),
                    _hdr('Status'),
                  ],
                ),
                ...data.items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final it = entry.value;
                  final g = n(it.grossWt);
                  final s = n(it.stoneWt);
                  final d = n(it.diamondWt);
                  final nw = n(it.netWt);
                  final p = n(it.pieces);
                  totalGross += g;
                  totalStone += s;
                  totalDiamond += d;
                  totalNet += nw;
                  totalPieces += p;
                  return pw.TableRow(
                    children: [
                      _cell('${idx + 1}'),
                      _cell(it.itemDetails, alignLeft: true),
                      _cell(fmt(g)),
                      _cell(fmt(s)),
                      _cell(fmt(d)),
                      _cell(fmt(nw)),
                      _cell(p.toInt().toString()),
                      _cell(it.status),
                    ],
                  );
                }),
                pw.TableRow(
                  children: [
                    _cell('Total', bold: true),
                    _cell(''),
                    _cell(fmt(totalGross), bold: true),
                    _cell(fmt(totalStone), bold: true),
                    _cell(fmt(totalDiamond), bold: true),
                    _cell(fmt(totalNet), bold: true),
                    _cell(totalPieces.toInt().toString(), bold: true),
                    _cell(''),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${filePrefix}_${data.sampleOutNo.isNotEmpty ? data.sampleOutNo : 'Print'}.pdf',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.failedToPrintPdfMessage('$e'))),
      );
    }
  }
}

pw.Widget _hdr(String text, {bool alignLeft = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _cell(String text, {bool alignLeft = false, bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
    ),
  );
}
