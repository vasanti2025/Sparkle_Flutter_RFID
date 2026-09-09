import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/bulk_item.dart';
import '../models/customer.dart';
import '../models/delivery_challan.dart';
import '../models/sample_in.dart';
import '../models/sample_out.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/label_stock_sync_service.dart';
import '../services/list_json_cache.dart';
import '../services/pref_service.dart';
import '../views/widgets/sample_print_pdf.dart';

import '../utils/tag_scan_batcher.dart';

class SampleInViewModel extends ChangeNotifier with LiveScanGate {
  final PrefService _prefService;
  final DbService _dbService;
  final ApiService _apiService;


  Map<String, BulkItem> _issueBulkItems = {};
  Future<void> _processTagsChain = Future<void>.value();
  final Map<String, Map<String, dynamic>> _scanKeyToIssue = {};
  final Map<String, BulkItem> _bulkByScanKey = {};
  final Set<String> _scopeTagSet = {};
  final Set<String> _issueItemCodes = {};
  final Set<String> _scannedNorm = {};
  int? _bulkLoadedForChallanId;
  Future<void>? _bulkLoadInFlight;

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
      final customersFuture = _apiService.getAllCustomers(code);
      final ratesFuture = _apiService.getDailyRates(code);
      final outsFuture = _apiService.getAllSampleOut(code);

      final rawCustomers = await customersFuture;
      _customers = rawCustomers
          .map((c) => CustomerModel.fromJson(c as Map<String, dynamic>))
          .toList();
      _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _returnDate = _selectedDate;
      // Customers first so the user can type while challans/rates finish.
      notifyListeners();

