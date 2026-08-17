import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../models/employee.dart';
import '../models/order_item.dart';
import '../models/bulk_item.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/list_json_cache.dart';
import '../services/pref_service.dart';

/// ViewModel for the Quotation create/edit screen and quotation list.
/// Quotation line items reuse the [OrderItem] model since the data shape is
/// identical to a custom order item.
class QuotationViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final DbService _dbService;
  final ApiService _apiService;

  QuotationViewModel({
    required PrefService prefService,
    required DbService dbService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _dbService = dbService,
        _apiService = apiService;

  String get baseUrl => _apiService.baseUrl;

  List<CustomerModel> _customers = [];
  List<CustomerModel> get customers => _customers;

  List<dynamic> _dailyRates = [];
  List<dynamic> get dailyRates => _dailyRates;

  List<dynamic> _branches = [];
  List<dynamic> get branches => _branches;

  final List<OrderItem> _productList = [];
  List<OrderItem> get productList => _productList;

  CustomerModel? _selectedCustomer;
  CustomerModel? get selectedCustomer => _selectedCustomer;

  bool _isGstChecked = true;
  bool get isGstChecked => _isGstChecked;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  DateTime? _lastMasterLoadAt;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _lastQuotationNo = 0;
  int get lastQuotationNo => _lastQuotationNo;

  // ---- Master data ---------------------------------------------------------
  Future<void> loadMasterData({bool force = false}) async {
    if (!force &&
        _customers.isNotEmpty &&
        _lastMasterLoadAt != null &&
        DateTime.now().difference(_lastMasterLoadAt!) < const Duration(minutes: 5)) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final rawCustomers = await _apiService.getAllCustomers(code);
      _customers = rawCustomers.map((c) => CustomerModel.fromJson(c as Map<String, dynamic>)).toList();
      _dailyRates = await _apiService.getDailyRates(code);
      _branches = await _apiService.getAllBranches(code);

      final lastNoRes = await _apiService.getLastQuotationNo(code);
      if (lastNoRes != null) {
        final raw = lastNoRes['LastQuotationNo'];
        _lastQuotationNo = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
      }
      _lastMasterLoadAt = DateTime.now();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSelectedCustomer(CustomerModel? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  void setGstChecked(bool value) {
    _isGstChecked = value;
    notifyListeners();
  }

  Future<bool> addCustomerProfile(Map<String, dynamic> req) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _apiService.addCustomer(req);
      if (result != null) {
        final code = _prefService.getEmployee()?.clientCode ?? '';
        final rawCustomers = await _apiService.getAllCustomers(code);
        _customers = rawCustomers.map((c) => CustomerModel.fromJson(c as Map<String, dynamic>)).toList();
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  double _getRateForPurity(String? purity) {
    if (purity == null || purity.isEmpty) return 0.0;
    final cleanPurity = purity.trim().toLowerCase();
    for (final rateObj in _dailyRates) {
      final purityName = (rateObj['PurityName'] as String? ?? '').trim().toLowerCase();
      if (purityName == cleanPurity) {
        return double.tryParse(rateObj['Rate']?.toString() ?? '') ?? 0.0;
      }
    }
    return 0.0;
  }

  OrderItem _buildItem(BulkItem matchedItem) {
    final rate = _getRateForPurity(matchedItem.purity);
    final netWt = double.tryParse(matchedItem.netWeight) ?? 0.0;
    final stoneAmt = double.tryParse(matchedItem.stoneAmount) ?? 0.0;
    final diamondAmt = double.tryParse(matchedItem.diamondAmount) ?? 0.0;

    final makingPerGram = double.tryParse(matchedItem.makingPerGram) ?? 0.0;
    final makingFixedAmt = double.tryParse(matchedItem.fixMaking) ?? 0.0;
    final makingPercent = double.tryParse(matchedItem.makingPercent) ?? 0.0;
    final makingFixedWastage = double.tryParse(matchedItem.fixWastage) ?? 0.0;

    final metalAmt = netWt * rate;
    final makingAmt = makingPerGram + makingFixedAmt + ((makingPercent / 100.0) * netWt) + makingFixedWastage;
    final itemAmt = stoneAmt + diamondAmt + metalAmt + makingAmt;
    final fineWt = netWt * makingPercent / 100.0;

    final employee = _prefService.getEmployee();

    return OrderItem(
      rfidCode: matchedItem.rfid.isNotEmpty ? matchedItem.rfid : matchedItem.itemCode,
      branchId: (matchedItem.branchId != 0 ? matchedItem.branchId : (employee?.defaultBranchId ?? 0)).toString(),
      branchName: matchedItem.branchName,
      exhibition: '',
      remark: '',
      purity: matchedItem.purity,
      size: '1',
      length: '',
      typeOfColor: '',
      screwType: '',
      polishType: '',
      finePer: makingPercent.toString(),
      wastage: matchedItem.makingPercent,
      orderDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      deliverDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      productName: matchedItem.productName,
      itemCode: matchedItem.itemCode,
      grWt: matchedItem.grossWeight,
      nWt: matchedItem.netWeight,
      stoneAmt: matchedItem.stoneAmount,
      finePlusWt: fineWt.toStringAsFixed(3),
      itemAmt: itemAmt.toStringAsFixed(2),
      packingWt: matchedItem.netWeight,
      totalWt: matchedItem.totalWt.toString(),
      stoneWt: matchedItem.totalStoneWt.toString(),
      dimondWt: matchedItem.diamondWeight,
      sku: matchedItem.sku,
      qty: '1',
      hallmarkAmt: '0.0',
      mrp: matchedItem.mrp.toString(),
      image: matchedItem.imageUrl,
      netAmt: itemAmt.toStringAsFixed(2),
      diamondAmt: matchedItem.diamondAmount,
      categoryId: matchedItem.categoryId,
      categoryName: matchedItem.category,
      productId: matchedItem.productId,
      productCode: matchedItem.productCode,
      skuId: matchedItem.skuId,
      designid: matchedItem.designId,
      designName: matchedItem.design,
      purityid: matchedItem.purityId,
      counterId: matchedItem.counterId,
      counterName: matchedItem.counterName,
      companyId: 0,
      epc: matchedItem.epc,
      tid: matchedItem.tid,
      todaysRate: rate.toStringAsFixed(2),
      makingPercentage: matchedItem.makingPercent,
      makingFixedAmt: matchedItem.fixMaking,
      makingFixedWastage: matchedItem.fixWastage,
      makingPerGram: matchedItem.makingPerGram,
      categoryWt: matchedItem.categoryWt,
    );
  }

  Future<String?> addProductByCodeOrRfid(String codeQuery) async {
    final query = codeQuery.trim().toUpperCase();
    if (query.isEmpty) return 'Please enter item code or RFID';

    final matchedItem = _dbService.findBulkItemByScanKeySync(codeQuery) ??
        await _dbService.findBulkItemByScanKey(codeQuery);

    if (matchedItem == null) {
      return 'No item found with code/RFID: $codeQuery';
    }

    final exists = _productList.any(
      (x) =>
          x.itemCode.toUpperCase() == matchedItem.itemCode.toUpperCase() ||
          x.rfidCode.toUpperCase() == matchedItem.rfid.toUpperCase() ||
          x.tid.toUpperCase() == matchedItem.tid.toUpperCase(),
    );
    if (exists) return 'Item already added';

    _productList.add(_buildItem(matchedItem));
    notifyListeners();
    return null;
  }

  Future<int> processScannedTags(List<String> epcs) async {
    int addedCount = 0;
    await _dbService.warmScanKeyIndex();

    for (final epcRaw in epcs) {
      final epc = epcRaw.trim().toUpperCase().replaceAll(' ', '');
      if (epc.isEmpty) continue;

      final matchedItem = _dbService.findBulkItemByScanKeySync(epcRaw) ??
          await _dbService.findBulkItemByScanKey(epcRaw);
      if (matchedItem == null) continue;

      final exists = _productList.any((x) => x.tid == matchedItem.tid || x.epc == matchedItem.epc);
      if (exists) continue;

      _productList.add(_buildItem(matchedItem));
      addedCount++;
    }

    if (addedCount > 0) notifyListeners();
    return addedCount;
  }

  void updateItem(int index, OrderItem updated) {
    if (index >= 0 && index < _productList.length) {
      _productList[index] = updated;
      notifyListeners();
    }
  }

  void updateAllItemsDetails({
    required String branchId,
    required String branchName,
    required String exhibition,
    required String remark,
    required String purity,
    required String size,
    required String length,
    required String color,
    required String screw,
    required String polish,
    required String wastage,
    required String orderDate,
    required String deliverDate,
  }) {
    for (int i = 0; i < _productList.length; i++) {
      final current = _productList[i];
      final rate = _getRateForPurity(purity.isNotEmpty ? purity : current.purity);
      final netWt = double.tryParse(current.nWt ?? '') ?? 0.0;
      final stoneAmt = double.tryParse(current.stoneAmt ?? '') ?? 0.0;
      final diamondAmt = double.tryParse(current.diamondAmt) ?? 0.0;
      final makingPerGram = double.tryParse(current.makingPerGram) ?? 0.0;
      final makingFixedAmt = double.tryParse(current.makingFixedAmt) ?? 0.0;
      final makingPercent = double.tryParse(wastage.isNotEmpty ? wastage : current.makingPercentage) ?? 0.0;
      final makingFixedWastage = double.tryParse(current.makingFixedWastage) ?? 0.0;
      final metalAmt = netWt * rate;
      final makingAmt = makingPerGram + makingFixedAmt + ((makingPercent / 100.0) * netWt) + makingFixedWastage;
      final itemAmt = stoneAmt + diamondAmt + metalAmt + makingAmt;

      _productList[i] = current.copyWith(
        branchId: branchId.isNotEmpty ? branchId : current.branchId,
        branchName: branchName.isNotEmpty ? branchName : current.branchName,
        exhibition: exhibition.isNotEmpty ? exhibition : current.exhibition,
        remark: remark.isNotEmpty ? remark : current.remark,
        purity: purity.isNotEmpty ? purity : current.purity,
        size: size.isNotEmpty ? size : current.size,
        length: length.isNotEmpty ? length : current.length,
        typeOfColor: color.isNotEmpty ? color : current.typeOfColor,
        screwType: screw.isNotEmpty ? screw : current.screwType,
        polishType: polish.isNotEmpty ? polish : current.polishType,
        wastage: wastage.isNotEmpty ? wastage : current.wastage,
        makingPercentage: wastage.isNotEmpty ? wastage : current.makingPercentage,
        orderDate: orderDate.isNotEmpty ? orderDate : current.orderDate,
        deliverDate: deliverDate.isNotEmpty ? deliverDate : current.deliverDate,
        todaysRate: rate.toStringAsFixed(2),
        itemAmt: itemAmt.toStringAsFixed(2),
        netAmt: itemAmt.toStringAsFixed(2),
      );
    }
    notifyListeners();
  }

  void deleteItem(int index) {
    if (index >= 0 && index < _productList.length) {
      _productList.removeAt(index);
      notifyListeners();
    }
  }

  void clearQuotation() {
    _productList.clear();
    _selectedCustomer = null;
    notifyListeners();
  }

  // ---- Totals --------------------------------------------------------------
  double getBaseTotal() =>
      _productList.fold(0.0, (sum, item) => sum + (double.tryParse(item.itemAmt ?? '') ?? 0.0));

  double calculateGstAmount() => _isGstChecked ? getBaseTotal() * 0.03 : 0.0;

  double getFinalTotal() => getBaseTotal() + calculateGstAmount();

  double _sum(double Function(OrderItem) sel) => _productList.fold(0.0, (s, it) => s + sel(it));

  // ---- Build a quotation item JSON (matches the Kotlin AddQuotation body) --
  Map<String, dynamic> _quotationItemJson(OrderItem item, String clientCode) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return {
      'ItemCode': item.itemCode,
      'SKU': item.sku,
      'SKUId': item.skuId,
      'CategoryId': item.categoryId ?? 0,
      'CategoryName': item.categoryName,
      'ProductId': item.productId,
      'ProductName': item.productName,
      'DesignId': item.designid,
      'DesignName': item.designName,
      'PurityId': item.purityid,
      'Purity': item.purity,
      'PurityName': item.purity,
      'Quantity': item.qty,
      'Pieces': '1',
      'GrossWt': item.grWt,
      'NetWt': item.nWt,
      'TotalWt': item.totalWt,
      'StoneWt': item.stoneWt,
      'DiamondWeight': item.dimondWt,
      'DiamondWt': item.dimondWt,
      'FinePercentage': item.finePer,
      'FineWastageWt': item.finePlusWt,
      'RatePerGram': item.todaysRate,
      'MetalAmount': item.netAmt,
      'StoneAmount': item.stoneAmt,
      'DiamondAmt': item.diamondAmt,
      'DiamondAmount': item.diamondAmt,
      'MakingPerGram': item.makingPerGram,
      'MakingFixed': item.makingFixedAmt,
      'MakingPercentage': item.makingPercentage,
      'MakingFixedWastage': item.makingFixedWastage,
      'HallmarkAmount': item.hallmarkAmt,
      'MRP': item.mrp,
      'Size': item.size,
      'Amount': item.itemAmt,
      'TotalItemAmount': item.itemAmt,
      'Description': item.remark,
      'Remark': item.remark,
      'Image': item.image,
      'BranchId': int.tryParse(item.branchId) ?? 0,
      'BranchName': item.branchName,
      'CustomerId': _selectedCustomer?.id ?? 0,
      'LabelledStockId': 0,
      'TIDNumber': item.tid,
      'RFIDCode': item.rfidCode,
      'ClientCode': clientCode,
      'CreatedOn': today,
    };
  }

  // ---- Save / Update -------------------------------------------------------
  Future<Map<String, dynamic>?> submitQuotation() async {
    if (_selectedCustomer == null) {
      throw Exception('Please select a customer first.');
    }
    final selectedCustId = _selectedCustomer!.id ?? 0;
    if (selectedCustId <= 0) {
      throw Exception('Please select a customer first.');
    }
    if (_productList.isEmpty) {
      throw Exception('Please add at least one item to the quotation.');
    }

    _isLoading = true;
    notifyListeners();

    try {
      final employee = _prefService.getEmployee();
      final clientCode = employee?.clientCode ?? '';
      // Same branch resolution as quotation list / Sparkle (pref → default).
      final branchId = _resolveBranchId(null, employee);

      // Always refresh the last quotation number before saving.
      final lastNoRes = await _apiService.getLastQuotationNo(clientCode);
      if (lastNoRes != null) {
        final raw = lastNoRes['LastQuotationNo'];
        _lastQuotationNo = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? _lastQuotationNo;
      }
      final nextNo = _isEditMode ? _editingQuotationNo : (_lastQuotationNo + 1).toString();

      final custName =
          '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim();
      final items = _productList.map((it) => _quotationItemJson(it, clientCode)).toList();
      final totalGst = calculateGstAmount();
      // Single quotation date only (list shows QuotationDate).
      // Add → today; Update → keep existing QuotationDate when present.
      final quotationDate = _isEditMode && _editingQuotationDate.isNotEmpty
          ? _editingQuotationDate
          : DateFormat('yyyy-MM-dd').format(DateTime.now());

      final payload = {
        if (_isEditMode) 'Id': _editingQuotationId,
        'ClientCode': clientCode,
        'BranchId': branchId,
        'CustomerId': selectedCustId.toString(),
        'CustomerName': custName,
        'FirstName': _selectedCustomer!.firstName ?? '',
        'LastName': _selectedCustomer!.lastName ?? '',
        'MobileNo': _selectedCustomer!.mobile ?? '',
        'Mobile': _selectedCustomer!.mobile ?? '',
        'Email': _selectedCustomer!.email ?? '',
        'QuotationNo': nextNo,
        'QuotationStatus': 'Delivered',
        'Date': quotationDate,
        'QuotationDate': quotationDate,
        'GST': _isGstChecked ? '3.0' : '0.0',
        'GSTApplied': _isGstChecked ? 'True' : 'False',
        'TotalAmount': getFinalTotal().toStringAsFixed(2),
        'TotalNetAmount': getBaseTotal().toStringAsFixed(2),
        'TotalGSTAmount': totalGst.toStringAsFixed(2),
        'GrossWt': _sum((it) => double.tryParse(it.grWt ?? '') ?? 0.0).toStringAsFixed(3),
        'NetWt': _sum((it) => double.tryParse(it.nWt ?? '') ?? 0.0).toStringAsFixed(3),
        'TotalStoneWeight': _sum((it) => double.tryParse(it.stoneWt) ?? 0.0).toStringAsFixed(3),
        'TotalStoneAmount': _sum((it) => double.tryParse(it.stoneAmt ?? '') ?? 0.0).toStringAsFixed(2),
        'TotalDiamondWeight': _sum((it) => double.tryParse(it.dimondWt) ?? 0.0).toStringAsFixed(3),
        'TotalDiamondAmount': _sum((it) => double.tryParse(it.diamondAmt) ?? 0.0).toStringAsFixed(2),
        'Qty': _productList.length.toString(),
        'EmployeeId': employee?.id ?? 0,
        'Remark': _productList
            .map((it) => it.remark.trim())
            .where((r) => r.isNotEmpty)
            .toSet()
            .join(', '),
        'Customer': {
          'FirstName': _selectedCustomer!.firstName ?? '',
          'LastName': _selectedCustomer!.lastName ?? '',
          'Mobile': _selectedCustomer!.mobile ?? '',
          'Email': _selectedCustomer!.email ?? '',
          'GstNo': _selectedCustomer!.gstNo ?? '',
          'PanNo': _selectedCustomer!.panNo ?? '',
          'ClientCode': _selectedCustomer!.clientCode ?? clientCode,
          'Id': selectedCustId,
        },
        'QuotationItem': items,
      };

      final response = _isEditMode
          ? await _apiService.updateQuotation(payload)
          : await _apiService.addQuotation(payload);

      // Keep customer + QuotationDate from payload when API omits/overwrites them.
      final merged = <String, dynamic>{
        ...payload,
        if (response is Map<String, dynamic>) ...response,
        'CustomerId': selectedCustId.toString(),
        'CustomerName': custName,
        'FirstName': _selectedCustomer!.firstName ?? '',
        'LastName': _selectedCustomer!.lastName ?? '',
        'Customer': payload['Customer'],
        'BranchId': branchId,
        'Date': quotationDate,
        'QuotationDate': quotationDate,
        'QuotationItem': items,
        'Remark': payload['Remark'],
      };

      await _upsertQuotationInHistory(merged, clientCode, branchId);

      _isLoading = false;
      notifyListeners();
      return merged;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // ---- Quotation history list + edit state ---------------------------------
  List<dynamic> _quotationsHistory = [];
  List<dynamic> get quotationsHistory => _quotationsHistory;
  DateTime? _lastQuotationsFetchAt;

  bool _isHistoryLoading = false;
  bool get isHistoryLoading => _isHistoryLoading;

  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;

  int _editingQuotationId = 0;
  String _editingQuotationNo = '';
  String _editingQuotationDate = '';

  String _quotationCacheKey(String clientCode, int branchId) =>
      'quotation_${clientCode}_$branchId';

  Future<void> _upsertQuotationInHistory(
    Map<String, dynamic> entry,
    String clientCode,
    int branchId,
  ) async {
    final key = _quotationCacheKey(clientCode, branchId);
    final entryId = entry['Id'];
    final entryNo = entry['QuotationNo']?.toString();
    _quotationsHistory = [
      entry,
      ..._quotationsHistory.where((q) {
        if (q is! Map) return true;
        if (entryId != null && q['Id'] == entryId) return false;
        if (entryNo != null &&
            entryNo.isNotEmpty &&
            q['QuotationNo']?.toString() == entryNo) {
          return false;
        }
        return true;
      }),
    ];
    _lastQuotationsFetchAt = null;
    ListJsonCache.instance.clearMemory(key);
    await ListJsonCache.instance.save(key, _quotationsHistory);
  }

  Future<void> fetchQuotationsHistory({int? branchId, bool forceNetwork = false}) async {
    final employee = _prefService.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    final resolvedBranchId = _resolveBranchId(branchId, employee);
    final cacheKey = _quotationCacheKey(clientCode, resolvedBranchId);

    // Instant: memory / disk cache first (Sparkle hasCached pattern).
    if (_quotationsHistory.isEmpty) {
      final mem = ListJsonCache.instance.readMemory(cacheKey);
      if (mem != null && mem.isNotEmpty) {
        _quotationsHistory = List<dynamic>.from(mem);
        notifyListeners();
      } else {
        final cached = await ListJsonCache.instance.load(cacheKey);
        if (cached.isNotEmpty) {
          _quotationsHistory = cached;
          notifyListeners();
        }
      }
    }

    if (!forceNetwork &&
        _quotationsHistory.isNotEmpty &&
        _lastQuotationsFetchAt != null &&
        DateTime.now().difference(_lastQuotationsFetchAt!) <
            const Duration(minutes: 2)) {
      await _enrichQuotationsCustomerNames(_quotationsHistory);
      notifyListeners();
      return;
    }

    final hasCached = _quotationsHistory.isNotEmpty;
    if (!hasCached) {
      _isHistoryLoading = true;
      notifyListeners();
    }
    _errorMessage = null;

    try {
      final raw = await _apiService.getAllQuotations(clientCode, resolvedBranchId);
      await _enrichQuotationsCustomerNames(raw);
      _quotationsHistory = raw;
      _lastQuotationsFetchAt = DateTime.now();
      await ListJsonCache.instance.save(cacheKey, raw);
    } catch (e) {
      if (!hasCached) {
        _errorMessage = e.toString();
      } else {
        await _enrichQuotationsCustomerNames(_quotationsHistory);
      }
    } finally {
      _isHistoryLoading = false;
      notifyListeners();
    }
  }

  /// When API returns CustomerId but empty Customer/CustomerName, fill from local customers.
  Future<void> _enrichQuotationsCustomerNames(List<dynamic> rows) async {
    final needsLookup = rows.any((q) {
      if (q is! Map) return false;
      final map = Map<String, dynamic>.from(q);
      return _quotationDisplayName(map).isEmpty && _parsePositiveId(map['CustomerId']) > 0;
    });
    if (!needsLookup) return;

    if (_customers.isEmpty) {
      try {
        final code = _prefService.getEmployee()?.clientCode ?? '';
        if (code.isEmpty) return;
        final rawCustomers = await _apiService.getAllCustomers(code);
        _customers =
            rawCustomers.map((c) => CustomerModel.fromJson(c as Map<String, dynamic>)).toList();
      } catch (_) {
        return;
      }
    }

    final byId = <int, CustomerModel>{};
    for (final c in _customers) {
      final id = c.id ?? 0;
      if (id > 0) byId[id] = c;
    }

    for (final q in rows) {
      if (q is! Map) continue;
      final map = q;
      if (_quotationDisplayName(Map<String, dynamic>.from(map)).isNotEmpty) continue;
      final cid = _parsePositiveId(map['CustomerId']);
      if (cid <= 0) continue;
      final c = byId[cid];
      if (c == null) continue;
      final name = '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim();
      if (name.isEmpty) continue;
      map['CustomerName'] = name;
      map['FirstName'] = c.firstName ?? '';
      map['LastName'] = c.lastName ?? '';
      map['Customer'] = {
        'Id': c.id,
        'FirstName': c.firstName ?? '',
        'LastName': c.lastName ?? '',
        'Mobile': c.mobile ?? '',
        'Email': c.email ?? '',
      };
    }
  }

  static String _quotationDisplayName(Map<String, dynamic> q) {
    final cust = q['Customer'];
    if (cust is Map) {
      final nested = '${cust['FirstName'] ?? ''} ${cust['LastName'] ?? ''}'.trim();
      if (nested.isNotEmpty) return nested;
    }
    final top = q['CustomerName']?.toString().trim() ?? '';
    if (top.isNotEmpty) return top;
    return '${q['FirstName'] ?? ''} ${q['LastName'] ?? ''}'.trim();
  }

  static int _parsePositiveId(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v > 0 ? v : 0;
    if (v is num) return v.toInt() > 0 ? v.toInt() : 0;
    final n = int.tryParse(v.toString().trim()) ?? 0;
    return n > 0 ? n : 0;
  }

  /// Same as Sparkle QuotationViewModel.resolveBranchId:
  /// use provided BranchId if > 0, else login pref branch, else employee defaultBranchId.
  int _resolveBranchId(int? branchId, Employee? employee) {
    if (branchId != null && branchId > 0) return branchId;
    final prefBranch = _prefService.getBranchId();
    if (prefBranch > 0) return prefBranch;
    final defaultId = employee?.defaultBranchId ?? 0;
    return defaultId > 0 ? defaultId : 0;
  }

  void setQuotationForEditing(Map<String, dynamic> quotation) {
    _isEditMode = true;
    _editingQuotationId = quotation['Id'] as int? ?? 0;
    _editingQuotationNo = quotation['QuotationNo']?.toString() ?? '';
    final rawDate = (quotation['QuotationDate'] ?? quotation['Date'] ?? quotation['CreatedOn'])
        ?.toString()
        .trim() ??
        '';
    if (rawDate.length >= 10) {
      _editingQuotationDate = rawDate.substring(0, 10);
    } else {
      _editingQuotationDate = rawDate;
    }

    final custJson = quotation['Customer'] as Map<String, dynamic>?;
    if (custJson != null) {
      _selectedCustomer = CustomerModel.fromJson(custJson);
    } else {
      _selectedCustomer = CustomerModel(
        id: _parsePositiveId(quotation['CustomerId']),
        firstName: quotation['CustomerName']?.toString() ?? quotation['FirstName']?.toString() ?? '',
        lastName: quotation['LastName']?.toString() ?? '',
      );
    }

    _isGstChecked = (quotation['GSTApplied']?.toString().toLowerCase() == 'true' ||
        quotation['GST']?.toString() == '3.0' ||
        (double.tryParse(quotation['TotalGSTAmount']?.toString() ?? '') ?? 0.0) > 0);

    _productList.clear();
    final itemsList = quotation['QuotationItem'] as List? ?? [];
    for (final itemJson in itemsList) {
      _productList.add(OrderItem.fromJson(itemJson as Map<String, dynamic>));
    }
    notifyListeners();
  }

  void clearEditMode() {
    _isEditMode = false;
    _editingQuotationId = 0;
    _editingQuotationNo = '';
    _editingQuotationDate = '';
    _selectedCustomer = null;
    _productList.clear();
    _isGstChecked = true;
    notifyListeners();
  }
}
