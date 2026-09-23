import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../l10n/l10n_extension.dart';
import '../../utils/app_fonts.dart';
import '../../utils/pdf_open_util.dart';

/// Writes one report row (no serial — added after isolate sort).
typedef InventoryReportRowEmit = Future<void> Function(List<String> cells);

/// Builds the Unmatched / Matched Item Report off the UI isolate so 50k-row
/// catalogs do not freeze or crash the inventory screen.
Future<void> printInventoryScanItemReport({
  required BuildContext context,
  required bool unmatched,
  required String scopeLabel,
  required Future<void> Function(InventoryReportRowEmit emit) writeRows,
}) async {
  final s = context.sRead;
  final title = unmatched ? s.unmatchedItemReport : s.matchedItemReport;
  final generated = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());
  final headers = [
    s.headerSr,
    s.counterName,
    s.fieldCategory,
    s.fieldProduct,
    s.fieldPurity,
    s.fieldRfidCode,
    s.itemCode,
    s.headerPcs,
    s.colGrossWt,
    s.colStoneWt,
    s.colNetWt,
    s.mrp,
    s.status,
  ];

  var cancelled = false;
  var progressVisible = true;
  void dismissProgress() {
    if (!progressVisible) return;
    progressVisible = false;
    if (context.mounted) {
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF5231A7)),
            const SizedBox(height: 16),
            Text(
              s.printingPleaseWait,
              textAlign: TextAlign.center,
              style: AppFonts.poppins(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              progressVisible = false;
              Navigator.of(ctx).pop();
            },
            child: Text(s.cancel, style: AppFonts.poppins()),
          ),
        ],
      );
    },
  );

  // Let the dialog paint before any file work.
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted || cancelled) return;

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final dir = await getTemporaryDirectory();
  final jsonl = File('${dir.path}/inv_scan_report_$stamp.jsonl');
  final pdfDir = Directory('${dir.path}/pdfs');
  if (!await pdfDir.exists()) {
    await pdfDir.create(recursive: true);
  }

  var rowCount = 0;
  try {
    final sink = jsonl.openWrite(encoding: utf8);
    try {
      await writeRows((cells) async {
        if (cancelled) throw const _InventoryPrintCancelled();
        sink.writeln(jsonEncode(cells));
        rowCount++;
        if (rowCount % 400 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      });
    } on _InventoryPrintCancelled {
      return;
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (cancelled) return;
    if (rowCount <= 0) {
      dismissProgress();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.noItemsToPrint, style: AppFonts.poppins())),
        );
      }
      return;
    }

    final prefix = unmatched ? 'UnmatchedItemReport' : 'MatchedItemReport';
    final paths = await compute(_buildInventoryReportPdfs, <String, dynamic>{
      'path': jsonl.path,
      'outDir': pdfDir.path,
      'filePrefix': '${prefix}_$stamp',
      'headers': headers,
      'title': title,
      'scopeLabel': scopeLabel,
      'totalLabel': s.totalItems(rowCount),
      'generated': generated,
      'pageOfTemplate': s.pageOf('{page}', '{total}'),
      'partTemplate': s.reportPartLabel('{current}', '{total}'),
    });

    if (!context.mounted || cancelled) return;
    dismissProgress();
    if (!context.mounted) return;

    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.printFailed, style: AppFonts.poppins())),
      );
      return;
    }

    if (paths.length == 1 && rowCount <= 500) {
      final bytes = await File(paths.first).readAsBytes();
      if (!context.mounted) return;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '$prefix.pdf',
      );
      return;
    }

    if (paths.length > 1 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.reportPartsHint(paths.length), style: AppFonts.poppins()),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    if (!context.mounted) return;
    final opened = await PdfOpenUtil.openPdfFile(paths.first);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.noPdfViewerInstalled, style: AppFonts.poppins())),
      );
    }
  } finally {
    try {
      if (await jsonl.exists()) {
        await jsonl.delete();
      }
    } catch (_) {}
    dismissProgress();
  }
}

class _InventoryPrintCancelled implements Exception {
  const _InventoryPrintCancelled();
}

const int _kRowsPerPage = 28;
const int _kPagesPerFile = 80;

