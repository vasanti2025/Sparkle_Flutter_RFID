import 'package:flutter/foundation.dart';

import '../models/epc_dto.dart';

import '../services/api_service.dart';

import '../services/db_service.dart';

import '../services/excel_product_service.dart';

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



  Uint8List? _fileBytes;

  ParsedExcelWorkbook? _workbook;

  ImportProgress _progress = const ImportProgress(totalFields: 0, importedFields: 0, failedFields: []);

  bool _importing = false;

  bool _importDone = false;

  Map<String, String>? _syncedRfidMap;

  bool _rfidSyncInProgress = false;

  Future<void>? _rfidSyncFuture;



  ImportProgress get progress => _progress;
  bool get importing => _importing;
  bool get importDone => _importDone;
  List<String> get excelColumns => _workbook?.headers ?? [];

  String get clientCode => _prefService.getEmployee()?.clientCode ?? '';



  void setFileBytes(Uint8List bytes) {

    _fileBytes = bytes;

    _workbook = ParsedExcelWorkbook.parse(bytes);

    notifyListeners();

  }



  /// Load GetAllRFID mapping in background while user maps Excel columns.

  Future<void> prefetchRfidMap() {

    _rfidSyncFuture ??= _loadRfidMapFromServer();

    return _rfidSyncFuture!;

  }



  /// Matches Kotlin [ImportExcelViewModel.syncRFIDDataIfNeeded].

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



  Future<void> importMappedData(Map<String, String> fieldMapping) async {

    if (_fileBytes == null || _workbook == null) return;

    _importing = true;

    _importDone = false;

    _progress = const ImportProgress(totalFields: 0, importedFields: 0, failedFields: []);

    notifyListeners();



    try {

      final rfidMap = await _resolveRfidMap();

      _progress = ImportProgress(totalFields: _workbook!.rows.length, importedFields: 0, failedFields: const []);

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



  void resetImportState() {

    _importDone = false;

    _fileBytes = null;

    _workbook = null;

    _progress = const ImportProgress(totalFields: 0, importedFields: 0, failedFields: []);

    notifyListeners();

  }

}


