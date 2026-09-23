import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/bulk_item.dart';
import '../models/stock_transfer_models.dart';
import '../models/user_permission.dart';
import '../models/wholesale_master.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/label_stock_sync_service.dart';
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

  bool get isBranchToBranch {
    if (transferTypeId == 15) return true;
    return _fromType == 'branch' && _toType == 'branch';
  }

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
  List<WholesaleCounter> _masterCounters = [];
  List<WholesaleBranch> _branchMasters = [];
  bool _masterLocationsLoaded = false;

  static const String fromPlaceholder = '__from__';
  static const String toPlaceholder = '__to__';
  static const String transferTypePlaceholder = '__transfer_type__';
  static const String categoryPlaceholder = '__category__';
  static const String productPlaceholder = '__product__';
  static const String designPlaceholder = '__design__';

  bool _initialized = false;
  int _formEpoch = 0;

  int get formEpoch => _formEpoch;

  bool _epochOk(int? epoch) => epoch == null || epoch == _formEpoch;

  /// Clears From/To/type/preview when Stock Transfer is opened again.
  /// Keeps labelled stock in memory so reopen stays fast.
  void resetTransferForm({bool notify = true}) {
    _formEpoch++;
    selectedTransferType = null;
    selectedFrom = fromPlaceholder;
    selectedTo = toPlaceholder;
    appliedCategory = null;
    appliedProduct = null;
    appliedDesign = null;
    sourceBranchId = null;
    destinationBranchId = null;
    previewItems = [];
    errorMessage = null;
    transferStatusMessage = null;
    if (allLabelledItems.isNotEmpty) {
      filteredItems = List.from(allLabelledItems);
    }
    if (notify) notifyListeners();
  }

  void resetSession() {
    _formEpoch++;
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
    _masterCounters = [];
    _branchMasters = [];
    _masterLocationsLoaded = false;
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
    final epoch = _formEpoch;
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
      if (epoch != _formEpoch) {
        filteredItems = List.from(allLabelledItems);
        notifyListeners();
        return;
      }
      // If From is set with a transfer type, keep that filter; else show all.
      if (selectedTransferType != null &&
          selectedFrom != fromPlaceholder &&
          _fromType != null) {
        final filtered = await _dbService.getLabelledBulkItemsFiltered(
          fromType: _fromType!,
          fromValue: selectedFrom,
        );
        if (epoch != _formEpoch) {
          filteredItems = List.from(allLabelledItems);
        } else {
          filteredItems = filtered;
        }
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
      if (clientCode.isNotEmpty) {
        await ensureMasterLocationsLoaded();
      }
      final apiCounters = _masterCounters.map((c) => c.name).where((n) => n.trim().isNotEmpty);
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
    if (allEmployees.isEmpty) return const [];

    List<UserPermission> byId() {
      if (branchId == null || branchId <= 0) return const [];
      return allEmployees.where((emp) {
        return parseBranchSelectionJson(emp.branchSelectionJson).any((b) => b.id == branchId);
      }).toList();
    }

    final matchedId = byId();
    if (matchedId.isNotEmpty) return matchedId;

    final destName = selectedTo.trim().toLowerCase();
    if (destName.isNotEmpty && destName != toPlaceholder) {
      final matchedName = allEmployees.where((emp) {
        return parseBranchSelectionJson(emp.branchSelectionJson).any(
          (b) => b.name.trim().toLowerCase() == destName,
        );
      }).toList();
      if (matchedName.isNotEmpty) return matchedName;
    }

    // Keep the dropdown usable if branch filter could not match.
    return List<UserPermission>.from(allEmployees);
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

  void selectTransferType(String type, {int? epoch}) {
    if (!_epochOk(epoch)) return;
    selectedTransferType = type;
    selectedFrom = fromPlaceholder;
    selectedTo = toPlaceholder;
    sourceBranchId = null;
    destinationBranchId = null;
    if (isBranchToBranch) {
      loadUserPermissions();
    }
    // Keep showing all labelled stock until From is chosen.
    unawaited(loadAllLabelledStock());
  }

  Future<void> selectFrom(String value, {int? epoch}) async {
    if (!_epochOk(epoch)) return;
    if (value == fromPlaceholder) return;
    final start = _formEpoch;
    selectedFrom = value;
    await _applyFromFilter();
    if (start != _formEpoch) return;
    _clearCategoryFilters(clearChecks: true);
    notifyListeners();
  }

  Future<void> selectTo(String value, {int? epoch}) async {
    if (!_epochOk(epoch)) return;
    if (value == toPlaceholder) return;
    final start = _formEpoch;
    selectedTo = value;
    if (isBranchToBranch) {
      sourceBranchId = await _resolveBranchId(selectedFrom);
      destinationBranchId = await _resolveBranchId(selectedTo);
    }
    if (start != _formEpoch) return;
    notifyListeners();
  }

  Future<int?> _resolveBranchId(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == fromPlaceholder || trimmed == toPlaceholder) {
      return null;
    }
    final dbId = await _dbService.getEntityIdByName('branch', trimmed);
    if (dbId != null && dbId > 0) return dbId;

    await ensureMasterLocationsLoaded();
    final needle = trimmed.toLowerCase();
    for (final branch in _branchMasters) {
      if (branch.id > 0 && branch.name.trim().toLowerCase() == needle) {
        return branch.id;
      }
    }
    for (final emp in allEmployees) {
      for (final branch in parseBranchSelectionJson(emp.branchSelectionJson)) {
        if (branch.id > 0 && branch.name.trim().toLowerCase() == needle) {
          return branch.id;
        }
      }
    }
    return null;
  }

  Future<void> ensureBranchIdsForTransfer() async {
    if (!isBranchToBranch) return;
    if (allEmployees.isEmpty) {
      await loadUserPermissions();
    }
    if (sourceBranchId == null || sourceBranchId! <= 0) {
      sourceBranchId = await _resolveBranchId(selectedFrom);
    }
    if (destinationBranchId == null || destinationBranchId! <= 0) {
      destinationBranchId = await _resolveBranchId(selectedTo);
    }
    notifyListeners();
  }

  Future<void> _applyFromFilter() async {
    final epoch = _formEpoch;
    final fromType = _fromType;
    if (fromType == null || selectedFrom == fromPlaceholder) {
      await loadAllLabelledStock();
      return;
    }
    try {
      var next = await _dbService.getLabelledBulkItemsFiltered(
        fromType: fromType,
        fromValue: selectedFrom.trim(),
      );
      if (epoch != _formEpoch) return;
      // If exact name match found nothing, try case-insensitive contains from local cache.
      if (next.isEmpty && allLabelledItems.isNotEmpty) {
        final needle = selectedFrom.trim().toLowerCase();
        next = allLabelledItems.where((item) {
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
      if (epoch != _formEpoch) return;
      filteredItems = next;
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
    int? epoch,
  }) {
    if (!_epochOk(epoch)) return;
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
    if (transferTypes.isEmpty) {
      final clientCode = _prefService.getEmployee()?.clientCode ?? '';
      if (clientCode.isNotEmpty) {
        try {
          transferTypes = await _apiService.getStockTransferTypes(clientCode);
          notifyListeners();
        } catch (e) {
          debugPrint('ensureTransferTypesLoaded error: $e');
        }
      }
    }
    await ensureMasterLocationsLoaded();
  }

  Future<void> ensureMasterLocationsLoaded() async {
    if (_masterLocationsLoaded) return;
    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    if (clientCode.isEmpty) return;
    try {
      _masterCounters = await _apiService.getAllCounters(clientCode);
      _branchMasters = await _apiService.getWholesaleBranches(clientCode);
      _masterLocationsLoaded = true;
    } catch (e) {
      debugPrint('ensureMasterLocationsLoaded error: $e');
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
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 0;
    await ensureMasterLocationsLoaded();
    if (type.toLowerCase() == 'counter') {
      for (final counter in _masterCounters) {
        if (counter.id > 0 &&
            counter.name.trim().toLowerCase() == trimmed.toLowerCase()) {
          return counter.id;
        }
      }
    }
    return await _dbService.getEntityIdByName(type, trimmed) ?? 0;
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

  Future<void> _applyLocalTransferMove({
    required List<BulkItem> moved,
    required String? toType,
    required String toName,
    required int destId,
  }) async {
    if (moved.isEmpty) return;
    if (toName.trim().isEmpty && destId <= 0) return;
    int? branchId;
    String? branchName;
    int? counterId;
    String? counterName;
    int? boxId;
    String? boxName;
    int? packetId;
    String? packetName;
    final type = (toType ?? '').trim().toLowerCase();
    if (type == 'branch') {
      branchId = destId > 0 ? destId : null;
      branchName = toName.trim();
      // Arrives at dest branch — drop source counter/box so Baner filter sees it.
      counterId = 0;
      counterName = '';
      boxId = 0;
      boxName = '';
      packetId = 0;
      packetName = '';
    } else if (type == 'counter') {
      counterId = destId > 0 ? destId : null;
      counterName = toName.trim();
    } else if (type == 'box') {
      boxId = destId > 0 ? destId : null;
      boxName = toName.trim();
    } else if (type == 'packet') {
      packetId = destId > 0 ? destId : null;
      packetName = toName.trim();
    }
    if (branchName == null &&
        counterName == null &&
        boxName == null &&
        packetName == null) {
      return;
    }

    try {
      await _dbService.updateStockTransferLocations(
        items: moved,
        branchId: branchId,
        branchName: branchName,
        counterId: counterId,
        counterName: counterName,
        boxId: boxId,
        boxName: boxName,
        packetId: packetId,
        packetName: packetName,
      );
    } catch (e) {
      debugPrint('_applyLocalTransferMove db: $e');
    }

    final keys = moved.map(itemKey).where((k) => k.isNotEmpty).toSet();
    BulkItem relocate(BulkItem item) {
      final map = item.toMap();
      if (branchId != null) map['branchId'] = branchId;
      if (branchName != null) map['branchName'] = branchName;
      if (counterId != null) map['counterId'] = counterId;
      if (counterName != null) map['counterName'] = counterName;
      if (boxId != null) map['boxId'] = boxId;
      if (boxName != null) {
        map['boxName'] = boxName;
        map['box'] = boxName;
      }
      if (packetId != null) map['packetId'] = packetId;
      if (packetName != null) map['packetName'] = packetName;
      return BulkItem.fromMap(map);
    }

    List<BulkItem> remap(List<BulkItem> list) => [
          for (final item in list)
            keys.contains(itemKey(item)) ? relocate(item) : item,
        ];
    allLabelledItems = remap(allLabelledItems);
    filteredItems = remap(filteredItems);
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

    if (isBranchToBranch) {
      final other = transferToEmployee.trim();
      if (other.isEmpty) {
        transferStatusMessage = 'Please select an employee';
        return false;
      }
      transferTo = other;
    }

    final fromType = _fromType;
    final toType = _toType;
    final fromName =
        selectedFrom != fromPlaceholder && selectedFrom.trim().isNotEmpty ? selectedFrom.trim() : '';
    final toName =
        selectedTo != toPlaceholder && selectedTo.trim().isNotEmpty ? selectedTo.trim() : '';

    late final int sourceId;
    late final int destinationId;
    late final String transferedBranch;
    late final String transferToBranch;

    if (isBranchToBranch) {
      final fromId = (sourceBranchId != null && sourceBranchId! > 0)
          ? sourceBranchId!
          : (await _resolveBranchId(fromName) ?? 0);
      var toId = (destinationBranchId != null && destinationBranchId! > 0)
          ? destinationBranchId!
          : (await _resolveBranchId(toName) ?? 0);
      if (toId <= 0 && toName.isNotEmpty) {
        toId = await resolveEntityId('branch', toName);
      }
      if (toId <= 0) {
        transferStatusMessage = 'Could not resolve destination branch';
        return false;
      }
      sourceId = fromId > 0 ? fromId : sourceBranch;
      destinationId = toId;
      sourceBranchId = sourceId;
      destinationBranchId = destinationId;
      transferedBranch = sourceId.toString();
      transferToBranch = destinationId.toString();
    } else {
      sourceId = fromName.isNotEmpty && fromType != null && fromType.isNotEmpty
          ? await resolveEntityId(fromType, fromName)
          : sourceBranch;
      destinationId = toName.isNotEmpty && toType != null && toType.isNotEmpty
          ? await resolveEntityId(toType, toName)
          : sourceBranch;
      transferedBranch = sourceBranch.toString();
      transferToBranch = sourceBranch.toString();
    }

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
      transferedBranch: transferedBranch,
      source: sourceId,
      destination: destinationId,
      remarks: remarks,
      stockTransferDate: DateFormat('dd-MM-yyyy').format(DateTime.now()),
      receivedByEmployee: '',
    );

    debugPrint(
      'submitTransfer Sparkle-parity: '
      'TransferedBranch=$transferedBranch TransferedToBranch=$transferToBranch '
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
        // Stock stays at From until In/Out approve (B2B: Pune until Baner accepts).
        resetTransferForm(notify: false);
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
    var anySuccess = false;

    Future<void> mergeFetch(int branchId, int uid) async {
      try {
        final list = await fetch(branchId, uid);
        anySuccess = true;
        for (final item in list) {
          if (item.id > 0) byId[item.id] = item;
        }
      } catch (e) {
        debugPrint('GetAllStockTransfers fetch failed branch=$branchId user=$uid: $e');
      }
    }

    // 1) Exact Sparkle query first (BranchId=0 when branchNo null).
    await mergeFetch(listBranchId, userId);

    // 2) Also try submit branch (defaultBranchId) — covers TransferedBranch from AddStockTransfer.
    if (submitBranch > 0 && submitBranch != listBranchId) {
      await mergeFetch(submitBranch, userId);
    }

    // 3) If still empty, try EmployeeId as UserID (some backends key Off EmpId).
    final empId = employee.employeeId ?? 0;
    if (byId.isEmpty && empId > 0 && empId != userId) {
      debugPrint('GetAllStockTransfers retry UserID=employeeId=$empId');
      await mergeFetch(listBranchId, empId);
      if (submitBranch > 0 && submitBranch != listBranchId) {
        await mergeFetch(submitBranch, empId);
      }
    }

    if (!anySuccess && byId.isEmpty) {
      throw Exception('Failed to load stock transfers');
    }

    debugPrint('GetAllStockTransfers merged count=${byId.length}');
    return _resolveInOutFromToNames(byId.values.toList());
  }

  Future<List<StockTransferInOutItem>> _resolveInOutFromToNames(
    List<StockTransferInOutItem> items,
  ) async {
    if (items.isEmpty) return items;
    await ensureMasterLocationsLoaded();

    final allIds = items.expand((item) => [item.source ?? 0, item.destination ?? 0]);
    final namesByType = <String, Map<int, String>>{
      'counter': await _dbService.getEntityNamesByIds('counter', allIds),
      'box': await _dbService.getEntityNamesByIds('box', allIds),
      'branch': await _dbService.getEntityNamesByIds('branch', allIds),
      'packet': await _dbService.getEntityNamesByIds('packet', allIds),
    };
    for (final counter in _masterCounters) {
      if (counter.id > 0 && counter.name.trim().isNotEmpty) {
        namesByType['counter']![counter.id] = counter.name.trim();
      }
    }

    String? nameFor(String? type, int? id) {
      final locId = id ?? 0;
      if (locId <= 0) return null;
      if (type != null && type.isNotEmpty) {
        final typed = namesByType[type]?[locId]?.trim();
        if (typed != null && typed.isNotEmpty) return typed;
        return null;
      }
      for (final map in namesByType.values) {
        final found = map[locId]?.trim();
        if (found != null && found.isNotEmpty) return found;
      }
      return null;
    }

    final resolved = <StockTransferInOutItem>[];
    for (final item in items) {
      final (fromType, toType) = parseTransferEndpointTypes(item.stockTransferTypeName);
      final firstLine =
          item.labelledStockItems.isNotEmpty ? item.labelledStockItems.first : null;

      // Only explicit From/To names — never the stock's current counter/box for To.
      // Counter→Counter stock is still at From (Counter1) until approved.
      String? from = cleanTransferLocationName(item.sourceName) ??
          cleanTransferLocationName(firstLine?.sourceName);
      String? to = cleanTransferLocationName(item.destinationName) ??
          cleanTransferLocationName(firstLine?.destinationName);

      from ??= nameFor(fromType, item.source);
      to ??= nameFor(toType, item.destination);

      if (from == null) {
        from = firstLine?.locationNameForType(fromType);
        final stockId = firstLine?.id ?? 0;
        if (from == null && stockId > 0) {
          final loc = await _dbService.getStockLocationNames(stockId);
          from = cleanTransferLocationName(fromType != null ? loc[fromType] : null) ??
              cleanTransferLocationName(loc['counter']) ??
              cleanTransferLocationName(loc['box']) ??
              cleanTransferLocationName(loc['branch']) ??
              cleanTransferLocationName(loc['packet']);
        }
      }

      if (to == null && (toType == null || toType == 'branch')) {
        to = cleanTransferLocationName(item.transferedToBranch) ??
            nameFor('branch', int.tryParse(item.transferedToBranch.trim()));
      }

      resolved.add(item.withFromTo(from ?? '-', to ?? '-'));
    }
    return resolved;
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

  BulkItem _bulkFromLabelled(LabelledStockItem e) {
    return BulkItem.fromMap({
      'bulkItemId': e.id ?? 0,
      'itemCode': e.itemCode ?? '',
      'rfid': e.rfidCode ?? '',
      'epc': e.rfidCode ?? '',
      'productName': e.productName ?? '',
      'branchId': e.branchId ?? 0,
      'branchName': e.branchName ?? '',
    });
  }

  /// After Approve succeeds, move those labelled rows onto the destination
  /// (Baner after Pune→Baner). Server LabelStock can lag; keep this local.
  Future<void> applyApprovedTransferDestination({
    required List<LabelledStockItem> items,
    required String transferTypeName,
    int? destinationId,
    String destinationName = '',
    String transferedToBranch = '',
  }) async {
    if (items.isEmpty) return;
    final (_, toType) = parseTransferEndpointTypes(transferTypeName);
    var toName = cleanTransferLocationName(destinationName) ??
        cleanTransferLocationName(transferedToBranch) ??
        '';
    var destId = destinationId ?? 0;
    final locType = (toType == null || toType.isEmpty) ? 'branch' : toType;
    if (destId <= 0 && toName.isNotEmpty) {
      if (locType == 'branch') {
        destId = await _resolveBranchId(toName) ?? 0;
      } else {
        destId = await resolveEntityId(locType, toName);
      }
    }
    if (toName.isEmpty && destId > 0) {
      final names = await _dbService.getEntityNamesByIds(locType, [destId]);
      toName = names[destId]?.trim() ?? '';
    }
    if (toName.isEmpty && destId > 0 && locType == 'branch') {
      await ensureMasterLocationsLoaded();
      for (final branch in _branchMasters) {
        if (branch.id == destId && branch.name.trim().isNotEmpty) {
          toName = branch.name.trim();
          break;
        }
      }
    }
    if (toName.isEmpty && destId <= 0) {
      debugPrint('applyApprovedTransferDestination skipped — no dest');
      return;
    }

    final moved = items
        .map(_bulkFromLabelled)
        .where(
          (b) =>
              b.bulkItemId > 0 ||
              b.itemCode.trim().isNotEmpty ||
              b.rfid.trim().isNotEmpty,
        )
        .toList();
    await _applyLocalTransferMove(
      moved: moved,
      toType: locType,
      toName: toName,
      destId: destId,
    );
    LabelStockSyncService.onLocalStockChanged?.call();
    debugPrint(
      'applyApprovedTransferDestination type=$locType dest=$destId '
      'name=$toName items=${moved.length}',
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
