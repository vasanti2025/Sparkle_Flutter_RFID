import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/stock_verification_report.dart';

/// Streams batch matched/unmatched rows to CSV (opens in Excel).
/// Memory-safe for large batches — avoids OOM crashes from in-memory xlsx.
class BatchReportExportService {
  static String _csvEscape(String? value) {
    final v = value ?? '';
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static Future<File> exportToCsv({
    required BatchDetailsResponse details,
    String? scanBatchId,
    void Function(int written)? onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final id = (scanBatchId ?? details.scanBatchId ?? 'batch')
        .replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/BatchReport_$id.csv');

    final sink = file.openWrite();
    sink.writeln('Status,Item Code,Product,Branch,Category,RFID');

    var count = 0;

    Future<void> writeRows(String status, List<BatchReportItem> items) async {
      for (final item in items) {
        sink.writeln([
          status,
          _csvEscape(item.itemCode),
          _csvEscape(item.productName),
          _csvEscape(item.branchName),
          _csvEscape(item.categoryName),
          _csvEscape(item.rfidCode),
        ].join(','));
        count++;
        if (count % 2000 == 0) {
          onProgress?.call(count);
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    await writeRows('Matched', details.matchedList);
    await writeRows('Unmatched', details.unmatchedList);

    await sink.flush();
    await sink.close();
    onProgress?.call(count);
    return file;
  }

  static Future<void> shareExportedFile(File file) async {
    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'text/csv',
          name: file.uri.pathSegments.last,
        ),
      ],
      subject: 'Batch Stock Verification Report',
    );
  }
}
