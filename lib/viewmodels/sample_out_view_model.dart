import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../models/customer_tunch.dart';
import '../models/delivery_challan.dart';
import '../models/sample_out.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../views/widgets/sample_print_pdf.dart';

class SampleOutViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final DbService _dbService;
  final ApiService _apiService;

  SampleOutViewModel({
    required PrefService prefService,
    required DbService dbService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _dbService = dbService,
        _apiService = apiService;

  List<SampleOutModel> _sampleOutList = [];
  List<SampleOutModel> get sampleOutList => _sampleOutList;

  List<CustomerModel> _customers = [];
  List<CustomerModel> get customers => _customers;

  List<CustomerTunchModel> _customerTunchList = [];
  List<CustomerTunchModel> get customerTunchList => _customerTunchList;

  List<dynamic> _dailyRates = [];
  List<dynamic> get dailyRates => _dailyRates;

  final List<ChallanDetailsModel> _productList = [];
  List<ChallanDetailsModel> get productList => _productList;

  CustomerModel? _selectedCustomer;
  CustomerModel? get selectedCustomer => _selectedCustomer;

  SampleOutModel? _selectedSampleOut;
  SampleOutModel? get selectedSampleOut => _selectedSampleOut;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isListLoading = false;
  bool get isListLoading => _isListLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _selectedDate = '';
  String get selectedDate => _selectedDate;

  String _returnDate = '';
  String get returnDate => _returnDate;

  String _description = '';
  String get description => _description;

  String _lastSampleOutNo = '';
  String get lastSampleOutNo => _lastSampleOutNo;

  void setSampleOutFields({
    required String date,
    required String returnDate,
    required String description,
  }) {
    _selectedDate = date;
    _returnDate = returnDate;
    _description = description;
    for (int i = 0; i < _productList.length; i++) {
      _productList[i] = _productList[i].copyWith(description: description);
    }
    notifyListeners();
  }

  Future<void> loadMasterData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';

      final rawCustomers = await _apiService.getAllCustomers(code);
      _customers = rawCustomers.map((c) => CustomerModel.fromJson(c as Map<String, dynamic>)).toList();

      final rawTunch = await _apiService.getAllCustomerTunch(code);
      _customerTunchList = rawTunch.map((t) => CustomerTunchModel.fromJson(t as Map<String, dynamic>)).toList();

      _dailyRates = await _apiService.getDailyRates(code);

      await fetchAllSampleOut();
      await fetchLastSampleOutNo();

      _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _returnDate = _selectedDate;
      _description = '';
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSampleOutList() async {
    _isListLoading = true;
    notifyListeners();
    try {
      await fetchAllSampleOut();
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAllSampleOut() async {
    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final raw = await _apiService.getAllSampleOut(code);
      _sampleOutList = raw.map((c) => SampleOutModel.fromJson(c as Map<String, dynamic>)).toList();
    } catch (e) {
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> fetchLastSampleOutNo() async {
    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final branchId = _prefService.getEmployee()?.branchNo ?? 0;
      final res = await _apiService.getLastSampleOutNo(code, branchId);
      _lastSampleOutNo = res ?? '';
    } catch (e) {
      _lastSampleOutNo = '';
    }
    notifyListeners();
  }

  void setSelectedCustomer(CustomerModel? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  void setSelectedSampleOut(SampleOutModel? sampleOut) {
    _selectedSampleOut = sampleOut;
    if (sampleOut != null) {
      _productList.clear();
      for (final item in sampleOut.issueItems) {
        _productList.add(SampleOutModel.issueItemToDetails(item));
      }
      _selectedDate = sampleOut.date.isNotEmpty
          ? sampleOut.date
          : DateFormat('yyyy-MM-dd').format(DateTime.now());
      _returnDate = sampleOut.returnDate.isNotEmpty ? sampleOut.returnDate : _selectedDate;
      _description = sampleOut.description;

      _selectedCustomer = _customers.firstWhere(
        (c) => c.id == sampleOut.customerId,
        orElse: () => CustomerModel(
          id: sampleOut.customerId,
          firstName: sampleOut.customerName,
          lastName: '',
          clientCode: sampleOut.clientCode,
        ),
      );
    } else {
      clearSampleOut();
    }
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

  Future<String?> addProductByCodeOrRfid(String codeQuery, {bool notify = true}) async {
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

    if (exists) {
      return 'Item already added';
    }

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
    final double makingAmt = makingPerGram + makingFixedAmt + ((makingPercent / 100.0) * netWt) + makingFixedWastage;
    final double itemAmt = stoneAmt + diamondAmt + metalAmt + makingAmt;
    final double fineWt = netWt * (makingFixedWastage / 100.0);

    final employee = _prefService.getEmployee();
    final customerName = _selectedCustomer != null
        ? '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim()
        : '';

    final lineItem = ChallanDetailsModel(
      challanId: 0,
      mrp: matchedItem.mrp.toString(),
      categoryName: matchedItem.category,
      challanStatus: 'SampleOut',
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
      challanType: 'SampleOut',
      finePercentage: finePercent.toString(),
      purchaseInvoiceNo: '',
      hallmarkAmount: '0.0',
      hallmarkNo: '',
      makingFixedAmt: makingFixedAmt.toString(),
      makingFixedWastage: makingFixedWastage.toString(),
      makingPerGram: makingPerGram.toString(),
      makingPercentage: makingPercent.toString(),
      description: _description,
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
      diamondWeight: matchedItem.diamondWeight,
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
      diamondSellAmount: matchedItem.diamondAmount,
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
      stoneLessPercent: makingFixedWastage.toString(),
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
      customerName: customerName,
      pcs: 1,
    );

    _productList.add(lineItem);
    if (notify) notifyListeners();
    return null;
  }

  void removeProductItem(int index) {
    if (index >= 0 && index < _productList.length) {
      _productList.removeAt(index);
      notifyListeners();
    }
  }

  void updateProductItemDetails(int index, ChallanDetailsModel updated) {
    if (index >= 0 && index < _productList.length) {
      _productList[index] = updated;
      notifyListeners();
    }
  }

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

  double _sumDouble(String Function(ChallanDetailsModel) sel) {
    return _productList.fold(0.0, (s, it) => s + (double.tryParse(sel(it)) ?? 0.0));
  }

  void clearSampleOut() {
    _productList.clear();
    _selectedCustomer = null;
    _selectedSampleOut = null;
    _errorMessage = null;
    _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _returnDate = _selectedDate;
    _description = '';
    notifyListeners();
  }

  Map<String, dynamic> _buildIssueItemsPayload(String sampleOutNo, String clientCode, int branchId, String customerName, String sampleInDate) {
    final custId = _selectedCustomer?.id ?? 0;
    return {
      'IssueItems': _productList
          .map((item) => SampleOutModel.detailsToIssueItem(
                item: item,
                sampleOutNo: sampleOutNo,
                customerId: custId,
                clientCode: clientCode,
                branchId: branchId,
                customerName: customerName,
                sampleInDate: sampleInDate,
              ))
          .toList(),
    };
  }

  Future<Map<String, dynamic>?> submitSampleOut() async {
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
      final customerName = '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim();

      await fetchLastSampleOutNo();
      final nextNo = getNextSampleOutNo(_lastSampleOutNo);
      final sampleInDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final payload = {
        'ClientCode': code,
        'BranchId': branchId,
        'CustomerId': _selectedCustomer!.id ?? 0,
        'SampleOutNo': nextNo,
        'ReturnDate': _returnDate.isNotEmpty ? _returnDate : _selectedDate,
        'Description': _description,
        'Date': _selectedDate.isNotEmpty ? _selectedDate : sampleInDate,
        'SampleStatus': 'SampleOut',
        'Quantity': _productList.length,
        'TotalDiamondWeight': _sumDouble((it) => it.diamondWt.isNotEmpty ? it.diamondWt : it.totalDiamondWeight).toString(),
        'TotalGrossWt': _sumDouble((it) => it.grossWt).toString(),
        'TotalNetWt': _sumDouble((it) => it.netWt).toString(),
        'TotalStoneWeight': _sumDouble((it) => it.stoneAmt.isNotEmpty ? it.stoneAmt : it.stoneAmount).toString(),
        'TotalWt': _sumDouble((it) => it.totalWt).toString(),
        ..._buildIssueItemsPayload(nextNo, code, branchId, customerName, sampleInDate),
      };

      final response = await _apiService.addSampleOut(payload);
      if (response != null) {
        await fetchAllSampleOut();
        _isLoading = false;
        notifyListeners();
        return {
          ...response,
          'SampleOutNo': response['SampleOutNo']?.toString() ?? nextNo,
        };
      }
      _errorMessage = 'Failed to save sample out';
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateSampleOutRecord() async {
    if (_selectedSampleOut == null) {
      _errorMessage = 'No active sample out to update';
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
      final customerName = '${_selectedCustomer!.firstName ?? ''} ${_selectedCustomer!.lastName ?? ''}'.trim();
      final sampleNo = _selectedSampleOut!.sampleOutNo;
      final sampleInDate = DateTime.now().toUtc().toIso8601String();

      final payload = {
        'Id': _selectedSampleOut!.id,
        'ClientCode': code,
        'BranchId': branchId,
        'CustomerId': _selectedCustomer!.id ?? 0,
        'SampleOutNo': sampleNo,
        'ReturnDate': _returnDate.isNotEmpty ? _returnDate : _selectedSampleOut!.returnDate,
        'Description': _description,
        'Date': _selectedDate.isNotEmpty ? _selectedDate : _selectedSampleOut!.date,
        'SampleStatus': 'SampleOut',
        'Quantity': _productList.length,
        'TotalDiamondWeight': _sumDouble((it) => it.diamondWt.isNotEmpty ? it.diamondWt : it.totalDiamondWeight).toString(),
        'TotalGrossWt': _sumDouble((it) => it.grossWt).toString(),
        'TotalNetWt': _sumDouble((it) => it.netWt).toString(),
        'TotalStoneWeight': _sumDouble((it) => it.stoneAmt.isNotEmpty ? it.stoneAmt : it.stoneAmount).toString(),
        'TotalWt': _sumDouble((it) => it.totalWt).toString(),
        'StatusType': true,
        'SampleInDate': sampleInDate,
        ..._buildIssueItemsPayload(sampleNo, code, branchId, customerName, sampleInDate),
      };

      final response = await _apiService.updateSampleOut(payload);
      if (response != null) {
        await fetchAllSampleOut();
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _errorMessage = 'Failed to update sample out';
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

  SamplePrintData buildSampleOutPrintData({
    required String sampleOutNo,
    Map<String, dynamic>? apiResponse,
  }) {
    final customer = _selectedCustomer;
    final custFromApi = apiResponse?['Customer'] as Map<String, dynamic>?;
    final customerName = custFromApi != null
        ? '${custFromApi['FirstName'] ?? ''} ${custFromApi['LastName'] ?? ''}'.trim()
        : '${customer?.firstName ?? ''} ${customer?.lastName ?? ''}'.trim();
    final addressCity = custFromApi?['CurrAddTown']?.toString() ??
        customer?.currAddTown ??
        customer?.city ??
        '';
    final contactNo = custFromApi?['Mobile']?.toString() ?? customer?.mobile ?? '';

    final items = _productList.map((it) {
      final details = [
        it.categoryName,
        it.productName,
        it.designName,
        it.purity,
      ].where((e) => e.trim().isNotEmpty).join(' - ');
      return SamplePrintItem(
        itemDetails: details,
        grossWt: it.grossWt,
        stoneWt: it.totalStoneWeight.isNotEmpty ? it.totalStoneWeight : it.stoneAmount,
        diamondWt: it.diamondWt.isNotEmpty ? it.diamondWt : it.totalDiamondWeight,
        netWt: it.netWt,
        pieces: it.pieces,
        status: 'Sample Out',
      );
    }).toList();

    return SamplePrintData(
      companyName: 'SPARKLE RFID',
      customerName: customerName,
      addressCity: addressCity,
      contactNo: contactNo,
      sampleOutNo: sampleOutNo,
      date: _selectedDate.isNotEmpty ? _selectedDate : DateFormat('yyyy-MM-dd').format(DateTime.now()),
      returnDate: _returnDate.isNotEmpty ? _returnDate : _selectedDate,
      items: items,
      isSampleIn: false,
    );
  }
}
