import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/bulk_item.dart';
import '../models/stock_transfer_models.dart';
import '../models/user_permission.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';

class StockTransferViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final DbService _dbService;
  final PrefService _prefService;

  StockTransferViewModel({
    required ApiService apiService,
    required DbService dbService,
    required PrefService prefService,
  })  : _apiService = apiService,
        _dbService = dbService,
        _prefService = prefService;

  List<TransferType> transferTypes = [];
  List<BulkItem> allLabelledItems = [];
  List<BulkItem> filteredItems = [];
  List<BulkItem> previewItems = [];

  String? selectedTransferType;
  String selectedFrom = fromPlaceholder;
  String selectedTo = toPlaceholder;
  String? appliedCategory;
  String? appliedProduct;
  String? appliedDesign;

  int? sourceBranchId;
  int? destinationBranchId;

  bool isLoading = false;
  bool isBootstrapping = false;
  String? errorMessage;
  String? transferStatusMessage;

  List<String> get fromOptions => _optionsForType(_fromType);
  List<String> get toOptions => _optionsForType(_toType);

  String? get _fromType => _parseTransferType(selectedTransferType).$1;
  String? get _toType => _parseTransferType(selectedTransferType).$2;

  int get transferTypeId {
    if (selectedTransferType == null) return -1;
    return transferTypes
            .firstWhere(
              (t) => t.transferType.toLowerCase() == selectedTransferType!.toLowerCase(),
              orElse: () => TransferType(id: -1, transferType: '', clientCode: ''),
            )
            .id;
  }

  bool get isBranchToBranch => transferTypeId == 15;

  (String?, String?) _parseTransferType(String? type) {
    if (type == null || !type.toLowerCase().contains(' to ')) return (null, null);
    final parts = type.split(RegExp(r'\s+to\s+', caseSensitive: false));
    if (parts.length != 2) return (null, null);
    return (parts[0].trim().toLowerCase(), parts[1].trim().toLowerCase());
  }

  List<String> _counterNames = [];
  List<String> _branchNames = [];
  List<String> _boxNames = [];
  List<String> _packetNames = [];
  List<String> _accessibleBranchNames = [];
  List<UserPermission> allEmployees = [];

  static const String fromPlaceholder = '__from__';
  static const String toPlaceholder = '__to__';
  static const String transferTypePlaceholder = '__transfer_type__';
  static const String categoryPlaceholder = '__category__';
  static const String productPlaceholder = '__product__';
  static const String designPlaceholder = '__design__';

  bool _initialized = false;

  void resetSession() {
    _initialized = false;
    transferTypes = [];
    allLabelledItems = [];
    filteredItems = [];
    previewItems = [];
    selectedTransferType = null;
    selectedFrom = fromPlaceholder;
    selectedTo = toPlaceholder;
    appliedCategory = null;
    appliedProduct = null;
    appliedDesign = null;
    sourceBranchId = null;
    destinationBranchId = null;
    _counterNames = [];
    _branchNames = [];
    _boxNames = [];
    _packetNames = [];
    _accessibleBranchNames = [];
    allEmployees = [];
    errorMessage = null;
    transferStatusMessage = null;
    isLoading = false;
    isBootstrapping = false;
    notifyListeners();
  }

  Future<void> initialize({bool forceReload = false}) async {
    if (_initialized && !forceReload) {
      // Keep existing in-memory stock for fast re-open; only refill if empty.
      if (allLabelledItems.isEmpty) {
        await loadAllLabelledStock();
      }
      return;
    }
    _initialized = true;

    isBootstrapping = true;
    notifyListeners();
    try {
      final clientCode = _prefService.getEmployee()?.clientCode ?? '';
      if (clientCode.isNotEmpty) {
        transferTypes = await _apiService.getStockTransferTypes(clientCode);
        unawaited(loadUserPermissions());
      }
      // Same as Sparkle: show ALL labelled stock immediately (type not required).
      await loadAllLabelledStock();
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isBootstrapping = false;
      notifyListeners();
    }

    unawaited(_loadFilterOptionsAndDefaults());
  }

  Future<void> loadAllLabelledStock() async {
    try {
      allLabelledItems = await _dbService.getLabelledBulkItems();
      // If From is set with a transfer type, keep that filter; else show all.
      if (selectedTransferType != null &&
          selectedFrom != fromPlaceholder &&
          _fromType != null) {
        filteredItems = await _dbService.getLabelledBulkItemsFiltered(
          fromType: _fromType!,
          fromValue: selectedFrom,
        );
      } else {
        filteredItems = List.from(allLabelledItems);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('loadAllLabelledStock error: $e');
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _loadFilterOptionsAndDefaults() async {
    try {
      final clientCode = _prefService.getEmployee()?.clientCode ?? '';
      final results = await Future.wait<List<String>>([
        _dbService.getDistinctValues('counterName'),
        _dbService.getDistinctValues('branchName'),
        _dbService.getDistinctValues('boxName'),
        _dbService.getDistinctPacketNames(),
      ]);
      final dbCounters = results[0];
      final apiCounters = clientCode.isNotEmpty
          ? await _apiService.getAllCounterNames(clientCode)
          : <String>[];
      // Union API + DB names so dropdown matches items we can actually filter.
      final merged = <String>{...apiCounters, ...dbCounters}.toList()..sort();
      _counterNames = merged.isNotEmpty ? merged : dbCounters;
      _branchNames = results[1];
      _boxNames = results[2];
      _packetNames = results[3];
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadUserPermissions() async {
    final employee = _prefService.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    if (clientCode.isEmpty) return;
    try {
      allEmployees = await _apiService.getAllUserPermissionsAll(clientCode);
      UserPermission? current;
      for (final entry in allEmployees) {
        if (entry.userId == employee?.id) {
          current = entry;
          break;
        }
      }
      if (current != null) {
        final branches = parseBranchSelectionJson(current.branchSelectionJson);
        setAccessibleBranches(branches.map((b) => b.name).toList());
      }
      notifyListeners();
    } catch (e) {
      debugPrint('loadUserPermissions error: $e');
    }
  }

  List<UserPermission> employeesForDestinationBranch(int? branchId) {
    if (branchId == null || branchId <= 0) return allEmployees;
    return allEmployees.where((emp) {
      return parseBranchSelectionJson(emp.branchSelectionJson).any((b) => b.id == branchId);
    }).toList();
  }

  void setAccessibleBranches(List<String> names) {
    _accessibleBranchNames = names;
    notifyListeners();
  }

  List<String> _optionsForType(String? type) {
    if (type == null) return [];
    if (isBranchToBranch && (type == 'branch')) return _accessibleBranchNames.isNotEmpty ? _accessibleBranchNames : _branchNames;
    switch (type) {
      case 'counter':
        return _counterNames;
      case 'branch':
        return _branchNames;
      case 'box':
        return _boxNames;
      case 'packet':
        return _packetNames;
      default:
        return [];
    }
  }

  void selectTransferType(String type) {
    selectedTransferType = type;
    selectedFrom = fromPlaceholder;
    selectedTo = toPlaceholder;
    sourceBranchId = null;
    destinationBranchId = null;
    if (transferTypeId == 15) {
      loadUserPermissions();
    }
    // Keep showing all labelled stock until From is chosen.
    unawaited(loadAllLabelledStock());
  }

  Future<void> selectFrom(String value) async {
    if (value == fromPlaceholder) return;
    selectedFrom = value;
    await _applyFromFilter();
    _clearCategoryFilters(clearChecks: true);
    notifyListeners();
  }

  Future<void> selectTo(String value) async {
    if (value == toPlaceholder) return;
    selectedTo = value;
    if (isBranchToBranch && _fromType == 'branch') {
      sourceBranchId = await _dbService.getEntityIdByName('branch', selectedFrom);
      destinationBranchId = await _dbService.getEntityIdByName('branch', selectedTo);
    }
    notifyListeners();
  }

  Future<void> _applyFromFilter() async {
    final fromType = _fromType;
    if (fromType == null || selectedFrom == fromPlaceholder) {
      await loadAllLabelledStock();
      return;
    }
    try {
      filteredItems = await _dbService.getLabelledBulkItemsFiltered(
        fromType: fromType,
        fromValue: selectedFrom.trim(),
      );
      // If exact name match found nothing, try case-insensitive contains from local cache.
      if (filteredItems.isEmpty && allLabelledItems.isNotEmpty) {
        final needle = selectedFrom.trim().toLowerCase();
        filteredItems = allLabelledItems.where((item) {
          final value = switch (fromType) {
            'counter' => item.counterName,
            'branch' => item.branchName,
            'box' => item.boxName,
            'packet' => item.packetName,
            _ => '',
          };
          return value.trim().toLowerCase() == needle ||
              value.trim().toLowerCase().contains(needle);
        }).toList();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('_applyFromFilter error: $e');
      notifyListeners();
    }
  }

  void applyCategoryProductDesignFilters({
    String? category,
    String? product,
    String? design,
  }) {
    appliedCategory = category;
    appliedProduct = product;
    appliedDesign = design;
    notifyListeners();
  }

  List<String> filterProductsFor(String? category) {
    var list = filteredItems;
    if (category != null && category.isNotEmpty) {
      list = list.where((i) => i.category.toLowerCase() == category.toLowerCase()).toList();
    }
    return list.map((e) => e.productName).where((e) => e.isNotEmpty).toSet().toList()..sort();
  }

  List<String> filterDesignsFor(String? category, String? product) {
    var list = filteredItems;
    if (category != null && category.isNotEmpty) {
      list = list.where((i) => i.category.toLowerCase() == category.toLowerCase()).toList();
    }
    if (product != null && product.isNotEmpty) {
      list = list.where((i) => i.productName.toLowerCase() == product.toLowerCase()).toList();
    }
    return list.map((e) => e.design).where((e) => e.isNotEmpty).toSet().toList()..sort();
  }

  Future<void> ensureTransferTypesLoaded() async {
    if (transferTypes.isNotEmpty) return;
    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    if (clientCode.isEmpty) return;
    try {
      transferTypes = await _apiService.getStockTransferTypes(clientCode);
      notifyListeners();
    } catch (e) {
      debugPrint('ensureTransferTypesLoaded error: $e');
    }
  }

  void _clearCategoryFilters({bool clearChecks = false}) {
    appliedCategory = null;
    appliedProduct = null;
    appliedDesign = null;
    if (clearChecks) notifyListeners();
  }

  Future<void> clearAppliedFilters() async {
    appliedCategory = null;
    appliedProduct = null;
    appliedDesign = null;
    await _applyFromFilter();
    notifyListeners();
  }

  void removePreviewItemsByKeys(Set<String> keys) {
    previewItems = previewItems.where((i) => !keys.contains(itemKey(i))).toList();
    notifyListeners();
  }

  List<String> get distinctCategories => filteredItems.map((e) => e.category).where((e) => e.isNotEmpty).toSet().toList()..sort();
  List<String> get distinctProducts => filteredItems.map((e) => e.productName).where((e) => e.isNotEmpty).toSet().toList()..sort();
  List<String> get distinctDesigns => filteredItems.map((e) => e.design).where((e) => e.isNotEmpty).toSet().toList()..sort();

  List<BulkItem> get displayItems {
    var list = filteredItems;
    if (appliedCategory != null && appliedCategory!.isNotEmpty) {
      list = list.where((i) => i.category.toLowerCase() == appliedCategory!.toLowerCase()).toList();
    }
    if (appliedProduct != null && appliedProduct!.isNotEmpty) {
      list = list.where((i) => i.productName.toLowerCase() == appliedProduct!.toLowerCase()).toList();
    }
    if (appliedDesign != null && appliedDesign!.isNotEmpty) {
      list = list.where((i) => i.design.toLowerCase() == appliedDesign!.toLowerCase()).toList();
    }
    return list;
  }

  String itemKey(BulkItem item) {
    final code = item.itemCode.trim();
    if (code.isNotEmpty) return code;
    return item.rfid.trim();
  }

  void setPreviewItems(List<BulkItem> items) {
    previewItems = items;
    notifyListeners();
  }

  void clearPreviewItems() {
    previewItems = [];
    notifyListeners();
  }

  Future<int> resolveEntityId(String type, String name) async {
    return await _dbService.getEntityIdByName(type, name) ?? 0;
  }

  Future<bool> submitTransfer({
    required String transferByEmployee,
    required String transferToEmployee,
    required String transferedToBranch,
    required String receivedByEmployee,
    required String remarks,
  }) async {
    final employee = _prefService.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    if (clientCode.isEmpty || selectedTransferType == null) return false;

    final fromType = _fromType ?? '';
    final toType = _toType ?? '';
    final sourceId = isBranchToBranch && sourceBranchId != null
        ? sourceBranchId!
        : await resolveEntityId(fromType, selectedFrom);
    final destId = isBranchToBranch && destinationBranchId != null
        ? destinationBranchId!
        : await resolveEntityId(toType, selectedTo);

    final transferBy = employee?.employeeId?.toString() ?? transferByEmployee;
    final transferTo = isBranchToBranch ? transferToEmployee : transferBy;
    final destBranch = isBranchToBranch ? transferedToBranch : (employee?.defaultBranchId.toString() ?? '');

    final stockItems = previewItems
        .map((e) {
          final stockId = e.bulkItemId > 0 ? e.bulkItemId : (int.tryParse(e.itemCode) ?? 0);
          return stockId > 0 ? StockTransferItemPayload(stockId: stockId) : null;
        })
        .whereType<StockTransferItemPayload>()
        .toList();
    if (stockItems.isEmpty) return false;

    final branchId = employee?.branchNo ?? employee?.defaultBranchId ?? 0;
    final request = StockTransferRequest(
      clientCode: clientCode,
      stockTransferItems: stockItems,
      stockType: 'labelled',
      stockTransferTypeName: selectedTransferType!,
      transferTypeId: transferTypeId,
      transferByEmployee: transferBy,
      transferedToBranch: destBranch,
      transferToEmployee: transferTo,
      transferedBranch: branchId.toString(),
      source: sourceId,
      destination: destId,
      remarks: remarks,
      stockTransferDate: DateFormat('dd-MM-yyyy').format(DateTime.now()),
      receivedByEmployee: receivedByEmployee,
    );

    isLoading = true;
    notifyListeners();
    try {
      final ok = await _apiService.addStockTransfer(request);
      transferStatusMessage = ok ? 'Transfer successful' : 'Transfer failed';
      if (ok) {
        previewItems = [];
        await initialize();
      }
      return ok;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<List<StockTransferInOutItem>> fetchInOutRequests({
    required String requestType,
    int? transferTypeFilterId,
  }) async {
    final employee = _prefService.getEmployee();
    if (employee == null) return [];
    await ensureTransferTypesLoaded();
    final branchId = employee.branchNo ?? employee.defaultBranchId;
    return _apiService.getAllStockTransfers(
      StockInOutRequest(
        clientCode: employee.clientCode ?? '',
        transferType: transferTypeFilterId,
        branchId: branchId,
        userId: employee.id,
        requestType: requestType,
      ),
    );
  }

  Future<String?> cancelTransfer(int id) async {
    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    return _apiService.cancelStockTransfer(CancelStockTransferRequest(id: id, clientCode: clientCode));
  }

  Future<String?> approveRejectTransfer({
    required List<LabelledStockItem> items,
    required String requestTyp,
    required int statusType,
  }) async {
    final employee = _prefService.getEmployee();
    if (employee == null) return null;
    final payloadItems = items
        .map((e) => e.approveId)
        .where((id) => id > 0)
        .map(
          (id) => StApproveRejectItem(
            id: id,
            approved: statusType == 1,
            status: statusType,
          ),
        )
        .toList();
    if (payloadItems.isEmpty) return 'Invalid transfer item id';
    return _apiService.approveStockTransfer(
      StApproveRejectRequest(
        stockTransferItems: payloadItems,
        clientCode: employee.clientCode ?? '',
        userId: employee.id.toString(),
        requestTyp: requestTyp,
      ),
    );
  }

  /// Ranked item-code suggestions (itemCode only) — same as Sparkle StockTransferItemCode.
  List<BulkItem> searchItemCodeSuggestions(String query, {int limit = 100}) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final matches = displayItems.where((i) {
      return i.itemCode.trim().toLowerCase().contains(q.toLowerCase());
    }).toList();
    matches.sort((a, b) {
      int rank(BulkItem i) {
        final code = i.itemCode.trim();
        if (code.toLowerCase() == q.toLowerCase()) return 0;
        if (code.toLowerCase().startsWith(q.toLowerCase())) return 1;
        if (code.toLowerCase().contains(q.toLowerCase())) return 2;
        return 3;
      }
      return rank(a).compareTo(rank(b));
    });
    if (matches.length <= limit) return matches;
    return matches.sublist(0, limit);
  }

  BulkItem? findExactItemCode(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final i in displayItems) {
      if (i.itemCode.trim().toLowerCase() == q) return i;
    }
    return null;
  }
}
