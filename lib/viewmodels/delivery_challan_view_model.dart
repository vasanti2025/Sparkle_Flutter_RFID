import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../models/delivery_challan.dart';
import '../models/customer_tunch.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';

class DeliveryChallanViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final DbService _dbService;
  final ApiService _apiService;

  DeliveryChallanViewModel({
    required PrefService prefService,
    required DbService dbService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _dbService = dbService,
        _apiService = apiService;

  String get baseUrl => _apiService.baseUrl;

  // Master Data States
  List<DeliveryChallanModel> _challans = [];
  List<DeliveryChallanModel> get challans => _challans;

  List<CustomerModel> _customers = [];
  List<CustomerModel> get customers => _customers;

  List<CustomerTunchModel> _customerTunchList = [];
  List<CustomerTunchModel> get customerTunchList => _customerTunchList;

  List<dynamic> _dailyRates = [];
  List<dynamic> get dailyRates => _dailyRates;

  List<dynamic> _branches = [];
  List<dynamic> get branches => _branches;

  // Active Challan State
  final List<ChallanDetailsModel> _productList = [];
  List<ChallanDetailsModel> get productList => _productList;

  CustomerModel? _selectedCustomer;
  CustomerModel? get selectedCustomer => _selectedCustomer;

  bool _isGstChecked = true;
  bool get isGstChecked => _isGstChecked;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isListLoading = false;
  bool get isListLoading => _isListLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _lastChallanNo = 0;
  int get lastChallanNo => _lastChallanNo;

  DeliveryChallanModel? _selectedChallan;
  DeliveryChallanModel? get selectedChallan => _selectedChallan;

  // Challan Header Fields
  String _selectedBranchId = '';
  String get selectedBranchId => _selectedBranchId;

  String _selectedBranchName = '';
  String get selectedBranchName => _selectedBranchName;

  String _selectedDate = '';
  String get selectedDate => _selectedDate;

  String _selectedSalesmanName = '';
  String get selectedSalesmanName => _selectedSalesmanName;

  void setChallanFields({
    required String branchName,
    required String branchId,
    required String date,
    required String salesmanName,
  }) {
    _selectedBranchName = branchName;
    _selectedBranchId = branchId;
    _selectedDate = date;
    _selectedSalesmanName = salesmanName;

    // Bulk update all active items in the productList
    for (int i = 0; i < _productList.length; i++) {
      _productList[i] = _productList[i].copyWith(
        branchId: int.tryParse(branchId),
      );
    }
    notifyListeners();
  }

  // Load master data on startup/screen mount
  Future<void> loadMasterData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';

      // 1. Load customers
      final rawCustomers = await _apiService.getAllCustomers(code);
      _customers = rawCustomers.map((c) => CustomerModel.fromJson(c as Map<String, dynamic>)).toList();

      // 2. Load customer tunch settings
      final rawTunch = await _apiService.getAllCustomerTunch(code);
      _customerTunchList = rawTunch.map((t) => CustomerTunchModel.fromJson(t as Map<String, dynamic>)).toList();

      // 3. Load daily rates
      _dailyRates = await _apiService.getDailyRates(code);

      // 4. Load branches
      _branches = await _apiService.getAllBranches(code);

      // 5. Load delivery challans
      await fetchAllChallans();

      // 6. Fetch last challan number
      await fetchLastChallanNo();

      // Initialize challan header defaults
      final emp = _prefService.getEmployee();
      _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _selectedSalesmanName = emp?.username ?? '';
      _selectedBranchId = (emp?.defaultBranchId ?? 0).toString();
      final defaultBranch = _branches.firstWhere((b) => (b['Id'] ?? 0).toString() == _selectedBranchId, orElse: () => null);
      if (defaultBranch != null) {
        _selectedBranchName = defaultBranch['BranchName']?.toString() ?? '';
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadChallanList() async {
    _isListLoading = true;
    notifyListeners();
    try {
      await fetchAllChallans();
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  // Reload challans only
  Future<void> fetchAllChallans() async {
    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final branchId = _prefService.getEmployee()?.branchNo ?? 0;
      final rawChallans = await _apiService.getAllDeliveryChallans(code, branchId);
      _challans = rawChallans.map((c) => DeliveryChallanModel.fromJson(c as Map<String, dynamic>)).toList();
    } catch (e) {
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  // Fetch last challan number
  Future<void> fetchLastChallanNo() async {
    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final branchId = _prefService.getEmployee()?.branchNo ?? 0;
      final res = await _apiService.getLastChallanNo(code, branchId);
      if (res != null) {
        _lastChallanNo = res['LastChallanNo'] as int? ?? 0;
      }
    } catch (e) {
      _lastChallanNo = 0;
    }
    notifyListeners();
  }

  // Set selected customer
  void setSelectedCustomer(CustomerModel? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  // Set selected challan for editing
  void setSelectedChallan(DeliveryChallanModel? challan) {
    _selectedChallan = challan;
    if (challan != null) {
      _productList.clear();
      _productList.addAll(challan.challanDetails);
      // Try to find customer
      _selectedCustomer = _customers.firstWhere(
        (c) => c.id == challan.customerId,
        orElse: () => CustomerModel(
          id: challan.customerId,
          firstName: challan.customerName ?? '',
          lastName: '',
          clientCode: challan.clientCode,
        ),
      );
      _isGstChecked = challan.gstApplied?.toUpperCase() == 'TRUE';
    } else {
      clearChallan();
    }
    notifyListeners();
  }

  // Toggle GST checked state
  void setGstChecked(bool value) {
    _isGstChecked = value;
    notifyListeners();
  }

  // Add customer profile
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

  // Pricing helper
  double _getRateForPurity(String purity) {
    if (_dailyRates.isEmpty) return 0.0;
    final match = _dailyRates.firstWhere(
      (r) => r['PurityName'].toString().trim().toUpperCase() == purity.trim().toUpperCase(),
      orElse: () => null,
    );
    if (match != null) {
      return double.tryParse(match['Rate'].toString()) ?? 0.0;
    }
    return 0.0;
  }

  // Manual/RFID scanned search implementation
  Future<String?> addProductByCodeOrRfid(String codeQuery, {bool notify = true}) async {
    final query = codeQuery.trim().toUpperCase();
    if (query.isEmpty) return 'Please enter item code or RFID';

    // 1. Fetch matching item in local SQLite inventory
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

    // 2. Resolve Customer Tunch matches
    final customerId = _selectedCustomer?.id ?? 0;
    final selectedSku = matchedItem.sku;
    CustomerTunchModel? touchMatch;
    
    if (customerId > 0 && selectedSku.isNotEmpty) {
      for (final t in _customerTunchList) {
        if (t.customerId == customerId && t.stockKeepingUnit?.toUpperCase() == selectedSku.toUpperCase()) {
          touchMatch = t;
          break;
        }
      }
    }

    // Overrides
    var makingPercentStr = touchMatch?.makingPercentage ?? matchedItem.makingPercent;
    var makingFixedWastageStr = touchMatch?.makingFixedWastage ?? matchedItem.fixWastage;
    var makingFixedAmtStr = touchMatch?.makingFixedAmt ?? matchedItem.fixMaking;
    var makingPerGramStr = touchMatch?.makingPerGram ?? matchedItem.makingPerGram;
    var finePercentStr = touchMatch != null ? touchMatch.finePercentage.toString() : matchedItem.makingPercent;

    final double makingPercent = double.tryParse(makingPercentStr) ?? 0.0;
    final double makingFixedWastage = double.tryParse(makingFixedWastageStr) ?? 0.0;
    final double makingFixedAmt = double.tryParse(makingFixedAmtStr) ?? 0.0;
    final double makingPerGram = double.tryParse(makingPerGramStr) ?? 0.0;
    final double finePercent = double.tryParse(finePercentStr) ?? 0.0;

    final double netWt = double.tryParse(matchedItem.netWeight) ?? 0.0;
    final double rate = _getRateForPurity(matchedItem.purity);
    final double metalAmt = netWt * rate;
    final double stoneAmt = double.tryParse(matchedItem.stoneAmount) ?? 0.0;
    final double diamondAmt = double.tryParse(matchedItem.diamondAmount) ?? 0.0;

    // Making Amt = makingPerGram + makingFixedAmt + ((makingPercent / 100.0) * netWt) + makingFixedWastage
    final double makingAmt = makingPerGram + makingFixedAmt + ((makingPercent / 100.0) * netWt) + makingFixedWastage;

    // Final total item amount
    final double itemAmt = stoneAmt + diamondAmt + metalAmt + makingAmt;

    // Fine weight
    final double fineWt = netWt * (makingFixedWastage / 100.0);

    final employee = _prefService.getEmployee();

    final challanItem = ChallanDetailsModel(
      challanId: _selectedChallan?.id ?? 0,
      mrp: matchedItem.mrp.toString(),
      categoryName: matchedItem.category,
      challanStatus: _selectedChallan != null ? 'Sold' : 'Pending',
      productName: matchedItem.productName,
      quantity: (matchedItem.totalQty > 0 ? matchedItem.totalQty : matchedItem.pcs > 0 ? matchedItem.pcs : 1).toString(),
      hsnCode: '',
      itemCode: matchedItem.itemCode,
      grossWt: matchedItem.grossWeight,
      netWt: matchedItem.netWeight,
      productId: matchedItem.productId,
      customerId: customerId,
      metalRate: rate.toString(),
      makingCharg: makingAmt.toStringAsFixed(2),
      price: matchedItem.mrp.toString(),
      huidCode: '',
      productCode: matchedItem.productCode,
      productNo: '',
      size: '1',
      stoneAmount: matchedItem.stoneAmount,
      totalWt: matchedItem.totalGwt.toString(),
      packingWeight: '0.0',
      metalAmount: metalAmt.toStringAsFixed(2),
      oldGoldPurchase: false,
      ratePerGram: rate.toString(),
      amount: itemAmt.toStringAsFixed(2),
      challanType: 'Delivery',
      finePercentage: finePercent.toString(),
      purchaseInvoiceNo: '',
      hallmarkAmount: '0.0',
      hallmarkNo: '',
      makingFixedAmt: makingFixedAmt.toString(),
      makingFixedWastage: makingFixedWastage.toString(),
      makingPerGram: makingPerGram.toString(),
      makingPercentage: makingPercent.toString(),
      description: '',
      cuttingGrossWt: matchedItem.grossWeight,
      cuttingNetWt: matchedItem.netWeight,
      baseCurrency: 'INR',
      categoryId: matchedItem.categoryId,
      purityId: matchedItem.purityId,
      totalStoneWeight: matchedItem.stoneWeight,
      totalStoneAmount: matchedItem.stoneAmount,
      totalStonePieces: '0',
      totalDiamondWeight: matchedItem.diamondWeight,
      totalDiamondPieces: '0',
      totalDiamondAmount: matchedItem.diamondAmount,
      skuId: matchedItem.skuId,
      sku: matchedItem.sku,
      fineWastageWt: fineWt.toStringAsFixed(3),
      totalItemAmount: itemAmt.toStringAsFixed(2),
      itemAmount: itemAmt.toStringAsFixed(2),
      itemGSTAmount: '0.0',
      clientCode: employee?.clientCode ?? '',
      diamondSize: '',
      diamondWeight: '0.0',
      diamondPurchaseRate: '0.0',
      diamondSellRate: '0.0',
      diamondClarity: '',
      diamondColour: '',
      diamondShape: '',
      diamondCut: '',
      diamondName: '',
      diamondSettingType: '',
      diamondCertificate: '',
      diamondPieces: '0',
      diamondPurchaseAmount: '0.0',
      diamondSellAmount: '0.0',
      diamondDescription: '',
      metalName: '',
      netAmount: itemAmt.toStringAsFixed(2),
      gstAmount: '0.0',
      totalAmount: itemAmt.toStringAsFixed(2),
      purity: matchedItem.purity,
      designName: matchedItem.design,
      companyId: 0,
      branchId: matchedItem.branchId != 0 ? matchedItem.branchId : (employee?.branchNo ?? 1),
      counterId: matchedItem.counterId,
      employeeId: employee?.id ?? 0,
      labelledStockId: matchedItem.bulkItemId,
      fineSilver: '0.0',
      fineGold: '0.0',
      debitSilver: '0.0',
      debitGold: '0.0',
      balanceSilver: '0.0',
      balanceGold: '0.0',
      convertAmt: '0.0',
      pieces: '1',
      stoneLessPercent: '0.0',
      designId: matchedItem.designId,
      packetId: matchedItem.packetId,
      rfidCode: matchedItem.rfid.isNotEmpty ? matchedItem.rfid : matchedItem.itemCode,
      image: matchedItem.imageUrl,
      diamondWt: matchedItem.diamondWeight,
      stoneAmt: matchedItem.stoneAmount,
      diamondAmt: matchedItem.diamondAmount,
      finePer: finePercent.toString(),
      fineWt: fineWt.toStringAsFixed(3),
      qty: 1,
      tid: matchedItem.tid,
      totayRate: rate.toString(),
      makingPercent: makingPercent.toString(),
      fixMaking: makingFixedAmt.toString(),
      fixWastage: makingFixedWastage.toString(),
      tidNumber: matchedItem.tid,
      customerName: _selectedCustomer != null ? '${_selectedCustomer!.firstName} ${_selectedCustomer!.lastName}'.trim() : '',
      pcs: 1,
    );

    _productList.add(challanItem);
    if (notify) notifyListeners();
    return null;
  }

  // Remove item from active list
  void removeProductItem(int index) {
    if (index >= 0 && index < _productList.length) {
      _productList.removeAt(index);
      notifyListeners();
    }
  }

  // Update item details manually (netweight, charges overrides)
  void updateProductItemDetails(int index, ChallanDetailsModel updated) {
    if (index >= 0 && index < _productList.length) {
      _productList[index] = updated;
      notifyListeners();
    }
  }

  // Process a list of scanned tags (rfid scan)
  void processScannedTags(List<String> tags) async {
    if (tags.isEmpty) return;
    await _dbService.warmScanKeyIndex();
    var changed = false;
    for (final epc in tags) {
      final err = await addProductByCodeOrRfid(epc, notify: false);
      if (err == null) changed = true;
    }
    if (changed) notifyListeners();
  }

  // Aggregates
  double getBaseTotal() {
    double total = 0.0;
    for (final item in _productList) {
      total += double.tryParse(item.amount) ?? 0.0;
    }
    return total;
  }

  double getGstAmount() {
    if (!_isGstChecked) return 0.0;
    return getBaseTotal() * 0.03; // GST 3.00%
  }

  double getFinalTotal() {
    return getBaseTotal() + getGstAmount();
  }

  // Clear current active state
  void clearChallan() {
    _productList.clear();
    _selectedCustomer = null;
    _selectedChallan = null;
    _errorMessage = null;
    notifyListeners();
  }

  // Save new delivery challan
  Future<Map<String, dynamic>?> submitDeliveryChallan() async {
    if (_selectedCustomer == null) {
      _errorMessage = 'Please select a customer';
      notifyListeners();
      return null;
    }
    if (_productList.isEmpty) {
      _errorMessage = 'Please add at least one item';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final employee = _prefService.getEmployee();
      final branchId = employee?.branchNo ?? 1;

      // 1. Fetch latest lastChallanNo to avoid conflicts
      await fetchLastChallanNo();
      final nextChallanNo = _lastChallanNo + 1;

      final double baseTotal = getBaseTotal();
      final double gstVal = getGstAmount();
      final double finalTotal = getFinalTotal();

      final List<Map<String, dynamic>> itemsJson = _productList.map((item) {
        final map = item.toJson();
        map['CustomerId'] = _selectedCustomer!.id ?? 0;
        map['ClientCode'] = code;
        map['EmployeeId'] = employee?.id ?? 0;
        map['CustomerName'] = '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim();
        return map;
      }).toList();

      final payload = {
        'BranchId': int.tryParse(_selectedBranchId) ?? branchId,
        'TransactionAmtType': 'CREDIT',
        'TransactionMetalType': 'GOLD',
        'MetalType': 'GOLD',
        'TransactionDetails': 'Delivery Challan Created',
        'UrdWt': '0.0',
        'UrdAmt': '0.0',
        'UrdQuantity': '0',
        'UrdGrossWt': '0.0',
        'UrdNetWt': '0.0',
        'UrdStoneWt': '0.0',
        'URDNo': '',
        'ClientCode': code,
        'CustomerId': (_selectedCustomer!.id ?? 0).toString(),
        'Billedby': _selectedSalesmanName.isNotEmpty ? _selectedSalesmanName : (employee?.username ?? ''),
        'SaleType': 'Challan',
        'Soldby': _selectedSalesmanName.isNotEmpty ? _selectedSalesmanName : (employee?.username ?? ''),
        'PaymentMode': 'Credit',
        'UrdPurchaseAmt': '0.0',
        'GST': _isGstChecked ? '3.00' : '0.00',
        'gstDiscout': '0.0',
        'TDS': '0.0',
        'ReceivedAmount': '0.0',
        'ChallanStatus': 'Sold',
        'Visibility': 'True',
        'Offer': '0.0',
        'CourierCharge': '0.0',
        'TotalAmount': finalTotal.toStringAsFixed(2),
        'BillType': 'Challan',
        'InvoiceDate': _selectedDate.isNotEmpty ? _selectedDate : DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'InvoiceNo': nextChallanNo.toString(),
        'BalanceAmt': finalTotal.toStringAsFixed(2),
        'CreditAmount': '0.0',
        'CreditGold': '0.0',
        'CreditSilver': '0.0',
        'GrossWt': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.grossWt) ?? 0.0)).toStringAsFixed(3),
        'NetWt': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.netWt) ?? 0.0)).toStringAsFixed(3),
        'StoneWt': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.stoneAmount) ?? 0.0)).toStringAsFixed(3),
        'StonePieces': '0',
        'Qty': _productList.length.toString(),
        'TotalDiamondAmount': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.totalDiamondAmount) ?? 0.0)).toStringAsFixed(2),
        'TotalDiamondPieces': '0',
        'DiamondPieces': '0',
        'TotalDiamondWeight': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.totalDiamondWeight) ?? 0.0)).toStringAsFixed(3),
        'DiamondWt': '0.0',
        'TotalSaleGold': '0.0',
        'TotalSaleSilver': '0.0',
        'TotalSaleUrdGold': '0.0',
        'TotalSaleUrdSilver': '0.0',
        'TotalStoneAmount': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.totalStoneAmount) ?? 0.0)).toStringAsFixed(2),
        'TotalStonePieces': '0',
        'TotalStoneWeight': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.totalStoneWeight) ?? 0.0)).toStringAsFixed(3),
        'BalanceGold': '0.0',
        'BalanceSilver': '0.0',
        'OrderType': 'Normal',
        'ChallanDetails': itemsJson,
        'Payments': [],
        'TotalPaidMetal': '0.0',
        'TotalPaidAmount': '0.0',
        'TotalAdvanceAmount': '0.0',
        'TotalAdvancePaid': '0.0',
        'TotalNetAmount': baseTotal.toStringAsFixed(2),
        'TotalFineMetal': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.fineWastageWt) ?? 0.0)).toStringAsFixed(3),
        'TotalBalanceMetal': '0.0',
        'GSTApplied': _isGstChecked ? 'True' : 'False',
        'gstCheckboxConfirm': 'False',
        'AdditionTaxApplied': 'False',
        'TotalGSTAmount': gstVal.toStringAsFixed(2),
        'CustomerName': '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim(),
      };

      final response = await _apiService.addDeliveryChallan(payload);
      if (response != null) {
        await fetchAllChallans();
        _isLoading = false;
        notifyListeners();
        return response;
      }
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  // Update existing delivery challan
  Future<bool> updateDeliveryChallan() async {
    if (_selectedChallan == null) {
      _errorMessage = 'No active challan to update';
      notifyListeners();
      return false;
    }
    if (_selectedCustomer == null) {
      _errorMessage = 'Please select a customer';
      notifyListeners();
      return false;
    }
    if (_productList.isEmpty) {
      _errorMessage = 'Please add at least one item';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final employee = _prefService.getEmployee();
      final branchId = employee?.branchNo ?? 1;

      final double baseTotal = getBaseTotal();
      final double gstVal = getGstAmount();
      final double finalTotal = getFinalTotal();

      final List<Map<String, dynamic>> itemsJson = _productList.map((item) {
        final map = item.toJson();
        map['CustomerId'] = _selectedCustomer!.id ?? 0;
        map['ClientCode'] = code;
        map['EmployeeId'] = employee?.id ?? 0;
        map['ChallanId'] = _selectedChallan!.id;
        map['CustomerName'] = '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim();
        return map;
      }).toList();

      final payload = {
        'Id': _selectedChallan!.id,
        'StatusType': _selectedChallan!.statusType ?? true,
        'CustomerId': _selectedCustomer!.id ?? 0,
        'CustomerName': '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim(),
        'VendorId': _selectedChallan!.vendorId,
        'BranchId': _selectedChallan!.branchId != 0 ? _selectedChallan!.branchId : branchId,
        'TotalAmount': finalTotal.toStringAsFixed(2),
        'PaymentMode': _selectedChallan!.paymentMode ?? 'Credit',
        'Offer': _selectedChallan!.offer ?? '0.0',
        'Qty': _productList.length.toString(),
        'GST': _isGstChecked ? '3.00' : '0.00',
        'ReceivedAmount': _selectedChallan!.receivedAmount ?? '0.0',
        'ChallanStatus': _selectedChallan!.challanStatus ?? 'Sold',
        'Visibility': _selectedChallan!.visibility ?? 'True',
        'MRP': _selectedChallan!.mrp ?? '0.0',
        'GrossWt': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.grossWt) ?? 0.0)).toStringAsFixed(3),
        'NetWt': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.netWt) ?? 0.0)).toStringAsFixed(3),
        'StoneWt': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.stoneAmount) ?? 0.0)).toStringAsFixed(3),
        'TotalNetAmount': baseTotal.toStringAsFixed(2),
        'TotalGSTAmount': gstVal.toStringAsFixed(2),
        'TotalPurchaseAmount': _selectedChallan!.totalPurchaseAmount ?? '0.0',
        'PurchaseStatus': _selectedChallan!.purchaseStatus,
        'GSTApplied': _isGstChecked ? 'True' : 'False',
        'Discount': _selectedChallan!.discount ?? '0.0',
        'TotalBalanceMetal': _selectedChallan!.totalBalanceMetal ?? '0.0',
        'BalanceAmount': finalTotal.toStringAsFixed(2),
        'TotalFineMetal': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.fineWastageWt) ?? 0.0)).toStringAsFixed(3),
        'CourierCharge': _selectedChallan!.courierCharge ?? '0.0',
        'TDS': _selectedChallan!.tds ?? '0.0',
        'URDNo': _selectedChallan!.urdNo ?? '',
        'gstCheckboxConfirm': 'False',
        'AdditionTaxApplied': 'False',
        'CategoryId': _selectedChallan!.categoryId ?? 0,
        'InvoiceNo': _selectedChallan!.invoiceNo ?? '',
        'DeliveryAddress': _selectedChallan!.deliveryAddress,
        'BillType': _selectedChallan!.billType ?? 'Challan',
        'UrdPurchaseAmt': _selectedChallan!.urdPurchaseAmt ?? '0.0',
        'BilledBy': employee?.username ?? '',
        'TotalAdvanceAmount': _selectedChallan!.totalAdvanceAmount ?? '0.0',
        'TotalAdvancePaid': _selectedChallan!.totalAdvancePaid ?? '0.0',
        'CreditSilver': _selectedChallan!.creditSilver ?? '0.0',
        'CreditGold': _selectedChallan!.creditGold ?? '0.0',
        'CreditAmount': _selectedChallan!.creditAmount ?? '0.0',
        'BalanceAmt': finalTotal.toStringAsFixed(2),
        'BalanceSilver': _selectedChallan!.balanceSilver ?? '0.0',
        'BalanceGold': _selectedChallan!.balanceGold ?? '0.0',
        'TotalSaleGold': _selectedChallan!.totalSaleGold ?? '0.0',
        'TotalSaleSilver': _selectedChallan!.totalSaleSilver ?? '0.0',
        'TotalSaleUrdGold': _selectedChallan!.totalSaleUrdGold ?? '0.0',
        'TotalSaleUrdSilver': _selectedChallan!.totalSaleUrdSilver ?? '0.0',
        'SaleType': _selectedChallan!.saleType ?? 'Challan',
        'FinancialYear': _selectedChallan!.financialYear,
        'BaseCurrency': _selectedChallan!.baseCurrency ?? 'INR',
        'TotalStoneWeight': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.totalStoneWeight) ?? 0.0)).toStringAsFixed(3),
        'TotalStoneAmount': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.totalStoneAmount) ?? 0.0)).toStringAsFixed(2),
        'TotalStonePieces': '0',
        'TotalDiamondWeight': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.totalDiamondWeight) ?? 0.0)).toStringAsFixed(3),
        'TotalDiamondPieces': '0',
        'TotalDiamondAmount': _productList.fold<double>(0.0, (val, element) => val + (double.tryParse(element.totalDiamondAmount) ?? 0.0)).toStringAsFixed(2),
        'ClientCode': code,
        'ChallanNo': _selectedChallan!.challanNo,
        'InvoiceCount': _selectedChallan!.invoiceCount ?? '1',
        'FineSilver': _selectedChallan!.fineSilver ?? '0.0',
        'FineGold': _selectedChallan!.fineGold ?? '0.0',
        'DebitSilver': _selectedChallan!.debitSilver ?? '0.0',
        'DebitGold': _selectedChallan!.debitGold ?? '0.0',
        'TotalPaidMetal': '0.0',
        'TotalPaidAmount': '0.0',
        'UrdWt': '0.0',
        'UrdAmt': '0.0',
        'TransactionAmtType': 'CREDIT',
        'TransactionMetalType': 'GOLD',
        'Description': 'Updated from mobile app',
        'MetalType': 'GOLD',
        'ChallanDetails': itemsJson,
        'Payments': [],
      };

      final response = await _apiService.updateDeliveryChallan(payload);
      if (response != null) {
        await fetchAllChallans();
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
}
