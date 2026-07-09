import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/bulk_item.dart';
import '../models/customer.dart';
import '../models/delivery_challan.dart';
import '../models/sample_in.dart';
import '../models/sample_out.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../views/widgets/sample_print_pdf.dart';

class SampleInViewModel extends ChangeNotifier {
  final PrefService _prefService;
  final DbService _dbService;
  final ApiService _apiService;


  Map<String, BulkItem> _issueBulkItems = {};

  SampleInViewModel({
    required PrefService prefService,
    required DbService dbService,
    required ApiService apiService,
  })  : _prefService = prefService,
        _dbService = dbService,
        _apiService = apiService;

  List<SampleInModel> _sampleInList = [];
  List<SampleInModel> get sampleInList => _sampleInList;

  List<SampleOutModel> _openSampleOuts = [];
  List<SampleOutModel> get openSampleOuts => _openSampleOuts;

  List<CustomerModel> _customers = [];
  List<CustomerModel> get customers => _customers;

  List<dynamic> _dailyRates = [];
  List<dynamic> get dailyRates => _dailyRates;

  CustomerModel? _selectedCustomer;
  CustomerModel? get selectedCustomer => _selectedCustomer;

  SampleOutModel? _selectedChallan;
  SampleOutModel? get selectedChallan => _selectedChallan;

  final Set<String> _scannedCodes = {};
  Set<String> get scannedCodes => Set.unmodifiable(_scannedCodes);

  bool _isReturnMode = false;
  bool get isReturnMode => _isReturnMode;

  final Set<String> _selectedReturnCodes = {};
  Set<String> get selectedReturnCodes => Set.unmodifiable(_selectedReturnCodes);

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

  Map<String, dynamic>? _lastSaveResponse;
  Map<String, dynamic>? get lastSaveResponse => _lastSaveResponse;

  List<Map<String, dynamic>> get issueItems =>
      _selectedChallan?.issueItems ?? const [];

  List<SampleOutModel> get customerWiseSampleOuts {
    if (_selectedCustomer == null) return _openSampleOuts;
    final cid = _selectedCustomer!.id ?? 0;
    return _openSampleOuts.where((c) => c.customerId == cid).toList();
  }

  int get matchCount => issueItems.where((i) => isIssueMatched(i)).length;
  int get notMatchCount => issueItems.length - matchCount;

