import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../viewmodels/product_view_model.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../services/email_service.dart';
import 'widgets/scan_bottom_bar.dart';

class ScannedBulkItem {
  final BulkItem originalBulkItem;
  String currentScannedStatus; // 'Matched' or 'Unmatched'

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
  int _selectedPower = 30; // Default power level

  // Drawer / overlay menu and unlabelled items
  bool _showMenu = false;
  final List<String> _unlabelledEpcs = [];

  // Search filter
  bool _showSearchInput = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Fast scan lookup — mirrors Kotlin filteredDbEpcSet + matchedEpcSet
  final Map<String, int> _epcToMasterIndex = {};
  final Set<String> _matchedEpcSet = {};
  Set<String> _filteredDbEpcSet = {};
  int _lastScanUiUpdateMs = 0;
  int _lastTriggerMs = 0;
  Timer? _scanUiFlushTimer;

  List<ScannedBulkItem>? _cachedFilteredItems;
  Map<String, List<ScannedBulkItem>>? _cachedGroupedMap;
  int _cachedViewHash = 0;
  int _cachedMatchedCount = 0;
  int _cachedTotalCount = 0;
  double _cachedTotalGrossWt = 0;
  double _cachedTotalMatchedWt = 0;

  @override
  void initState() {
    super.initState();
    _selectedPower = context.read<PrefService>().inventoryPower;
    _rfidService.preWarmReader();
    _rfidService.clearSearchTags();
    _tagsSubscription = _rfidService.tagsStream.listen(_onTagScanned);
    // Subscribe to physical trigger key presses
    _triggerSubscription = _rfidService.triggerStream.listen((_) {
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
    );

    if (!mounted) return;

    final scanned = List<ScannedBulkItem>.generate(
      list.length,
      (i) => ScannedBulkItem(list[i], 'Unmatched'),
    );

    setState(() {
      _scannedItems = scanned;
      _isLoadingItems = false;
    });

    // Build lookup maps after the list is on screen so first paint stays smooth.
    scheduleMicrotask(() {
      if (!mounted) return;
      _buildLookupMaps();
      _setFilteredItemsForScan();
    });
  }

  List<String> _matchKeysForItem(ScannedBulkItem item) {
    final keys = <String>[];
    final epc = item.epc.trim().toUpperCase();
    final rfid = item.rfid.trim().toUpperCase();
    if (epc.isNotEmpty) keys.add(epc);
    if (rfid.isNotEmpty && rfid != epc) keys.add(rfid);
    return keys;
  }

  String _statusForItem(ScannedBulkItem item) {
    for (final key in _matchKeysForItem(item)) {
      if (_matchedEpcSet.contains(key)) return 'Matched';
    }
    return 'Unmatched';
  }

  void _registerMatchForItem(ScannedBulkItem item, String scannedTag) {
    _matchedEpcSet.add(scannedTag.trim().toUpperCase());
    for (final key in _matchKeysForItem(item)) {
      _matchedEpcSet.add(key);
    }
  }

  void _syncItemStatusesFromMatchedSet() {
    for (final item in _scannedItems) {
      item.currentScannedStatus = _statusForItem(item);
    }
  }

  void _buildLookupMaps() {
    _epcToMasterIndex.clear();
    for (int i = 0; i < _scannedItems.length; i++) {
      _indexTagKey(_epcToMasterIndex, _scannedItems[i].epc, i);
      _indexTagKey(_epcToMasterIndex, _scannedItems[i].rfid, i);
    }
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

  void _indexTagKey(Map<String, int> map, String value, int index) {
    final key = value.trim().toUpperCase();
    if (key.isNotEmpty) map[key] = index;
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

  void _refreshDisplayCache() {
    final filteredItems = _getFilteredScopeItems();
    _cachedFilteredItems = filteredItems;
    _cachedGroupedMap = _getGroupedMap(filteredItems);
    _cachedViewHash = _viewStateHash();
    _cachedTotalCount = filteredItems.length;
    _cachedMatchedCount = filteredItems.where((i) => i.currentScannedStatus == 'Matched').length;
    _cachedTotalGrossWt = 0;
    _cachedTotalMatchedWt = 0;
    for (final item in filteredItems) {
      final gw = double.tryParse(item.grossWeight) ?? 0.0;
      _cachedTotalGrossWt += gw;
      if (item.currentScannedStatus == 'Matched') {
        _cachedTotalMatchedWt += gw;
      }
    }
  }

  void _ensureDisplayCache() {
    final hash = _viewStateHash();
    if (_cachedFilteredItems == null || _cachedGroupedMap == null || hash != _cachedViewHash) {
      _refreshDisplayCache();
    }
  }

  void _scheduleScanUiUpdate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastScanUiUpdateMs >= 80) {
      _lastScanUiUpdateMs = now;
      _scanUiFlushTimer?.cancel();
      _scanUiFlushTimer = null;
      _syncItemStatusesFromMatchedSet();
      _cachedViewHash = 0;
      if (mounted) setState(() {});
      _checkAutoStopScan();
    } else {
      _scanUiFlushTimer ??= Timer(
        Duration(milliseconds: (80 - (now - _lastScanUiUpdateMs)).clamp(1, 80)),
        () {
          _scanUiFlushTimer = null;
          _lastScanUiUpdateMs = DateTime.now().millisecondsSinceEpoch;
          _syncItemStatusesFromMatchedSet();
          _cachedViewHash = 0;
          if (mounted) setState(() {});
          _checkAutoStopScan();
        },
      );
    }
  }

  void _checkAutoStopScan() {
    if (!_isScanning) return;
    final scope = _getDisplayScopeItems();
    if (scope.isEmpty) return;
    final allMatched = scope.every((i) => i.currentScannedStatus == 'Matched');
    if (allMatched) {
      _stopScanning();
      _showToast(context.sRead.allItemsMatchedScanStopped);
    }
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
    if (!_isScanning && !_rfidService.isScanning) return;

    final scannedEpc = tag.trim().toUpperCase();
    if (scannedEpc.isEmpty) return;

    if (_filteredDbEpcSet.contains(scannedEpc)) {
      final masterIndex = _epcToMasterIndex[scannedEpc];
      if (masterIndex != null && masterIndex < _scannedItems.length) {
        _registerMatchForItem(_scannedItems[masterIndex], scannedEpc);
      } else {
        _matchedEpcSet.add(scannedEpc);
      }
      _scheduleScanUiUpdate();
      return;
    }

    if (!_unlabelledEpcs.contains(scannedEpc)) {
      _unlabelledEpcs.add(scannedEpc);
      _scheduleScanUiUpdate();
    }
  }

  void _toggleScanning() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTriggerMs < 300) return;
    _lastTriggerMs = now;

