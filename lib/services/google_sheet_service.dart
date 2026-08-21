import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;

/// Google Sheet helpers matching Sparkle BulkViewModel / ImportExcelViewModel.
/// Uses public CSV export (sheet must be shared "Anyone with the link").
class GoogleSheetService {
  GoogleSheetService._();

  /// Accepts a full docs URL or a raw spreadsheet ID (Sparkle stores ID).
  static String? extractSheetId(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;
    final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(t);
    if (match != null) return match.group(1);
    if (RegExp(r'^[a-zA-Z0-9-_]+$').hasMatch(t)) return t;
    return null;
  }

  static String csvExportUrl(String sheetId) =>
      'https://docs.google.com/spreadsheets/d/$sheetId/export?format=csv';

  /// Sparkle [BulkViewModel.parseGoogleSheetHeaders] — first CSV row.
  static Future<List<String>> parseHeaders(String csvUrl) async {
    final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.trim().isEmpty) return const [];
    final rows = const CsvToListConverter(shouldParseNumbers: false).convert(text);
    if (rows.isEmpty) return const [];
    return rows.first
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// Sparkle [ImportExcelViewModel.parseGoogleSheetRows].
  static Future<List<Map<String, String>>> parseRows(String csvUrl) async {
    final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(minutes: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.trim().isEmpty) return const [];
    final rows = const CsvToListConverter(shouldParseNumbers: false).convert(text);
    if (rows.isEmpty) return const [];

    final headers = rows.first.map((e) => e.toString().trim()).toList(growable: false);
    if (headers.isEmpty) return const [];

    final out = <Map<String, String>>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      final map = <String, String>{};
      for (var c = 0; c < headers.length; c++) {
        final key = headers[c];
        if (key.isEmpty) continue;
        final value = c < row.length ? row[c].toString().trim() : '';
        map[key] = value;
      }
      if (map.values.every((v) => v.isEmpty)) continue;
      out.add(map);
    }
    return out;
  }
}
