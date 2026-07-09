import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../l10n/l10n_extension.dart';
import '../../models/delivery_challan.dart';

Future<void> printDeliveryChallanPdf({
  required BuildContext context,
  required DeliveryChallanModel challan,
  required String orgName,
}) async {
  try {
    final pdf = pw.Document();

    final String custName = challan.customerName ?? 'Walk-in Customer';
    // Format date
    String formattedDate = '';
    if (challan.createdOn != null) {
      try {
        final parsed = DateTime.parse(challan.createdOn!);
        formattedDate = DateFormat('dd-MM-yyyy').format(parsed);
      } catch (_) {
        formattedDate = challan.createdOn!;
      }
    } else {
      formattedDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
    }

    // Group items for the summary table
    final Map<String, List<ChallanDetailsModel>> grouped = {};
    for (final item in challan.challanDetails) {
      final name = item.productName;
      if (!grouped.containsKey(name)) {
        grouped[name] = [];
      }
      grouped[name]!.add(item);
    }

    final summaryRows = grouped.entries.map((entry) {
      final name = entry.key;
      final list = entry.value;
      final int totalPcs = list.length;
      final double totalGross = list.fold(0.0, (sum, x) => sum + (double.tryParse(x.grossWt) ?? 0.0));
      final double totalNet = list.fold(0.0, (sum, x) => sum + (double.tryParse(x.netWt) ?? 0.0));
      return {
        'name': name,
        'pcs': totalPcs,
        'gross': totalGross,
        'net': totalNet,
      };
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context pContext) {
          return [
            // Top Header Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      orgName.isNotEmpty ? orgName : 'SPARKLE RFID',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Client Code: ${challan.clientCode}', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 2),
                    pw.Text('Name: $custName', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Date: $formattedDate', style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text('Challan No: ${challan.challanNo ?? challan.invoiceNo ?? '-'}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text('Status: Sold (Challan Summary)', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 8),

            // Main Items Table Title
            pw.Text(
              'Item Listing',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),

            // Items Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(30), // S.No
                1: const pw.FlexColumnWidth(3),   // Item Name
                2: const pw.FixedColumnWidth(40), // Pcs
                3: const pw.FixedColumnWidth(60), // Gross Wt
                4: const pw.FixedColumnWidth(60), // Stone Wt
                5: const pw.FixedColumnWidth(60), // Net Wt
                6: const pw.FixedColumnWidth(70), // Amount
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('S.No', isHeader: true),
                    _pdfCell('Item Name', isHeader: true, alignLeft: true),
                    _pdfCell('Pcs', isHeader: true),
                    _pdfCell('Gross Wt', isHeader: true),
                    _pdfCell('Stone Wt', isHeader: true),
                    _pdfCell('Net Wt', isHeader: true),
                    _pdfCell('Amount', isHeader: true),
                  ],
                ),
                // Rows
                ...List.generate(challan.challanDetails.length, (index) {
                  final item = challan.challanDetails[index];
                  final double gr = double.tryParse(item.grossWt) ?? 0.0;
                  final double st = double.tryParse(item.stoneAmount) ?? 0.0;
                  final double nt = double.tryParse(item.netWt) ?? 0.0;
                  final double amt = double.tryParse(item.amount) ?? 0.0;

                  return pw.TableRow(
                    children: [
                      _pdfCell('${index + 1}'),
                      _pdfCell(item.productName, alignLeft: true),
                      _pdfCell(item.pcs > 0 ? item.pcs.toString() : '1'),
                      _pdfCell(gr.toStringAsFixed(3)),
                      _pdfCell(st.toStringAsFixed(3)),
                      _pdfCell(nt.toStringAsFixed(3)),
                      _pdfCell(amt.toStringAsFixed(2)),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 20),

            // Summary Table Title
            pw.Text(
              'Summary Table (Grouped)',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),

            // Summary Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),   // Item Name
                1: const pw.FixedColumnWidth(60), // Total Pcs
                2: const pw.FixedColumnWidth(80), // Total Gross Wt
                3: const pw.FixedColumnWidth(80), // Total Net Wt
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('Item Name', isHeader: true, alignLeft: true),
                    _pdfCell('Total Pcs', isHeader: true),
                    _pdfCell('Total Gross', isHeader: true),
                    _pdfCell('Total Net', isHeader: true),
                  ],
                ),
                ...summaryRows.map((row) {
                  return pw.TableRow(
                    children: [
                      _pdfCell(row['name'] as String, alignLeft: true),
                      _pdfCell(row['pcs'].toString()),
                      _pdfCell((row['gross'] as double).toStringAsFixed(3)),
                      _pdfCell((row['net'] as double).toStringAsFixed(3)),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 24),

            // Totals and Aggregates Box
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 200,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  ),
                  child: pw.Column(
                    children: [
                      _pdfSummaryRow('Qty / Items:', '${challan.qty ?? challan.challanDetails.length}'),
                      _pdfSummaryRow('Gross Weight:', '${challan.grossWt ?? 0.0} g'),
                      _pdfSummaryRow('Net Weight:', '${challan.netWt ?? 0.0} g'),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                      if (challan.gstApplied?.toUpperCase() == 'TRUE') ...[
                        _pdfSummaryRow('Total GST (3%):', '₹${challan.totalGSTAmount ?? '0.0'}'),
                      ],
                      _pdfSummaryRow(
                        'Grand Total:',
                        '₹${challan.totalAmount ?? '0.0'}',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 40),

            // Billed / Sold by footer
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Billed By: ${challan.billedBy ?? '-'}', style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 4),
                    pw.Text('Sold By: ${challan.soldBy ?? '-'}', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(width: 80, height: 1, color: PdfColors.grey400),
                    pw.SizedBox(height: 4),
                    pw.Text('Authorized Signature', style: const pw.TextStyle(fontSize: 9)),
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
      name: 'Challan_${challan.challanNo ?? challan.invoiceNo ?? challan.id}.pdf',
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.sRead.failedToPrintPdfMessage('$e'))),
    );
  }
}

pw.Widget _pdfCell(String text, {bool isHeader = false, bool alignLeft = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      textAlign: alignLeft
          ? pw.TextAlign.left
          : pw.TextAlign.center,
      style: pw.TextStyle(
        fontSize: isHeader ? 9 : 8,
        fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _pdfSummaryRow(String label, String val, {bool isBold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          val,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}
