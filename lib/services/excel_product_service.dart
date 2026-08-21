import 'dart:convert';

import 'dart:io';

import 'package:excel/excel.dart';

import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';

import 'package:share_plus/share_plus.dart';

import '../models/bulk_item.dart';

import 'db_service.dart';



class ImportProgress {

  final int totalFields;

  final int importedFields;

  final List<String> failedFields;



  const ImportProgress({

    required this.totalFields,

    required this.importedFields,

    required this.failedFields,

  });

}



/// Pre-parsed workbook — decode Excel once, reuse for headers + import.

class ParsedExcelWorkbook {

  final List<String> headers;

  final Map<String, int> headerIndexMap;

  final List<List<String>> rows;



  const ParsedExcelWorkbook({

    required this.headers,

    required this.headerIndexMap,

    required this.rows,

  });



  static ParsedExcelWorkbook parse(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return const ParsedExcelWorkbook(headers: [], headerIndexMap: {}, rows: []);
    }

    final sheet = excel.tables.values.first;
    if (sheet.rows.isEmpty) {
      return const ParsedExcelWorkbook(headers: [], headerIndexMap: {}, rows: []);
    }

    final headerRow = sheet.rows.first;
    final headers = <String>[];
    final headerIndexMap = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final raw = ExcelProductService._cellToString(headerRow[i]?.value).trim();
      if (raw.isEmpty) continue;
      headers.add(raw);
      headerIndexMap[raw.toLowerCase()] = i;
    }

    final rows = <List<String>>[];
    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      if (row.isEmpty) continue;
      rows.add(List.generate(row.length, (i) => ExcelProductService._cellToString(row[i]?.value).trim()));
    }

    return ParsedExcelWorkbook(headers: headers, headerIndexMap: headerIndexMap, rows: rows);
  }

  /// Decode Excel off the UI isolate (large files).
  static Future<ParsedExcelWorkbook> parseAsync(List<int> bytes) {
    return compute(_parseExcelBytesInBackground, bytes);
  }
}

class ExcelImportBuildResult {

  final List<Map<String, dynamic>> itemMaps;

  final int totalRows;

  final int importedRows;

  final List<String> failedRows;



  const ExcelImportBuildResult({

    required this.itemMaps,

    required this.totalRows,

    required this.importedRows,

    required this.failedRows,

  });

}



class _ExcelImportArgs {

  final ParsedExcelWorkbook workbook;

  final Map<String, String> fieldMapping;

  final Map<String, String> rfidMap;



  const _ExcelImportArgs({

    required this.workbook,

    required this.fieldMapping,

    required this.rfidMap,

  });

}



ExcelImportBuildResult _buildImportItemsInBackground(_ExcelImportArgs args) {
  return ExcelProductService.buildItemsFromWorkbook(
    workbook: args.workbook,
    fieldMapping: args.fieldMapping,
    rfidMap: args.rfidMap,
  );
}

class _SheetImportArgs {
  final List<Map<String, String>> rows;
  final Map<String, String> fieldMapping;
  final Map<String, String> rfidMap;

  const _SheetImportArgs({
    required this.rows,
    required this.fieldMapping,
    required this.rfidMap,
  });
}

ExcelImportBuildResult _buildSheetItemsInBackground(_SheetImportArgs args) {
  return ExcelProductService.buildItemsFromSheetRows(
    rows: args.rows,
    fieldMapping: args.fieldMapping,
    rfidMap: args.rfidMap,
  );
}

ParsedExcelWorkbook _parseExcelBytesInBackground(List<int> bytes) {
  return ParsedExcelWorkbook.parse(bytes);
}



class ExcelProductService {

  static const importFieldKeys = [

    'itemCode',

    'rfid',

    'grossWeight',

    'stoneWeight',

    'diamondWeight',

    'netWeight',

    'counterName',

    'category',

    'productName',

    'branchName',

    'design',

    'purity',

    'makingPerGram',

    'makingPercent',

    'fixMaking',

    'fixWastage',

    'stoneAmount',

    'diamondAmount',

    'sku',

    'vendor',

    'boxName',

  ];



