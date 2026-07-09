import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/bulk_item.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../services/sync_isolate.dart';

import '../services/api_service.dart';

class ProductViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final DbService _dbService;
  final ApiService _apiService;

  ProductViewModel({
    required PrefService prefService,
    required DbService dbService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _dbService = dbService,
        _apiService = apiService;

  // Sync state variables
  bool _isLoading = false;
  double _syncProgress = 0.0;
  String _syncStatusText = '';
  int _syncTotalCount = 0;
  int _syncSyncedCount = 0;
  bool _syncCompleted = false;
  List<String> _skippedItemCodes = [];
  String? _errorMessage;
  StreamSubscription<dynamic>? _syncSubscription;

  bool get isLoading => _isLoading;
  double get syncProgress => _syncProgress;
  String get syncStatusText => _syncStatusText;
  int get syncTotalCount => _syncTotalCount;
  int get syncSyncedCount => _syncSyncedCount;
  bool get syncCompleted => _syncCompleted;
  List<String> get skippedItemCodes => _skippedItemCodes;
  String? get errorMessage => _errorMessage;

  // Product List state variables (Pagination)
  final List<BulkItem> _products = [];
  bool _isListLoading = false;
  bool _hasReachedEnd = false;
  int _offset = 0;
  static const int _pageSize = 50;

  List<BulkItem> get products => _products;
  bool get isListLoading => _isListLoading;
  bool get hasReachedEnd => _hasReachedEnd;

  // Search and Filter variables
  String _searchQuery = '';
  String _selectedSku = '';
  String _selectedCategory = '';
  String _selectedProduct = '';
  String _selectedDesign = '';
  String _selectedPurity = '';

  // Filter option lists
  List<String> _skuOptions = [];
  List<String> _categoryOptions = [];
  List<String> _productOptions = [];
  List<String> _designOptions = [];
  List<String> _purityOptions = [];

  // Getters for Search & Filter
  String get searchQuery => _searchQuery;
  String get selectedSku => _selectedSku;
  String get selectedCategory => _selectedCategory;
  String get selectedProduct => _selectedProduct;
  String get selectedDesign => _selectedDesign;
  String get selectedPurity => _selectedPurity;

  // Getters for Options
  List<String> get skuOptions => _skuOptions;
  List<String> get categoryOptions => _categoryOptions;
  List<String> get productOptions => _productOptions;
  List<String> get designOptions => _designOptions;
  List<String> get purityOptions => _purityOptions;

  // Setters that trigger refresh
  void updateSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
    refreshList();
  }

  void updateFilters({
    String? sku,
    String? category,
    String? product,
    String? design,
    String? purity,
  }) {
    if (sku != null) _selectedSku = sku;
    if (category != null) _selectedCategory = category;
    if (product != null) _selectedProduct = product;
    if (design != null) _selectedDesign = design;
    if (purity != null) _selectedPurity = purity;
    notifyListeners();
    refreshList();
  }

  void resetFilters() {
    _searchQuery = '';
    _selectedSku = '';
    _selectedCategory = '';
    _selectedProduct = '';
    _selectedDesign = '';
    _selectedPurity = '';
    notifyListeners();
    refreshList();
  }

  void clearSyncCompleted() {
    _syncCompleted = false;
    notifyListeners();
  }

  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }

  // Trigger non-blocking database sync from API using Dart Isolate
  Future<void> syncProducts() async {
    if (_isLoading) return;

    await _syncSubscription?.cancel();
    _syncSubscription = null;

    _isLoading = true;
    _syncProgress = 0.0;
    _syncStatusText = 'Initializing sync...';
    _syncTotalCount = 0;
    _syncSyncedCount = 0;
    _syncCompleted = false;
    _skippedItemCodes = [];
    _errorMessage = null;
    notifyListeners();

    final employee = _prefService.getEmployee();
    if (employee == null) {
      _isLoading = false;
      _errorMessage = 'Session expired. Please login again.';
      notifyListeners();
      return;
    }

    final tokenStr = _prefService.getToken() ?? '';
    final clientCode = employee.clientCode ?? '';
    final roleId = employee.roleId ?? 0;
    final branchIds = _prefService.getBranchIds();
    final baseUrl = _prefService.getCustomApi() ?? 'https://rrgold.loyalstring.co.in/';
    final tagType = _prefService.getRfidType();
    final allowSingleAndWebReusable = _prefService.isWebReusableTagEnabled();

    final dbPath = p.join(await getDatabasesPath(), 'sparkle_rfid.db');
    final rootToken = RootIsolateToken.instance;

    if (rootToken == null) {
      _isLoading = false;
      _errorMessage = 'Failed to fetch RootIsolateToken';
      notifyListeners();
      return;
    }

    final receivePort = ReceivePort();
    int lastUiUpdateMs = 0;

    final params = {
      'token': rootToken,
      'sendPort': receivePort.sendPort,
      'baseUrl': baseUrl,
      'clientCode': clientCode,
      'roleId': roleId,
      'branchIds': branchIds,
      'tokenStr': tokenStr,
      'dbPath': dbPath,
      'tagType': tagType,
      'allowSingleAndWebReusable': allowSingleAndWebReusable,
    };

    _syncSubscription = receivePort.listen((message) {
      if (message is! Map<String, dynamic>) return;

      final String status = message['status'] ?? '';

      switch (status) {
        case 'init':
        case 'rfid':
        case 'downloading':
          _syncStatusText = message['message'] ?? '';
          notifyListeners();
          break;
        case 'syncing':
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastUiUpdateMs < 700) return;
          lastUiUpdateMs = now;

          final total = message['total'] as int? ?? 0;
          final processed = message['processed'] as int? ?? 0;
          _syncProgress = total > 0 ? processed / total : 0.0;
          _syncSyncedCount = message['synced'] ?? 0;
          _syncTotalCount = total;
          _syncStatusText = message['message'] ?? '';
          notifyListeners();
          break;
        case 'completed':
          _isLoading = false;
          _syncCompleted = true;
          _syncSyncedCount = message['synced'] ?? 0;
          _syncTotalCount = message['total'] ?? 0;
          _syncProgress = 1.0;
          _syncStatusText = 'Sync completed successfully';
          _skippedItemCodes = List<String>.from(message['skipped'] ?? []);
          receivePort.close();
          _syncSubscription?.cancel();
          _syncSubscription = null;
          _dbService.resetConnection();
          notifyListeners();
          break;
        case 'error':
          _isLoading = false;
          _errorMessage =
              message['message'] ?? 'Unknown error occurred during sync';
          _syncStatusText = 'Sync failed';
          receivePort.close();
          _syncSubscription?.cancel();
          _syncSubscription = null;
          _dbService.resetConnection();
          notifyListeners();
          break;
      }
    });

    await Isolate.spawn(SyncIsolate.run, params);
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  // Load paginated list of products from SQLite with filtering
  Future<void> loadNextPage() async {
    if (_isListLoading || _hasReachedEnd) return;

    _isListLoading = true;
    notifyListeners();

    try {
      final items = await _dbService.getMinimalItemsPagedFiltered(
        _pageSize,
        _offset,
        searchQuery: _searchQuery,
        sku: _selectedSku,
        category: _selectedCategory,
        productName: _selectedProduct,
        design: _selectedDesign,
        purity: _selectedPurity,
      );
      
      if (items.length < _pageSize) {
        _hasReachedEnd = true;
      }
      
      _products.addAll(items);
      _offset += items.length;
    } catch (e) {
      _errorMessage = 'Failed to load products: ${e.toString()}';
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  // Clear list and restart pagination
  Future<void> refreshList() async {
    _products.clear();
    _offset = 0;
    _hasReachedEnd = false;
    _isListLoading = false;
    notifyListeners();
    await loadNextPage();
  }

  // Fetch distinct options for filter dropdowns from SQLite database
  Future<void> loadFilterOptions() async {
    try {
      _skuOptions = await _dbService.getDistinctValues('sku');
      _categoryOptions = await _dbService.getDistinctValues('category');
      _productOptions = await _dbService.getDistinctValues('productName');
      _designOptions = await _dbService.getDistinctValues('design');
      _purityOptions = await _dbService.getDistinctValues('purity');
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading filter options: $e');
    }
  }

  // Get ALL matching items (no pagination) for PDF Export
  Future<List<BulkItem>> getFilteredProductsForExport() async {
    return await _dbService.getAllMinimalItemsFiltered(
      searchQuery: _searchQuery,
      sku: _selectedSku,
      category: _selectedCategory,
      productName: _selectedProduct,
      design: _selectedDesign,
      purity: _selectedPurity,
    );
  }

  // Delete product: calls remote API and deletes locally on success
  Future<bool> deleteProductItem(int bulkItemId) async {
    final employee = _prefService.getEmployee();
    if (employee == null) {
      _errorMessage = 'Session expired. Please login again.';
      notifyListeners();
      return false;
    }

    _isListLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await _apiService.deleteProduct(bulkItemId, employee.clientCode ?? '');
      if (success) {
        // Delete locally in SQLite
        await _dbService.deleteItemLocally(bulkItemId);
        
        // Remove from memory list and notify
        _products.removeWhere((item) => item.bulkItemId == bulkItemId);
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Delete failed on server.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  // Update product: updates metadata, uploads image if selected, updates local database
  Future<bool> updateProductItem(BulkItem updatedItem, String? localImagePath) async {
    final employee = _prefService.getEmployee();
    if (employee == null) {
      _errorMessage = 'Session expired. Please login again.';
      notifyListeners();
      return false;
    }

    _isListLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Upload new image if chosen
      if (localImagePath != null && localImagePath.isNotEmpty) {
        final remoteImagePath = await _apiService.uploadProductImage(
          employee.clientCode ?? '',
          updatedItem.itemCode,
          localImagePath,
        );
        if (remoteImagePath != null && remoteImagePath.isNotEmpty) {
          updatedItem.imageUrl = remoteImagePath;
        }
      }

      // 2. Call remote update API
      final editRequestMap = {
        'Id': updatedItem.bulkItemId,
        'ProductTitle': updatedItem.productName,
        'ClipWeight': '0.000',
        'ClipQuantity': '0',
        'ItemCode': updatedItem.itemCode,
        'HSNCode': '',
        'Description': '',
        'ProductCode': updatedItem.productCode,
        'MetalName': '',
        'CategoryId': updatedItem.categoryId,
        'ProductId': updatedItem.productId,
        'DesignId': updatedItem.designId,
        'PurityId': updatedItem.purityId,
        'Colour': '',
        'Size': '',
        'WeightCategory': null,
        'GrossWt': updatedItem.grossWeight,
        'NetWt': updatedItem.netWeight,
        'CollectionName': '',
        'OccassionName': '',
        'Gender': '',
        'MakingFixedAmt': updatedItem.fixMaking,
        'MakingPerGram': updatedItem.makingPerGram,
        'MakingFixedWastage': updatedItem.fixWastage,
        'MakingPercentage': updatedItem.makingPercent,
        'TotalStoneWeight': updatedItem.stoneWeight,
        'TotalStoneAmount': updatedItem.stoneAmount,
        'TotalStonePieces': '0',
        'TotalDiamondWeight': updatedItem.diamondWeight,
        'TotalDiamondPieces': '0',
        'TotalDiamondAmount': updatedItem.diamondAmount,
        'Featured': '',
        'Pieces': updatedItem.pcs.toString(),
        'HallmarkAmount': '',
        'HUIDCode': '',
        'MRP': updatedItem.mrp.toString(),
        'VendorId': 1,
        'FirmName': '',
        'BoxId': updatedItem.boxId,
        'TIDNumber': updatedItem.epc,
        'RFIDCode': updatedItem.rfid,
        'FinePercent': '',
        'WastagePercent': '',
        'Images': updatedItem.imageUrl,
        'BlackBeads': '',
        'Height': '',
        'Width': '',
        'OrderedItemId': '',
        'OrderNo': '',
        'UrdNo': '',
        'UrdId': null,
        'CuttingGrossWt': '',
        'CuttingNetWt': '',
        'MetalRate': '',
        'LotNumber': '',
        'DeptId': 0,
        'PurchaseCost': '',
        'Margin': '',
        'BranchName': updatedItem.branchName,
        'BranchType': updatedItem.branchType,
        'BoxName': updatedItem.boxName,
        'EstimatedDays': '',
        'OfferPrice': '',
        'Rating': '',
        'Ranking': '',
        'CompanyId': 0,
        'BranchId': updatedItem.branchId,
        'EmployeeId': employee.employeeId,
        'Status': updatedItem.status,
        'ClientCode': employee.clientCode,
        'UpdatedFrom': null,
        'count': 0,
        'SalesmanId': null,
        'TotalCount': 0,
        'MetalId': 1,
        'WarehouseId': 0,
        'CreatedOn': DateTime.now().toIso8601String().split('T').first,
        'LastUpdated': DateTime.now().toIso8601String().split('T').first,
        'TaxId': 0,
        'TaxPercentage': '',
        'OtherWeight': '0.000',
        'PouchWeight': '',
        'CategoryName': updatedItem.category,
        'PurityName': updatedItem.purity,
        'TodaysRate': '',
        'ProductName': updatedItem.productName,
        'DesignName': updatedItem.design,
        'DiamondSize': '',
        'DiamondWeight': updatedItem.diamondWeight,
        'DiamondPurchaseRate': '',
        'DiamondSellRate': '',
        'DiamondClarity': '',
        'DiamondColour': '',
        'DiamondShape': '',
        'DiamondCut': '',
        'DiamondSettingType': '',
        'DiamondCertificate': '',
        'DiamondPieces': '0',
        'DiamondPurchaseAmount': updatedItem.diamondAmount,
        'DiamondSellAmount': updatedItem.diamondAmount,
        'DiamondDescription': '',
        'TagWeight': '',
        'FindingWeight': '',
        'LanyardWeight': '',
        'PacketId': 0,
        'PacketName': '',
        'CollectionId': 0,
        'CollectionNameSKU': updatedItem.sku,
        'PackingWeight': 0.0,
        'TotalWeight': updatedItem.totalGwt,
        'StoneColour': '',
        'StoneShape': '',
        'StoneSize': '',
        'StoneRatePerPiece': '',
        'StoneWeightType': '',
        'StoneCertificate': '',
        'StoneSettingType': '',
        'StoneCategory': '',
        'DiamondCategory': '',
        'FromDate': DateTime.now().toIso8601String().split('T').first,
        'ToDate': DateTime.now().toIso8601String().split('T').first,
        'DiamondSleveName': '',
        'DiamondSizeName': '',
        'DiamondRate': '',
        'DiamondAmount': updatedItem.diamondAmount,
        'DiamondBoxName': '',
        'DiamondPacketName': '',
        'HexCode': '',
        'DiamondDeduct': '',
        'SoldDate': DateTime.now().toIso8601String().split('T').first,
        'OldItemCode': false,
        'Stones': const [],
        'Diamonds': const [],
        'InvoiceDetails': const [],
        'Counter': '',
        'Branch': {
          'label': updatedItem.branchName,
          'value': updatedItem.branchId,
        },
        'StonePieces': '0',
        'Quantity': 1,
        'StoneWeight': updatedItem.stoneWeight,
        'epc': updatedItem.epc,
        'SKUId': 1,
        'UserId': employee.userId,
      };

      final apiSuccess = await _apiService.updateProduct(editRequestMap);
      if (apiSuccess) {
        // 3. Update locally in SQLite
        await _dbService.updateItemLocally(updatedItem);

        // 4. Update in memory and notify
        final idx = _products.indexWhere((item) => item.bulkItemId == updatedItem.bulkItemId);
        if (idx != -1) {
          _products[idx] = updatedItem;
        }
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Update failed on server.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  // Get distinct counters from SQLite
  Future<List<String>> getCounters() async {
    try {
      return await _dbService.getDistinctValues('counterName');
    } catch (e) {
      debugPrint('Error getting counters: $e');
      return [];
    }
  }

  // Get distinct boxes from SQLite
  Future<List<String>> getBoxes() async {
    try {
      return await _dbService.getDistinctValues('boxName');
    } catch (e) {
      debugPrint('Error getting boxes: $e');
      return [];
    }
  }

  // Get distinct branches from SQLite
  Future<List<String>> getBranches() async {
    try {
      return await _dbService.getDistinctValues('branchName');
    } catch (e) {
      debugPrint('Error getting branches: $e');
      return [];
    }
  }

  // Get distinct exhibitions from SQLite
  Future<List<String>> getExhibitions() async {
    try {
      return await _dbService.getDistinctExhibitions();
    } catch (e) {
      debugPrint('Error getting exhibitions: $e');
      return [];
    }
  }

  // Get scoped verification items
  Future<List<BulkItem>> getItemsForVerification({
    required String filterType,
    required String filterValue,
  }) async {
    return _dbService.getItemsForVerification(
      filterType: filterType,
      filterValue: filterValue,
    );
  }

  /// Paginated minimal-column load for scan display with progress callback.
  Future<List<BulkItem>> loadScanDisplayItems({
    String? filterType,
    String? filterValue,
    void Function(int loaded, int total)? onProgress,
  }) async {
    const pageSize = 5000;
    final total = await _dbService.getScanDisplayItemCount(
      filterType: filterType,
      filterValue: filterValue,
    );
    if (total == 0) {
      onProgress?.call(0, 0);
      return [];
    }

    final all = <BulkItem>[];
    for (int offset = 0; offset < total; offset += pageSize) {
      final batch = await _dbService.getScanDisplayItemsPaged(
        pageSize,
        offset,
        filterType: filterType,
        filterValue: filterValue,
      );
      all.addAll(batch);
      onProgress?.call(all.length, total);
      if (batch.length < pageSize) break;
    }
    return all;
  }

  // Save scan results locally
  Future<void> saveScanResults(List<BulkItem> items) async {
    try {
      await _dbService.saveScanResultsLocally(items);
    } catch (e) {
      debugPrint('Error saving scan results: $e');
    }
  }

  // Upload Stock Verification payload
  Future<bool> uploadVerification({
    required String clientCode,
    required List<Map<String, dynamic>> items,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Chunk items into batches of 2000 to match Compose behavior
      const int batchSize = 2000;
      for (int i = 0; i < items.length; i += batchSize) {
        final end = (i + batchSize < items.length) ? i + batchSize : items.length;
        final batch = items.sublist(i, end);
        await _apiService.uploadStockVerification(clientCode, batch);
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