      _dailyRates = await ratesFuture;
      try {
        final raw = await outsFuture;
        _openSampleOuts = raw.map((c) => SampleOutModel.fromJson(c as Map<String, dynamic>)).toList();
      } catch (e) {
        _errorMessage = e.toString();
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSampleInList() async {
    final code = _prefService.getEmployee()?.clientCode ?? '';
    final cacheKey = 'sample_in_$code';

    if (_sampleInList.isEmpty) {
      final mem = ListJsonCache.instance.readMemory(cacheKey);
      if (mem != null && mem.isNotEmpty) {
        _sampleInList = mem
            .whereType<Map>()
            .map((c) => SampleInModel.fromJson(Map<String, dynamic>.from(c)))
            .toList();
        notifyListeners();
      } else {
        final cached = await ListJsonCache.instance.load(cacheKey);
        if (cached.isNotEmpty) {
          _sampleInList = cached
              .whereType<Map>()
              .map((c) => SampleInModel.fromJson(Map<String, dynamic>.from(c)))
              .toList();
          notifyListeners();
        }
      }
    }

    final hasCached = _sampleInList.isNotEmpty;
    if (!hasCached) {
      _isListLoading = true;
      notifyListeners();
    }

    try {
      await fetchAllSampleIn(cacheKey: cacheKey);
    } finally {
      _isListLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAllSampleIn({String? cacheKey}) async {
    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      final key = cacheKey ?? 'sample_in_$code';
      final raw = await _apiService.getAllSampleIn(code);
      _sampleInList = raw
          .whereType<Map>()
          .map((c) => SampleInModel.fromJson(Map<String, dynamic>.from(c)))
          .toList();
      await ListJsonCache.instance.save(key, raw);
    } catch (e) {
      if (_sampleInList.isEmpty) {
        _errorMessage = e.toString();
      }
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
    _scannedNorm.clear();
    _isReturnMode = false;
    _clearScanIndexes();
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
    _scannedNorm.clear();
    _isReturnMode = false;
    if (_description.isEmpty) _description = challan.description;
    if (_returnDate.isEmpty) _returnDate = challan.returnDate;
    if (_selectedDate.isEmpty) _selectedDate = challan.date.isNotEmpty ? challan.date : DateFormat('yyyy-MM-dd').format(DateTime.now());
    _rebuildScanIndexes();
    unawaited(ensureIssueBulkItems());
    notifyListeners();
  }

  void clearSelectedChallan() {
    _selectedChallan = null;
    _scannedCodes.clear();
    _selectedReturnCodes.clear();
    _scannedNorm.clear();
    _isReturnMode = false;
    _clearScanIndexes();
    notifyListeners();
  }

  void clearSampleIn() {
    _selectedCustomer = null;
    _selectedChallan = null;
    _scannedCodes.clear();
    _selectedReturnCodes.clear();
    _scannedNorm.clear();
    _isReturnMode = false;
    _errorMessage = null;
    _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _returnDate = _selectedDate;
    _description = '';
    _clearScanIndexes();
    notifyListeners();
  }

  bool isIssueMatched(Map<String, dynamic> issue) {
    final code = normSampleCode(issue['ItemCode']?.toString());
    if (code.isEmpty) return false;
    return _scannedNorm.contains(code) || _scannedCodes.contains(code);
  }

  Future<void> refreshBulkItems() async {
    _bulkLoadedForChallanId = null;
    await ensureIssueBulkItems();
  }

  void _clearScanIndexes() {
    _issueBulkItems = {};
    _scanKeyToIssue.clear();
    _bulkByScanKey.clear();
    _scopeTagSet.clear();
    _issueItemCodes.clear();
    _bulkLoadedForChallanId = null;
  }

  void _rebuildScanIndexes() {
    _scanKeyToIssue.clear();
    _bulkByScanKey.clear();
    _scopeTagSet.clear();
    _issueItemCodes.clear();
    for (final issue in issueItems) {
      for (final code in _codesForIssue(issue)) {
        _scanKeyToIssue[code] = issue;
        _scopeTagSet.add(code);
      }
      for (final key in ['ItemCode', 'RFIDCode', 'TIDNumber']) {
        final raw = issue[key]?.toString().trim().toUpperCase() ?? '';
        if (raw.isNotEmpty) _scopeTagSet.add(raw);
      }
      final itemCode = normSampleCode(issue['ItemCode']?.toString());
      if (itemCode.isNotEmpty) _issueItemCodes.add(itemCode);
    }
    for (final item in _issueBulkItems.values) {
      void put(String raw) {
        final trimmed = raw.trim().toUpperCase();
        if (trimmed.isNotEmpty) _scopeTagSet.add(trimmed);
        final key = normSampleCode(raw);
        if (key.isEmpty) return;
        _bulkByScanKey[key] = item;
        _scopeTagSet.add(key);
      }
      put(item.epc);
      put(item.rfid);
      put(item.tid);
      put(item.itemCode);
    }
  }

  void _applyScanned(Set<String> updated) {
    if (!identical(updated, _scannedCodes)) {
      _scannedCodes
        ..clear()
        ..addAll(updated);
    }
    _scannedNorm
      ..clear()
      ..addAll(_scannedCodes.map(normSampleCode).where((c) => c.isNotEmpty));
  }

  Future<void> ensureIssueBulkItems() async {
    final id = _selectedChallan?.id;
    if (id != null && _bulkLoadedForChallanId == id) return;
    if (_bulkLoadInFlight != null) {
      await _bulkLoadInFlight;
      if (id != null && _bulkLoadedForChallanId == id) return;
    }
    if (_selectedChallan?.id != id) return;
    final future = loadIssueBulkItems();
    _bulkLoadInFlight = future;
    try {
      await future;
      if (_selectedChallan?.id == id) {
        _bulkLoadedForChallanId = id;
      }
    } finally {
      if (identical(_bulkLoadInFlight, future)) _bulkLoadInFlight = null;
    }
  }

  Future<void> loadIssueBulkItems() async {
    final challanId = _selectedChallan?.id;
    if (issueItems.isEmpty) {
      _issueBulkItems = {};
      _rebuildScanIndexes();
      return;
    }
    try {
      final codes = issueItems
          .map((i) => normSampleCode(i['ItemCode']?.toString()))
          .where((c) => c.isNotEmpty)
          .toSet();
      final loaded = await _dbService.findBulkItemsByItemCodes(codes);
      if (_selectedChallan?.id != challanId) return;
      _issueBulkItems = loaded;
    } catch (e) {
      debugPrint('SampleIn loadIssueBulkItems: $e');
      if (_selectedChallan?.id != challanId) return;
      _issueBulkItems = {};
    }
    _rebuildScanIndexes();
  }

  List<String> get scanScopeTags => _scopeTagSet.toList();

  void _addIssueCodesToSet(Set<String> target, Map<String, dynamic> issue) {
    for (final code in _codesForIssue(issue)) {
      if (code.isNotEmpty) target.add(code);
    }
  }

  List<String> _codesForIssue(Map<String, dynamic> issue) {
    return [
      normSampleCode(issue['ItemCode']?.toString()),
      normSampleCode(issue['RFIDCode']?.toString()),
      normSampleCode(issue['TIDNumber']?.toString()),
    ].where((c) => c.isNotEmpty).toList();
  }

  /// Whether a tray tag maps to an item in the active Sample Out issue list.
  bool isTagInScanScope(String tag) {
    final scanned = normSampleCode(tag);
    if (scanned.isEmpty || _scopeTagSet.isEmpty) return false;
    return _scopeTagSet.contains(scanned);
  }

  void manualMatchIssue(Map<String, dynamic> issue) {
    _scannedCodes.addAll(_codesForIssue(issue));
    _applyScanned(_scannedCodes);
    notifyListeners();
  }

  void manualRemoveIssue(Map<String, dynamic> issue) {
    final toRemove = _codesForIssue(issue).toSet();
    _scannedCodes.removeWhere((c) => toRemove.contains(normSampleCode(c)));
    _selectedReturnCodes.removeWhere((c) => toRemove.contains(normSampleCode(c)));
    _applyScanned(_scannedCodes);
    notifyListeners();
  }

  Future<bool> processScannedTags(List<String> tags, {bool fromLiveScan = true}) {
    final result = Completer<bool>();
    _processTagsChain = _processTagsChain.then((_) async {
      try {
        result.complete(await _processScannedTagsBody(tags, fromLiveScan: fromLiveScan));
      } catch (e, st) {
        debugPrint('SampleIn processScannedTags: $e\n$st');
        if (!result.isCompleted) result.complete(false);
      }
    }).catchError((Object e, StackTrace st) {
      debugPrint('SampleIn process chain: $e\n$st');
      if (!result.isCompleted) result.complete(false);
    });
    return result.future;
  }

  Future<bool> _processScannedTagsBody(List<String> tags, {required bool fromLiveScan}) async {
    if (_selectedChallan == null || issueItems.isEmpty) return false;

    if (_bulkLoadedForChallanId != _selectedChallan?.id) {
      await ensureIssueBulkItems();
    }
    if (!acceptLiveScan(fromLiveScan)) return false;

    final before = _scannedCodes.length;
    final updated = Set<String>.from(_scannedCodes);
    var lastNotifyMs = 0;

    for (final tag in tags) {
      if (!acceptLiveScan(fromLiveScan)) break;
      final scanned = normSampleCode(tag);
      if (scanned.isEmpty) continue;

      final issue = _scanKeyToIssue[scanned];
      if (issue != null) {
        _addIssueCodesToSet(updated, issue);
      } else {
        var bulk = _bulkByScanKey[scanned] ?? _dbService.findBulkItemByScanKeySync(tag);
        if (bulk == null && !fromLiveScan) {
          bulk = await _dbService.findBulkItemByScanKey(tag);
          if (!acceptLiveScan(fromLiveScan)) break;
        }
        if (bulk == null) continue;

        final bulkItemCode = normSampleCode(bulk.itemCode);
        if (!_issueItemCodes.contains(bulkItemCode)) continue;

        updated.add(bulkItemCode);
        final bulkRfid = normSampleCode(bulk.rfid);
        final bulkTid = normSampleCode(bulk.tid);
        if (bulkRfid.isNotEmpty) updated.add(bulkRfid);
        if (bulkTid.isNotEmpty) updated.add(bulkTid);
      }

      if (!fromLiveScan) continue;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastNotifyMs >= 80) {
        _applyScanned(updated);
        notifyListeners();
        lastNotifyMs = now;
      }
    }

    _applyScanned(updated);
    if (acceptLiveScan(fromLiveScan)) notifyListeners();
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
    _rebuildScanIndexes();
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
        final returnedIds = <int>[];
        final returnedCodes = <String>[];
        for (final issue in issueItems) {
          final itemCode = normSampleCode(issue['ItemCode']?.toString());
          if (itemCode.isEmpty || !scannedNorm.contains(itemCode)) continue;
          returnedCodes.add(itemCode);
          final sid = (issue['LabelledStockId'] as num?)?.toInt() ??
              int.tryParse('${issue['LabelledStockId'] ?? ''}') ??
              0;
          if (sid > 0) returnedIds.add(sid);
        }
        await LabelStockSyncService.afterStockIn(
          prefService: _prefService,
          dbService: _dbService,
          labelledStockIds: returnedIds,
          itemCodes: returnedCodes,
        );
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
