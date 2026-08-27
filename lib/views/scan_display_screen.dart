import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:rfid_flutter/utils/app_fonts.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../viewmodels/product_view_model.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/settings_view_model.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../services/email_service.dart';
import '../services/session_lifecycle.dart';
import '../utils/product_image.dart';
import '../utils/tray_scan_auto_stop.dart';
import 'search_screen.dart';
import 'widgets/scan_bottom_bar.dart';
import 'widgets/scan_branch_counter_dialog.dart';
import '../models/wholesale_master.dart';

String _normalizeInventoryScanKey(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.toUpperCase();
  if (s.contains(' ')) s = s.replaceAll(' ', '');
  return s;
}

class _GroupBucket {
  _GroupBucket(this.label);
  final String label;
  final List<ScannedBulkItem> items = [];
  int matchedQty = 0;
  double totalWt = 0;
  double matchedWt = 0;
}

class ScannedBulkItem {
  final BulkItem originalBulkItem;
  String currentScannedStatus; // 'Matched' or 'Unmatched'
  List<String>? _matchKeys;
  double? _parsedGrossWt;

  ScannedBulkItem(this.originalBulkItem, [this.currentScannedStatus = 'Unmatched']);

  String get category => originalBulkItem.category;
  String get productName => originalBulkItem.productName;
  String get design => originalBulkItem.design;
  String get epc => originalBulkItem.epc;
  String get rfid => originalBulkItem.rfid;
  String get itemCode => originalBulkItem.itemCode;
  String get grossWeight => originalBulkItem.grossWeight;
  String get netWeight => originalBulkItem.netWeight;
  String get counterName => originalBulkItem.counterName;
  String get boxName => originalBulkItem.boxName;
  String get branchName => originalBulkItem.branchName;
  String get branchType => originalBulkItem.branchType;
  String get purity => originalBulkItem.purity;
  int get counterId => originalBulkItem.counterId;
  int get categoryId => originalBulkItem.categoryId;
  int get productId => originalBulkItem.productId;
  int get designId => originalBulkItem.designId;
  int get branchId => originalBulkItem.branchId;

  List<String> get matchKeys => _matchKeys ??= _computeMatchKeys();
  double get parsedGrossWt =>
      _parsedGrossWt ??= double.tryParse(grossWeight) ?? 0.0;

  List<String> _computeMatchKeys() {
    final keys = <String>{};
    void addKey(String raw) {
      final v = _normalizeInventoryScanKey(raw);
      if (v.isEmpty) return;
      keys.add(v);
      final hash = v.indexOf('#');
      if (hash > 0) keys.add(v.substring(0, hash));
    }

    addKey(epc);
    addKey(rfid);
    return keys.toList(growable: false);
  }

  static ScannedBulkItem unlabelled(String epc) {
    return ScannedBulkItem(
      BulkItem(
        bulkItemId: 0,
        productName: 'Unlabelled Item',
        itemCode: '',
        rfid: epc,
        grossWeight: '0.000',
        stoneWeight: '0.000',
        diamondWeight: '0.000',
        netWeight: '0.000',
        category: 'Unlabelled',
        design: 'Unlabelled',
        purity: '',
        makingPerGram: '',
        makingPercent: '',
        fixMaking: '',
        fixWastage: '',
        stoneAmount: '',
        diamondAmount: '',
        sku: '',
        epc: epc,
        vendor: '',
        tid: '',
        box: '',
        designCode: '',
        productCode: '',
        imageUrl: '',
        totalQty: 1,
        pcs: 1,
        matchedPcs: 1,
        totalGwt: 0.0,
        matchGwt: 0.0,
        totalStoneWt: 0.0,
        matchStoneWt: 0.0,
        totalNetWt: 0.0,
        matchNetWt: 0.0,
        unmatchedQty: 0,
        matchedQty: 1,
        unmatchedGrossWt: 0.0,
        mrp: 0.0,
        counterName: '',
        counterId: 0,
        boxId: 0,
        boxName: '',
        branchId: 0,
        branchName: '',
        packetId: 0,
        packetName: '',
        scannedStatus: 'Matched',
        categoryId: 0,
        productId: 0,
        branchType: '',
        designId: 0,
        isScanned: 1,
        totalWt: 0.0,
        categoryWt: '',
        skuId: 0,
        purityId: 0,
        status: '',
      ),
      'Matched',
    );
  }
}

class ScanDisplayScreen extends StatefulWidget {
  const ScanDisplayScreen({super.key});

  @override
  State<ScanDisplayScreen> createState() => _ScanDisplayScreenState();
}

class _ScanDisplayScreenState extends State<ScanDisplayScreen> {
  String _filterType = '';
  String _filterValue = '';
  bool _isInit = false;
  bool _isLoadingItems = false;
  bool _isSaving = false;

  List<ScannedBulkItem> _scannedItems = [];
  
  // Drill-down states
  String _currentLevel = 'Category'; // 'Category', 'Product', 'Design', 'DesignItems'
  String? _selectedCategory;
  String? _selectedProduct;
  String? _selectedDesign;
  final List<String> _selectedCategories = [];
  final List<String> _selectedProducts = [];
  final List<String> _selectedDesigns = [];

  // Selected tab menu
  String _selectedMenu = 'ALL'; // 'ALL', 'MATCHED', 'UNMATCHED', 'UNLABELLED'

  // RFID scan states
  final RfidService _rfidService = RfidService();
  StreamSubscription? _tagsSubscription;
  StreamSubscription? _triggerSubscription;
  bool _isScanning = false;
  /// Blocks re-entrant start while 10k EPC prep / hardware handoff is in flight.
  bool _scanStartInProgress = false;
  /// After user taps Stop with unmatched items left — bottom button shows Resume.
  bool _showResumeOnScanButton = false;
  int _selectedPower = 30; // Default power level
  /// Scope size / matched count for O(1) auto-stop on large catalogs.
  int _scanScopeItemCount = 0;
  int _scanMatchedItemCount = 0;
  RfidDeviceAssignment? _sessionLocation;
  bool _locationPromptOpen = false;

  // Drawer / overlay menu and unlabelled items
  bool _showMenu = false;
  final List<String> _unlabelledEpcs = [];
  final Set<String> _unlabelledEpcSet = {};
  final Map<String, ScannedBulkItem> _unlabelledItemCache = {};

  // Search filter
  bool _showSearchInput = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Fast scan lookup — mirrors Kotlin filteredDbEpcSet + matchedEpcSet
  final Map<String, int> _epcToMasterIndex = {};
  final Set<String> _matchedEpcSet = {};
  Set<String> _filteredDbEpcSet = {};
  bool _lookupMapsReady = false;
  int _lastScanUiUpdateMs = 0;
  int _lastTriggerMs = 0;
  int _lastBeepMs = 0;
  int _scopeUnmatchedRemaining = 0;
  int _allUnmatchedCount = 0;
  bool _needsAutoStopCheck = false;
  Timer? _scanUiFlushTimer;
  final TrayInventoryScanSession _trayScanSession = TrayInventoryScanSession();

  List<ScannedBulkItem>? _cachedFilteredItems;
  List<_GroupBucket>? _cachedGroupedBuckets;
  int _cachedViewHash = 0;
  int _cachedMatchedCount = 0;
  int _cachedTotalCount = 0;
  double _cachedTotalGrossWt = 0;
  double _cachedTotalMatchedWt = 0;

  int _matchedCount = 0;
  double _totalGrossWt = 0.0;
  double _totalMatchedWt = 0.0;
  int _lastListRefreshMs = 0;