  static const importFieldLabels = {

    'itemCode': 'Item Code',

    'rfid': 'RFID',

    'grossWeight': 'Gross Weight',

    'stoneWeight': 'Stone Weight',

    'diamondWeight': 'Diamond Weight',

    'netWeight': 'Net Weight',

    'counterName': 'Counter Name',

    'category': 'Category',

    'productName': 'Product Name',

    'branchName': 'Branch Name',

    'design': 'Design',

    'purity': 'Purity',

    'makingPerGram': 'Making/Gram',

    'makingPercent': 'Making %',

    'fixMaking': 'Fix Making',

    'fixWastage': 'Fix Wastage',

    'stoneAmount': 'Stone Amount',

    'diamondAmount': 'Diamond Amount',

    'sku': 'SKU',

    'vendor': 'Vendor',

    'boxName': 'Box Name',

  };



  static List<String> parseExcelHeaders(List<int> bytes) {

    return ParsedExcelWorkbook.parse(bytes).headers;

  }



  static String _cellToString(dynamic value) {

    if (value == null) return '';

    if (value is DateTime) return value.toIso8601String();

    return value.toString();

  }



  /// Matches Sparkle [BulkViewModel.convertToHex] / [ImportExcelViewModel.stringToHex]:
  /// text → hex, then leading zeros until length % 4 == 0.
  /// Example: `"18001"` → `"003138303031"`.
  static String stringToHex(String value) {
    final hex = utf8.encode(value.trim()).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final paddedLen = ((hex.length + 3) ~/ 4) * 4;
    return hex.padLeft(paddedLen, '0').toUpperCase();
  }



  /// Matches Kotlin [ImportExcelViewModel.syncAndMapRow] — BarcodeNumber → TidValue (EPC).

  static String syncAndMapRow(String rfid, Map<String, String> rfidMap) {

    final key = rfid.trim().toUpperCase();

    if (key.isEmpty) return '';

    return rfidMap[key] ?? '';

  }



  static String _getStringFromParsedRow(

    List<String> row,

    Map<String, int> headerIndexMap,

    String? columnName,

  ) {

    if (columnName == null || columnName.isEmpty) return '';

    final index = headerIndexMap[columnName.toLowerCase()];

    if (index == null || index >= row.length) return '';

    return row[index].trim();

  }



  static ExcelImportBuildResult buildItemsFromWorkbook({

    required ParsedExcelWorkbook workbook,

    required Map<String, String> fieldMapping,

    required Map<String, String> rfidMap,

  }) {

    final failed = <String>[];

    var imported = 0;

    final total = workbook.rows.length;

    final itemMaps = <Map<String, dynamic>>[];



    final normalizedMapping = fieldMapping.map(

      (k, v) => MapEntry(k.trim().toLowerCase(), v.trim().toLowerCase()),

    );



    for (var rowIndex = 0; rowIndex < workbook.rows.length; rowIndex++) {

      final row = workbook.rows[rowIndex];

      try {

        final itemCode = _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['itemcode']);

        final rfid = _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['rfid']);



        var epcVal = syncAndMapRow(rfid, rfidMap);

        if (rfid.isEmpty && itemCode.isNotEmpty) {

          epcVal = stringToHex(itemCode);

        }



        final item = BulkItem.local(

          category: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['category']),

          productName: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['productname']),

