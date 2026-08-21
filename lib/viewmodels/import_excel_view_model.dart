import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/epc_dto.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/excel_product_service.dart';
import '../services/google_sheet_service.dart';
import '../services/pref_service.dart';

class ImportExcelViewModel extends ChangeNotifier {
  final DbService _dbService;
  final ApiService _apiService;
  final PrefService _prefService;

  ImportExcelViewModel({
    required DbService dbService,
    required ApiService apiService,
    required PrefService prefService,
  })  : _dbService = dbService,
        _apiService = apiService,
        _prefService = prefService;

  ParsedExcelWorkbook? _workbook;
  ImportProgress _progress = const ImportProgress(totalFields: 0, importedFields: 0, failedFields: []);
  bool _importing = false;
  bool _importDone = false;
  Map<String, String>? _syncedRfidMap;
  bool _rfidSyncInProgress = false;
  Future<void>? _rfidSyncFuture;
  String? _pendingSheetCsvUrl;

  ImportProgress get progress => _progress;
  bool get importing => _importing;
  bool get importDone => _importDone;
  List<String> get excelColumns => _workbook?.headers ?? [];
  String? get pendingSheetCsvUrl => _pendingSheetCsvUrl;
  String get clientCode => _prefService.getEmployee()?.clientCode ?? '';

  /// Parse Excel off the UI isolate to avoid hang/crash on large files.
  Future<void> setFileBytesAsync(Uint8List bytes) async {
    _workbook = await ParsedExcelWorkbook.parseAsync(bytes);
    notifyListeners();
  }

  /// Prefer file path → read + parse in background (lower peak memory than picker bytes).
  Future<void> setFileFromPathAsync(String path) async {
    final bytes = await File(path).readAsBytes();
    await setFileBytesAsync(bytes);
  }

  @Deprecated('Use setFileBytesAsync')
  void setFileBytes(Uint8List bytes) {
    _workbook = ParsedExcelWorkbook.parse(bytes);
    notifyListeners();
  }

  Future<void> prefetchRfidMap() {
    _rfidSyncFuture ??= _loadRfidMapFromServer();
    return _rfidSyncFuture!;
  }

  Future<void> syncRfidDataIfNeeded() async {
    await prefetchRfidMap();
  }

  Future<Map<String, String>> _resolveRfidMap() async {
    await prefetchRfidMap();
    if (_syncedRfidMap != null && _syncedRfidMap!.isNotEmpty) {
      return _syncedRfidMap!;
    }
    return _dbService.getRFIDTagsMap();
  }

  Future<void> _loadRfidMapFromServer() async {
    if (_syncedRfidMap != null || clientCode.isEmpty || _rfidSyncInProgress) return;
    _rfidSyncInProgress = true;
    try {
      final localMap = await _dbService.getRFIDTagsMap();
      try {
        final tags = await _apiService.getAllRfidTags(clientCode);
        final dtos = tags
            .whereType<Map>()
            .map((t) => EpcDto.fromJson(Map<String, dynamic>.from(t)))
            .where((t) => t.barcodeNumber.trim().isNotEmpty)
            .toList();

        if (dtos.isNotEmpty) {
          await _dbService.insertRFIDTagsInBatch(dtos);
        }

        final serverMap = <String, String>{
          for (final t in dtos)
            t.barcodeNumber.trim().toUpperCase(): t.tidValue.trim().toUpperCase(),
        };

        _syncedRfidMap = {...localMap, ...serverMap};
      } catch (_) {
        _syncedRfidMap = localMap;
      }
    } finally {
      _rfidSyncInProgress = false;
    }
  }

  Future<List<String>> fetchGoogleSheetHeaders(String csvUrl) {
    return GoogleSheetService.parseHeaders(csvUrl);
  }

  void prepareSheetImport(String csvUrl) {
    _pendingSheetCsvUrl = csvUrl;
    _workbook = null;
  }

  Future<void> importMappedData(Map<String, String> fieldMapping) async {
    if (_workbook == null) return;
    _importing = true;
    _importDone = false;
    _progress = const ImportProgress(totalFields: 0, importedFields: 0, failedFields: []);
    notifyListeners();

    try {
      final rfidMap = await _resolveRfidMap();
      _progress = ImportProgress(
        totalFields: _workbook!.rows.length,
        importedFields: 0,
        failedFields: const [],
      );
      notifyListeners();

      _progress = await ExcelProductService.importMappedData(
        workbook: _workbook!,
        fieldMapping: fieldMapping,
        dbService: _dbService,
        rfidMap: rfidMap,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );
    } catch (e) {
      _progress = ImportProgress(
        totalFields: 0,
        importedFields: 0,
        failedFields: [e.toString()],
      );
    } finally {
      _importing = false;
      _importDone = true;
      notifyListeners();
    }
  }

  /// Sparkle [ImportExcelViewModel.importMappedDataFromSheet].
  Future<void> importMappedDataFromSheet(
    String csvUrl,
    Map<String, String> fieldMapping,
  ) async {
    _importing = true;
    _importDone = false;
    _progress = const ImportProgress(totalFields: 0, importedFields: 0, failedFields: []);
    notifyListeners();

    try {
      final rfidMap = await _resolveRfidMap();
      final rows = await GoogleSheetService.parseRows(csvUrl);
      if (rows.isEmpty) {
        _progress = const ImportProgress(
          totalFields: 0,
          importedFields: 0,
          failedFields: ['No rows parsed from sheet'],
        );
        return;
      }

      _progress = ImportProgress(totalFields: rows.length, importedFields: 0, failedFields: const []);
      notifyListeners();

      _progress = await ExcelProductService.importMappedSheetData(
        rows: rows,
        fieldMapping: fieldMapping,
        dbService: _dbService,
        rfidMap: rfidMap,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );
    } catch (e) {
      _progress = ImportProgress(
        totalFields: 0,
        importedFields: 0,
        failedFields: [e.toString()],
      );
    } finally {
      _importing = false;
      _importDone = true;
      _pendingSheetCsvUrl = null;
      notifyListeners();
    }
  }

  void resetImportState() {
    _importDone = false;
    _workbook = null;
    _pendingSheetCsvUrl = null;
    _progress = const ImportProgress(totalFields: 0, importedFields: 0, failedFields: []);
    notifyListeners();
  }
}