    if (_isScanning) {
      _stopScanning();
    } else {
      _startScanning();
    }
  }

  void _startScanning() async {
    if (_isScanning) return;
    if (_isLoadingItems) {
      _showToast(context.sRead.pleaseWaitItemsLoading);
      return;
    }

    _buildLookupMaps();
    // Kotlin: setFilteredItems(displayItems) — use full nav scope, not tab-filtered.
    if (_selectedMenu == 'UNLABELLED') {
      _filteredDbEpcSet = {};
    } else {
      _setFilteredItemsForScan(_getDisplayScopeItems());
    }

    final displayScope = _getDisplayScopeItems();
    if (displayScope.isEmpty && _selectedMenu != 'UNLABELLED') {
      _showToast(context.sRead.noItemsInCurrentScope);
      return;
    }
    if (_filteredDbEpcSet.isEmpty &&
        _selectedMenu != 'UNLABELLED' &&
        displayScope.isNotEmpty) {
      _showToast(context.sRead.noRfidEpcInScope);
      return;
    }
    if (displayScope.isNotEmpty &&
        displayScope.every((i) => i.currentScannedStatus == 'Matched') &&
        _selectedMenu != 'UNLABELLED') {
      _showToast(context.sRead.allItemsAlreadyMatched);
      return;
    }

    // Kotlin sets isScanning=true BEFORE hardware start.
    setState(() => _isScanning = true);

    await _rfidService.stopScanning();
    await _rfidService.clearSearchTags();
    await _rfidService.setInventoryScanMode(true);
    await _rfidService.prepareForScan();
    await _rfidService.setInventoryScopeEpcsBatched(_filteredDbEpcSet.toList());
    await _rfidService.setPower(_selectedPower);

    final started = await _rfidService.startScanning(
      power: _selectedPower,
      inventory: true,
      simulatedScopeTags: _filteredDbEpcSet.toList(),
    );

    if (!mounted) return;
    if (!started) {
      setState(() => _isScanning = false);
      await _rfidService.haltScan();
      _showToast(context.sRead.failedToStartRfidScanner);
    }
  }

  void _stopScanning() async {
    if (!_isScanning) return;
    await _rfidService.stopScanning();
    await _rfidService.haltScan();
    _scanUiFlushTimer?.cancel();
    _scanUiFlushTimer = null;
    _syncItemStatusesFromMatchedSet();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _resetScanning() {
    _stopScanning();
    setState(() {
      _matchedEpcSet.clear();
      for (var item in _scannedItems) {
        item.currentScannedStatus = 'Unmatched';
      }
      _unlabelledEpcs.clear();
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
      _selectedMenu = 'ALL';
      _currentLevel = 'Category';
      _selectedCategory = null;
      _selectedProduct = null;
      _selectedDesign = null;
    });
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
      return;
    }

    // 1. Prepare local update payload (Kotlin uses tagKey = epc ?: rfid)
    final finalItems = _scannedItems.map((item) {
      final map = item.originalBulkItem.toMap();
      final isMatched = _matchKeysForItem(item)
          .any((key) => _matchedEpcSet.contains(key));
      map['isScanned'] = isMatched ? 1 : 0;
      map['scannedStatus'] = isMatched ? 'Matched' : 'Unmatched';
      return BulkItem.fromMap(map);
    }).toList();

    // 2. Prepare upload payload
    final uploadItemsPayload = _scannedItems.map((item) {
      final double grossWt = double.tryParse(item.grossWeight) ?? 0.0;
      final double netWt = double.tryParse(item.netWeight) ?? 0.0;
      final isMatched = _matchKeysForItem(item)
          .any((key) => _matchedEpcSet.contains(key));
      final String status = isMatched ? 'match' : 'unmatch';

      return {
        'ItemCode': item.itemCode,
        'Status': status,
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
      };
    }).toList();

    // 3. Save locally in SQLite
    await viewModel.saveScanResults(finalItems);

    // 4. Call stock verification API
    final success = await viewModel.uploadVerification(
      clientCode: employee.clientCode!,
      items: uploadItemsPayload,
    );

    setState(() => _isSaving = false);

    if (success) {
      _showToast(context.sRead.stockVerificationUploaded);
    } else {
      _showToast(context.sRead.verificationUploadFailed(viewModel.errorMessage ?? ''));
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
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
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3053F0), Color(0xFFE82E5A)],
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Container(
          margin: const EdgeInsets.all(1.0), // Border width
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3.0),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: const Color(0xFF5231A7),
              ),
              const SizedBox(height: 4),
              Text(
                displayText,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Navigation scope (drill-down + search) — mirrors Kotlin navFilteredItems / scannedItemsSequence base.
  List<ScannedBulkItem> _getNavScopeItems() {
    _syncItemStatusesFromMatchedSet();
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
      final dummyItem = BulkItem(
        bulkItemId: 0,
        productName: 'Unlabelled Item',
        itemCode: '',
        rfid: '',
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
        epc: '',
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
      );
      
      var list = _unlabelledEpcs.map((epc) {
        final dummyMap = dummyItem.toMap();
        dummyMap['epc'] = epc;
        dummyMap['rfid'] = epc;
        return ScannedBulkItem(BulkItem.fromMap(dummyMap), 'Matched');
      }).toList();

      if (_searchQuery.isNotEmpty) {
        list = list.where((i) => i.epc.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
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
  Map<String, List<ScannedBulkItem>> _getGroupedMap(List<ScannedBulkItem> items) {
    final Map<String, List<ScannedBulkItem>> grouped = {};
    for (var item in items) {
      String key = '';
      if (_currentLevel == 'Category') {
        key = item.category.isNotEmpty ? item.category : 'Unknown';
      } else if (_currentLevel == 'Product') {
        key = item.productName.isNotEmpty ? item.productName : 'Unknown';
      } else if (_currentLevel == 'Design') {
        key = item.design.isNotEmpty ? item.design : 'Unknown';
      }

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(item);
    }
    return grouped;
  }

  void _showDetailsDialog(BulkItem item) {
    final s = context.sRead;
    showDialog(
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
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
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
                const Icon(Icons.image, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                _buildInfoRow(s.productName, item.productName),
                _buildInfoRow(s.itemCode, item.itemCode),
                _buildInfoRow('${s.lblRfid} / ${s.colEpc}', item.epc.isNotEmpty ? item.epc : item.rfid),
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
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value.isNotEmpty ? value : '-',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
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
    
    showDialog(
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
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (savedEmails.isNotEmpty) ...[
                      Text(
                        s.savedEmails,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700]),
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
                                  style: GoogleFonts.poppins(fontSize: 13),
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
                        labelStyle: GoogleFonts.poppins(fontSize: 13),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        newEmail = val;
                      },
                      style: GoogleFonts.poppins(fontSize: 13),
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
                  child: Text(s.cancel, style: GoogleFonts.poppins(color: Colors.grey[600])),
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
                      : Text(s.send, style: GoogleFonts.poppins(color: Colors.white)),
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
    final groupedMap = _cachedGroupedMap!;

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
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: s.searchProductRfidEpc,
                        hintStyle: GoogleFonts.poppins(color: Colors.white60),
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
                      _filterValue.isNotEmpty ? _filterValue : s.inventory,
                      style: GoogleFonts.poppins(
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
                  DropdownButton<int>(
                    value: _selectedPower,
                    dropdownColor: const Color(0xFF5231A7),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                    underline: Container(),
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        setState(() => _selectedPower = newValue);
                        _rfidService.setPower(newValue);
                        context.read<PrefService>().savePower(PrefService.keyInventoryCount, newValue);
                      }
                    },
                    items: [5, 10, 15, 20, 25, 30].map<DropdownMenuItem<int>>((int val) {
                      return DropdownMenuItem<int>(
                        value: val,
                        child: Text(s.powerLabel(val), style: GoogleFonts.poppins(color: Colors.white)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(width: 8),
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
                  child: _buildMainList(filteredItems, groupedMap),
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
                                        count: totalCount,
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
                                        onTap: () {
                                          setState(() => _showMenu = false);
                                          final unmatched = _scannedItems
                                              .where((item) => item.currentScannedStatus == 'Unmatched')
                                              .map((item) => item.originalBulkItem)
                                              .toList();
                                          Navigator.pushNamed(context, '/search', arguments: {
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
    Map<String, List<ScannedBulkItem>> groupedMap,
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
              : groupedMap.length,
          itemBuilder: (context, index) {
            if (_currentLevel == 'DesignItems' || _selectedMenu == 'UNLABELLED') {
              final item = filteredItems[index];
              return _buildDesignItemRow(item);
            } else {
              final entry = groupedMap.entries.elementAt(index);
              return _buildGroupRow(entry.key, entry.value);
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
                style: GoogleFonts.poppins(
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

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(
                s.selectFilterType(filterTypeLocal),
                style: GoogleFonts.poppins(
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
                                            selected.add(item);
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
                                      style: GoogleFonts.poppins(
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
                            style: GoogleFonts.poppins(
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
                            style: GoogleFonts.poppins(
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
        style: GoogleFonts.poppins(
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

  Widget _buildGroupRow(String label, List<ScannedBulkItem> items) {
    final qty = items.length;
    double grossWt = 0.0;
    int mQty = 0;
    double mWt = 0.0;

    for (var i in items) {
      final double gw = double.tryParse(i.grossWeight) ?? 0.0;
      grossWt += gw;
      if (i.currentScannedStatus == 'Matched') {
        mQty++;
        mWt += gw;
      }
    }

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
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 10,
              child: Text('$qty', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 15,
              child: Text(grossWt.toStringAsFixed(3), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 10,
              child: Text('$mQty', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 15,
              child: Text(mWt.toStringAsFixed(3), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700])),
            ),
            Expanded(
              flex: 10,
              child: Center(
                child: Icon(
                  isMatched ? Icons.check_circle : Icons.error_outline,
                  color: isMatched ? Colors.green : Colors.orange,
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
    final double grossWt = double.tryParse(item.grossWeight) ?? 0.0;
    final isMatched = item.currentScannedStatus == 'Matched';

    return InkWell(
      onTap: () => _showDetailsDialog(item.originalBulkItem),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 28,
              child: Text(
                item.design.isNotEmpty ? item.design : '-',
                style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 18,
              child: Text(
                item.rfid.isNotEmpty ? item.rfid : '-',
                style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 17,
              child: Text(
                item.itemCode.isNotEmpty ? item.itemCode : '-',
                style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 17,
              child: Text(
                grossWt.toStringAsFixed(3),
                style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
              ),
            ),
            Expanded(
              flex: 10,
              child: Center(
                child: Icon(
                  isMatched ? Icons.check_circle : Icons.error_outline,
                  color: isMatched ? Colors.green : Colors.orange,
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
                      style: GoogleFonts.poppins(
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
          style: GoogleFonts.poppins(
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
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