          design: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['design']),

          itemCode: itemCode,

          rfid: rfid,

          epc: epcVal,

          tid: epcVal,

          grossWeight: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['grossweight']),

          stoneWeight: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['stoneweight']),

          diamondWeight: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['diamondweight']),

          netWeight: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['netweight']),

          purity: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['purity']),

          makingPerGram: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['makingpergram']),

          makingPercent: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['makingpercent']),

          fixMaking: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['fixmaking']),

          fixWastage: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['fixwastage']),

          stoneAmount: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['stoneamount']),

          diamondAmount: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['diamondamount']),

          sku: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['sku']),

          vendor: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['vendor']),

          counterName: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['countername']),

          branchName: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['branchname']),

          boxName: _getStringFromParsedRow(row, workbook.headerIndexMap, normalizedMapping['boxname']),

        );



        if (item.itemCode.isEmpty && item.epc.isEmpty) continue;

        itemMaps.add(item.toMap());

        imported++;

      } catch (_) {

        failed.add('Row ${rowIndex + 2}');

      }

    }



    return ExcelImportBuildResult(
      itemMaps: itemMaps,
      totalRows: total,
      importedRows: imported,
      failedRows: failed,
    );
  }

  /// Same mapping rules as Excel, but for Google Sheet CSV row maps (Sparkle).
  static ExcelImportBuildResult buildItemsFromSheetRows({
    required List<Map<String, String>> rows,
    required Map<String, String> fieldMapping,
    required Map<String, String> rfidMap,
  }) {
    final failed = <String>[];
    var imported = 0;
    final total = rows.length;
    final itemMaps = <Map<String, dynamic>>[];

    // fieldKey -> excel/sheet column name (as stored in mapping dialog).
    final colByField = <String, String>{};
    for (final e in fieldMapping.entries) {
      final field = e.key.trim().toLowerCase();
      final col = e.value.trim();
      if (field.isEmpty || col.isEmpty) continue;
      colByField[field] = col;
    }

    String cell(Map<String, String> row, String fieldKey) {
      final col = colByField[fieldKey];
      if (col == null || col.isEmpty) return '';
      return row[col]?.trim() ?? '';
    }

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      try {
        final itemCode = cell(row, 'itemcode');
        final rfid = cell(row, 'rfid');
        var epcVal = cell(row, 'epc');
        if (epcVal.isEmpty) {
          epcVal = syncAndMapRow(rfid, rfidMap);
        }
        if (epcVal.isEmpty && rfid.isEmpty && itemCode.isNotEmpty) {
          epcVal = stringToHex(itemCode);
        }
        if (epcVal.isEmpty) {
          epcVal = 'TEMP-${DateTime.now().millisecondsSinceEpoch}-$rowIndex';
        }

        final item = BulkItem.local(
          category: cell(row, 'category'),
          productName: cell(row, 'productname'),
          design: cell(row, 'design'),
          itemCode: itemCode,
          rfid: rfid,
          epc: epcVal,
          tid: epcVal,
          grossWeight: cell(row, 'grossweight'),
          stoneWeight: cell(row, 'stoneweight'),
          diamondWeight: cell(row, 'diamondweight'),
          netWeight: cell(row, 'netweight'),
          purity: cell(row, 'purity'),
          makingPerGram: cell(row, 'makingpergram'),
          makingPercent: cell(row, 'makingpercent'),
          fixMaking: cell(row, 'fixmaking'),
          fixWastage: cell(row, 'fixwastage'),
          stoneAmount: cell(row, 'stoneamount'),
          diamondAmount: cell(row, 'diamondamount'),
          sku: cell(row, 'sku'),
          vendor: cell(row, 'vendor'),
          counterName: cell(row, 'countername'),
          branchName: cell(row, 'branchname'),
          boxName: cell(row, 'boxname'),
        );

        if (item.itemCode.isEmpty && item.epc.isEmpty) continue;
        itemMaps.add(item.toMap());
        imported++;
      } catch (_) {
        failed.add('Row ${rowIndex + 2}');
      }
    }

    return ExcelImportBuildResult(
      itemMaps: itemMaps,
      totalRows: total,
      importedRows: imported,
      failedRows: failed,
    );
  }

  static Future<ImportProgress> _persistImportResult({
    required ExcelImportBuildResult buildResult,
    required DbService dbService,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    onProgress?.call(ImportProgress(
      totalFields: buildResult.totalRows,
      importedFields: 0,
      failedFields: buildResult.failedRows,
    ));

    await dbService.clearAllItems();

    if (buildResult.itemMaps.isNotEmpty) {
      final items = buildResult.itemMaps.map(BulkItem.fromMap).toList();
      await dbService.insertBulkItemsInBatch(
        items,
        onProgress: (done, total) {
          onProgress?.call(ImportProgress(
            totalFields: buildResult.totalRows,
            importedFields: done,
            failedFields: buildResult.failedRows,
          ));
        },
      );
    }

    return ImportProgress(
      totalFields: buildResult.totalRows,
      importedFields: buildResult.importedRows,
      failedFields: buildResult.failedRows,
    );
  }

  static Future<ImportProgress> importMappedData({
    required ParsedExcelWorkbook workbook,
    required Map<String, String> fieldMapping,
    required DbService dbService,
    required Map<String, String> rfidMap,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final buildResult = await compute(
      _buildImportItemsInBackground,
      _ExcelImportArgs(workbook: workbook, fieldMapping: fieldMapping, rfidMap: rfidMap),
    );
    return _persistImportResult(
      buildResult: buildResult,
      dbService: dbService,
      onProgress: onProgress,
    );
  }

  static Future<ImportProgress> importMappedSheetData({
    required List<Map<String, String>> rows,
    required Map<String, String> fieldMapping,
    required DbService dbService,
    required Map<String, String> rfidMap,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final buildResult = await compute(
      _buildSheetItemsInBackground,
      _SheetImportArgs(rows: rows, fieldMapping: fieldMapping, rfidMap: rfidMap),
    );
    return _persistImportResult(
      buildResult: buildResult,
      dbService: dbService,
      onProgress: onProgress,
    );
  }



  static Future<File> exportBulkItemsToExcel(List<BulkItem> items) async {

    final excel = Excel.createExcel();

    final defaultName = excel.getDefaultSheet() ?? 'Sheet1';

    excel.rename(defaultName, 'all_sync_items');

    final sheet = excel['all_sync_items'];



    const headers = [

      'Category',

      'Product Name',

      'Design',

      'Item Code',

      'RFID',

      'Gross Weight',

      'Stone Weight',

      'Dust Weight',

      'Net Weight',

      'Purity',

      'Making/Gram',

      'Making %',

      'Fix Making',

      'Fix Wastage',

      'Stone Amount',

      'Dust Amount',

      'SKU',

      'EPC',

      'Vendor',

      'TID',

      'Box',

      'Product Code',

      'Design Code',

    ];



    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());



    for (final item in items) {

      sheet.appendRow([

        TextCellValue(item.category),

        TextCellValue(item.productName),

        TextCellValue(item.design),

        TextCellValue(item.itemCode),

        TextCellValue(item.rfid),

        TextCellValue(item.grossWeight),

        TextCellValue(item.stoneWeight),

        TextCellValue(item.diamondWeight),

        TextCellValue(item.netWeight),

        TextCellValue(item.purity),

        TextCellValue(item.makingPerGram),

        TextCellValue(item.makingPercent),

        TextCellValue(item.fixMaking),

        TextCellValue(item.fixWastage),

        TextCellValue(item.stoneAmount),

        TextCellValue(item.diamondAmount),

        TextCellValue(item.sku),

        TextCellValue(item.epc),

        TextCellValue(item.vendor),

        TextCellValue(item.tid),

        TextCellValue(item.box),

        TextCellValue(item.productCode),

        TextCellValue(item.designCode),

      ]);

    }



    final dir = await getApplicationDocumentsDirectory();

    final file = File('${dir.path}/all_items.xlsx');

    final bytes = excel.encode();

    if (bytes == null) throw Exception('Failed to encode Excel file');

    await file.writeAsBytes(bytes, flush: true);

    return file;

  }



  static Future<void> shareExportedFile(File file) async {

    await Share.shareXFiles([XFile(file.path)], text: 'Exported product data');

  }

}