  @override
  void initState() {
    super.initState();
    _selectedPower = context.read<PrefService>().inventoryPower.clamp(1, 30);
    _rfidService.preWarmReader();
    _rfidService.clearSearchTags();
    _tagsSubscription = _rfidService.tagsStream.listen(_onTagScanned);
    // Subscribe to physical trigger key presses
    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      _toggleScanning();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _filterType = args['filterType'] as String? ?? '';
        _filterValue = args['filterValue'] as String? ?? '';
      }
      _isInit = true;
      _isLoadingItems = true;
      // Paint full screen shell first, then load data (matches Jetpack).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadItems();
      });
    }
  }

  @override
  void dispose() {
    _tagsSubscription?.cancel();
    _triggerSubscription?.cancel();
    _scanUiFlushTimer?.cancel();
    _rfidService.stopScanning();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoadingItems = true);

    final viewModel = Provider.of<ProductViewModel>(context, listen: false);
    final String? filterType =
        _filterType == 'Scan Display' ? null : _filterType;
    final String? filterValue =
        _filterType == 'Scan Display' ? null : _filterValue;

    final list = await viewModel.loadScanDisplayItems(
      filterType: filterType,
      filterValue: filterValue,
      onProgress: (loaded, total) {
        // Keep splash/spinner responsive while large catalogs load.
        if (!mounted || total <= 0) return;
        if (loaded == total || loaded % 4000 == 0) {
          // Avoid setState every page — only tick occasionally.
        }
      },
    );

    if (!mounted) return;

    // Build scanned wrappers in chunks so we don't freeze on huge lists.
    final scanned = <ScannedBulkItem>[];
    const chunk = 2500;
    for (var i = 0; i < list.length; i += chunk) {
      final end = (i + chunk < list.length) ? i + chunk : list.length;
      for (var j = i; j < end; j++) {
        scanned.add(ScannedBulkItem(list[j], 'Unmatched'));
      }
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }

    setState(() {
      _scannedItems = scanned;
      _isLoadingItems = false;
      _lookupMapsReady = false;
      _allUnmatchedCount = scanned.length;
      _recalculateScopeCounts();
      _refreshDisplayCache(forceListRefresh: true);
    });

    scheduleMicrotask(() async {
      if (!mounted) return;
      await _buildLookupMapsChunked();
      if (!mounted) return;
      await _setFilteredItemsForScanChunked();
      if (!mounted) return;
      // Warm UART while user reviews the list — first Scan tap starts faster.
      unawaited(_rfidService.prepareForScan());
    });
  }

  List<String> _matchKeysForItem(ScannedBulkItem item) => item.matchKeys;

  String _statusForItem(ScannedBulkItem item) {
    for (final key in _matchKeysForItem(item)) {
      if (_matchedEpcSet.contains(key)) return 'Matched';
    }
    return 'Unmatched';
  }

  void _registerMatchForItem(ScannedBulkItem item, String scannedTag) {
    final wasMatched = item.currentScannedStatus == 'Matched';
    _matchedEpcSet.add(_normalizeInventoryScanKey(scannedTag));
    for (final key in item.matchKeys) {
      _matchedEpcSet.add(key);
    }
    if (!wasMatched) {
      item.currentScannedStatus = 'Matched';
      _matchedCount++;
      _totalMatchedWt += item.parsedGrossWt;
      if (_scopeUnmatchedRemaining > 0) _scopeUnmatchedRemaining--;
      if (_allUnmatchedCount > 0) _allUnmatchedCount--;
      _needsAutoStopCheck = true;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastBeepMs >= 40) {
        _lastBeepMs = now;
        unawaited(_rfidService.playBeep());
      }
    }
  }

  void _syncItemStatusesFromMatchedSet() {
    for (final item in _scannedItems) {
      item.currentScannedStatus = _statusForItem(item);
    }
  }

  /// Full status sync is O(n); avoid on every tag tick when catalog is large.
  void _syncItemStatusesFromMatchedSetChunked() {
    if (_scannedItems.length <= 2500) {
      _syncItemStatusesFromMatchedSet();
      return;
    }
    // Large catalog: _registerMatchForItem already sets currentScannedStatus.
    // Skipping O(n) walks keeps the UART inventory session alive under 10k load.
  }

  void _buildLookupMaps() {
    _epcToMasterIndex.clear();
    for (int i = 0; i < _scannedItems.length; i++) {
      for (final key in _matchKeysForItem(_scannedItems[i])) {
        _epcToMasterIndex[key] = i;
      }
    }
    _lookupMapsReady = true;
  }

  Future<void> _buildLookupMapsChunked() async {
    _epcToMasterIndex.clear();
    const chunk = 2000;
    for (int i = 0; i < _scannedItems.length; i++) {
      for (final key in _matchKeysForItem(_scannedItems[i])) {
        _epcToMasterIndex[key] = i;
      }
      if (i > 0 && i % chunk == 0) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }
    _lookupMapsReady = true;
  }

  /// Same as Kotlin setFilteredItems(displayItems) — scope tag keys for matching.
  void _setFilteredItemsForScan([List<ScannedBulkItem>? scopeItems]) {
    _filteredDbEpcSet = {};
    final scope = scopeItems ?? _getDisplayScopeItems();
    for (final item in scope) {
      for (final key in _matchKeysForItem(item)) {
        _filteredDbEpcSet.add(key);
      }
    }
  }

  Future<void> _setFilteredItemsForScanChunked([List<ScannedBulkItem>? scopeItems]) async {
    // Build into a new set, then swap — never clear the live set first
    // (that raced with scan start and briefly emptied match keys).
    final next = <String>{};
    final scope = scopeItems ?? _getDisplayScopeItems();
    const chunk = 2000;
    for (var i = 0; i < scope.length; i++) {
      for (final key in _matchKeysForItem(scope[i])) {
        next.add(key);
      }
      if (i > 0 && i % chunk == 0) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }
    _filteredDbEpcSet = next;
  }

  int _viewStateHash() {
    return Object.hash(
      _currentLevel,
      _selectedMenu,
      _searchQuery,
      _selectedCategory,
      _selectedProduct,
      _selectedDesign,
      _selectedCategories.length,
      _selectedProducts.length,
      _selectedDesigns.length,
      _matchedEpcSet.length,
      _scannedItems.length,
    );
  }

  void _recountScopeUnmatched() {
    final scope = _getDisplayScopeItems();
    var n = 0;
    for (final item in scope) {
      if (item.currentScannedStatus != 'Matched') n++;
    }
    _scopeUnmatchedRemaining = n;
  }

  void _recalculateScopeCounts() {
    final scope = _selectedMenu == 'UNLABELLED' ? _getFilteredScopeItems() : _getNavScopeItems();

    int matched = 0;
    double totalWt = 0.0;
    double matchedWt = 0.0;

    for (final item in scope) {
      final gw = item.parsedGrossWt;
      totalWt += gw;
      if (item.currentScannedStatus == 'Matched') {
        matched++;
        matchedWt += gw;
      }
    }

    _matchedCount = matched;
    _totalGrossWt = totalWt;
    _totalMatchedWt = matchedWt;
    _cachedTotalCount = scope.length;
    if (_selectedMenu != 'UNLABELLED') {
      _scopeUnmatchedRemaining = scope.length - matched;
    }
  }

  void _refreshDisplayCache({bool forceListRefresh = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastListRefreshMs;
    final n = _scannedItems.length;
    final detailTab = _selectedMenu == 'UNMATCHED' ||
        _selectedMenu == 'MATCHED' ||
        _selectedMenu == 'UNLABELLED' ||
        _currentLevel == 'DesignItems';
    final listInterval = !_isScanning
        ? 0
        : (detailTab ? (n > 20000 ? 450 : 350) : (n > 20000 ? 1200 : 1000));
    final needListRefresh = forceListRefresh ||
        !_isScanning ||
        elapsed >= listInterval ||
        _cachedFilteredItems == null;

    if (needListRefresh) {
      _lastListRefreshMs = now;
      final filteredItems = _getFilteredScopeItems();
      _cachedFilteredItems = filteredItems;
      _cachedGroupedBuckets = _getGroupedBuckets(filteredItems);
      _cachedViewHash = _viewStateHash();
    }

    _cachedMatchedCount = _matchedCount;
    _cachedTotalGrossWt = _totalGrossWt;
    _cachedTotalMatchedWt = _totalMatchedWt;
  }

  void _ensureDisplayCache() {
    final hash = _viewStateHash();
    if (_cachedFilteredItems == null ||
        _cachedGroupedBuckets == null ||
        hash != _cachedViewHash) {
      _recalculateScopeCounts();
      _refreshDisplayCache(forceListRefresh: true);
    }
  }

  void _scheduleScanUiUpdate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = _scannedItems.length;
    final minInterval = n > 20000 ? 280 : (n > 2500 ? 200 : 80);
    if (now - _lastScanUiUpdateMs >= minInterval) {
      _lastScanUiUpdateMs = now;
      _scanUiFlushTimer?.cancel();
      _scanUiFlushTimer = null;
      _syncItemStatusesFromMatchedSetChunked();
      _refreshDisplayCache();
      if (mounted) setState(() {});
      _checkAutoStopScan();
    } else {
      _scanUiFlushTimer ??= Timer(
        Duration(milliseconds: (minInterval - (now - _lastScanUiUpdateMs)).clamp(1, minInterval)),
        () {
          _scanUiFlushTimer = null;
          _lastScanUiUpdateMs = DateTime.now().millisecondsSinceEpoch;
          _syncItemStatusesFromMatchedSetChunked();
          _refreshDisplayCache();
          if (mounted) setState(() {});
          _checkAutoStopScan();
        },
      );
    }
  }

  void _checkAutoStopScan() {
    if (!_isScanning) return;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    // Tray: stop once every tag physically on the tray is matched (not full list).
    if (_rfidService.trayReaderActive) {
      if (_trayScanSession.shouldStop(_matchedEpcSet)) {
        _stopScanning();
      }
      return;
    }

    if (!_needsAutoStopCheck) return;
    if (_scopeUnmatchedRemaining > 0) {
      _needsAutoStopCheck = false;
      return;
    }
    _needsAutoStopCheck = false;
    if (_scannedItems.isEmpty) return;

    _stopScanning();
    _showToast(context.sRead.allItemsMatchedScanStopped);
  }

  // Handle drill-down back press
  Future<bool> _handleBackPress() async {
    if (_showMenu) {
      setState(() {
        _showMenu = false;
      });
      return false;
    }
    if (_showSearchInput) {
      setState(() {
        _showSearchInput = false;
        _searchQuery = '';
        _searchController.clear();
      });
      return false;
    }
    if (_currentLevel == 'DesignItems') {
      setState(() {
        _currentLevel = 'Design';
        _selectedDesign = null;
        _selectedDesigns.clear();
      });
      return false;
    } else if (_currentLevel == 'Design') {
      setState(() {
        _currentLevel = 'Product';
        _selectedProduct = null;
        _selectedProducts.clear();
      });
      return false;
    } else if (_currentLevel == 'Product') {
      setState(() {
        _currentLevel = 'Category';
        _selectedCategory = null;
        _selectedCategories.clear();
      });
      return false;
    }

    if (_selectedMenu != 'ALL') {
      setState(() {
        _selectedMenu = 'ALL';
        _currentLevel = 'Category';
        _selectedCategory = null;
        _selectedProduct = null;
        _selectedDesign = null;
      });
      return false;
    }

    _stopScanning();
    return true;
  }

  void _onTagScanned(String tag) {
    try {
      // Only handle tags while this screen owns the scan session.
      if (!_isScanning) return;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;

      final scannedEpc = _normalizeInventoryScanKey(tag);
      if (scannedEpc.isEmpty) return;

      if (_matchedEpcSet.contains(scannedEpc)) {
        if (_rfidService.trayReaderActive && _filteredDbEpcSet.contains(scannedEpc)) {
          _trayScanSession.recordInScope(scannedEpc, _filteredDbEpcSet);
          _scheduleScanUiUpdate();
        } else if (_scopeUnmatchedRemaining <= 0 &&
            _scannedItems.isNotEmpty &&
            _selectedMenu != 'UNLABELLED') {
          _needsAutoStopCheck = true;
          _checkAutoStopScan();
        }
        return;
      }

      final mapsWarming = !_lookupMapsReady ||
          (_filteredDbEpcSet.isEmpty &&
              _scannedItems.isNotEmpty &&
              _selectedMenu != 'UNLABELLED');
      final inScope = _filteredDbEpcSet.contains(scannedEpc);
      final masterIndex = _epcToMasterIndex[scannedEpc];

      if (inScope || (mapsWarming && masterIndex != null)) {
        if (_rfidService.trayReaderActive) {
          _trayScanSession.recordInScope(scannedEpc, _filteredDbEpcSet);
        }
        if (masterIndex != null && masterIndex < _scannedItems.length) {
          _registerMatchForItem(_scannedItems[masterIndex], scannedEpc);
        } else {
          _matchedEpcSet.add(scannedEpc);
        }
        _scheduleScanUiUpdate();
        return;
      }

      // Don't classify unknown tags as unlabelled until lookup maps are ready.
      if (mapsWarming) return;

      if (_unlabelledEpcSet.length >= 20000) return;
      if (_unlabelledEpcSet.add(scannedEpc)) {
        _unlabelledEpcs.add(scannedEpc);
        if (_scopeUnmatchedRemaining <= 0 && _scannedItems.isNotEmpty) {
          _needsAutoStopCheck = true;
        }
        _scheduleScanUiUpdate();
      }
    } catch (e, st) {
      debugPrint('Inventory tag handler: $e\n$st');
    }
  }

  void _toggleScanning() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final debounceMs = _scanStartInProgress ? 800 : 300;
    if (now - _lastTriggerMs < debounceMs) return;
    _lastTriggerMs = now;

    if (_scanStartInProgress) return;
    if (_isScanning) {
      _stopScanning(fromUser: true);
    } else {
      unawaited(_startScanningAfterLocation());
    }
  }

  Future<void> _startScanningAfterLocation() async {
    if (!await _ensureBranchCounterForWholesale()) return;
    _startScanning();
  }

  Future<bool> _ensureBranchCounterForWholesale() async {
    final pref = context.read<PrefService>();
    if (!pref.isWholesaleLoginUser()) return true;
    final existing = _sessionLocation;
    if (existing != null && existing.isValid) return true;
    if (_locationPromptOpen) return false;
    _locationPromptOpen = true;
    try {
      final picked = await showScanBranchCounterDialog(
        context: context,
        initial: existing ??
            (pref.getWholesaleAssignments().isNotEmpty
                ? pref.getWholesaleAssignments().first
                : null),
      );
      if (picked == null) return false;
      _sessionLocation = picked;
      return true;
    } finally {
      _locationPromptOpen = false;
    }
  }

  /// Sparkle-style inventory start: claim UI + start UART immediately.
  /// Never walk/rebuild ~10k rows on the tap path (that caused start failures).
  void _startScanning() async {
    if (_isScanning || _scanStartInProgress) return;
    if (_isLoadingItems) {
      _showToast(context.sRead.pleaseWaitItemsLoading);
      return;
    }
    if (_scannedItems.isEmpty && _selectedMenu != 'UNLABELLED') {
      _showToast(context.sRead.noItemsInCurrentScope);
      return;
    }

    _scanStartInProgress = true;
    // Claim session immediately so trigger cannot double-start.
    if (mounted) setState(() => _isScanning = true);
    _trayScanSession.reset();
    _needsAutoStopCheck = false;
    _recountScopeUnmatched();

    try {
      if (_selectedMenu == 'UNLABELLED') {
        _filteredDbEpcSet = {};
      } else if (_filteredDbEpcSet.isEmpty) {
        // Warm keys in background — do not block UART start.
        unawaited(_setFilteredItemsForScanChunked());
      }

      // Lean inventory start (retries inside service). No error toast on failure.
      final started = await _rfidService.startInventoryScanning(
        power: _selectedPower,
      );

      if (!mounted) return;
      if (!started) {
        setState(() => _isScanning = false);
        await _rfidService.stopInventorySound();
        await _rfidService.haltScan();
      }
    } finally {
      _scanStartInProgress = false;
    }
  }

  void _stopScanning({bool fromUser = false}) async {
    if (!_isScanning && !_scanStartInProgress) return;
    _scanStartInProgress = false;
    _trayScanSession.reset();
    await _rfidService.stopScanning();
    await _rfidService.haltScan();
    _scanUiFlushTimer?.cancel();
    _scanUiFlushTimer = null;
    // Full reconcile once on stop (not per-tag) so save/resume stay accurate.
    _syncItemStatusesFromMatchedSet();
    var unmatchedLeft = 0;
    for (final item in _scannedItems) {
      if (item.currentScannedStatus != 'Matched') unmatchedLeft++;
    }
    _allUnmatchedCount = unmatchedLeft;
    _recountScopeUnmatched();
    final incomplete = fromUser && _scannedItems.isNotEmpty && unmatchedLeft > 0;

    if (mounted) {
      setState(() {
        _isScanning = false;
        // User Stop mid-session → show Resume; auto/system stop → Scan.
        _showResumeOnScanButton = incomplete;
        _recalculateScopeCounts();
        _refreshDisplayCache(forceListRefresh: true);
      });
    }
  }

  void _resetScanning() {
    _stopScanning();
    setState(() {
      _showResumeOnScanButton = false;
      _matchedEpcSet.clear();
      for (var item in _scannedItems) {
        item.currentScannedStatus = 'Unmatched';
      }
      _unlabelledEpcs.clear();
      _unlabelledEpcSet.clear();
      _unlabelledItemCache.clear();
      _allUnmatchedCount = _scannedItems.length;
      _selectedCategories.clear();
      _selectedProducts.clear();
      _selectedDesigns.clear();
      _selectedMenu = 'ALL';
      _currentLevel = 'Category';
      _selectedCategory = null;
      _selectedProduct = null;
      _selectedDesign = null;
      _searchQuery = '';
      _showSearchInput = false;
      _searchController.clear();
    });
    _buildLookupMaps();
    _setFilteredItemsForScan();
    _recalculateScopeCounts();
    _refreshDisplayCache(forceListRefresh: true);
    _showToast(context.sRead.scanResetSuccessful);
  }

  void _resumeScan() {
    setState(() {
      _matchedEpcSet.clear();
      for (var item in _scannedItems) {
        if (item.originalBulkItem.isScanned == 1) {
          for (final key in _matchKeysForItem(item)) {
            _matchedEpcSet.add(key);
          }
        }
      }
      _syncItemStatusesFromMatchedSet();
      var unmatched = 0;
      for (final item in _scannedItems) {
        if (item.currentScannedStatus != 'Matched') unmatched++;
      }
      _allUnmatchedCount = unmatched;
      _selectedMenu = 'ALL';
      _currentLevel = 'Category';
      _selectedCategory = null;
      _selectedProduct = null;
      _selectedDesign = null;
    });
    _recalculateScopeCounts();
    _refreshDisplayCache(forceListRefresh: true);
    _showToast(context.sRead.previousScanRestored);
  }

  void _saveScanResults() async {
    _stopScanning();
    _syncItemStatusesFromMatchedSet();
    setState(() => _isSaving = true);

    final viewModel = Provider.of<ProductViewModel>(context, listen: false);
    final dashboardViewModel = Provider.of<DashboardViewModel>(context, listen: false);
    final employee = dashboardViewModel.employee;

    if (employee == null || employee.clientCode == null) {
      setState(() => _isSaving = false);
      _showToast(context.sRead.errorSessionExpired);
      unawaited(SessionLifecycle.instance.forceLogoutToLogin());
      return;
    }

    try {
      // Single pass: local DB rows + API payload (Sparkle buildItemsForUpload).
      final finalItems = <BulkItem>[];
      final uploadItemsPayload = <Map<String, dynamic>>[];
      final seenKeys = <String>{};

      for (var i = 0; i < _scannedItems.length; i++) {
        final item = _scannedItems[i];
        final isMatched = _matchKeysForItem(item)
            .any((key) => _matchedEpcSet.contains(key));

        final map = item.originalBulkItem.toMap();
        map['isScanned'] = isMatched ? 1 : 0;
        map['scannedStatus'] = isMatched ? 'Matched' : 'Unmatched';
        finalItems.add(BulkItem.fromMap(map));

        final code = item.itemCode.trim();
        if (code.isEmpty) continue;
        final dedupeKey = (item.epc.trim().isNotEmpty
                ? item.epc
                : code)
            .trim()
            .toUpperCase();
        if (dedupeKey.isEmpty || !seenKeys.add(dedupeKey)) continue;

        final grossWt = double.tryParse(item.grossWeight) ?? 0.0;
        final netWt = double.tryParse(item.netWeight) ?? 0.0;
        uploadItemsPayload.add({
          'ItemCode': code,
          'Status': isMatched ? 'match' : 'unmatch',
          'GrossWeight': grossWt,
          'NetWeight': netWt,
          'Quantity': 1,
          'CounterName': item.counterName,
          'CategoryName': item.category,
          'ProductName': item.productName,
          'DesignName': item.design,
          'PurityName': item.purity,
          'CompanyName': '',
          'BranchName': item.branchName,
          'CounterId': item.counterId,
          'CategoryId': item.categoryId,
          'ProductId': item.productId,
          'DesignId': item.designId,
          'PurityId': 0,
          'CompanyId': 0,
          'BranchId': item.branchId,
        });

        // Keep UI responsive while building large payloads (2–5L).
        if (i > 0 && i % 4000 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (!mounted) return;
        }
      }

      // Local SQLite + file/API upload in parallel (same end result as Sparkle).
      final uploadFuture = viewModel.uploadVerification(
        clientCode: employee.clientCode!,
        items: uploadItemsPayload,
      );
      unawaited(viewModel.saveScanResults(finalItems));
      final success = await uploadFuture;
    // 4. Call stock verification API
    String? deviceCode;
    if (pref.isWholesaleLoginUser()) {
      deviceCode = (await settingsVm.ensureDeviceId()).trim();
      if (!mounted) return;
      if (_sessionLocation == null || !_sessionLocation!.isValid) {
        if (!await _ensureBranchCounterForWholesale()) {
          if (mounted) setState(() => _isSaving = false);
          return;
        }
      }
    }
    if (!mounted) return;
    final location = _sessionLocation;
    final success = await viewModel.uploadVerification(
      clientCode: employee.clientCode!,
      items: uploadItemsPayload,
      counterId: location?.counterId,
      counterName: location?.counterName,
      branchId: location?.branchId,
      branchName: location?.branchName,
      deviceCode: deviceCode,
    );

      if (!mounted) return;
      setState(() => _isSaving = false);
    if (!mounted) return;
    setState(() => _isSaving = false);

      if (success) {
        _showResumeOnScanButton = false;
        _showToast(context.sRead.stockVerificationUploaded);
      } else {
        _showToast(
          context.sRead.verificationUploadFailed(viewModel.errorMessage ?? ''),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showToast(context.sRead.verificationUploadFailed(e.toString()));
    }
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



  Widget _buildMenuCard({
    required String title,
    required IconData icon,
    int? count,
    required VoidCallback onTap,
  }) {
    final displayText = count != null ? '$title ($count)' : title;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3053F0), Color(0xFFE82E5A)],
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Container(
          margin: const EdgeInsets.all(1.0), // Border width
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3.0),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: const Color(0xFF5231A7),
              ),
              const SizedBox(height: 4),
              Text(
                displayText,
                style: AppFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
                // Show full label inside this card (wrap below; no single-line clip).
                softWrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Navigation scope (drill-down + search) — mirrors Kotlin navFilteredItems / scannedItemsSequence base.
  List<ScannedBulkItem> _getNavScopeItems() {
    // Do NOT sync all item statuses here — with ~10k rows that blocks the UI
    // isolate and makes startScanning fail ("Failed to start RFID scanner").
    // Statuses are kept current by _scheduleScanUiUpdate / stop / save paths.
    var list = _scannedItems;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((i) {
        return i.productName.toLowerCase().contains(q) ||
            i.itemCode.toLowerCase().contains(q) ||
            i.epc.toLowerCase().contains(q) ||
            i.rfid.toLowerCase().contains(q);
      }).toList();
    }

    if (_selectedCategories.isNotEmpty) {
      list = list.where((i) => _selectedCategories.contains(i.category.trim())).toList();
    } else if (_selectedCategory != null) {
      list = list.where((i) => i.category.trim() == _selectedCategory!.trim()).toList();
    }
    if (_selectedProducts.isNotEmpty) {
      list = list.where((i) => _selectedProducts.contains(i.productName.trim())).toList();
    } else if (_selectedProduct != null) {
      list = list.where((i) => i.productName.trim() == _selectedProduct!.trim()).toList();
    }
    if (_selectedDesigns.isNotEmpty) {
      list = list.where((i) => _selectedDesigns.contains(i.design.trim())).toList();
    } else if (_selectedDesign != null) {
      list = list.where((i) => i.design.trim() == _selectedDesign!.trim()).toList();
    }

    return list;
  }

  /// Current visible list before tab filter — used when starting scan (Kotlin displayItems on ALL).
  List<ScannedBulkItem> _getDisplayScopeItems() => _getNavScopeItems();

  // Get active items taking tab, drill-down, and search query filters into account
  List<ScannedBulkItem> _getFilteredScopeItems() {
    if (_selectedMenu == 'UNLABELLED') {
      var list = _unlabelledEpcs
          .map((epc) => _unlabelledItemCache.putIfAbsent(
                epc,
                () => ScannedBulkItem.unlabelled(epc),
              ))
          .toList();

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        list = list.where((i) => i.epc.toLowerCase().contains(q)).toList();
      }
      return list;
    }

    var list = _getNavScopeItems();

    // Apply Tab Filter
    if (_selectedMenu == 'MATCHED') {
      list = list.where((i) => i.currentScannedStatus == 'Matched').toList();
    } else if (_selectedMenu == 'UNMATCHED') {
      list = list.where((i) => i.currentScannedStatus == 'Unmatched').toList();
    }

    return list;
  }

  // Helpers to get grouped rows at category, product or design levels
  List<_GroupBucket> _getGroupedBuckets(List<ScannedBulkItem> items) {
    final grouped = <String, _GroupBucket>{};
    for (final item in items) {
      String key = '';
      if (_currentLevel == 'Category') {
        key = item.category.isNotEmpty ? item.category : 'Unknown';
      } else if (_currentLevel == 'Product') {
        key = item.productName.isNotEmpty ? item.productName : 'Unknown';
      } else if (_currentLevel == 'Design') {
        key = item.design.isNotEmpty ? item.design : 'Unknown';
      }

      final bucket = grouped.putIfAbsent(key, () => _GroupBucket(key));
      bucket.items.add(item);
      final gw = item.parsedGrossWt;
      bucket.totalWt += gw;
      if (item.currentScannedStatus == 'Matched') {
        bucket.matchedQty++;
        bucket.matchedWt += gw;
      }
    }
    return grouped.values.toList(growable: false);
  }


  void _showDetailsDialog(BulkItem item) {
    // Kick off decode before dialog builds (inventory list has no row thumbs).
    ProductImage.warmUrls([item.imageUrl]);
    final s = context.sRead;
    showAppDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                s.itemDetails,
                style: AppFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 150,
                    height: 150,
                    color: Colors.grey[100],
                    child: ProductImage.fromBulkItem(
                      item,
                      iconSize: 48,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow(s.productName, item.productName),
                _buildInfoRow(s.itemCode, item.itemCode),
                _buildInfoRow(s.fieldRfidCode, item.rfid),
                _buildInfoRow(
                  s.colEpc,
                  item.tid.trim().isNotEmpty ? item.tid.trim() : item.epc,
                ),
                _buildInfoRow(s.lblGrossWt, item.grossWeight),
                _buildInfoRow(s.lblNetWt, item.netWeight),
                _buildInfoRow(s.fieldCategory, item.category),
                _buildInfoRow(s.fieldDesign, item.design),
                _buildInfoRow(s.fieldPurity, item.purity),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: AppFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value.isNotEmpty ? value : '-',
              style: AppFonts.poppins(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  String _generateCsvString() {
    final buffer = StringBuffer();
    
    void writeRow(List<dynamic> values) {
      final line = values.map((v) {
        final valStr = v?.toString() ?? '-';
        final clean = valStr.replaceAll('"', '""');
        return '"$clean"';
      }).join(',');
      buffer.writeln(line);
    }

    // 1. ALL ITEMS SUMMARY
    writeRow(["All Items Summary"]);
    writeRow([
      "Counter Name", "Category", "Product",
      "Total Qty", "Match Qty", "Unmatch Qty",
      "Total G.Wt", "Match G.Wt", "Unmatch G.Wt"
    ]);

    final groups = <String, Map<String, dynamic>>{};
    for (var item in _scannedItems) {
      final key = "${item.counterName}_${item.category}_${item.productName}";
      final g = groups.putIfAbsent(key, () => {
        'counter': item.counterName,
        'category': item.category,
        'product': item.productName,
        'totalQty': 0,
        'matchQty': 0,
        'totalGwt': 0.0,
        'matchGwt': 0.0,
      });
      g['totalQty'] += 1;
      final double gwt = double.tryParse(item.grossWeight) ?? 0.0;
      g['totalGwt'] += gwt;
      if (item.currentScannedStatus == 'Matched') {
        g['matchQty'] += 1;
        g['matchGwt'] += gwt;
      }
    }

    int grandTotalQty = 0;
    int grandMatchQty = 0;
    int grandUnmatchQty = 0;
    double grandTotalGwt = 0.0;
    double grandMatchGwt = 0.0;
    double grandUnmatchGwt = 0.0;

    groups.forEach((key, g) {
      final int tQty = g['totalQty'];
      final int mQty = g['matchQty'];
      final int uQty = tQty - mQty;
      final double tGwt = g['totalGwt'];
      final double mGwt = g['matchGwt'];
      final double uGwt = tGwt - mGwt;

      writeRow([
        g['counter'], g['category'], g['product'],
        tQty, mQty, uQty,
        tGwt.toStringAsFixed(3),
        mGwt.toStringAsFixed(3),
        uGwt.toStringAsFixed(3)
      ]);

      grandTotalQty += tQty;
      grandMatchQty += mQty;
      grandUnmatchQty += uQty;
      grandTotalGwt += tGwt;
      grandMatchGwt += mGwt;
      grandUnmatchGwt += uGwt;
    });

    writeRow([
      "TOTAL", "", "",
      grandTotalQty, grandMatchQty, grandUnmatchQty,
      grandTotalGwt.toStringAsFixed(3),
      grandMatchGwt.toStringAsFixed(3),
      grandUnmatchGwt.toStringAsFixed(3)
    ]);

    buffer.writeln();

    // 2. UNMATCHED ITEMS
    writeRow(["Unmatched Items"]);
    writeRow([
      "Counter Name", "Category", "Product", "Purity",
      "Barcode No", "Item Code", "Pieces",
      "Gross Wt", "Stone Wt", "Net Wt", "MRP", "Status"
    ]);

    for (var item in _scannedItems.where((i) => i.currentScannedStatus == 'Unmatched')) {
      writeRow([
        item.counterName, item.category, item.productName, item.purity,
        item.rfid, item.itemCode, item.originalBulkItem.pcs,
        item.grossWeight, item.originalBulkItem.stoneWeight, item.netWeight,
        item.originalBulkItem.mrp, "Not Found"
      ]);
    }

    buffer.writeln();

    // 3. MATCHED ITEMS
    writeRow(["Matched Items"]);
    writeRow([
      "Counter Name", "Category", "Product", "Purity",
      "Barcode No", "Item Code", "Pieces",
      "Gross Wt", "Stone Wt", "Net Wt", "MRP", "Status"
    ]);

    for (var item in _scannedItems.where((i) => i.currentScannedStatus == 'Matched')) {
      writeRow([
        item.counterName, item.category, item.productName, item.purity,
        item.rfid, item.itemCode, item.originalBulkItem.pcs,
        item.grossWeight, item.originalBulkItem.stoneWeight, item.netWeight,
        item.originalBulkItem.mrp, "Found"
      ]);
    }

    return buffer.toString();
  }

  void _showEmailReportDialog() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedEmails = prefs.getStringList('saved_emails') ?? [];
    
    if (!mounted) return;
    
    String? selectedEmail;
    String newEmail = '';
    bool isSending = false;
    final s = context.sRead;
    
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                s.sendReport,
                style: AppFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (savedEmails.isNotEmpty) ...[
                      Text(
                        s.savedEmails,
                        style: AppFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: savedEmails.length,
                          itemBuilder: (context, idx) {
                            final email = savedEmails[idx];
                            final isSelected = selectedEmail == email;
                            return InkWell(
                              onTap: isSending
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        selectedEmail = email;
                                        newEmail = email;
                                      });
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                color: isSelected ? Colors.grey[200] : Colors.transparent,
                                child: Text(
                                  email,
                                  style: AppFonts.poppins(fontSize: 13),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: TextEditingController(text: newEmail)..selection = TextSelection.fromPosition(TextPosition(offset: newEmail.length)),
                      enabled: !isSending,
                      decoration: InputDecoration(
                        labelText: s.enterEmailAddress,
                        labelStyle: AppFonts.poppins(fontSize: 13),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        newEmail = val;
                      },
                      style: AppFonts.poppins(fontSize: 13),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () {
                          Navigator.pop(context);
                        },
                  child: Text(s.cancel, style: AppFonts.poppins(color: Colors.grey[600])),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final emailToSend = newEmail.trim().isNotEmpty ? newEmail.trim() : (selectedEmail ?? '').trim();
                          if (emailToSend.isEmpty) {
                            _showToast(s.pleaseEnterOrSelectEmail);
                            return;
                          }
                          
                          // Simple regex validation
                          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                          if (!emailRegex.hasMatch(emailToSend)) {
                            _showToast(s.pleaseEnterValidEmail);
                            return;
                          }

                          final navigator = Navigator.of(context);
                          setDialogState(() {
                            isSending = true;
                          });

                          try {
                            // 1. Save email if new
                            if (newEmail.trim().isNotEmpty && !savedEmails.contains(newEmail.trim())) {
                              savedEmails.add(newEmail.trim());
                              await prefs.setStringList('saved_emails', savedEmails);
                            }

                            // 2. Generate CSV
                            final csvString = _generateCsvString();
                            final tempDir = await getTemporaryDirectory();
                            final file = File('${tempDir.path}/scan_report.csv');
                            await file.writeAsString(csvString);

                            // 3. Send email via Hostinger
                            final success = await EmailService.sendEmailWithAttachment(
                              toEmails: [emailToSend],
                              subject: s.inventoryScanReportSubject,
                              bodyHtml: s.reportEmailBody,
                              attachments: {'scan_report.csv': file},
                            );

                            if (success) {
                              _showToast(s.reportSentTo(emailToSend));
                            } else {
                              _showToast(s.failedToSendEmail);
                            }
                            navigator.pop();
                          } catch (e) {
                            _showToast(s.failedWithMessage(e.toString()));
                            setDialogState(() {
                              isSending = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5231A7),
                  ),
                  child: isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(s.send, style: AppFonts.poppins(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    _ensureDisplayCache();
    final filteredItems = _cachedFilteredItems!;
    final groupedBuckets = _cachedGroupedBuckets!;

    final totalCount = _cachedTotalCount;
    final matchedCount = _cachedMatchedCount;
    final unmatchedCount = totalCount - matchedCount;
    final totalGrossWt = _cachedTotalGrossWt;
    final totalMatchedWt = _cachedTotalMatchedWt;
    final totalUnmatchedWt = totalGrossWt - totalMatchedWt;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _handleBackPress();
        if (shouldPop) {
          navigator.pop();
        }
      },
      child: Scaffold(
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
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  if (await _handleBackPress()) {
                    navigator.pop();
                  }
                },
              ),
              title: _showSearchInput
                  ? TextField(
                      controller: _searchController,
                      style: AppFonts.poppins(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: s.searchProductRfidEpc,
                        hintStyle: AppFonts.poppins(color: Colors.white60),
                        border: InputBorder.none,
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      autofocus: true,
                    )
                  : Text(
                      _filterType == 'Scan Display'
                          ? s.scanDisplay
                          : (_filterValue.isNotEmpty
                              ? _filterValue.replaceAll('\u001F', ', ')
                              : s.inventory),
                      style: AppFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
              actions: [
                if (_showSearchInput)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _showSearchInput = false;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                  )
                else ...[
                  // White counter box showing selected power (1-30), same as Delivery Challan.
                  PopupMenuButton<int>(
                    tooltip: s.rfidPower,
                    color: Colors.white,
                    constraints: const BoxConstraints(maxHeight: 320, minWidth: 60),
                    onSelected: (val) {
                      setState(() => _selectedPower = val);
                      _rfidService.setPower(val);
                      context.read<PrefService>().savePower(PrefService.keyInventoryCount, val);
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
                ]
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            Column(
              children: [
                // Horizontal category dropdown filters (Category, Product, Design)
                _buildLevelFilters(),

                // Table Header row matching Compose dark grey
                _buildTableHeader(),

                // Scrollable group or details list
                Expanded(
                  child: _buildMainList(filteredItems, groupedBuckets),
                ),

                // Scanned summary info row matching compose
                _buildSummaryRow(
                  totalCount: totalCount,
                  matchedCount: matchedCount,
                  unmatchedCount: unmatchedCount,
                  totalGrossWt: totalGrossWt,
                  totalMatchedWt: totalMatchedWt,
                  totalUnmatchedWt: totalUnmatchedWt,
                ),

                // Bottom actions buttons matching ScanBottomBarInventory
                _buildBottomBar(),
              ],
            ),

            if (_showMenu)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _showMenu = false),
                  child: Container(
                    color: Colors.black54,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 60,
                          bottom: 70,
                          width: 180,
                          child: GestureDetector(
                            onTap: () {}, // Prevent dismissal when clicking menu body
                            child: Material(
                              elevation: 8,
                              color: Colors.white,
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(4),
                                bottomRight: Radius.circular(4),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      _buildMenuCard(
                                        title: s.matchedItems,
                                        icon: Icons.check_circle_outline,
                                        count: matchedCount,
                                        onTap: () {
                                          setState(() {
                                            _selectedMenu = 'MATCHED';
                                            _currentLevel = 'DesignItems';
                                            _showMenu = false;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      _buildMenuCard(
                                        title: s.unmatchedItems,
                                        icon: Icons.error_outline,
                                        count: unmatchedCount,
                                        onTap: () {
                                          setState(() {
                                            _selectedMenu = 'UNMATCHED';
                                            _currentLevel = 'DesignItems';
                                            _showMenu = false;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      _buildMenuCard(
                                        title: s.unlabelledItems,
                                        icon: Icons.label_off_outlined,
                                        count: _unlabelledEpcs.length,
                                        onTap: () {
                                          setState(() {
                                            _selectedMenu = 'UNLABELLED';
                                            _currentLevel = 'DesignItems';
                                            _showMenu = false;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      _buildMenuCard(
                                        title: s.resumeScan,
                                        icon: Icons.play_arrow_outlined,
                                        onTap: () {
                                          setState(() => _showMenu = false);
                                          _resumeScan();
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      _buildMenuCard(
                                        title: s.searchUnmatched,
                                        icon: Icons.search,
                                        count: unmatchedCount,
                                        onTap: () async {
                                          setState(() => _showMenu = false);
                                          final navigator = Navigator.of(context);
                                          if (_isScanning) {
                                            await _rfidService.stopScanning();
                                            await _rfidService.stopInventorySound();
                                            if (mounted) setState(() => _isScanning = false);
                                          }
                                          final catalog = UnmatchedSearchCatalog.instance;
                                          catalog.clear();
                                          for (var i = 0; i < _scannedItems.length; i++) {
                                            final item = _scannedItems[i];
                                            if (item.currentScannedStatus != 'Unmatched') {
                                              continue;
                                            }
                                            catalog.items.add(SearchItem(
                                              epc: item.epc,
                                              itemCode: item.itemCode,
                                              productName: item.productName,
                                              rfid: item.rfid,
                                              tid: item.originalBulkItem.tid,
                                              hex: item.originalBulkItem.box,
                                            ));
                                            if (i > 0 && i % 600 == 0) {
                                              await Future<void>.delayed(Duration.zero);
                                              if (!mounted) return;
                                            }
                                          }
                                          if (!mounted) return;
                                          navigator.pushNamed('/search', arguments: {
                                            'listKey': 'unmatchedItems',
                                            'items': unmatched,
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainList(
    List<ScannedBulkItem> filteredItems,
    List<_GroupBucket> groupedBuckets,
  ) {
    if (_isLoadingItems && _scannedItems.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF5231A7)),
      );
    }

    if (_scannedItems.isEmpty &&
        _unlabelledEpcs.isEmpty &&
        !_isLoadingItems) {
      return _buildEmptyState();
    }

    final showLoaderOverlay =
        (_isLoadingItems || _isSaving) && _scannedItems.isNotEmpty;

    return Stack(
      children: [
        ListView.builder(
          itemCount: _currentLevel == 'DesignItems' || _selectedMenu == 'UNLABELLED'
              ? filteredItems.length
              : groupedBuckets.length,
          itemBuilder: (context, index) {
            if (_currentLevel == 'DesignItems' || _selectedMenu == 'UNLABELLED') {
              final item = filteredItems[index];
              return _buildDesignItemRow(item);
            } else {
              return _buildGroupRow(groupedBuckets[index]);
            }
          },
        ),
        if (showLoaderOverlay)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF5231A7)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLevelFilters() {
    final s = context.s;
    final catLabel = _selectedCategories.isEmpty ? s.fieldCategory : _selectedCategories.join(', ');
    final prodLabel = _selectedProducts.isEmpty ? s.fieldProduct : _selectedProducts.join(', ');
    final designLabel = _selectedDesigns.isEmpty ? s.fieldDesign : _selectedDesigns.join(', ');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFilterButton(
            label: catLabel,
            onTap: () => _openFilterSelectionDialog('Category'),
          ),
          _buildFilterButton(
            label: prodLabel,
            onTap: () => _openFilterSelectionDialog('Product'),
          ),
          _buildFilterButton(
            label: designLabel,
            onTap: () => _openFilterSelectionDialog('Design'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton({required String label, required VoidCallback onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3053F0), Color(0xFFE82E5A)],
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(1), // Border width
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
            ),
            child: TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFilterSelectionDialog(String filterType) {
    final s = context.sRead;
    List<String> items = [];
    List<String> selected = [];

    final allCategories = _scannedItems
        .map((i) => i.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();

    final allProducts = _scannedItems
        .where((i) => _selectedCategories.isEmpty || _selectedCategories.contains(i.category.trim()))
        .map((i) => i.productName.trim())
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    final allDesigns = _scannedItems
        .where((i) => _selectedCategories.isEmpty || _selectedCategories.contains(i.category.trim()))
        .where((i) => _selectedProducts.isEmpty || _selectedProducts.contains(i.productName.trim()))
        .map((i) => i.design.trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();

    if (filterType == 'Category') {
      items = allCategories;
      selected = List.from(_selectedCategories);
    } else if (filterType == 'Product') {
      items = allProducts;
      selected = List.from(_selectedProducts);
    } else if (filterType == 'Design') {
      items = allDesigns;
      selected = List.from(_selectedDesigns);
    }

    final filterTypeLocal = filterType == 'Category'
        ? s.fieldCategory
        : (filterType == 'Product' ? s.fieldProduct : s.fieldDesign);

    showAppDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allSelected =
                items.isNotEmpty && selected.length == items.length;

            void toggleSelectAll(bool? checked) {
              setDialogState(() {
                if (checked == true) {
                  selected
                    ..clear()
                    ..addAll(items);
                } else {
                  selected.clear();
                }
              });
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(
                s.selectFilterType(filterTypeLocal),
                style: AppFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Select All — same idea as Inventory Counter/Box multi-select.
                    InkWell(
                      onTap: () => toggleSelectAll(!allSelected),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                activeColor: const Color(0xFF3053F0),
                                value: allSelected,
                                onChanged: toggleSelectAll,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.selectAll,
                                style: AppFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, idx) {
                          final item = items[idx];
                          final isChecked = selected.contains(item);
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isChecked) {
                                  selected.remove(item);
                                } else {
                                  selected.add(item);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      activeColor: const Color(0xFF3053F0),
                                      value: isChecked,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          if (val == true) {
                                            if (!selected.contains(item)) {
                                              selected.add(item);
                                            }
                                          } else {
                                            selected.remove(item);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            s.cancel.toUpperCase(),
                            style: AppFonts.poppins(
                              color: const Color(0xFFE82E5A),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              if (filterType == 'Category') {
                                _selectedCategories.clear();
                                _selectedCategories.addAll(selected);
                                _selectedProducts.clear();
                                _selectedDesigns.clear();
                                _currentLevel = 'Product';
                                _selectedCategory = _selectedCategories.isNotEmpty
                                    ? _selectedCategories.first
                                    : null;
                              } else if (filterType == 'Product') {
                                _selectedProducts.clear();
                                _selectedProducts.addAll(selected);
                                _selectedDesigns.clear();
                                _currentLevel = 'Design';
                                _selectedProduct = _selectedProducts.isNotEmpty
                                    ? _selectedProducts.first
                                    : null;
                              } else if (filterType == 'Design') {
                                _selectedDesigns.clear();
                                _selectedDesigns.addAll(selected);
                                _currentLevel = 'DesignItems';
                                _selectedDesign = _selectedDesigns.isNotEmpty
                                    ? _selectedDesigns.first
                                    : null;
                              }
                            });
                            _setFilteredItemsForScan();
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3053F0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            s.ok,
                            style: AppFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTableHeader() {
    final s = context.s;
    return Container(
      color: const Color(0xFF3B363E),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (_currentLevel == 'DesignItems' || _selectedMenu == 'UNLABELLED') ...[
            _buildHeaderCell(s.fieldDesign, 2.8),
            _buildHeaderCell(s.rfidNo, 1.8),
            _buildHeaderCell(s.itemcode, 1.7),
            _buildHeaderCell(s.colGrossWt, 1.7),
            _buildHeaderCell(s.status, 1.0, isCenter: true),
          ] else ...[
            _buildHeaderCell(
              _currentLevel == 'Category'
                  ? s.fieldCategory
                  : (_currentLevel == 'Product'
                      ? s.fieldProduct
                      : (_currentLevel == 'Design' ? s.fieldDesign : _currentLevel)),
              2,
            ),
            _buildHeaderCell(s.qty, 1),
            _buildHeaderCell(s.colGrossWt, 1.5),
            _buildHeaderCell(s.mQty, 1),
            _buildHeaderCell(s.mWt, 1.5),
            _buildHeaderCell(s.status, 1, isCenter: true),
          ]
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, double flex, {bool isCenter = false}) {
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Text(
        text,
        style: AppFonts.poppins(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        textAlign: isCenter ? TextAlign.center : TextAlign.start,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildGroupRow(_GroupBucket bucket) {
    final label = bucket.label;
    final qty = bucket.items.length;
    final grossWt = bucket.totalWt;
    final mQty = bucket.matchedQty;
    final mWt = bucket.matchedWt;

    final isMatched = qty > 0 && mQty == qty;

    return InkWell(
      onTap: () {
        setState(() {
          if (_currentLevel == 'Category') {
            _selectedCategory = label;
            _selectedCategories.clear();
            _selectedCategories.add(label);
            _selectedProducts.clear();
            _selectedDesigns.clear();
            _currentLevel = 'Product';
          } else if (_currentLevel == 'Product') {
            _selectedProduct = label;
            if (!_selectedProducts.contains(label)) {
              _selectedProducts.add(label);
            }
            _selectedDesigns.clear();
            _currentLevel = 'Design';
          } else if (_currentLevel == 'Design') {
            _selectedDesign = label;
            if (!_selectedDesigns.contains(label)) {
              _selectedDesigns.add(label);
            }
            _currentLevel = 'DesignItems';
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 20,
              child: Text(
                label,
                style: AppFonts.poppins(fontSize: 12, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 10,
              child: Text('$qty', style: AppFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 15,
              child: Text(grossWt.toStringAsFixed(3), style: AppFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 10,
              child: Text('$mQty', style: AppFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 15,
              child: Text(mWt.toStringAsFixed(3), style: AppFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 10,
              child: Center(
                child: Icon(
                  isMatched ? Icons.check_circle : Icons.cancel,
                  color: isMatched ? Colors.green : Colors.red,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesignItemRow(ScannedBulkItem item) {
    final double grossWt = item.parsedGrossWt;
    final isMatched = item.currentScannedStatus == 'Matched';

    return InkWell(
      onTap: () => _showDetailsDialog(item.originalBulkItem),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 36,
                height: 36,
                child: ColoredBox(
                  color: Colors.grey.shade100,
                  child: ProductImage.fromBulkItem(
                    item.originalBulkItem,
                    iconSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 28,
              child: Text(
                item.design.isNotEmpty ? item.design : '-',
                style: AppFonts.poppins(fontSize: 10.5, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 18,
              child: Text(
                item.rfid.isNotEmpty ? item.rfid : '-',
                style: AppFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 17,
              child: Text(
                item.itemCode.isNotEmpty ? item.itemCode : '-',
                style: AppFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 17,
              child: Text(
                grossWt.toStringAsFixed(3),
                style: AppFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
              ),
            ),
            Expanded(
              flex: 10,
              child: Center(
                child: Icon(
                  isMatched ? Icons.check_circle : Icons.cancel,
                  color: isMatched ? Colors.green : Colors.red,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow({
    required int totalCount,
    required int matchedCount,
    required int unmatchedCount,
    required double totalGrossWt,
    required double totalMatchedWt,
    required double totalUnmatchedWt,
  }) {
    final s = context.s;
    final showDesignSummary = _currentLevel == 'DesignItems' ||
                              _selectedMenu == 'UNLABELLED' ||
                              _selectedMenu == 'MATCHED' ||
                              _selectedMenu == 'UNMATCHED';

    return Container(
      color: const Color(0xFF3B363E),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: showDesignSummary
            ? [
                _buildSummaryCell(s.total, 2),
                _buildSummaryCell('$totalCount', 2),
                Expanded(
                  flex: 20,
                  child: Container(
                    padding: const EdgeInsets.only(left: 10, top: 3, bottom: 3),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${s.matchedItems[0]}:$matchedCount\n${s.unmatchedItems[0]}:$unmatchedCount',
                      style: AppFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        height: 1.1,
                      ),
                      maxLines: 2,
                    ),
                  ),
                ),
                _buildSummaryCell(totalGrossWt.toStringAsFixed(3), 2),
                _buildSummaryCell('', 1),
              ]
            : [
                _buildSummaryCell(s.total, 2),
                _buildSummaryCell('$totalCount', 1),
                _buildSummaryCell(totalGrossWt.toStringAsFixed(3), 1.5),
                _buildSummaryCell('$matchedCount', 1),
                _buildSummaryCell(totalMatchedWt.toStringAsFixed(3), 1.5),
                _buildSummaryCell('', 1),
              ],
      ),
    );
  }

  Widget _buildSummaryCell(String text, double flex, {bool isCenter = false}) {
    return Expanded(
      flex: (flex * 10).toInt(),
      child: Container(
        padding: const EdgeInsets.only(left: 10, top: 3, bottom: 3),
        alignment: isCenter ? Alignment.center : Alignment.centerLeft,
        child: Text(
          text,
          style: AppFonts.poppins(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return ScanBottomBarInventory(
      onSave: _saveScanResults,
      onList: () {
        setState(() {
          _showMenu = !_showMenu;
        });
      },
      onScan: _toggleScanning,
      onEmail: _showEmailReportDialog,
      onReset: _resetScanning,
      isScanning: _isScanning,
      showResume: _showResumeOnScanButton,
    );
  }

  Widget _buildEmptyState() {
    final s = context.s;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            s.noItemsFoundUnderScope,
            style: AppFonts.poppins(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
