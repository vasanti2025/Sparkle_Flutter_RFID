import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../l10n/l10n_extension.dart';
import '../../utils/pdf_open_util.dart';

/// Quotation PDF — same layout as Sparkle Kotlin GenerateQuotationPdf.
Future<void> printQuotationPdf({
  required BuildContext context,
  required Map<String, dynamic> quotation,
  required String orgName,
}) async {
  try {
    final pdf = pw.Document();
    final customer = quotation['Customer'];
    final custName = _firstNonEmpty([
      quotation['CustomerName']?.toString(),
      if (customer is Map)
        '${customer['FirstName'] ?? ''} ${customer['LastName'] ?? ''}'.trim(),
      '${quotation['FirstName'] ?? ''} ${quotation['LastName'] ?? ''}'.trim(),
    ]);
    final mobile = _firstNonEmpty([
      quotation['Mobile']?.toString(),
      if (customer is Map) customer['Mobile']?.toString(),
    ]);
    final address = _firstNonEmpty([
      quotation['CustomerAddress']?.toString(),
      quotation['Address']?.toString(),
      if (customer is Map) ...[
        customer['Address']?.toString(),
        customer['Town']?.toString(),
      ],
    ]);
    final remark = _firstNonEmpty([
      quotation['Remark']?.toString(),
      quotation['Remarks']?.toString(),
    ]);

    final qNo = quotation['QuotationNo']?.toString() ?? '';
    final items = (quotation['QuotationItem'] as List? ?? []).cast<dynamic>();

    double totalGross = 0, totalNet = 0, totalStoneWt = 0, totalStoneAmt = 0, totalAmt = 0;
    int totalPcs = 0;
    final parsedRows = <_QRow>[];

    for (final raw in items) {
      final m = raw as Map;
      final gwt = _toDouble(m['GrossWt'] ?? m['GWt']);
      final nwt = _toDouble(m['NetWt'] ?? m['NWt']);
      final stWt = _toDouble(m['StoneWt']);
      final stAmt = _toDouble(m['StoneAmount'] ?? m['StoneAmt']);
      final pcs = _toInt(m['Pcs'] ?? m['Quantity']) ?? 1;
      final amt = _toDouble(m['Amount'] ?? m['TotalAmount']);
      final wastage = _printWastagePercent(
        fineWastageWt: m['FineWastageWt']?.toString(),
        fixWastage: m['Wastage']?.toString() ?? m['MakingPercent']?.toString(),
        makingFixedWastage: m['MakingFixedWastage']?.toString(),
      );
      totalGross += gwt;
      totalNet += nwt;
      totalStoneWt += stWt;
      totalStoneAmt += stAmt;
      totalAmt += amt;
      totalPcs += pcs;
      parsedRows.add(
        _QRow(
          itemCode: _dash(m['ItemCode']?.toString() ?? m['DesignName']?.toString()),
          rfid: _dash(m['RFIDCode']?.toString() ?? m['TidValue']?.toString()),
          gross: _fmtWt(gwt),
          net: _fmtWt(nwt),
          pcs: '$pcs',
          stWt: _fmtWt(stWt),
          stAmt: _fmtAmt(stAmt),
          wastage: wastage,
          amount: _fmtAmt(amt),
        ),
      );
    }

    final headerTotalAmt = _toDouble(quotation['TotalAmount'] ?? quotation['totalAmount']);
    final displayTotalAmt = headerTotalAmt > 0 ? headerTotalAmt : totalAmt;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (ctx) {
          final tableChildren = <pw.TableRow>[
            pw.TableRow(
              children: [
                _qCell('Item Code', header: true, align: pw.TextAlign.left),
                _qCell('RFID', header: true, align: pw.TextAlign.left),
                _qCell('Gr Wt', header: true),
                _qCell('Nt Wt', header: true),
                _qCell('Pcs', header: true),
                _qCell('St Wt', header: true),
                _qCell('St Amt', header: true),
                _qCell('Wastage%', header: true),
                _qCell('Amount', header: true, align: pw.TextAlign.right),
              ],
            ),
            ...parsedRows.map(
              (r) => pw.TableRow(
                children: [
                  _qCell(r.itemCode, align: pw.TextAlign.left),
                  _qCell(r.rfid, align: pw.TextAlign.left),
                  _qCell(r.gross, align: pw.TextAlign.right),
                  _qCell(r.net, align: pw.TextAlign.right),
                  _qCell(r.pcs, align: pw.TextAlign.right),
                  _qCell(r.stWt, align: pw.TextAlign.right),
                  _qCell(r.stAmt, align: pw.TextAlign.right),
                  _qCell(r.wastage, align: pw.TextAlign.right),
                  _qCell(r.amount, align: pw.TextAlign.right),
                ],
              ),
            ),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F3F3)),
              children: [
                _qCell('Total', header: true, align: pw.TextAlign.left),
                _qCell('', header: true),
                _qCell(_fmtWt(totalGross), header: true, align: pw.TextAlign.right),
                _qCell(_fmtWt(totalNet), header: true, align: pw.TextAlign.right),
                _qCell('$totalPcs', header: true, align: pw.TextAlign.right),
                _qCell(_fmtWt(totalStoneWt), header: true, align: pw.TextAlign.right),
                _qCell(_fmtAmt(totalStoneAmt), header: true, align: pw.TextAlign.right),
                _qCell('', header: true),
                _qCell(_fmtAmt(totalAmt), header: true, align: pw.TextAlign.right),
              ],
            ),
          ];

          return [
            pw.Center(
              child: pw.Text(
                'QUOTATION',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
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
                      _headerLine('Customer Name', custName),
                      _headerLine('Mobile', mobile),
                      _headerLine('Customer Address', address),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _headerLine('Remark', remark),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1, color: PdfColors.black),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 1),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.16),
                1: const pw.FlexColumnWidth(0.10),
                2: const pw.FlexColumnWidth(0.10),
                3: const pw.FlexColumnWidth(0.10),
                4: const pw.FlexColumnWidth(0.08),
                5: const pw.FlexColumnWidth(0.10),
                6: const pw.FlexColumnWidth(0.11),
                7: const pw.FlexColumnWidth(0.09),
                8: const pw.FlexColumnWidth(0.16),
              },
              children: tableChildren,
            ),
            pw.SizedBox(height: 18),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 260,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFFDADADA)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Amount', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      _fmtAmt(displayTotalAmt),
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 36),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Customer Sign:', style: const pw.TextStyle(fontSize: 11)),
                pw.Text(
                  orgName.trim().isNotEmpty ? 'For ${orgName.trim()}' : 'For VT',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
          ];
        },
      ),
    );

    final ok = await PdfOpenUtil.openPdfBytes(
      bytes: await pdf.save(),
      fileName: 'Quotation_${qNo.isNotEmpty ? qNo : DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.noPdfViewerInstalled)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.failedToPrintPdfMessage('$e'))),
      );
    }
  }
}

