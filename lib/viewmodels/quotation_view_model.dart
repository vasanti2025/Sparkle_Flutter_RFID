import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../models/order_item.dart';
import '../models/bulk_item.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
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

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _lastQuotationNo = 0;
  int get lastQuotationNo => _lastQuotationNo;

  // ---- Master data ---------------------------------------------------------
  Future<void> loadMasterData() async {
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
      'Image': item.image,
      'BranchId': int.tryParse(item.branchId) ?? 0,
      'BranchName': item.branchName,
      'CustomerId': _selectedCustomer?.id ?? 0,
      'LabelledStockId': 0,
      'TIDNumber': item.tid,
      'RFIDCode': item.rfidCode,
      'ClientCode': clientCode,
      'CreatedOn': DateFormat('yyyy-MM-dd').format(DateTime.now()),
    };
  }

  // ---- Save / Update -------------------------------------------------------
  Future<Map<String, dynamic>?> submitQuotation() async {
    if (_selectedCustomer == null) {
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

      // Always refresh the last quotation number before saving.
      final lastNoRes = await _apiService.getLastQuotationNo(clientCode);
      if (lastNoRes != null) {
        final raw = lastNoRes['LastQuotationNo'];
        _lastQuotationNo = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? _lastQuotationNo;
      }
      final nextNo = _isEditMode ? _editingQuotationNo : (_lastQuotationNo + 1).toString();

      final items = _productList.map((it) => _quotationItemJson(it, clientCode)).toList();
      final totalGst = calculateGstAmount();

      final payload = {
        if (_isEditMode) 'Id': _editingQuotationId,
        'ClientCode': clientCode,
        'BranchId': employee?.defaultBranchId ?? 0,
        'CustomerId': (_selectedCustomer!.id ?? 0).toString(),
        'CustomerName': '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim(),
        'QuotationNo': nextNo,
        'QuotationStatus': 'Delivered',
        'Date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'QuotationDate': DateFormat('yyyy-MM-dd').format(DateTime.now()),
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
        'Customer': {
          'FirstName': _selectedCustomer!.firstName ?? '',
          'LastName': _selectedCustomer!.lastName ?? '',
          'Mobile': _selectedCustomer!.mobile ?? '',
          'Email': _selectedCustomer!.email ?? '',
          'GstNo': _selectedCustomer!.gstNo ?? '',
          'PanNo': _selectedCustomer!.panNo ?? '',
          'ClientCode': _selectedCustomer!.clientCode ?? clientCode,
          'Id': _selectedCustomer!.id ?? 0,
        },
        'QuotationItem': items,
      };

      final response = _isEditMode
          ? await _apiService.updateQuotation(payload)
          : await _apiService.addQuotation(payload);

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

  // ---- Quotation history list + edit state ---------------------------------
  List<dynamic> _quotationsHistory = [];
  List<dynamic> get quotationsHistory => _quotationsHistory;

  bool _isHistoryLoading = false;
  bool get isHistoryLoading => _isHistoryLoading;

  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;

  int _editingQuotationId = 0;
  String _editingQuotationNo = '';

  Future<void> fetchQuotationsHistory() async {
    _isHistoryLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final clientCode = _prefService.getEmployee()?.clientCode ?? '';
      _quotationsHistory = await _apiService.getAllQuotations(clientCode);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isHistoryLoading = false;
      notifyListeners();
    }
  }

  void setQuotationForEditing(Map<String, dynamic> quotation) {
    _isEditMode = true;
    _editingQuotationId = quotation['Id'] as int? ?? 0;
    _editingQuotationNo = quotation['QuotationNo']?.toString() ?? '';

    final custJson = quotation['Customer'] as Map<String, dynamic>?;
    if (custJson != null) {
      _selectedCustomer = CustomerModel.fromJson(custJson);
    } else {
      _selectedCustomer = CustomerModel(
        id: quotation['CustomerId'] as int?,
        firstName: quotation['CustomerName']?.toString() ?? quotation['FirstName']?.toString() ?? '',
        lastName: '',
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
    _selectedCustomer = null;
    _productList.clear();
    _isGstChecked = true;
    notifyListeners();
  }
}
