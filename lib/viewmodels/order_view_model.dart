import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../models/order_item.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/order_offline_service.dart';
import '../services/order_payload_builder.dart';
import '../services/order_sync_service.dart';
import '../services/pref_service.dart';

class OrderViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final DbService _dbService;
  final ApiService _apiService;

  OrderViewModel({
    required PrefService prefService,
    required DbService dbService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _dbService = dbService,
        _apiService = apiService;

  String get baseUrl => _apiService.baseUrl;

  OrderOfflineService get _offline => OrderOfflineService(
        dbService: _dbService,
        apiService: _apiService,
        prefService: _prefService,
      );

  bool _isOfflineMode = false;
  bool get isOfflineMode => _isOfflineMode;

  int _pendingSyncCount = 0;
  int get pendingSyncCount => _pendingSyncCount;

  bool _lastCustomerWasOffline = false;
  bool get lastCustomerWasOffline => _lastCustomerWasOffline;

  Future<void> _refreshPendingCount() async {
    final code = _prefService.getEmployee()?.clientCode ?? '';
    var count = await _offline.pendingCount(code);
    // If client_code filter finds nothing, still count any leftover pending rows.
    if (count == 0) {
      try {
        final all = await _dbService.getAllPendingOrders();
        final cust = await _dbService.getAllPendingCustomers();
        count = all.length + cust.length;
      } catch (_) {}
    }
    _pendingSyncCount = count;
  }

  // State lists
  List<CustomerModel> _customers = [];
  List<CustomerModel> get customers => _customers;

  List<dynamic> _dailyRates = [];
  List<dynamic> get dailyRates => _dailyRates;

  List<dynamic> _branches = [];
  List<dynamic> get branches => _branches;

  final List<OrderItem> _productList = [];
  List<OrderItem> get productList => _productList;

  // Active inputs state
  CustomerModel? _selectedCustomer;
  CustomerModel? get selectedCustomer => _selectedCustomer;

  bool _isGstChecked = false; // Match Sparkle create default (GSTApplied=false)
  bool get isGstChecked => _isGstChecked;

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  DateTime? _lastMasterLoadAt;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _lastOrderNo = 0;
  int get lastOrderNo => _lastOrderNo;

  // Load all master data needed for order screen (online first, cache fallback)
  Future<void> loadMasterData({bool force = false}) async {
    if (!force &&
        _customers.isNotEmpty &&
        _lastMasterLoadAt != null &&
        DateTime.now().difference(_lastMasterLoadAt!) < const Duration(minutes: 5)) {
      return;
    }

    final code = _prefService.getEmployee()?.clientCode ?? '';

    // Paint from cache first so the screen isn't blank while network runs.
    if (_customers.isEmpty) {
      try {
        await _loadMasterFromCache(code);
        if (_customers.isNotEmpty) notifyListeners();
      } catch (_) {}
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await _refreshPendingCount();

    try {
      final online = await _offline.isOnline();
      _isOfflineMode = !online;

      if (online) {
        final rawCustomers = await _apiService.getAllCustomers(code);
        _customers = rawCustomers.map((c) => CustomerModel.fromJson(c as Map<String, dynamic>)).toList();
        _dailyRates = await _apiService.getDailyRates(code);
        _branches = await _apiService.getAllBranches(code);
        final orderNoRes = await _apiService.getLastOrderNo(code);
        final lastUsed = OrderOfflineService.parseLastOrderNoResponse(orderNoRes);
        _lastOrderNo = OrderOfflineService.nextOrderNoFromLastUsed(lastUsed);
        if (_lastOrderNo <= 0) {
          _lastOrderNo = await _offline.resolveNextOrderNo(code);
        }
        await _offline.cacheMasterData(
          clientCode: code,
          customers: _customers,
          dailyRates: _dailyRates,
          branches: _branches,
          lastOrderNo: _lastOrderNo,
        );
        await _mergePendingCustomers(code);
        unawaited(OrderSyncService.syncNow());
        _lastMasterLoadAt = DateTime.now();
      } else {
        await _loadMasterFromCache(code);
        _lastMasterLoadAt = DateTime.now();
      }
    } catch (e) {
      try {
        await _loadMasterFromCache(code);
        _lastMasterLoadAt = DateTime.now();
      } catch (_) {
        _errorMessage = e.toString();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadMasterFromCache(String code) async {
    final cache = await _offline.loadMasterCache(code);
    if (cache == null) {
      _isOfflineMode = true;
      throw Exception('Offline — no cached order data. Connect to internet once to download customers and rates.');
    }
    _customers = cache.customers;
    _dailyRates = cache.dailyRates;
    _branches = cache.branches;
    _lastOrderNo = cache.lastOrderNo;
    if (_lastOrderNo <= 0) {
      _lastOrderNo = await _offline.resolveNextOrderNo(code);
    }
    _isOfflineMode = true;
    _errorMessage = null;
    await _mergePendingCustomers(code);
  }

  Future<void> _mergePendingCustomers(String code) async {
    final pending = await _offline.getPendingCustomerModels(code);
    for (final p in pending) {
      if (!_customers.any((c) => c.id == p.id)) {
        _customers.add(p);
      }
    }
  }

  // Set selected customer
  void setSelectedCustomer(CustomerModel? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  // Toggle GST checked state
  void setGstChecked(bool value) {
    _isGstChecked = value;
    notifyListeners();
  }

  // Save new customer profile (online or offline queue)
  Future<bool> addCustomerProfile(Map<String, dynamic> req) async {
    _isLoading = true;
    _errorMessage = null;
    _lastCustomerWasOffline = false;
    notifyListeners();

    final code = _prefService.getEmployee()?.clientCode ?? '';

    try {
      final online = await _offline.isOnline();
      if (online) {
        try {
          final result = await _apiService.addCustomer(req);
          if (result != null) {
            final rawCustomers = await _apiService.getAllCustomers(code);
            _customers = rawCustomers.map((c) => CustomerModel.fromJson(c as Map<String, dynamic>)).toList();
            await _mergePendingCustomers(code);
            _isLoading = false;
            notifyListeners();
            return true;
          }
        } catch (_) {}
      }

      final customer = await _offline.saveCustomerOffline(req);
      _customers = [..._customers, customer];
      await _offline.updateCustomersInCache(code, _customers);
      _selectedCustomer = customer;
      _isOfflineMode = true;
      _lastCustomerWasOffline = true;
      await _refreshPendingCount();
      unawaited(_offline.syncAll().then((_) => _refreshPendingCount()));
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Manual search by item code or RFID
  Future<String?> addProductByCodeOrRfid(String codeQuery) async {
    final query = codeQuery.trim().toUpperCase();
    if (query.isEmpty) return 'Please enter item code or RFID';

    // 1. Fetch matching item in the cached inventory
    final matchedItem = _dbService.findBulkItemByScanKeySync(codeQuery) ??
        await _dbService.findBulkItemByScanKey(codeQuery);

    if (matchedItem == null) {
      return 'No item found with code/RFID: $codeQuery';
    }

    // Check duplicate in active list
    final exists = _productList.any(
      (x) =>
          x.itemCode.toUpperCase() == matchedItem.itemCode.toUpperCase() ||
          x.rfidCode.toUpperCase() == matchedItem.rfid.toUpperCase() ||
          x.tid.toUpperCase() == matchedItem.tid.toUpperCase(),
    );

    if (exists) {
      return 'Item already added';
    }

    // 2. Perform price calculations
    final rate = _getRateForPurity(matchedItem.purity);
    final netWt = double.tryParse(matchedItem.netWeight) ?? 0.0;
    final stoneAmt = double.tryParse(matchedItem.stoneAmount) ?? 0.0;
    final diamondAmt = double.tryParse(matchedItem.diamondAmount) ?? 0.0;

    final makingPerGram = double.tryParse(matchedItem.makingPerGram) ?? 0.0;
    final makingFixedAmt = double.tryParse(matchedItem.fixMaking) ?? 0.0;
    final makingPercent = double.tryParse(matchedItem.makingPercent) ?? 0.0;
    final makingFixedWastage = double.tryParse(matchedItem.fixWastage) ?? 0.0;

    // Metal = netWeight * today's purity rate
    final metalAmt = netWt * rate;

    // Making amount
    final makingAmt = makingPerGram + makingFixedAmt + ((makingPercent / 100.0) * netWt) + makingFixedWastage;

    // Final item amount
    final itemAmt = stoneAmt + diamondAmt + metalAmt + makingAmt;

    // Fine weight
    final finePercent = double.tryParse(matchedItem.makingPercent) ?? 0.0;
    final fineWt = netWt * finePercent / 100.0;

    final employee = _prefService.getEmployee();

    final orderItem = OrderItem(
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
      finePer: finePercent.toString(),
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

    _productList.add(orderItem);
    notifyListeners();
    return null;
  }

  // Handle scanned Gscan tags or single scans
  Future<int> processScannedTags(List<String> epcs) async {
    int addedCount = 0;
    await _dbService.warmScanKeyIndex();

    for (final epcRaw in epcs) {
      final epc = epcRaw.trim().toUpperCase().replaceAll(' ', '');
      if (epc.isEmpty) continue;

      final matchedItem = _dbService.findBulkItemByScanKeySync(epcRaw) ??
          await _dbService.findBulkItemByScanKey(epcRaw);
      if (matchedItem == null) continue;

      // Duplicate check
      final exists = _productList.any((x) => x.tid == matchedItem.tid || x.epc == matchedItem.epc);
      if (exists) continue;

      // Calculate details
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

      final finePercent = double.tryParse(matchedItem.makingPercent) ?? 0.0;
      final fineWt = netWt * finePercent / 100.0;

      final employee = _prefService.getEmployee();

      final orderItem = OrderItem(
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
        finePer: finePercent.toString(),
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

      _productList.add(orderItem);
      addedCount++;
    }

    if (addedCount > 0) notifyListeners();
    return addedCount;
  }

  // Update single item at an index
  void updateItem(int index, OrderItem updated) {
    if (index >= 0 && index < _productList.length) {
      _productList[index] = updated;
      notifyListeners();
    }
  }

  // Bulk update of order details (dates, remarks)
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
      
      // Calculate rate based on updated purity
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

  // Delete item from list
  void deleteItem(int index) {
    if (index >= 0 && index < _productList.length) {
      _productList.removeAt(index);
      notifyListeners();
    }
  }

  // Clear active order list
  void clearOrder() {
    _productList.clear();
    _selectedCustomer = null;
    notifyListeners();
  }

  // Save or Update the full custom order (online API, or offline queue like Sparkle).
  Future<Map<String, dynamic>?> submitCustomOrder() async {
    if (_selectedCustomer == null) {
      throw Exception('Please select a customer first.');
    }
    // Resolve server CustomerId (0 / negative breaks AddCustomOrder sync).
    var resolvedCustomerId = _selectedCustomer!.id ?? 0;
    if (resolvedCustomerId <= 0) {
      final mobile = (_selectedCustomer!.mobile ?? '').trim();
      if (mobile.isNotEmpty) {
        for (final c in _customers) {
          if ((c.mobile ?? '').trim() == mobile && (c.id ?? 0) > 0) {
            resolvedCustomerId = c.id!;
            break;
          }
        }
      }
    }
    if (resolvedCustomerId <= 0 &&
        (_selectedCustomer!.mobile == null || _selectedCustomer!.mobile!.trim().isEmpty)) {
      throw Exception('Selected customer has no Id/Mobile — cannot sync. Re-select customer.');
    }
    if (_productList.isEmpty) {
      throw Exception('Please add at least one item to the order.');
    }

    _isLoading = true;
    notifyListeners();

    try {
      final employee = _prefService.getEmployee();
      final clientCode = employee?.clientCode ?? '';

      final totalGst = calculateGstAmount();
      final orderId = _isEditMode ? _editingOrderId : 0;
      final isPendingLocalEdit =
          _isEditMode && orderId <= 0 && (_editingLocalOrderId?.isNotEmpty ?? false);

      if (_lastOrderNo <= 0 && !isPendingLocalEdit) {
        _lastOrderNo = await _offline.resolveNextOrderNo(clientCode);
      }
      final orderDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final orderNoForPayload = isPendingLocalEdit && _editingOrderNo.isNotEmpty
          ? _editingOrderNo
          : _lastOrderNo.toString();

      final List<Map<String, dynamic>> orderItemsJson = _productList.map((item) {
        final itemMap = item.toJson();
        itemMap['CustomOrderId'] = orderId;
        itemMap['CustomerId'] = resolvedCustomerId > 0
            ? resolvedCustomerId
            : (_selectedCustomer!.id ?? 0);
        itemMap['ClientCode'] = clientCode;
        itemMap['EmployeeId'] = employee?.id ?? 0;
        itemMap['OrderNo'] = orderNoForPayload;
        itemMap['OrderDate'] = itemMap['OrderDate']?.toString().isNotEmpty == true
            ? itemMap['OrderDate']
            : orderDateStr;
        itemMap['totalGstAmount'] = totalGst.toStringAsFixed(2);
        itemMap['Stones'] = itemMap['Stones'] ?? [];
        itemMap['Diamond'] = itemMap['Diamond'] ?? [];
        itemMap.remove('OrderId');
        return itemMap;
      }).toList();

      final custIdForPayload =
          resolvedCustomerId > 0 ? resolvedCustomerId : (_selectedCustomer!.id ?? 0);

      final payload = {
        'CustomOrderId': orderId,
        'CustomerId': custIdForPayload.toString(),
        'CustomOrderItem': orderItemsJson,
        'Payments': [],
        'uRDPurchases': [],
        'Customer': {
          'FirstName': _selectedCustomer!.firstName ?? '',
          'LastName': _selectedCustomer!.lastName ?? '',
          'PerAddStreet': '',
          'CurrAddStreet': '',
          'Mobile': _selectedCustomer!.mobile ?? '',
          'Email': _selectedCustomer!.email ?? '',
          'Password': '',
          'CustomerLoginId': _selectedCustomer!.email ?? '',
          'DateOfBirth': '',
          'MiddleName': '',
          'PerAddPincode': '',
          'Gender': '',
          'OnlineStatus': '',
          'CurrAddTown': _selectedCustomer!.currAddTown ?? '',
          'CurrAddPincode': '',
          'CurrAddState': _selectedCustomer!.currAddState ?? '',
          'PerAddTown': '',
          'PerAddState': '',
          'GstNo': _selectedCustomer!.gstNo ?? '',
          'PanNo': _selectedCustomer!.panNo ?? '',
          'AadharNo': '',
          'BalanceAmount': '0',
          'AdvanceAmount': '0',
          'Discount': '0',
          'CreditPeriod': '',
          'FineGold': '0',
          'FineSilver': '0',
          'ClientCode': _selectedCustomer!.clientCode ?? clientCode,
          'VendorId': 0,
          'AddToVendor': false,
          'CustomerSlabId': 0,
          'CreditPeriodId': 0,
          'RateOfInterestId': 0,
          'Remark': '',
          'Area': '',
          'City': _selectedCustomer!.city ?? '',
          'Country': _selectedCustomer!.country ?? '',
          'Id': custIdForPayload,
          'CreatedOn': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'LastUpdated': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'StatusType': true
        },
        'GSTApplied': _isGstChecked ? 'true' : 'false',
        'GST': _isGstChecked ? 'true' : '0',
        'TotalAmount': getFinalTotal().toStringAsFixed(2),
        'TotalNetAmount': getBaseTotal().toStringAsFixed(2),
        'TotalGSTAmount': totalGst.toStringAsFixed(2),
        'GstAmount': totalGst.toStringAsFixed(2),
        'GstCheck': _isGstChecked ? 'true' : 'false',
        'AdditionTaxApplied': _isGstChecked ? 'true' : 'false',
        'OrderNo': orderNoForPayload,
        'OrderDate': orderDateStr,
        'DeliverDate': orderDateStr,
        'CreatedOn': orderDateStr,
        'OrderStatus': 'Order Received',
        'syncStatus': false,
        'LastUpdated': null,
        'RfidCode': '',
        'TidNumber': ''
      };

      // Match Sparkle CustomOrderRequest before online/offline save.
      final enrichedPayload = OrderPayloadBuilder.toSparkleApiPayload(
        payload,
        clientCode: clientCode,
        employee: employee,
        customOrderId: orderId,
        customerId: custIdForPayload > 0 ? custIdForPayload : null,
        orderNo: isPendingLocalEdit ? null : orderNoForPayload,
        forceCreateDefaults: !_isEditMode || orderId <= 0,
      );

      if (custIdForPayload <= 0) {
        throw Exception(
          'Customer Id is missing (0). Select a customer that already exists on the server, then save again.',
        );
      }

      Map<String, dynamic>? response;
      final online = await _offline.isOnline();
      String? onlineSubmitError;

      if (online && !isPendingLocalEdit) {
        try {
          if (_isEditMode && orderId > 0) {
            response = await _apiService.updateCustomOrder(enrichedPayload);
          } else if (!_isEditMode) {
            response = await _apiService.addCustomOrder(enrichedPayload);
          }
          if (response != null) {
            await _offline.cacheOrdersHistory(
              clientCode,
              await _apiService.getAllOrders(clientCode),
            );
          }
        } catch (e) {
          onlineSubmitError = e.toString();
          debugPrint('Online order submit failed: $e');
          response = null;
        }
      }

      // Pending local edit while online: try create now and drop queue row.
      if (online && isPendingLocalEdit && response == null) {
        try {
          final nextNo = await _offline.resolveNextOrderNo(clientCode);
          final ready = OrderPayloadBuilder.toSparkleApiPayload(
            enrichedPayload,
            clientCode: clientCode,
            employee: employee,
            customOrderId: 0,
            customerId: custIdForPayload > 0 ? custIdForPayload : null,
            orderNo: nextNo.toString(),
          );
          response = await _apiService.addCustomOrder(ready);
          if (response != null) {
            await _offline.deletePendingOrder(_editingLocalOrderId!);
            await _offline.cacheOrdersHistory(
              clientCode,
              await _apiService.getAllOrders(clientCode),
            );
            _lastOrderNo = nextNo + 1;
            await _dbService.updateCachedLastOrderNo(clientCode, _lastOrderNo);
          }
        } catch (e) {
          onlineSubmitError = e.toString();
          debugPrint('Online pending-edit submit failed: $e');
          response = null;
        }
      }

      if (response == null) {
        // Offline (or API failed): queue create / update like Sparkle.
        String operation;
        if (isPendingLocalEdit) {
          operation = 'create';
        } else if (_isEditMode && orderId > 0) {
          operation = 'update';
        } else if (_isEditMode && orderId <= 0) {
          throw Exception('Unable to update order offline — order not synced yet.');
        } else {
          operation = 'create';
        }

        response = await _offline.saveOrderOffline(
          payload: enrichedPayload,
          operation: operation,
          customOrderId: orderId,
          orderNo: orderNoForPayload,
          localOrderId: isPendingLocalEdit ? _editingLocalOrderId : null,
        );
        if (onlineSubmitError != null) {
          _errorMessage = onlineSubmitError;
          final localId = response['LocalOrderId']?.toString();
          if (localId != null && localId.isNotEmpty) {
            await _dbService.markPendingOrderFailed(localId, onlineSubmitError);
          }
        }
        _isOfflineMode = true;
        await _refreshPendingCount();

        // If network is up, sync immediately and refresh so * clears when upload works.
        if (online) {
          try {
            await _offline.syncAll();
          } catch (e) {
            debugPrint('Post-save sync failed: $e');
          }
          await _refreshPendingCount();
          await fetchOrdersHistory();
        } else {
          unawaited(_offline.syncAll().then((_) async {
            await _refreshPendingCount();
            await fetchOrdersHistory();
          }));
        }
      } else if (!_isEditMode) {
        _lastOrderNo++;
        await _dbService.updateCachedLastOrderNo(clientCode, _lastOrderNo);
      }

      _isLoading = false;
      notifyListeners();
      return response;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // Calculations Helpers
  double getBaseTotal() {
    return _productList.fold(0.0, (sum, item) => sum + (double.tryParse(item.itemAmt ?? '') ?? 0.0));
  }

  double calculateGstAmount() {
    if (!_isGstChecked) return 0.0;
    return getBaseTotal() * 0.03; // 3% GST
  }

  double getFinalTotal() {
    return getBaseTotal() + calculateGstAmount();
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

  // --- Order History List and Edit state ---
  List<dynamic> _ordersHistory = [];
  List<dynamic> get ordersHistory => _ordersHistory;
  DateTime? _lastHistoryFetchAt;

  bool _isHistoryLoading = false;
  bool get isHistoryLoading => _isHistoryLoading;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;

  int _editingOrderId = 0;
  int get editingOrderId => _editingOrderId;

  /// Local pending queue id when editing an unsynced offline-created order.
  String? _editingLocalOrderId;
  String get editingLocalOrderId => _editingLocalOrderId ?? '';

  String _editingOrderNo = '';

  Future<void> fetchOrdersHistory({bool syncPendingFirst = true, bool forceNetwork = false}) async {
    _errorMessage = null;

    // Avoid re-hitting network on every navigation when dashboard already warmed the list.
    if (!forceNetwork &&
        !syncPendingFirst &&
        _ordersHistory.isNotEmpty &&
        _lastHistoryFetchAt != null &&
        DateTime.now().difference(_lastHistoryFetchAt!) < const Duration(minutes: 2)) {
      return;
    }

    final employee = _prefService.getEmployee();
    final clientCode = employee?.clientCode ?? '';

    // Instant: show local DB cache + pending before waiting on network (Sparkle).
    try {
      final pending = await _offline.getPendingOrders(clientCode);
      final cached = await _offline.loadCachedHistory(clientCode);
      if (cached.isNotEmpty || pending.isNotEmpty) {
        _ordersHistory = _offline.mergeHistoryWithPending(
          serverOrCached: cached,
          pending: pending,
        );
        notifyListeners();
      }
    } catch (_) {}

    final hasCached = _ordersHistory.isNotEmpty;
    if (!hasCached) {
      _isHistoryLoading = true;
      notifyListeners();
    }

    try {
      await _refreshPendingCount();
      final online = await _offline.isOnline();

      if (online) {
        // Sync pending first so * rows clear before list rebuild.
        // Skip when caller already synced (avoids double hang on cloud button).
        if (syncPendingFirst) {
          try {
            await _offline.syncAll().timeout(const Duration(seconds: 90));
          } catch (e) {
            debugPrint('fetchOrdersHistory syncAll: $e');
          }
          await _refreshPendingCount();
        }

        final raw = await _apiService.getAllOrders(clientCode);
        // Drop any pending creates that already exist on server (same OrderNo).
        await _offline.dropPendingCreatesAlreadyOnServer(clientCode, raw);
        final pendingFresh = await _offline.getPendingOrders(clientCode);
        _ordersHistory = _offline.mergeHistoryWithPending(
          serverOrCached: raw,
          pending: pendingFresh,
        );
        // Never overwrite a good cache with an empty accidental response.
        if (raw.isNotEmpty) {
          await _offline.cacheOrdersHistory(clientCode, raw);
        } else {
          final cached = await _offline.loadCachedHistory(clientCode);
          if (cached.isNotEmpty) {
            _ordersHistory = _offline.mergeHistoryWithPending(
              serverOrCached: cached,
              pending: pendingFresh,
            );
          }
        }
        _isOfflineMode = false;
      } else {
        final pending = await _offline.getPendingOrders(clientCode);
        final cached = await _offline.loadCachedHistory(clientCode);
        _ordersHistory = _offline.mergeHistoryWithPending(
          serverOrCached: cached,
          pending: pending,
        );
        _isOfflineMode = true;
      }
    } catch (e) {
      try {
        final cached = await _offline.loadCachedHistory(clientCode);
        final pending = await _offline.getPendingOrders(clientCode);
        _ordersHistory = _offline.mergeHistoryWithPending(
          serverOrCached: cached,
          pending: pending,
        );
        _isOfflineMode = true;
      } catch (_) {
        if (!hasCached) {
          _errorMessage = e.toString();
        }
      }
    } finally {
      _isHistoryLoading = false;
      _lastHistoryFetchAt = DateTime.now();
      notifyListeners();
    }
  }

  Future<bool> deleteOrderFromHistory(int customOrderId, {String? localOrderId}) async {
    _isHistoryLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final employee = _prefService.getEmployee();
      final clientCode = employee?.clientCode ?? '';

      if (localOrderId != null && localOrderId.isNotEmpty) {
        await _offline.deletePendingOrder(localOrderId);
        _ordersHistory.removeWhere(
          (o) => o is Map && o['LocalOrderId'] == localOrderId,
        );
        await _refreshPendingCount();
        return true;
      }

      if (customOrderId <= 0) {
        return false;
      }

      final online = await _offline.isOnline();
      if (online) {
        final success = await _apiService.deleteCustomOrder(clientCode, customOrderId);
        if (success) {
          _ordersHistory.removeWhere((o) => o['CustomOrderId'] == customOrderId);
        }
        return success;
      }

      await _offline.saveOrderOffline(
        payload: {
          'CustomOrderId': customOrderId,
          'ClientCode': clientCode,
        },
        operation: 'delete',
        customOrderId: customOrderId,
        orderNo: '0',
      );
      _ordersHistory.removeWhere((o) => o['CustomOrderId'] == customOrderId);
      await _refreshPendingCount();
      unawaited(_offline.syncAll().then((_) async {
        await _refreshPendingCount();
        await fetchOrdersHistory();
      }));
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isHistoryLoading = false;
      notifyListeners();
    }
  }

  Future<int> syncPendingOrdersNow() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    _errorMessage = null;
    notifyListeners();

    final code = _prefService.getEmployee()?.clientCode?.trim() ?? '';
    int count = 0;

    try {
      // Use THIS app's ApiService/PrefService (same token + base URL).
      count = await _offline.syncAll().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw Exception('Sync timed out after 90s — check internet and try again');
        },
      );
    } catch (e, st) {
      debugPrint('syncPendingOrdersNow failed: $e\n$st');
      _errorMessage = e.toString();
    }

    try {
      await _refreshPendingCount();
      if (code.isNotEmpty) {
        _lastOrderNo = await _offline.resolveNextOrderNo(code);
      }
      // Already synced above — just refresh list from server/cache.
      await fetchOrdersHistory(syncPendingFirst: false);

      if (count == 0 && _pendingSyncCount > 0) {
        final err = await _offline.lastPendingError(code);
        _errorMessage = err ?? _errorMessage ?? 'Sync failed — see pending order error';
      } else if (count > 0 && _pendingSyncCount == 0) {
        _errorMessage = null;
      } else if (count > 0 && _pendingSyncCount > 0) {
        final err = await _offline.lastPendingError(code);
        _errorMessage = err ?? 'Synced $count item(s); $_pendingSyncCount still pending';
      } else if (count == 0 && _pendingSyncCount == 0 && _errorMessage == null) {
        // No queue rows — still useful feedback for the button.
        _errorMessage = null;
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return count;
  }

  /// Deletes stuck pending CREATE rows so user can recreate with a clean payload.
  Future<int> clearFailedPendingCreates() async {
    final code = _prefService.getEmployee()?.clientCode?.trim() ?? '';
    final n = await _offline.clearPendingCreates(code);
    await _refreshPendingCount();
    await fetchOrdersHistory(syncPendingFirst: false);
    return n;
  }

  void setOrderForEditing(Map<String, dynamic> order) {
    _isEditMode = true;
    _editingOrderId = order['CustomOrderId'] as int? ??
        int.tryParse(order['CustomOrderId']?.toString() ?? '') ??
        0;
    _editingLocalOrderId = order['LocalOrderId']?.toString();
    if (_editingLocalOrderId != null && _editingLocalOrderId!.isEmpty) {
      _editingLocalOrderId = null;
    }

    final custJson = order['Customer'] as Map<String, dynamic>?;
    if (custJson != null) {
      _selectedCustomer = CustomerModel.fromJson(custJson);
    } else {
      _selectedCustomer = null;
    }

    _isGstChecked = (order['GSTApplied']?.toString().toLowerCase() == 'true' ||
                     order['GST']?.toString() == '3.0' ||
                     (double.tryParse(order['TotalGSTAmount']?.toString() ?? '') ?? 0.0) > 0);

    final orderNoStr = order['OrderNo']?.toString() ?? '0';
    _editingOrderNo = orderNoStr;
    _lastOrderNo = int.tryParse(orderNoStr) ?? _lastOrderNo;

    _productList.clear();
    final itemsList = order['CustomOrderItem'] as List? ?? [];
    for (final itemJson in itemsList) {
      _productList.add(OrderItem.fromJson(Map<String, dynamic>.from(itemJson as Map)));
    }
    notifyListeners();
  }

  void clearEditMode() {
    _isEditMode = false;
    _editingOrderId = 0;
    _editingLocalOrderId = null;
    _editingOrderNo = '';
    _selectedCustomer = null;
    _productList.clear();
    _isGstChecked = false;
    notifyListeners();
  }
}
