import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rfid_flutter/utils/app_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../utils/app_dropdown.dart';
import 'widgets/scan_bottom_bar.dart';

class SearchItem {
  final String epc;
  final String itemCode;
  final String productName;
  final String rfid;
  final String tid;
  final String hex;
  String rssi;
  int proximityPercent;

  late final String normEpc;
  late final String normRfid;
  late final String normItemCode;
  late final String normTid;
  late final String normHex;

  SearchItem({
    required this.epc,
    required this.itemCode,
    required this.productName,
    required this.rfid,
    this.tid = '',
    this.hex = '',
    this.rssi = '',
    this.proximityPercent = 0,
  }) {
    normEpc = epc.trim().toUpperCase().replaceAll(' ', '');
    normRfid = rfid.trim().toUpperCase().replaceAll(' ', '');
    normItemCode = itemCode.trim().toUpperCase().replaceAll(' ', '');
    normTid = tid.trim().toUpperCase().replaceAll(' ', '');
    normHex = hex.trim().toUpperCase().replaceAll(' ', '');
  }

  void applyScan({String? rssi, int? proximityPercent}) {
    if (rssi != null) this.rssi = rssi;
    if (proximityPercent != null && proximityPercent > this.proximityPercent) {
      this.proximityPercent = proximityPercent;
    }
  }

  void clearScan() {
    rssi = '';
    proximityPercent = 0;
  }
}

/// Single compact unmatched list shared with inventory — avoids a second 50k copy
/// on 3GB handhelds (Navigator arguments + SearchItem list would OOM/ANR).
class UnmatchedSearchCatalog {
  UnmatchedSearchCatalog._();
  static final UnmatchedSearchCatalog instance = UnmatchedSearchCatalog._();

  final List<SearchItem> items = [];

  void clear() => items.clear();
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final RfidService _rfidService = RfidService();
  final TextEditingController _searchController = TextEditingController();
  
  StreamSubscription? _tagsSubscription;
  StreamSubscription? _triggerSubscription;
  Timer? _debounceTimer;
  Timer? _uiFlushTimer;
  Timer? _proximityDecayTimer;
  bool _scanBusy = false;

  bool _isInit = false;
  bool _isLoading = false;
  bool _isScanning = false;
  int _selectedPower = 30;

  String _listKey = 'normal'; // 'unmatchedItems' or 'normal'
  String _selectedSearchType = 'LabelStock'; // 'LabelStock', 'Order', 'Box'
  String _searchQuery = '';

  List<SearchItem> _searchItems = [];

  // O(1) tag lookup — mirrors Kotlin SearchViewModel.epcToIndex
  final Map<String, int> _tagIndexMap = {};
  final Map<int, int> _lastRssiUpdateMs = {};
  int _lastSearchUiUpdateUs = 0;
  final Set<int> _dirtyIndices = {};
  final Set<int> _hotSet = {};
  final Set<int> _atMaxProximity = {};
  final List<int> _hotIndices = [];
  final List<int> _coldIndices = [];
  bool _displayIndexValid = false;
  int _filteredCount = 0;
  bool _indexReady = true;
  int _lastRssiSoundMs = 0;
  int _lastRssiSoundId = -1;
  final ValueNotifier<int> _nearbyTick = ValueNotifier<int>(0);

