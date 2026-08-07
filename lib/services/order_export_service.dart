import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Exports order list / summary rows to CSV (opens in Excel).
class OrderExportService {
  static String csvEscape(String? value) {
    final v = value ?? '';
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static Future<File> exportToCsv({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/$safeName.csv');

    final sink = file.openWrite();
    sink.writeln(headers.map(csvEscape).join(','));
    for (final row in rows) {
      sink.writeln(row.map(csvEscape).join(','));
    }
    await sink.flush();
    await sink.close();
    return file;
  }

  static Future<void> shareExportedFile(File file, {String subject = 'Customer Orders'}) async {
    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'text/csv',
          name: file.uri.pathSegments.last,
        ),
      ],
      subject: subject,
    );
  }
}
