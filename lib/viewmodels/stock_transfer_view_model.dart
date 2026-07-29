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
      // Page load so Stock Transfer open doesn't freeze the UI on large DBs.
      const pageSize = 3000;
      final all = <BulkItem>[];
      var offset = 0;
      while (true) {
        final batch =
            await _dbService.getLabelledBulkItemsPaged(pageSize, offset);
        if (batch.isEmpty) break;
        all.addAll(batch);
        offset += batch.length;
        await Future<void>.delayed(Duration.zero);
        if (batch.length < pageSize) break;
        if (all.length >= 20000) break;
      }
      allLabelledItems = all;
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
    // Sparkle: if destination branch unknown, filtered list is empty (not all employees).
    if (branchId == null || branchId <= 0) return const [];
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
    } else if (isBranchToBranch) {
      // Type 15 always resolves From/To as branches even if name parse differs.
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

  /// Sparkle submit: `UserPreferences.getBranchID()` (login-saved defaultBranchId).
  int sparkleSubmitBranchId() {
    final prefsBranch = _prefService.getBranchId();
    if (prefsBranch > 0) return prefsBranch;
    return _prefService.getEmployee()?.defaultBranchId ?? 0;
  }

  /// Sparkle StockInScreen list: `employee?.branchNo ?: 0` — keep 0 when BranchNo is null.
  /// Do NOT substitute defaultBranchId here (that was returning empty for LS000419).
  int sparkleListBranchId() {
    return _prefService.getEmployee()?.branchNo ?? 0;
  }

  /// Same payload rules as Sparkle [StockTransferPreviewScreen] OK handler.
  Future<bool> submitTransfer({
    required String transferToEmployee,
    required String remarks,
  }) async {
    final employee = _prefService.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    if (clientCode.isEmpty || selectedTransferType == null) {
      transferStatusMessage = 'Missing client or transfer type';
      return false;
    }

    await ensureTransferTypesLoaded();
    final typeId = transferTypeId;
    if (typeId <= 0) {
      transferStatusMessage = 'Invalid transfer type';
      return false;
    }

    // Exact Sparkle: sourceBranch = UserPreferences.getBranchID()
    final sourceBranch = sparkleSubmitBranchId();
    if (sourceBranch <= 0) {
      transferStatusMessage = 'Missing branch id';
      return false;
    }

    final transferByEmployee = employee?.employeeId?.toString() ?? '';
    if (transferByEmployee.isEmpty) {
      transferStatusMessage = 'Missing employee id';
      return false;
    }

    // Default: same user / same branch (counter↔box, etc.)
    var transferTo = transferByEmployee;
    var transferToBranch = sourceBranch.toString();
    var destinationBranch = sourceBranch;

    if (isBranchToBranch) {
      final other = transferToEmployee.trim();
      if (other.isEmpty) {
        transferStatusMessage = 'Please select an employee';
        return false;
      }
      transferTo = other;
      destinationBranch = destinationBranchId ?? sourceBranch;
      transferToBranch = destinationBranch.toString();
    }

    final fromType = _fromType;
    final toType = _toType;
    final fromName =
        selectedFrom != fromPlaceholder && selectedFrom.trim().isNotEmpty ? selectedFrom.trim() : '';
    final toName =
        selectedTo != toPlaceholder && selectedTo.trim().isNotEmpty ? selectedTo.trim() : '';

    final sourceId = isBranchToBranch
        ? sourceBranch
        : (fromName.isNotEmpty && fromType != null && fromType.isNotEmpty
            ? await resolveEntityId(fromType, fromName)
            : sourceBranch);

    final destinationId = isBranchToBranch
        ? destinationBranch
        : (toName.isNotEmpty && toType != null && toType.isNotEmpty
            ? await resolveEntityId(toType, toName)
            : sourceBranch);

    final transferredKeys = previewItems.map(itemKey).where((k) => k.isNotEmpty).toSet();
    final stockItems = previewItems
        .map((e) {
          // Sparkle: bulkItemId ?: itemCode.toInt — keep positive ids only.
          final stockId = e.bulkItemId > 0 ? e.bulkItemId : (int.tryParse(e.itemCode) ?? 0);
          return stockId > 0 ? StockTransferItemPayload(stockId: stockId) : null;
        })
        .whereType<StockTransferItemPayload>()
        .toList();
    if (stockItems.isEmpty) {
      transferStatusMessage = 'No valid stock items to transfer';
      return false;
    }

    final request = StockTransferRequest(
      clientCode: clientCode,
      stockTransferItems: stockItems,
      stockType: 'labelled',
      stockTransferTypeName: selectedTransferType!,
      transferTypeId: typeId,
      transferByEmployee: transferByEmployee,
      transferedToBranch: transferToBranch,
      transferToEmployee: transferTo,
      transferedBranch: sourceBranch.toString(),
      source: sourceId,
      destination: destinationId,
      remarks: remarks,
      stockTransferDate: DateFormat('dd-MM-yyyy').format(DateTime.now()),
      receivedByEmployee: '',
    );

    debugPrint(
      'submitTransfer Sparkle-parity: '
      'TransferedBranch=$sourceBranch listBranch=${sparkleListBranchId()} '
      'userId=${employee?.id} employeeId=${employee?.employeeId} '
      'typeId=$typeId source=$sourceId dest=$destinationId items=${stockItems.length}',
    );

    isLoading = true;
    transferStatusMessage = null;
    notifyListeners();
    try {
      final ok = await _apiService.addStockTransfer(request);
      transferStatusMessage = ok ? 'Transfer successful' : 'Transfer failed';
      if (ok) {
        previewItems = [];
        if (transferredKeys.isNotEmpty) {
          filteredItems =
              filteredItems.where((i) => !transferredKeys.contains(itemKey(i))).toList();
          allLabelledItems =
              allLabelledItems.where((i) => !transferredKeys.contains(itemKey(i))).toList();
        }
      }
      return ok;
    } catch (e) {
      transferStatusMessage = e.toString();
      return false;
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

    final clientCode = employee.clientCode ?? '';
    if (clientCode.isEmpty) return [];

    // Exact Sparkle StockInScreen.fetchStockTransfers:
    //   BranchId = employee?.branchNo ?: 0
    //   UserID   = employee?.id ?: 0
    // When BranchNo is null (this account), Sparkle queries BranchId=0 — NOT defaultBranchId.
    final listBranchId = sparkleListBranchId(); // 0 when branchNo null
    final userId = employee.id;
    final submitBranch = sparkleSubmitBranchId();

    Future<List<StockTransferInOutItem>> fetch(int branchId, int uid) {
      debugPrint(
        'GetAllStockTransfers Sparkle-parity: '
        'RequestType=$requestType BranchId=$branchId UserID=$uid '
        'branchNo=${employee.branchNo} prefs=$submitBranch '
        'default=${employee.defaultBranchId} TransferType=$transferTypeFilterId',
      );
      return _apiService.getAllStockTransfers(
        StockInOutRequest(
          clientCode: clientCode,
          transferType: transferTypeFilterId,
          branchId: branchId,
          userId: uid,
          requestType: requestType,
        ),
      );
    }

    final byId = <int, StockTransferInOutItem>{};

    void merge(List<StockTransferInOutItem> list) {
      for (final item in list) {
        if (item.id > 0) byId[item.id] = item;
      }
    }

    // 1) Exact Sparkle query first (BranchId=0 when branchNo null).
    merge(await fetch(listBranchId, userId));

    // 2) Also try submit branch (defaultBranchId) — covers TransferedBranch from AddStockTransfer.
    if (submitBranch > 0 && submitBranch != listBranchId) {
      merge(await fetch(submitBranch, userId));
    }

    // 3) If still empty, try EmployeeId as UserID (some backends key Off EmpId).
    final empId = employee.employeeId ?? 0;
    if (byId.isEmpty && empId > 0 && empId != userId) {
      debugPrint('GetAllStockTransfers retry UserID=employeeId=$empId');
      merge(await fetch(listBranchId, empId));
      if (submitBranch > 0 && submitBranch != listBranchId) {
        merge(await fetch(submitBranch, empId));
      }
    }

    debugPrint('GetAllStockTransfers merged count=${byId.length}');
    return byId.values.toList();
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
    final q = query.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (q.isEmpty) return null;
    for (final i in filteredItems) {
      final code = i.itemCode.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
      final epc = i.epc.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
      final rfid = i.rfid.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
      if (code == q || epc == q || rfid == q) return i;
    }
    return null;
  }
}
