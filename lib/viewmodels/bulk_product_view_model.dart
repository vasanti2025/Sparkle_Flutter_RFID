import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bulk_item.dart';
import '../services/db_service.dart';
import '../services/rfid_service.dart';

class ScannedTagRow {
  final String epc;
  final String tid;

  ScannedTagRow({required this.epc, this.tid = ''});
}

class BulkProductViewModel extends ChangeNotifier {
  BulkProductViewModel({required DbService dbService}) : _dbService = dbService;

  final DbService _dbService;
  final RfidService _rfidService = RfidService();

  List<String> _categories = [];
  List<String> _products = [];
  List<String> _designs = [];
  final List<ScannedTagRow> _scannedTags = [];
  final Map<int, String> _itemCodes = {};
  final Map<int, String> _rfidCodes = {};

  bool _isBulkMode = false;
  bool _isScanning = false;
  bool _dropdownsLoaded = false;
  int? _lastClickedIndex;
  int _scanGeneration = 0;
  StreamSubscription<String>? _tagSub;
  Timer? _notifyDebounce;

  void _scheduleNotify() {
    _notifyDebounce ??= Timer(const Duration(milliseconds: 120), () {
      _notifyDebounce = null;
      notifyListeners();
    });
  }

  List<String> get categories => _categories;
  List<String> get products => _products;
  List<String> get designs => _designs;
  List<ScannedTagRow> get scannedTags => List.unmodifiable(_scannedTags);
  Map<int, String> get itemCodes => Map.unmodifiable(_itemCodes);
  Map<int, String> get rfidCodes => Map.unmodifiable(_rfidCodes);
  bool get isBulkMode => _isBulkMode;
  bool get isScanning => _isScanning;
  bool get dropdownsLoaded => _dropdownsLoaded;
  int? get lastClickedIndex => _lastClickedIndex;
  RfidService get rfidService => _rfidService;

  Future<void> loadDropdowns({bool force = false}) async {
    if (_dropdownsLoaded && !force) return;
    final data = await _dbService.getLocalDropdownData();
    _categories = data.categories;
    _products = data.products;
    _designs = data.designs;
    _dropdownsLoaded = true;
    notifyListeners();
  }

  Future<void> addLocalCategory(String name) async {
    await _dbService.insertLocalCategory(name);
    await loadDropdowns(force: true);
  }

  Future<void> addLocalProduct(String name) async {
    await _dbService.insertLocalProduct(name);
    await loadDropdowns(force: true);
  }

  Future<void> addLocalDesign(String name) async {
    await _dbService.insertLocalDesign(name);
    await loadDropdowns(force: true);
  }

  void setLastClickedIndex(int? index) {
    _lastClickedIndex = index;
  }

  void setItemCode(int index, String value) {
    _itemCodes[index] = value;
  }

  void setRfidCode(int index, String value) {
    _rfidCodes[index] = value;
  }

  void setBulkMode(bool value) {
    if (_isBulkMode == value) return;
    _isBulkMode = value;
    notifyListeners();
  }

  void listenToTags() {
    _tagSub?.cancel();
    _tagSub = _rfidService.tagsStream.listen(_onTagScanned);
  }

  void _onTagScanned(String rawEpc) {
    if (!_isScanning) return;
    final epc = rawEpc.trim().toUpperCase();
    if (epc.isEmpty) return;

    if (_isBulkMode) {
      if (_scannedTags.any((t) => t.epc == epc)) return;
      _scannedTags.add(ScannedTagRow(epc: epc, tid: epc));
      // Sparkle BulkViewModel Gscan: beep on each new tag added to the list.
      unawaited(_rfidService.playBeep());
    } else {
      final idx = _lastClickedIndex ?? _scannedTags.length;
      if (idx < _scannedTags.length) {
        _scannedTags[idx] = ScannedTagRow(epc: epc, tid: epc);
      } else {
        while (_scannedTags.length <= idx) {
          _scannedTags.add(ScannedTagRow(epc: '', tid: ''));
        }
        _scannedTags[idx] = ScannedTagRow(epc: epc, tid: epc);
      }
      unawaited(stopScanning());
      unawaited(_rfidService.playBeep());
    }
    _scheduleNotify();
  }

  Future<bool> startScanning({
    required int power,
    List<String> simulatedScopeTags = const [],
    bool playStartSound = true,
  }) async {
    final gen = ++_scanGeneration;
    listenToTags();
    _isScanning = true;
    notifyListeners();

    final started = await _rfidService.startScanning(
      power: power,
      simulatedScopeTags: simulatedScopeTags,
      playStartSound: playStartSound,
    );

    if (gen != _scanGeneration) {
      if (started) {
        await _rfidService.stopScanning();
        await _rfidService.haltScan();
      }
      return false;
    }

    _isScanning = started;
    notifyListeners();
    return started;
  }

  Future<void> stopScanning() async {
    _scanGeneration++;
    if (!_isScanning) {
      await _rfidService.haltScan();
      return;
    }
    _isScanning = false;
    notifyListeners();
    await _rfidService.stopScanning();
    await _rfidService.haltScan();
  }

  Future<void> resetScanResults() async {
    await stopScanning();
    _isBulkMode = false;
    _scannedTags.clear();
    _itemCodes.clear();
    _rfidCodes.clear();
    _lastClickedIndex = null;
    notifyListeners();
  }

  Future<bool> saveAllBulkProductRows({
    required String category,
    required String product,
    required String design,
  }) async {
    if (category.isEmpty || product.isEmpty || design.isEmpty) return false;

    final items = <BulkItem>[];
    for (var i = 0; i < _scannedTags.length; i++) {
      final tag = _scannedTags[i];
      final epc = tag.epc.trim().toUpperCase();
      if (epc.isEmpty) continue;
      final itemCode = (_itemCodes[i] ?? '').trim();
      if (itemCode.isEmpty) continue;
      final rfid = (_rfidCodes[i] ?? '').trim();

      items.add(BulkItem.local(
        category: category,
        productName: product,
        design: design,
        itemCode: itemCode,
        rfid: rfid,
        epc: epc,
        tid: tag.tid.isNotEmpty ? tag.tid : epc,
      ));
    }

    if (items.isEmpty) return false;
    await _dbService.clearAllItems();
    await _dbService.insertBulkItemsInBatch(items);
    return true;
  }

  @override
  void dispose() {
    _notifyDebounce?.cancel();
    _tagSub?.cancel();
    unawaited(_rfidService.stopScanning());
    unawaited(_rfidService.haltScan());
    super.dispose();
  }
}