  Future<void> loadMasterData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final rawCustomers = await _apiService.getAllCustomers(code);
      _customers = rawCustomers.map((c) => CustomerModel.fromJson(c as Map<String, dynamic>)).toList();
      _dailyRates = await _apiService.getDailyRates(code);
      await fetchAllSampleIn();
      await fetchOpenSampleOuts();
      _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _returnDate = _selectedDate;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSampleInList() async {
    _isListLoading = true;
    notifyListeners();
    try {
      await fetchAllSampleIn();
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAllSampleIn() async {
    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final raw = await _apiService.getAllSampleIn(code);
      _sampleInList = raw.map((c) => SampleInModel.fromJson(c as Map<String, dynamic>)).toList();
    } catch (e) {
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> fetchOpenSampleOuts() async {
    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final raw = await _apiService.getAllSampleOut(code);
      _openSampleOuts = raw.map((c) => SampleOutModel.fromJson(c as Map<String, dynamic>)).toList();
    } catch (e) {
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  void setSelectedCustomer(CustomerModel? customer) {
    _selectedCustomer = customer;
    _selectedChallan = null;
    _scannedCodes.clear();
    _selectedReturnCodes.clear();
    _isReturnMode = false;
    notifyListeners();
  }

  void setSampleInFields({
    required String date,
    required String returnDate,
    required String description,
  }) {
    _selectedDate = date;
    _returnDate = returnDate;
    _description = description;
    notifyListeners();
  }

  void selectSampleOut(SampleOutModel challan) {
    _selectedChallan = challan;
    _scannedCodes.clear();
    _selectedReturnCodes.clear();
    _isReturnMode = false;
    if (_description.isEmpty) _description = challan.description;
    if (_returnDate.isEmpty) _returnDate = challan.returnDate;
    if (_selectedDate.isEmpty) _selectedDate = challan.date.isNotEmpty ? challan.date : DateFormat('yyyy-MM-dd').format(DateTime.now());
    loadIssueBulkItems();
    notifyListeners();
  }

  void clearSelectedChallan() {
    _selectedChallan = null;
    _scannedCodes.clear();
    _selectedReturnCodes.clear();
    _isReturnMode = false;
    notifyListeners();
  }

  void clearSampleIn() {
    _selectedCustomer = null;
    _selectedChallan = null;
    _scannedCodes.clear();
    _selectedReturnCodes.clear();
    _isReturnMode = false;
    _errorMessage = null;
    _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _returnDate = _selectedDate;
    _description = '';
    notifyListeners();
  }

  bool isIssueMatched(Map<String, dynamic> issue) {
    final code = normSampleCode(issue['ItemCode']?.toString());
    if (code.isEmpty) return false;
    final scannedNorm = _scannedCodes.map(normSampleCode).toSet();
    return scannedNorm.contains(code);
  }

  Future<void> refreshBulkItems() async {
    await loadIssueBulkItems();
  }

  Future<void> loadIssueBulkItems() async {
    if (issueItems.isEmpty) {
      _issueBulkItems = {};
      return;
    }
    try {
      final codes = issueItems
          .map((i) => normSampleCode(i['ItemCode']?.toString()))
          .where((c) => c.isNotEmpty)
          .toSet();
      _issueBulkItems = await _dbService.findBulkItemsByItemCodes(codes);
    } catch (e) {
      debugPrint('SampleIn loadIssueBulkItems: $e');
      _issueBulkItems = {};
    }
  }

  List<String> get scanScopeTags {
    final tags = <String>{};
    for (final issue in issueItems) {
      for (final key in ['ItemCode', 'RFIDCode', 'TIDNumber']) {
        final v = issue[key]?.toString().trim().toUpperCase() ?? '';
        if (v.isNotEmpty) tags.add(v);
      }
    }
    for (final item in _issueBulkItems.values) {
      for (final v in [item.epc, item.rfid, item.tid, item.itemCode]) {
        final t = v.trim().toUpperCase();
        if (t.isNotEmpty) tags.add(t);
      }
    }
    return tags.toList();
  }

  void _addIssueCodesToSet(Set<String> target, Map<String, dynamic> issue) {
    for (final code in _codesForIssue(issue)) {
      if (code.isNotEmpty) target.add(code);
    }
  }

  BulkItem? _findBulkItemByCode(String scanned) {
    for (final item in _issueBulkItems.values) {
      if (normSampleCode(item.itemCode) == scanned ||
          normSampleCode(item.rfid) == scanned ||
          normSampleCode(item.epc) == scanned ||
          normSampleCode(item.tid) == scanned) {
        return item;
      }
    }
    return null;
  }

  List<String> _codesForIssue(Map<String, dynamic> issue) {
    return [
      normSampleCode(issue['ItemCode']?.toString()),
      normSampleCode(issue['RFIDCode']?.toString()),
      normSampleCode(issue['TIDNumber']?.toString()),
    ].where((c) => c.isNotEmpty).toList();
  }

  void manualMatchIssue(Map<String, dynamic> issue) {
    _scannedCodes.addAll(_codesForIssue(issue));
    notifyListeners();
  }

  void manualRemoveIssue(Map<String, dynamic> issue) {
    final toRemove = _codesForIssue(issue).toSet();
    _scannedCodes.removeWhere((c) => toRemove.contains(normSampleCode(c)));
    _selectedReturnCodes.removeWhere((c) => toRemove.contains(normSampleCode(c)));
    notifyListeners();
  }

  Future<bool> processScannedTags(List<String> tags) async {
    if (_selectedChallan == null || issueItems.isEmpty) return false;

    if (_issueBulkItems.isEmpty) {
      await loadIssueBulkItems();
    }

    final issueItemCodes = issueItems
        .map((i) => normSampleCode(i['ItemCode']?.toString()))
        .where((c) => c.isNotEmpty)
        .toSet();

    final before = _scannedCodes.length;
    final updated = Set<String>.from(_scannedCodes);

    for (final tag in tags) {
      final scanned = normSampleCode(tag);
      if (scanned.isEmpty) continue;

      var matched = false;
      for (final issue in issueItems) {
        final itemCode = normSampleCode(issue['ItemCode']?.toString());
        final rfid = normSampleCode(issue['RFIDCode']?.toString());
        final tid = normSampleCode(issue['TIDNumber']?.toString());

        if (scanned == itemCode || scanned == rfid || scanned == tid) {
          matched = true;
          _addIssueCodesToSet(updated, issue);
        }
      }

      if (matched) continue;

      var bulk = _findBulkItemByCode(scanned);
      bulk ??= await _dbService.findBulkItemByScanKey(tag);
      if (bulk == null) continue;

      final bulkItemCode = normSampleCode(bulk.itemCode);
      if (!issueItemCodes.contains(bulkItemCode)) continue;

      updated.add(bulkItemCode);
      final bulkRfid = normSampleCode(bulk.rfid);
      final bulkTid = normSampleCode(bulk.tid);
      if (bulkRfid.isNotEmpty) updated.add(bulkRfid);
      if (bulkTid.isNotEmpty) updated.add(bulkTid);
    }

    _scannedCodes
      ..clear()
      ..addAll(updated);
    notifyListeners();
    return _scannedCodes.length > before;
  }

  void setReturnMode(bool value) {
    _isReturnMode = value;
    _selectedReturnCodes.clear();
    notifyListeners();
  }

  void toggleReturnSelection(String itemCode) {
    final norm = normSampleCode(itemCode);
    if (norm.isEmpty) return;
    if (_selectedReturnCodes.any((c) => normSampleCode(c) == norm)) {
      _selectedReturnCodes.removeWhere((c) => normSampleCode(c) == norm);
    } else {
      _selectedReturnCodes.add(norm);
    }
    notifyListeners();
  }

  void updateIssueItem(int index, ChallanDetailsModel updated) {
    if (_selectedChallan == null || index < 0 || index >= issueItems.length) return;
    final items = List<Map<String, dynamic>>.from(_selectedChallan!.issueItems);
    final map = Map<String, dynamic>.from(items[index]);
    map['GrossWt'] = updated.grossWt;
    map['NetWt'] = updated.netWt;
    map['TotalWt'] = updated.totalWt;
    map['StoneWeight'] = updated.totalStoneWeight;
    map['DiamondWeight'] = updated.diamondWt.isNotEmpty ? updated.diamondWt : updated.totalDiamondWeight;
    map['Quantity'] = updated.qty;
    map['Pieces'] = updated.pieces;
    map['Description'] = updated.description;
    map['FineWastageWt'] = updated.fineWastageWt;
    map['StoneAmount'] = updated.stoneAmt.isNotEmpty ? updated.stoneAmt : updated.stoneAmount;
    map['DiamondAmount'] = updated.diamondAmt.isNotEmpty ? updated.diamondAmt : updated.totalDiamondAmount;
    map['MetalAmount'] = updated.metalAmount;
    map['RatePerGram'] = updated.metalRate;
    items[index] = map;
    _selectedChallan = SampleOutModel(
      id: _selectedChallan!.id,
      sampleStatus: _selectedChallan!.sampleStatus,
      sampleOutNo: _selectedChallan!.sampleOutNo,
      statusType: _selectedChallan!.statusType,
      createdOn: _selectedChallan!.createdOn,
      lastUpdated: _selectedChallan!.lastUpdated,
      customerId: _selectedChallan!.customerId,
      quantity: _selectedChallan!.quantity,
      totalWt: _selectedChallan!.totalWt,
      totalGrossWt: _selectedChallan!.totalGrossWt,
      totalNetWt: _selectedChallan!.totalNetWt,
      totalStoneWeight: _selectedChallan!.totalStoneWeight,
      totalDiamondWeight: _selectedChallan!.totalDiamondWeight,
      returnDate: _returnDate,
      description: _description,
      date: _selectedDate,
      clientCode: _selectedChallan!.clientCode,
      branchId: _selectedChallan!.branchId,
      issueItems: items,
      customerFirstName: _selectedChallan!.customerFirstName,
    );
    notifyListeners();
  }

  ChallanDetailsModel issueToDetails(Map<String, dynamic> issue) {
    return SampleOutModel.issueItemToDetails(issue);
  }

  Future<bool> addCustomerProfile(Map<String, dynamic> req) async {
    _isLoading = true;
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
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false;
    notifyListeners();
    return false;
  }

  double _sumIssues(String Function(Map<String, dynamic>) sel) {
    return issueItems.fold(0.0, (s, it) => s + (double.tryParse(sel(it)) ?? 0.0));
  }

  SamplePrintData buildSampleInPrintData({Map<String, dynamic>? apiResponse}) {
    final scannedNorm = _scannedCodes.map(normSampleCode).toSet();
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

    final items = issueItems.map((issue) {
      final itemCode = normSampleCode(issue['ItemCode']?.toString());
      final status = scannedNorm.contains(itemCode) ? 'SampleIn' : 'SampleOut';
      return SamplePrintItem(
        itemDetails: sampleItemDetailsFromIssue(issue),
        grossWt: issue['GrossWt']?.toString() ?? '0.000',
        stoneWt: issue['StoneWeight']?.toString() ?? '0.000',
        diamondWt: issue['DiamondWeight']?.toString() ?? '0.000',
        netWt: issue['NetWt']?.toString() ?? '0.000',
        pieces: issue['Pieces']?.toString() ?? '0',
        status: status,
      );
    }).toList();

    return SamplePrintData(
      companyName: 'SPARKLE RFID',
      customerName: customerName,
      addressCity: addressCity,
      contactNo: contactNo,
      sampleOutNo: _selectedChallan?.sampleOutNo ?? apiResponse?['SampleOutNo']?.toString() ?? '',
      date: _selectedDate.isNotEmpty ? _selectedDate : (_selectedChallan?.date ?? ''),
      returnDate: _returnDate.isNotEmpty ? _returnDate : (_selectedChallan?.returnDate ?? ''),
      items: items,
      isSampleIn: true,
    );
  }

  Future<bool> submitSampleIn() async {
    if (_selectedCustomer == null) {
      _errorMessage = 'Please select a customer';
      notifyListeners();
      return false;
    }
    if (_selectedChallan == null || issueItems.isEmpty) {
      _errorMessage = 'Please select a Sample Out No';
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
      final sampleInDate = DateTime.now().toUtc().toIso8601String();
      final scannedNorm = _scannedCodes.map(normSampleCode).toSet();

      final allItemCodes = issueItems
          .map((i) => normSampleCode(i['ItemCode']?.toString()))
          .where((c) => c.isNotEmpty)
          .toSet();
      final allMatched = allItemCodes.isNotEmpty && allItemCodes.every((c) => scannedNorm.contains(c));
      final mainStatus = allMatched ? 'SampleIn' : 'SampleOut';

      final issuePayloads = issueItems.map((issue) {
        final itemCode = normSampleCode(issue['ItemCode']?.toString());
        final itemStatus = scannedNorm.contains(itemCode) ? 'SampleIn' : 'SampleOut';
        return issueMapToIssueItemPayload(
          issue: issue,
          parentSampleOutNo: _selectedChallan!.sampleOutNo,
          customerId: _selectedCustomer!.id ?? 0,
          clientCode: code,
          branchId: branchId,
          customerName: customerName,
          sampleInDate: sampleInDate,
          itemStatus: itemStatus,
        );
      }).toList();

      final payload = {
        'Id': _selectedChallan!.id,
        'ClientCode': code,
        'BranchId': branchId,
        'CustomerId': _selectedCustomer!.id ?? 0,
        'SampleOutNo': _selectedChallan!.sampleOutNo,
        'ReturnDate': _returnDate.isNotEmpty ? _returnDate : _selectedChallan!.returnDate,
        'Description': _description.isNotEmpty ? _description : _selectedChallan!.description,
        'Date': _selectedDate.isNotEmpty ? _selectedDate : _selectedChallan!.date,
        'SampleStatus': mainStatus,
        'Quantity': issueItems.length,
        'TotalDiamondWeight': _sumIssues((i) => i['DiamondWeight']?.toString() ?? '0').toString(),
        'TotalGrossWt': _sumIssues((i) => i['GrossWt']?.toString() ?? '0').toString(),
        'TotalNetWt': _sumIssues((i) => i['NetWt']?.toString() ?? '0').toString(),
        'TotalStoneWeight': _sumIssues((i) => i['StoneWeight']?.toString() ?? '0').toString(),
        'TotalWt': _sumIssues((i) => i['TotalWt']?.toString() ?? i['NetWt']?.toString() ?? '0').toString(),
        'StatusType': true,
        'SampleInDate': sampleInDate,
        'IssueItems': issuePayloads,
      };

      final response = await _apiService.updateSampleOut(payload);
      if (response != null) {
        await fetchAllSampleIn();
        await fetchOpenSampleOuts();
        _lastSaveResponse = response;
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _errorMessage = 'Failed to save sample in';
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
}
