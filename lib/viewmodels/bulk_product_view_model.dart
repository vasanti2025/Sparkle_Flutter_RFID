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
  final DbService _dbService;
  final RfidService _rfidService = RfidService();

  BulkProductViewModel({required DbService dbService}) : _dbService = dbService;

  List<String> _categories = [];
  List<String> _products = [];
  List<String> _designs = [];
  final List<ScannedTagRow> _scannedTags = [];
  final Map<int, String> _itemCodes = {};
  final Map<int, String> _rfidCodes = {};

  bool _isBulkMode = false;
  bool _isScanning = false;
  int? _lastClickedIndex;
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
  int? get lastClickedIndex => _lastClickedIndex;
  RfidService get rfidService => _rfidService;

  Future<void> loadDropdowns() async {
    _categories = await _dbService.getLocalCategories();
    _products = await _dbService.getLocalProducts();
    _designs = await _dbService.getLocalDesigns();
    notifyListeners();
  }

  Future<void> addLocalCategory(String name) async {
    await _dbService.insertLocalCategory(name);
    await loadDropdowns();
  }

  Future<void> addLocalProduct(String name) async {
    await _dbService.insertLocalProduct(name);
    await loadDropdowns();
  }

  Future<void> addLocalDesign(String name) async {
    await _dbService.insertLocalDesign(name);
    await loadDropdowns();
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
    _isBulkMode = value;
    notifyListeners();
  }

  void listenToTags() {
    _tagSub?.cancel();
    _tagSub = _rfidService.tagsStream.listen(_onTagScanned);
  }

  void _onTagScanned(String rawEpc) {
    final epc = rawEpc.trim().toUpperCase();
    if (epc.isEmpty) return;

    if (_isBulkMode) {
      if (_scannedTags.any((t) => t.epc == epc)) return;
      _scannedTags.add(ScannedTagRow(epc: epc, tid: epc));
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
      stopScanning();
    }
    _scheduleNotify();
  }

  Future<bool> startScanning({required int power, List<String> simulatedScopeTags = const []}) async {
    listenToTags();
    final started = await _rfidService.startScanning(power: power, simulatedScopeTags: simulatedScopeTags);
    _isScanning = started;
    notifyListeners();
    return started;
  }

  Future<void> stopScanning() async {
    await _rfidService.stopScanning();
    _isScanning = false;
    notifyListeners();
  }

  void resetScanResults() {
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
    _rfidService.stopScanning();
    super.dispose();
  }
}
