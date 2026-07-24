import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Opens a PDF like the Kotlin Sparkle app: write file → system PDF viewer
/// (`Intent.ACTION_VIEW` / iOS document open). Not the print layout sheet.
class PdfOpenUtil {
  static const _channel = MethodChannel('com.loyalstring.rfid/pdf');

  static Future<bool> openPdfBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final name = safeName.toLowerCase().endsWith('.pdf') ? safeName : '$safeName.pdf';

    final dir = await getTemporaryDirectory();
    final pdfDir = Directory(p.join(dir.path, 'pdfs'));
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    final file = File(p.join(pdfDir.path, name));
    await file.writeAsBytes(bytes, flush: true);

    try {
      final ok = await _channel.invokeMethod<bool>('openPdf', {'path': file.path});
      return ok ?? false;
    } catch (e) {
      debugPrint('openPdf failed: $e');
      return false;
    }
  }
}