class _QRow {
  final String itemCode, rfid, gross, net, pcs, stWt, stAmt, wastage, amount;
  _QRow({
    required this.itemCode,
    required this.rfid,
    required this.gross,
    required this.net,
    required this.pcs,
    required this.stWt,
    required this.stAmt,
    required this.wastage,
    required this.amount,
  });
}

pw.Widget _headerLine(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: value.isEmpty ? '-' : value,
            style: const pw.TextStyle(fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _qCell(
  String text, {
  bool header = false,
  pw.TextAlign align = pw.TextAlign.center,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: header ? 10 : 9.5,
        fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

String _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    final t = v?.trim() ?? '';
    if (t.isNotEmpty) return t;
  }
  return '';
}

String _dash(String? v) {
  final t = v?.trim() ?? '';
  return t.isEmpty ? '-' : t;
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  return double.tryParse(v.toString().replaceAll(',', '').replaceAll('gm', '').replaceAll('g', '').trim()) ?? 0;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  return int.tryParse(v.toString().trim()) ?? double.tryParse(v.toString().trim())?.round();
}

String _fmtWt(double v) => v == 0 ? '-' : v.toStringAsFixed(3);
String _fmtAmt(double v) => v == 0 ? '-' : v.toStringAsFixed(2);

/// Same as Sparkle resolveQuotationPrintWastagePercent: FineWastageWt * 10.
String _printWastagePercent({
  String? fineWastageWt,
  String? fixWastage,
  String? makingFixedWastage,
}) {
  final fine = fineWastageWt?.trim() ?? '';
  if (fine.isNotEmpty && fine.toLowerCase() != 'null') {
    final wt = double.tryParse(fine.replaceAll(',', ''));
    if (wt != null) return '${(wt * 10).toStringAsFixed(2)}%';
  }
  for (final raw in [fixWastage, makingFixedWastage]) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) continue;
    if (t.endsWith('%')) return t;
    final v = double.tryParse(t.replaceAll(',', ''));
    if (v != null) {
      final pct = (v > 0 && v < 1) ? v * 10 : v;
      return '${pct.toStringAsFixed(2)}%';
    }
    return t;
  }
  return '-';
}
