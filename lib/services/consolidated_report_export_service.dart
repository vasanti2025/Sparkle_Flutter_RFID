import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/stock_verification_report.dart';

/// Streams consolidated report items to a CSV file (opens in Excel).
/// Memory-safe for very large datasets (10L+ rows).
class ConsolidatedReportExportService {
  static String _csvEscape(String? value) {
    final v = value ?? '';
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static Future<File> exportToCsv({
    required StockVerificationReportResponse report,
    void Function(int written)? onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final date = report.reportDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${dir.path}/ConsolidatedReport_$date.csv');

    final sink = file.openWrite();
    sink.writeln(
      'Item Code,RFID,TID,Category,Product,Design,Gross Weight,Net Weight,Status',
    );

    var count = 0;
    for (final branch in report.branches) {
      for (final category in branch.categories) {
        for (final product in category.products) {
          for (final design in product.designs) {
            for (final item in design.items) {
              sink.writeln([
                _csvEscape(item.itemCode),
                _csvEscape(item.rfidCode),
                _csvEscape(item.tidNumber),
                _csvEscape(item.categoryName),
                _csvEscape(item.productName),
                _csvEscape(item.designName),
                _csvEscape(item.grossWeight?.toString()),
                _csvEscape(item.netWeight?.toString()),
                _csvEscape(item.status),
              ].join(','));
              count++;
              if (count % 5000 == 0) {
                onProgress?.call(count);
                await Future<void>.delayed(Duration.zero);
              }
            }
          }
        }
      }
    }

    await sink.flush();
    await sink.close();
    onProgress?.call(count);
    return file;
  }

  static Future<void> shareExportedFile(File file) async {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: file.uri.pathSegments.last)],
      subject: 'Consolidated Stock Verification Report',
    );
  }

  /// Filter items in isolate for large lists (search on detail screen).
  static Future<List<ReportItem>> filterItems(List<ReportItem> items, String query) {
    if (query.trim().isEmpty) return Future.value(items);
    return compute(_filterItemsIsolate, _FilterArgs(items, query.trim().toLowerCase()));
  }
}

class _FilterArgs {
  final List<ReportItem> items;
  final String query;
  _FilterArgs(this.items, this.query);
}

List<ReportItem> _filterItemsIsolate(_FilterArgs args) {
  return args.items.where((it) {
    final q = args.query;
    return (it.itemCode?.toLowerCase().contains(q) ?? false) ||
        (it.rfidCode?.toLowerCase().contains(q) ?? false) ||
        (it.productName?.toLowerCase().contains(q) ?? false) ||
        (it.categoryName?.toLowerCase().contains(q) ?? false);
  }).toList();
}

String formatReportDateTime(String? dateTime) {
  if (dateTime == null || dateTime.isEmpty) return '-';
  try {
    final parsed = DateTime.parse(dateTime);
    return DateFormat('dd/MM/yyyy hh:mm a').format(parsed);
  } catch (_) {
    return dateTime;
  }
}

String formatDisplayDate(String date) {
  try {
    final parsed = DateTime.parse(date);
    return DateFormat('dd-MM-yy').format(parsed);
  } catch (_) {
    return date;
  }
}

String todayDateString() => DateFormat('yyyy-MM-dd').format(DateTime.now());