Future<List<String>> _buildInventoryReportPdfs(Map<String, dynamic> args) async {
  final path = args['path'] as String;
  final outDir = args['outDir'] as String;
  final filePrefix = args['filePrefix'] as String;
  final headers = List<String>.from(args['headers'] as List);
  final title = args['title'] as String;
  final scopeLabel = args['scopeLabel'] as String;
  final totalLabel = args['totalLabel'] as String;
  final generated = args['generated'] as String;
  final pageOfTemplate = args['pageOfTemplate'] as String;
  final partTemplate = args['partTemplate'] as String;

  final lines = File(path).readAsLinesSync();
  final rows = <List<String>>[];
  for (final line in lines) {
    if (line.isEmpty) continue;
    rows.add(List<String>.from(jsonDecode(line) as List));
  }
  lines.clear();

  int cmp(String a, String b) => a.toLowerCase().trim().compareTo(b.toLowerCase().trim());
  rows.sort((a, b) {
    final byProduct = cmp(a.length > 2 ? a[2] : '', b.length > 2 ? b[2] : '');
    if (byProduct != 0) return byProduct;
    final byCode = cmp(a.length > 5 ? a[5] : '', b.length > 5 ? b[5] : '');
    if (byCode != 0) return byCode;
    return cmp(a.length > 4 ? a[4] : '', b.length > 4 ? b[4] : '');
  });

  final totalPages = rows.isEmpty ? 0 : (rows.length / _kRowsPerPage).ceil();
  final fileCount = totalPages == 0 ? 0 : (totalPages / _kPagesPerFile).ceil();
  final outPaths = <String>[];
  var offset = 0;
  var pageNumber = 0;

  for (var part = 0; part < fileCount; part++) {
    final doc = pw.Document();
    var pagesInFile = 0;
    while (pagesInFile < _kPagesPerFile && offset < rows.length) {
      final end = (offset + _kRowsPerPage) > rows.length
          ? rows.length
          : offset + _kRowsPerPage;
      final slice = rows.sublist(offset, end);
      final startSr = offset + 1;
      final pageLabel = pageOfTemplate
          .replaceAll('{page}', '${pageNumber + 1}')
          .replaceAll('{total}', '$totalPages');
      final partLabel = fileCount > 1
          ? partTemplate
              .replaceAll('{current}', '${part + 1}')
              .replaceAll('{total}', '$fileCount')
          : '';
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(15),
          build: (context) => _inventoryReportPage(
            headers: headers,
            rows: slice,
            startSr: startSr,
            title: title,
            scopeLabel: scopeLabel,
            totalLabel: totalLabel,
            generated: generated,
            pageLabel: pageLabel,
            partLabel: partLabel,
          ),
        ),
      );
      pageNumber++;
      pagesInFile++;
      offset = end;
    }
    final outPath = fileCount == 1
        ? '$outDir/$filePrefix.pdf'
        : '$outDir/${filePrefix}_part${part + 1}.pdf';
    final bytes = await doc.save();
    await File(outPath).writeAsBytes(bytes, flush: true);
    outPaths.add(outPath);
  }

  rows.clear();
  return outPaths;
}

pw.Widget _inventoryReportPage({
  required List<String> headers,
  required List<List<String>> rows,
  required int startSr,
  required String title,
  required String scopeLabel,
  required String totalLabel,
  required String generated,
  required String pageLabel,
  required String partLabel,
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
        child: pw.Text(
          text,
          style: cellStyle,
          textAlign: pw.TextAlign.center,
          maxLines: 2,
        ),
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
          pw.Text(
            scopeLabel.isNotEmpty ? scopeLabel : title,
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Text(totalLabel, style: const pw.TextStyle(fontSize: 8)),
          if (partLabel.isNotEmpty)
            pw.Text(partLabel, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(generated, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(pageLabel, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.3),
        columnWidths: const {
          0: pw.FixedColumnWidth(22),
          1: pw.FixedColumnWidth(55),
          2: pw.FixedColumnWidth(50),
          3: pw.FixedColumnWidth(70),
          4: pw.FixedColumnWidth(40),
          5: pw.FixedColumnWidth(70),
          6: pw.FixedColumnWidth(55),
          7: pw.FixedColumnWidth(28),
          8: pw.FixedColumnWidth(40),
          9: pw.FixedColumnWidth(40),
          10: pw.FixedColumnWidth(40),
          11: pw.FixedColumnWidth(40),
          12: pw.FixedColumnWidth(45),
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
                ...List<pw.Widget>.generate(
                  12,
                  (c) => bodyCell(c < rows[i].length ? rows[i][c] : ''),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}
