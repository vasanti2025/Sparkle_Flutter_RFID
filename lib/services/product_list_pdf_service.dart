import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'db_service.dart';

/// Product List "Labelled Stock" PDF. Rows are paged from SQLite and the PDF is
/// built in a background isolate so 50k items do not crash the UI isolate.
class ProductListPdfService {
  static const dbColumns = [
    'productName',
    'itemCode',
    'rfid',
    'grossWeight',
    'stoneWeight',
    'diamondWeight',
    'netWeight',
    'category',
    'design',
    'purity',
    'sku',
    'epc',
    'vendor',
  ];

  static const rowsPerPage = 28;

  static Future<String> buildLabelledStockPdf({
    required DbService dbService,
    required List<String> headers,
    required String title,
    required String Function(int count) totalItemsLabel,
    required String Function(int page, int totalPages) pageOfLabel,
    String? searchQuery,
    String? sku,
    String? category,
    String? productName,
    String? design,
    String? purity,
  }) async {
    final total = await dbService.getTotalItemCountFiltered(
      searchQuery: searchQuery,
      sku: sku,
      category: category,
      productName: productName,
      design: design,
      purity: purity,
    );
    if (total <= 0) {
      return '';
    }

    final pageCount = (total / rowsPerPage).ceil();
    final dir = await getTemporaryDirectory();
    final jsonl = File(
      '${dir.path}/labelled_stock_${DateTime.now().millisecondsSinceEpoch}.jsonl',
    );
    final pdfFile = File(
      '${dir.path}/pdfs/LabelledStock_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await pdfFile.parent.create(recursive: true);
    try {
      final sink = jsonl.openWrite(encoding: utf8);
      var offset = 0;
      while (offset < total) {
        final rows = await dbService.getExportStringRowsPaged(
          columns: dbColumns,
          limit: 400,
          offset: offset,
          searchQuery: searchQuery,
          sku: sku,
          category: category,
          productName: productName,
          design: design,
          purity: purity,
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          sink.writeln(jsonEncode(row));
        }
        offset += rows.length;
        if (offset % 2000 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      await sink.flush();
      await sink.close();

      await compute(_buildPdfFromJsonl, <String, dynamic>{
        'path': jsonl.path,
        'outPath': pdfFile.path,
        'headers': headers,
        'title': title,
        'totalLabel': totalItemsLabel(total),
        'pageOfTemplate': _pageOfTemplate(pageOfLabel, pageCount),
      });
      return pdfFile.path;
    } finally {
      try {
        if (await jsonl.exists()) {
          await jsonl.delete();
        }
      } catch (_) {}
    }
  }

  /// Encode "Page {n} of {total}" without calling the l10n closure in the isolate.
  static List<String> _pageOfTemplate(
    String Function(int page, int totalPages) pageOfLabel,
    int pageCount,
  ) {
    return List<String>.generate(pageCount, (i) => pageOfLabel(i + 1, pageCount));
  }
}

Future<void> _buildPdfFromJsonl(Map<String, dynamic> args) async {
  final path = args['path'] as String;
  final outPath = args['outPath'] as String;
  final headers = List<String>.from(args['headers'] as List);
  final title = args['title'] as String;
  final totalLabel = args['totalLabel'] as String;
  final pageLabels = List<String>.from(args['pageOfTemplate'] as List);
  final lines = File(path).readAsLinesSync();

  final doc = pw.Document();
  final pageFormat = PdfPageFormat.a4.landscape;
  var offset = 0;
  var pageNumber = 0;
  while (offset < lines.length) {
    final end = (offset + ProductListPdfService.rowsPerPage) > lines.length
        ? lines.length
        : offset + ProductListPdfService.rowsPerPage;
    final rows = <List<String>>[];
    for (var i = offset; i < end; i++) {
      final decoded = jsonDecode(lines[i]);
      rows.add(List<String>.from(decoded as List));
    }
    final startSr = offset + 1;
    final capturedPage = pageNumber;
    final pageLabel = capturedPage < pageLabels.length
        ? pageLabels[capturedPage]
        : '${capturedPage + 1}';
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(15),
        build: (context) => _labelledStockPage(
          headers: headers,
          rows: rows,
          startSr: startSr,
          title: title,
          totalLabel: totalLabel,
          pageLabel: pageLabel,
        ),
      ),
    );
    pageNumber++;
    offset = end;
  }
  lines.clear();
  final bytes = await doc.save();
  await File(outPath).writeAsBytes(bytes, flush: true);
}

pw.Widget _labelledStockPage({
  required List<String> headers,
  required List<List<String>> rows,
  required int startSr,
  required String title,
  required String totalLabel,
  required String pageLabel,
}) {
  final headerStyle = pw.TextStyle(
    fontSize: 7,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );
  const cellStyle = pw.TextStyle(fontSize: 6);
  pw.Widget headerCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(text, style: headerStyle, textAlign: pw.TextAlign.center),
      );
  pw.Widget bodyCell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(text, style: cellStyle, textAlign: pw.TextAlign.center, maxLines: 2),
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Center(
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(totalLabel, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(pageLabel, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.3),
        columnWidths: const {
          0: pw.FixedColumnWidth(25),
          1: pw.FixedColumnWidth(70),
          2: pw.FixedColumnWidth(55),
          3: pw.FixedColumnWidth(55),
          4: pw.FixedColumnWidth(40),
          5: pw.FixedColumnWidth(40),
          6: pw.FixedColumnWidth(40),
          7: pw.FixedColumnWidth(40),
          8: pw.FixedColumnWidth(50),
          9: pw.FixedColumnWidth(50),
          10: pw.FixedColumnWidth(40),
          11: pw.FixedColumnWidth(45),
          12: pw.FixedColumnWidth(85),
          13: pw.FixedColumnWidth(55),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.black),
            children: headers.map(headerCell).toList(growable: false),
          ),
          for (var i = 0; i < rows.length; i++)
            pw.TableRow(
              children: [
                bodyCell('${startSr + i}'),
                ...rows[i].map(bodyCell),
              ],
            ),
        ],
      ),
    ],
  );
}