  bool get _isLargeUnmatched =>
      _listKey == 'unmatchedItems' && _searchItems.length >= 500;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_rfidService.preWarmReader());
    });
    _tagsSubscription = _rfidService.tagsWithRssiStream.listen(_onTagScanned);
    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      _toggleScanning();
    });
    _loadPower();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        final listKey = args['listKey'] as String? ?? 'normal';
        _listKey = listKey;
        if (_listKey == 'unmatchedItems') {
          _isLoading = true;
          _indexReady = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_attachUnmatchedCatalog());
          });
        }
      }
      _isInit = true;
    }
  }

  @override
  void dispose() {
    _tagsSubscription?.cancel();
    _triggerSubscription?.cancel();
    _debounceTimer?.cancel();
    _uiFlushTimer?.cancel();
    _proximityDecayTimer?.cancel();
    _nearbyTick.dispose();
    unawaited(_rfidService.stopInventorySound());
    unawaited(_rfidService.stopSound());
    unawaited(_rfidService.stopScanning());
    unawaited(_rfidService.clearSearchTags());
    if (_listKey == 'unmatchedItems') {
      UnmatchedSearchCatalog.instance.clear();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPower() async {
    final power = context.read<PrefService>().searchPower;
    if (mounted) setState(() => _selectedPower = power.clamp(1, 30));
    _rfidService.setPower(power);
  }

  /// Trim + uppercase + strip spaces — matches native EPC keys and stock transfer.
  static String _normScanKey(String value) {
    var s = value.trim();
    if (s.isEmpty) return '';
    s = s.toUpperCase();
    if (s.contains(' ')) s = s.replaceAll(' ', '');
    return s;
  }

  Future<void> _attachUnmatchedCatalog() async {
    // Reuse the catalog inventory already filled — do not copy 50k rows.
    _searchItems = UnmatchedSearchCatalog.instance.items;
    if (!mounted) return;
    if (_searchItems.isEmpty) {
      setState(() {
        _isLoading = false;
        _indexReady = true;
        _displayIndexValid = false;
      });
      return;
    }
    await _rebuildTagIndexChunked();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _indexReady = true;
      _displayIndexValid = false;
    });
    unawaited(_rfidService.prepareForScan());
  }

  Future<void> _rebuildTagIndexChunked() async {
    _tagIndexMap.clear();
    const chunk = 600;
    for (int i = 0; i < _searchItems.length; i++) {
      final item = _searchItems[i];

      if (item.normEpc.isNotEmpty) _tagIndexMap[item.normEpc] = i;
      if (item.normRfid.isNotEmpty) _tagIndexMap[item.normRfid] = i;
      if (item.normItemCode.isNotEmpty) _tagIndexMap[item.normItemCode] = i;
      if (item.normTid.isNotEmpty) _tagIndexMap[item.normTid] = i;
      if (item.normHex.isNotEmpty) _tagIndexMap[item.normHex] = i;

      if (i > 0 && i % chunk == 0) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }
  }

  void _startProximityDecay() {
    // Disabled to prevent artificial RSSI fluctuations when gun and items are in the same place (matches Java stability)
  }

  void _stopProximityDecay() {
    // Disabled
  }

  void _rebuildTagIndex() {
    _tagIndexMap.clear();
    for (int i = 0; i < _searchItems.length; i++) {
      final item = _searchItems[i];
      if (item.normEpc.isNotEmpty) _tagIndexMap[item.normEpc] = i;
      if (item.normRfid.isNotEmpty) _tagIndexMap[item.normRfid] = i;
      if (item.normItemCode.isNotEmpty) _tagIndexMap[item.normItemCode] = i;
      if (item.normTid.isNotEmpty) _tagIndexMap[item.normTid] = i;
      if (item.normHex.isNotEmpty) _tagIndexMap[item.normHex] = i;
    }
  }

  void _rebuildNearbyOnly() {
    for (final i in _dirtyIndices) {
      if (i < 0 || i >= _searchItems.length) continue;
      final prox = _searchItems[i].proximityPercent;
      if (prox > 0) {
        _hotSet.add(i);
      } else {
        _hotSet.remove(i);
      }
      if (prox >= 100) {
        _atMaxProximity.add(i);
      } else {
        _atMaxProximity.remove(i);
      }
    }
    _dirtyIndices.clear();
    _hotIndices
      ..clear()
      ..addAll(_hotSet);
    _hotIndices.sort((a, b) => _searchItems[b]
        .proximityPercent
        .compareTo(_searchItems[a].proximityPercent));
    // Keep the live nearby pane small so 3GB devices never rebuild 50k rows.
    if (_hotIndices.length > 40) {
      _hotIndices.removeRange(40, _hotIndices.length);
    }
  }

  void _flushPendingSearchUpdates() {
    if (_dirtyIndices.isEmpty) return;
    if (!mounted) return;
    _rebuildNearbyOnly();
    _displayIndexValid = false;
    if (_isLargeUnmatched) {
      _nearbyTick.value++;
    }
    setState(() {});
    _checkAutoStopSearch();
  }

  /// Stop when every item in the current list reaches max proximity (Sparkle Search).
  void _checkAutoStopSearch() {
    if (!_isScanning || _scanBusy) return;
    if (_searchItems.isEmpty) return;
    if (_isLargeUnmatched) {
      if (_searchQuery.trim().isEmpty &&
          _atMaxProximity.length >= _searchItems.length) {
        unawaited(_stopSearchScan());
      }
      return;
    }
    if (!_displayIndexValid) _rebuildDisplayIndices();
    if (_filteredCount <= 0) return;
    if (_searchQuery.trim().isEmpty) {
      if (_atMaxProximity.length < _searchItems.length) return;
    } else {
      for (final i in _hotIndices) {
        if (_searchItems[i].proximityPercent < 100) return;
      }
      for (final i in _coldIndices) {
        if (_searchItems[i].proximityPercent < 100) return;
      }
    }
    unawaited(_stopSearchScan());
  }

  Future<void> _stopSearchScan() async {
    if (!_isScanning && !_rfidService.isScanning) return;
    _scanBusy = true;
    try {
      _stopProximityDecay();
      await _rfidService.stopScanning();
      await _rfidService.stopInventorySound();
      await _rfidService.stopSound();
      await _rfidService.clearSearchTags();
      if (mounted) {
        _displayIndexValid = false;
        setState(() => _isScanning = false);
        _nearbyTick.value++;
      }
    } finally {
      _scanBusy = false;
    }
  }

  void _scheduleSearchUiUpdate() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final minUs = _isLargeUnmatched ? 180000 : 16000;
    if (_lastSearchUiUpdateUs == 0 ||
        now - _lastSearchUiUpdateUs >= minUs) {
      _lastSearchUiUpdateUs = now;
      _uiFlushTimer?.cancel();
      _flushPendingSearchUpdates();
    } else {
      _uiFlushTimer ??= Timer(Duration(microseconds: minUs), () {
        _uiFlushTimer = null;
        _lastSearchUiUpdateUs = DateTime.now().microsecondsSinceEpoch;
        _flushPendingSearchUpdates();
      });
    }
  }

  SearchItem _searchItemFromBulk(BulkItem item) {
    final epcValue = item.epc.isNotEmpty
        ? item.epc
        : (item.rfid.isNotEmpty
            ? item.rfid
            : (item.itemCode.isNotEmpty ? item.itemCode : ''));
    return SearchItem(
      epc: epcValue,
      itemCode: item.itemCode,
      productName: item.productName,
      rfid: item.rfid,
      tid: item.tid,
      hex: item.box,
    );
  }

  /// Matches Sparkle SearchViewModel + native [playRssiSearchSound] buckets:
  /// lower |RSSI| = closer (stronger signal), higher |RSSI| = farther.
  int convertRssiToProximity(String rssi) {
    try {
      final raw = rssi.trim();
      if (raw.isEmpty) return -1;
      final rssiValue = double.parse(raw);
      if (rssiValue == 0) return -1;
      final magnitude = rssiValue.abs();
      return (((80 - magnitude).clamp(0.0, 40.0)) * 100 / 40).toInt().clamp(0, 100);
    } catch (_) {
      return -1;
    }
  }

  Color getColorByPercentage(int percent) {
    if (percent <= 25) return Colors.red;
    if (percent <= 50) return Colors.yellow[700]!;
    if (percent <= 75) return Colors.blue;
    return Colors.green;
  }

  void _playRssiSearchSound(String rssi) {
    final rssiAbs = double.tryParse(rssi.trim())?.abs() ?? 0;
    final id = rssiAbs > 0 && rssiAbs < 50
        ? 4
        : rssiAbs > 50 && rssiAbs < 60
            ? 2
            : rssiAbs > 60 && rssiAbs < 70
                ? 5
                : rssiAbs > 70
                    ? 1
                    : -1;
    if (id == -1) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id == _lastRssiSoundId && now - _lastRssiSoundMs < 40) return;
    _lastRssiSoundMs = now;
    _lastRssiSoundId = id;
    unawaited(_rfidService.playSound(id));
  }

  void _onTagScanned(Map<String, dynamic> tagEvent) {
    try {
      if (!_isScanning) return;

      final epc = _normScanKey(tagEvent['epc'] as String? ?? '');
      final rssi = (tagEvent['rssi'] as String? ?? '').trim();
      if (epc.isEmpty) return;

      final proximity = convertRssiToProximity(rssi);
      if (proximity < 0) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      final index = _tagIndexMap[epc];
      if (index == null || index < 0 || index >= _searchItems.length) return;

      _lastRssiUpdateMs[index] = now;
      final item = _searchItems[index];
      final previous = item.proximityPercent;
      item.applyScan(rssi: rssi, proximityPercent: proximity);
      if (_isLargeUnmatched) {
        _playRssiSearchSound(rssi);
      }
      // RSSI jitters even when the tag is still nearby — don't rebuild the
      // colored progress unless the displayed % actually increased.
      if (item.proximityPercent != previous) {
        _dirtyIndices.add(index);
        _scheduleSearchUiUpdate();
      }
    } catch (e) {
      debugPrint('Search tag handler: $e');
    }
  }

  void _toggleScanning() async {
    if (_scanBusy) return;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    if (_isScanning) {
      await _stopSearchScan();
      return;
    }

    if (!_indexReady) {
      _showToast(context.sRead.pleaseWaitItemsLoading);
      return;
    }

    if (_isLargeUnmatched) {
      if (_searchItems.isEmpty) {
        _showToast(context.sRead.noItemsToSearch);
        return;
      }
    } else {
      if (!_displayIndexValid) _rebuildDisplayIndices();
      if (_filteredCount <= 0) {
        _showToast(context.sRead.noItemsToSearch);
        return;
      }
    }

    _scanBusy = true;
    try {
      setState(() => _isScanning = true);
      unawaited(_rfidService.playBeep());
      _lastSearchUiUpdateUs = 0;
      _atMaxProximity.clear();
      _dirtyIndices.clear();
      _hotSet.clear();
      _hotIndices.clear();
      _startProximityDecay();

      bool started;
      if (_isLargeUnmatched) {
        // 3GB handhelds cannot take 50k search tags over the binder.
        // Match in Dart; native emits all tags (same RSSI proximity UX).
        await _rfidService.clearSearchTags();
        started = await _rfidService
            .startScanning(
              power: _selectedPower,
              playStartSound: false,
            )
            .timeout(const Duration(seconds: 12), onTimeout: () => false);
      } else {
        List<String> cleanTags;
        if (_searchQuery.trim().isEmpty && _tagIndexMap.isNotEmpty) {
          cleanTags = _tagIndexMap.keys.toList(growable: false);
        } else {
          final tags = <String>{};
          void addTag(String value) {
            final key = _normScanKey(value);
            if (key.isNotEmpty) tags.add(key);
          }
          for (var i = 0; i < _filteredCount; i++) {
            final item = _displayItemAt(i);
            addTag(item.epc);
            addTag(item.rfid);
            addTag(item.itemCode);
            addTag(item.tid);
            addTag(item.hex);
          }
          cleanTags = tags.toList(growable: false);
        }
        if (cleanTags.isEmpty) {
          _showToast(context.sRead.noSearchableIdentifiersFound);
          setState(() => _isScanning = false);
          _stopProximityDecay();
          return;
        }
        started = await _rfidService
            .startScanning(
              power: _selectedPower,
              searchTags: cleanTags,
              playStartSound: false,
            )
            .timeout(const Duration(seconds: 12), onTimeout: () => false);
      }

      if (!mounted) return;
      if (!started) {
        _stopProximityDecay();
        setState(() => _isScanning = false);
        await _rfidService.stopSound();
        await _rfidService.stopScanning();
        await _rfidService.clearSearchTags();
        if (!mounted) return;
        _showToast(context.sRead.failedToStartRfidScanner);
      }
    } catch (e) {
      if (mounted) {
        _stopProximityDecay();
        setState(() => _isScanning = false);
        unawaited(_rfidService.stopSound());
        _showToast(context.sRead.failedToStartRfidScanner);
      }
    } finally {
      _scanBusy = false;
    }
  }

  void _onQueryChanged(String val) {
    _searchQuery = val;
    _displayIndexValid = false;
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    if (_listKey == 'normal') {
      setState(() {});
      _debounceTimer = Timer(const Duration(milliseconds: 200), () {
        _performSearch(val);
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchItems.clear();
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<SearchItem> results = [];
      
      if (_selectedSearchType == 'LabelStock') {
        final dbService = Provider.of<DbService>(context, listen: false);
        final items = await dbService.searchItemsExact(trimmed);

        for (var item in items) {
          results.add(_searchItemFromBulk(item));
        }
      } else if (_selectedSearchType == 'Order') {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final dashboardViewModel = Provider.of<DashboardViewModel>(context, listen: false);
        final clientCode = dashboardViewModel.employee?.clientCode ?? '';
        if (clientCode.isNotEmpty) {
          final orders = await apiService.searchOrdersByRfid(clientCode, trimmed);
          for (var order in orders) {
            final items = order['CustomOrderItem'] as List? ?? [];
            final isOrderLevelMatch =
                order['CustomOrderId']?.toString() == trimmed ||
                order['Id']?.toString() == trimmed ||
                (order['OrderNo'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                (order['RfidCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                (order['TidNumber'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase();

            final matchedItems = isOrderLevelMatch
                ? items
                : items.where((item) =>
                    (item['RFIDCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                    (item['ItemCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                    (item['TIDNumber'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase()
                  ).toList();

            for (var item in matchedItems) {
              final rfid = (item['RFIDCode'] as String? ?? '').trim();
              final tid = (item['TIDNumber'] as String? ?? '').trim();
              final code = (item['ItemCode'] as String? ?? '').trim();
              final prodName = (item['ProductName'] as String? ?? '').trim();
              
              final parentRfid = (order['RfidCode'] as String? ?? '').trim();
              final parentTid = (order['TidNumber'] as String? ?? '').trim();
              
              final finalRfid = rfid.isNotEmpty ? rfid : parentRfid;
              final finalTid = tid.isNotEmpty ? tid : parentTid;
              
              final searchKey = finalTid.isNotEmpty
                  ? finalTid
                  : (finalRfid.isNotEmpty ? finalRfid : code);

              results.add(SearchItem(
                epc: searchKey,
                itemCode: code,
                productName: prodName,
                rfid: finalRfid,
                tid: finalTid,
              ));
            }
          }
        }
      } else if (_selectedSearchType == 'Box') {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final dashboardViewModel = Provider.of<DashboardViewModel>(context, listen: false);
        final clientCode = dashboardViewModel.employee?.clientCode ?? '';
        if (clientCode.isNotEmpty) {
          final data = await apiService.getBoxDetailsByRfidCode(clientCode, trimmed);
          if (data != null && data['Success'] == true) {
            final boxes = data['Boxes'] as List? ?? [];
            final products = data['Products'] as List? ?? [];
            
            for (var entry in boxes) {
              final boxProducts = entry['Products'] as List? ?? [];
              for (var p in boxProducts) {
                final rfid = (p['RfidCode'] as String? ?? '').trim();
                final tid = (p['TidNumber'] as String? ?? '').trim();
                final hex = (p['HexCode'] as String? ?? '').trim();
                final code = (p['ItemCode'] as String? ?? '').trim();
                final prodName = (p['ProductName'] as String? ?? p['ProductTitle'] as String? ?? '').trim();
                
                final searchKey = tid.isNotEmpty ? tid : (hex.isNotEmpty ? hex : (rfid.isNotEmpty ? rfid : code));
                results.add(SearchItem(
                  epc: searchKey,
                  itemCode: code,
                  productName: prodName,
                  rfid: rfid,
                  tid: tid,
                  hex: hex,
                ));
              }
            }
            
            for (var p in products) {
              final rfid = (p['RfidCode'] as String? ?? '').trim();
              final tid = (p['TidNumber'] as String? ?? '').trim();
              final hex = (p['HexCode'] as String? ?? '').trim();
              final code = (p['ItemCode'] as String? ?? '').trim();
              final prodName = (p['ProductName'] as String? ?? p['ProductTitle'] as String? ?? '').trim();
              
              final searchKey = tid.isNotEmpty ? tid : (hex.isNotEmpty ? hex : (rfid.isNotEmpty ? rfid : code));
              results.add(SearchItem(
                epc: searchKey,
                itemCode: code,
                productName: prodName,
                rfid: rfid,
                tid: tid,
                hex: hex,
              ));
            }
          }
        }
      }

      setState(() {
        _searchItems = results;
        _rebuildTagIndex();
        _displayIndexValid = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showToast(context.sRead.searchError(e));
    }
  }

  void _rebuildDisplayIndices() {
    if (_isLargeUnmatched && _searchQuery.trim().isEmpty) {
      _filteredCount = _searchItems.length;
      _displayIndexValid = true;
      return;
    }
    final query = _searchQuery.trim().toUpperCase().replaceAll(' ', '');
    _hotIndices.clear();
    _coldIndices.clear();
    for (var i = 0; i < _searchItems.length; i++) {
      final item = _searchItems[i];
      if (query.isNotEmpty) {
        if (!item.normItemCode.contains(query) &&
            !item.normRfid.contains(query) &&
            !item.normEpc.contains(query) &&
            !item.normTid.contains(query) &&
            !item.normHex.contains(query)) {
          continue;
        }
      }
      if (item.proximityPercent > 0) {
        _hotIndices.add(i);
      } else {
        _coldIndices.add(i);
      }
    }
    _hotIndices.sort((a, b) => _searchItems[b]
        .proximityPercent
        .compareTo(_searchItems[a].proximityPercent));
    if (query.isNotEmpty && _coldIndices.isNotEmpty) {
      final exact = <int>[];
      final rest = <int>[];
      for (final i in _coldIndices) {
        final item = _searchItems[i];
        final isExact = item.normItemCode == query ||
            item.normRfid == query ||
            item.normEpc == query ||
            item.normTid == query ||
            item.normHex == query;
        if (isExact) {
          exact.add(i);
        } else {
          rest.add(i);
        }
      }
      _coldIndices
        ..clear()
        ..addAll(exact)
        ..addAll(rest);
    }
    _filteredCount = _hotIndices.length + _coldIndices.length;
    _displayIndexValid = true;
  }

  SearchItem _displayItemAt(int index) {
    if (index < _hotIndices.length) {
      return _searchItems[_hotIndices[index]];
    }
    return _searchItems[_coldIndices[index - _hotIndices.length]];
  }

  void _resetSearch() {
    unawaited(_stopSearchScan());
    _stopProximityDecay();
    _searchController.clear();
    _atMaxProximity.clear();
    _dirtyIndices.clear();
    _hotSet.clear();
    _hotIndices.clear();
    setState(() {
      _searchQuery = '';
      _isScanning = false;
      if (_listKey == 'normal') {
        _searchItems.clear();
        _tagIndexMap.clear();
      } else {
        for (var i = 0; i < _searchItems.length; i++) {
          final item = _searchItems[i];
          if (item.proximityPercent != 0 || item.rssi.isNotEmpty) {
            item.clearScan();
          }
        }
      }
      _displayIndexValid = false;
    });
    _nearbyTick.value++;
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppFonts.poppins()),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isUnmatchedList = _listKey == 'unmatchedItems';
    final largeUnmatched = _isLargeUnmatched;
    final query = _searchQuery.trim();
    if (!largeUnmatched || query.isNotEmpty) {
      if (!_displayIndexValid) _rebuildDisplayIndices();
    }
    final catalogCount = (largeUnmatched && query.isEmpty)
        ? _searchItems.length
        : _filteredCount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              isUnmatchedList ? s.searchUnmatched : s.searchAllItems,
              style: AppFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
            ),
            actions: [
              // White counter box showing selected power (1-30), same as Scan Display / Delivery Challan.
              PopupMenuButton<int>(
                tooltip: s.rfidPower,
                color: Colors.white,
                constraints: const BoxConstraints(maxHeight: 320, minWidth: 60),
                onSelected: (val) {
                  setState(() => _selectedPower = val);
                  _rfidService.setPower(val);
                  context.read<PrefService>().savePower(PrefService.keySearchCount, val);
                },
                itemBuilder: (context) => List.generate(30, (i) => i + 1)
                    .map((p) => PopupMenuItem<int>(
                          value: p,
                          height: 36,
                          child: Text('$p', style: AppFonts.poppins(fontSize: 14)),
                        ))
                    .toList(),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$_selectedPower',
                    style: AppFonts.poppins(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Dropdown for search type (Normal mode only)
          if (!isUnmatchedList)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, top: 12.0, bottom: 4.0),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedSearchType,
                menuMaxHeight: kDropdownMenuMaxHeight,
                decoration: InputDecoration(
                  labelText: s.searchType,
                  labelStyle: AppFonts.poppins(fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'LabelStock', child: Text(s.labelStock, style: AppFonts.poppins(fontSize: 13))),
                  DropdownMenuItem(value: 'Order', child: Text(s.order, style: AppFonts.poppins(fontSize: 13))),
                  DropdownMenuItem(value: 'Box', child: Text(s.box, style: AppFonts.poppins(fontSize: 13))),
                ],
                onChanged: _isScanning
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() {
                            _selectedSearchType = val;
                            _searchQuery = '';
                            _searchController.clear();
                            _searchItems.clear();
                          });
                        }
                      },
              ),
            ),

          // Search Field
          Padding(
            padding: EdgeInsets.only(
              left: 12.0,
              right: 12.0,
              top: isUnmatchedList ? 12.0 : 4.0,
              bottom: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              enabled: !_isScanning,
              decoration: InputDecoration(
                labelText: isUnmatchedList
                    ? s.enterRfidItemcode
                    : (_selectedSearchType == 'Order'
                        ? s.enterRfidCustomOrderId
                        : (_selectedSearchType == 'Box'
                            ? s.enterRfidBoxRfid
                            : s.enterRfidItemcode)),
                labelStyle: AppFonts.poppins(fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _onQueryChanged,
              style: AppFonts.poppins(fontSize: 13),
            ),
          ),

          // Table Header
          Container(
            color: const Color(0xFF3B363E),
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _selectedSearchType == 'Order' && !isUnmatchedList
                  ? [
                      _buildHeaderCell(s.headerSno, 1),
                      _buildHeaderCell(s.lblRfid, 2),
                      _buildHeaderCell(s.progress, 3),
                      _buildHeaderCell(s.percent, 1),
                    ]
                  : [
                      _buildHeaderCell(s.headerSno, 1),
                      _buildHeaderCell(s.lblRfid, 2),
                      _buildHeaderCell(s.itemcode, 2),
                      _buildHeaderCell(s.progress, 3),
                      _buildHeaderCell(s.percent, 1),
                    ],
            ),
          ),

          // Results list or empty placeholder
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : catalogCount == 0 && !(largeUnmatched && _hotIndices.isNotEmpty)
                    ? Center(
                        child: Text(
                          isUnmatchedList && _searchItems.isEmpty
                              ? s.noUnmatchedItemsToSearch
                              : s.typeRfidItemcodeToSearch,
                          style: AppFonts.poppins(color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: [
                          if (largeUnmatched && query.isEmpty)
                            ValueListenableBuilder<int>(
                              valueListenable: _nearbyTick,
                              builder: (context, value, child) {
                                if (_hotIndices.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final n = _hotIndices.length > 8
                                    ? 8
                                    : _hotIndices.length;
                                return SizedBox(
                                  height: n * 34.0,
                                  child: ListView.builder(
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemExtent: 34,
                                    itemCount: n,
                                    itemBuilder: (context, index) {
                                      return _buildSearchRow(
                                        _searchItems[_hotIndices[index]],
                                        index,
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: catalogCount,
                              itemExtent: 34,
                              cacheExtent: 80,
                              addAutomaticKeepAlives: false,
                              addRepaintBoundaries: false,
                              itemBuilder: (context, index) {
                                final item = (largeUnmatched && query.isEmpty)
                                    ? _searchItems[index]
                                    : _displayItemAt(index);
                                return _buildSearchRow(item, index);
                              },
                            ),
                          ),
                        ],
                      ),
          ),

          // Bottom Navigation Bar
          ScanBottomBar(
            onSave: () {},
            onList: () {},
            onScan: _toggleScanning,
            onGscan: () {},
            onReset: _resetSearch,
            isScanning: _isScanning,
            isScreen: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow(SearchItem item, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: _selectedSearchType == 'Order' && _listKey != 'unmatchedItems'
            ? [
                _buildDataCell('${index + 1}', 1),
                _buildDataCell(item.rfid, 2),
                _buildProgressCell(item.proximityPercent, 3),
                _buildDataCell('${item.proximityPercent}%', 1),
              ]
            : [
                _buildDataCell('${index + 1}', 1),
                _buildDataCell(item.rfid, 2),
                _buildDataCell(item.itemCode, 2),
                _buildProgressCell(item.proximityPercent, 3),
                _buildDataCell('${item.proximityPercent}%', 1),
              ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AppFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDataCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text.isNotEmpty ? text : '-',
        style: AppFonts.poppins(fontSize: 11, color: Colors.black87),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildProgressCell(int proximity, int flex) {
    final value = proximity / 100.0;
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(getColorByPercentage(proximity)),
          ),
        ),
      ),
    );
  }
}
