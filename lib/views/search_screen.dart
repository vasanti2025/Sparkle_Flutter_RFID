import 'dart:async';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../viewmodels/dashboard_view_model.dart';
import 'widgets/scan_bottom_bar.dart';

class SearchItem {
  final String epc;
  final String itemCode;
  final String productName;
  final String rfid;
  final String tid;
  final String hex;
  final String rssi;
  final int proximityPercent;

  SearchItem({
    required this.epc,
    required this.itemCode,
    required this.productName,
    required this.rfid,
    this.tid = '',
    this.hex = '',
    this.rssi = '',
    this.proximityPercent = 0,
  });

  SearchItem copyWith({
    String? rssi,
    int? proximityPercent,
  }) {
    return SearchItem(
      epc: epc,
      itemCode: itemCode,
      productName: productName,
      rfid: rfid,
      tid: tid,
      hex: hex,
      rssi: rssi ?? this.rssi,
      proximityPercent: proximityPercent ?? this.proximityPercent,
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final RfidService _rfidService = RfidService();
  final TextEditingController _searchController = TextEditingController();
  
  StreamSubscription? _tagsSubscription;
  StreamSubscription? _triggerSubscription;
  Timer? _debounceTimer;
  Timer? _uiFlushTimer;

  bool _isInit = false;
  bool _isLoading = false;
  bool _isScanning = false;
  int _selectedPower = 30;

  String _listKey = 'normal'; // 'unmatchedItems' or 'normal'
  String _selectedSearchType = 'LabelStock'; // 'LabelStock', 'Order', 'Box'
  String _searchQuery = '';

  List<SearchItem> _searchItems = [];

  // O(1) tag lookup — mirrors Kotlin SearchViewModel.epcToIndex
  final Map<String, int> _tagIndexMap = {};
  int _lastSearchUiUpdateUs = 0;
  final Map<int, SearchItem> _pendingItemUpdates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_rfidService.preWarmReader());
    });
    _tagsSubscription = _rfidService.tagsWithRssiStream.listen(_onTagScanned);
    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      _toggleScanning();
    });
    _loadPower();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        final listKey = args['listKey'] as String? ?? 'normal';
        final rawItems = args['items'] as List?;
        final items = rawItems?.cast<BulkItem>().toList() ?? <BulkItem>[];
        setState(() {
          _listKey = listKey;
          if (_listKey == 'unmatchedItems') {
            _searchItems = items.map((i) => _searchItemFromBulk(i)).toList();
            _rebuildTagIndex();
          }
        });
      }
      _isInit = true;
    }
  }

  @override
  void dispose() {
    _tagsSubscription?.cancel();
    _triggerSubscription?.cancel();
    _debounceTimer?.cancel();
    _uiFlushTimer?.cancel();
    _rfidService.stopScanning();
    _rfidService.clearSearchTags();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPower() async {
    final power = context.read<PrefService>().searchPower;
    if (mounted) setState(() => _selectedPower = power);
    _rfidService.setPower(power);
  }

  void _rebuildTagIndex() {
    _tagIndexMap.clear();
    for (int i = 0; i < _searchItems.length; i++) {
      final item = _searchItems[i];
      void addKey(String value) {
        final key = value.trim().toUpperCase();
        if (key.isNotEmpty) _tagIndexMap[key] = i;
      }
      addKey(item.epc);
      addKey(item.rfid);
      addKey(item.itemCode);
      addKey(item.tid);
      addKey(item.hex);
    }
  }

  void _flushPendingSearchUpdates() {
    if (_pendingItemUpdates.isEmpty || !mounted) return;
    setState(() {
      _pendingItemUpdates.forEach((index, item) {
        if (index >= 0 && index < _searchItems.length) {
          _searchItems[index] = item;
        }
      });
      _pendingItemUpdates.clear();
    });
  }

  void _scheduleSearchUiUpdate(int index, SearchItem updated) {
    _pendingItemUpdates[index] = updated;
    final now = DateTime.now().microsecondsSinceEpoch;
    if (_lastSearchUiUpdateUs == 0 ||
        now - _lastSearchUiUpdateUs >= 16000) {
      _lastSearchUiUpdateUs = now;
      _uiFlushTimer?.cancel();
      _flushPendingSearchUpdates();
    } else {
      _uiFlushTimer ??= Timer(const Duration(milliseconds: 16), () {
        _uiFlushTimer = null;
        _lastSearchUiUpdateUs = DateTime.now().microsecondsSinceEpoch;
        _flushPendingSearchUpdates();
      });
    }
  }

  SearchItem _searchItemFromBulk(BulkItem item) {
    final epcValue = item.epc.isNotEmpty
        ? item.epc
        : (item.rfid.isNotEmpty
            ? item.rfid
            : (item.itemCode.isNotEmpty ? item.itemCode : ''));
    return SearchItem(
      epc: epcValue,
      itemCode: item.itemCode,
      productName: item.productName,
      rfid: item.rfid,
      tid: item.tid,
      hex: item.box,
    );
  }

  int convertRssiToProximity(String rssi) {
    try {
      final rssiValue = double.parse(rssi.trim());
      return (((rssiValue + 80).clamp(0.0, 40.0)) * 100 / 40).toInt().clamp(0, 100);
    } catch (_) {
      return 0;
    }
  }

  Color getColorByPercentage(int percent) {
    if (percent <= 25) return Colors.red;
    if (percent <= 50) return Colors.yellow[700]!;
    if (percent <= 75) return Colors.blue;
    return Colors.green;
  }

  void _onTagScanned(Map<String, dynamic> tagEvent) {
    if (!_isScanning) return;

    final epc = (tagEvent['epc'] as String? ?? '').trim().toUpperCase();
    final rssi = (tagEvent['rssi'] as String? ?? '').trim();
    if (epc.isEmpty) return;

    final index = _tagIndexMap[epc];
    if (index == null || index < 0 || index >= _searchItems.length) return;

    final proximity = convertRssiToProximity(rssi);
    _scheduleSearchUiUpdate(
      index,
      _searchItems[index].copyWith(
        rssi: rssi,
        proximityPercent: proximity,
      ),
    );
  }

  void _toggleScanning() async {
    if (_isScanning) {
      await _rfidService.stopScanning();
      await _rfidService.clearSearchTags();
      setState(() {
        _isScanning = false;
      });
    } else {
      final itemsToSearch = _getFilteredItems();
      if (itemsToSearch.isEmpty) {
        _showToast(context.sRead.noItemsToSearch);
        return;
      }
      
      final tags = <String>[];
      for (var item in itemsToSearch) {
        if (item.epc.isNotEmpty) tags.add(item.epc);
        if (item.rfid.isNotEmpty) tags.add(item.rfid);
        if (item.itemCode.isNotEmpty) tags.add(item.itemCode);
        if (item.tid.isNotEmpty) tags.add(item.tid);
        if (item.hex.isNotEmpty) tags.add(item.hex);
      }
      
      final cleanTags = tags.map((t) => t.trim().toUpperCase()).where((t) => t.isNotEmpty).toSet().toList();
      if (cleanTags.isEmpty) {
        _showToast(context.sRead.noSearchableIdentifiersFound);
        return;
      }
      
      await _rfidService.setSearchTags(cleanTags);
      _rebuildTagIndex();
      _lastSearchUiUpdateUs = 0;
      final started = await _rfidService.startScanning(
        power: _selectedPower,
      );
      if (started) {
        setState(() {
          _isScanning = true;
        });
      }
    }
  }

  void _onQueryChanged(String val) {
    setState(() {
      _searchQuery = val;
    });

    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    
    if (_listKey == 'normal') {
      _debounceTimer = Timer(const Duration(milliseconds: 200), () {
        _performSearch(val);
      });
    }
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchItems.clear();
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<SearchItem> results = [];
      
      if (_selectedSearchType == 'LabelStock') {
        final dbService = Provider.of<DbService>(context, listen: false);
        final items = await dbService.searchItemsExact(trimmed);

        for (var item in items) {
          results.add(_searchItemFromBulk(item));
        }
      } else if (_selectedSearchType == 'Order') {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final dashboardViewModel = Provider.of<DashboardViewModel>(context, listen: false);
        final clientCode = dashboardViewModel.employee?.clientCode ?? '';
        if (clientCode.isNotEmpty) {
          final orders = await apiService.searchOrdersByRfid(clientCode, trimmed);
          for (var order in orders) {
            final items = order['CustomOrderItem'] as List? ?? [];
            final isOrderLevelMatch =
                order['CustomOrderId']?.toString() == trimmed ||
                order['Id']?.toString() == trimmed ||
                (order['OrderNo'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                (order['RfidCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                (order['TidNumber'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase();

            final matchedItems = isOrderLevelMatch
                ? items
                : items.where((item) =>
                    (item['RFIDCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                    (item['ItemCode'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase() ||
                    (item['TIDNumber'] as String? ?? '').trim().toLowerCase() == trimmed.toLowerCase()
                  ).toList();

            for (var item in matchedItems) {
              final rfid = (item['RFIDCode'] as String? ?? '').trim();
              final tid = (item['TIDNumber'] as String? ?? '').trim();
              final code = (item['ItemCode'] as String? ?? '').trim();
              final prodName = (item['ProductName'] as String? ?? '').trim();
              
              final parentRfid = (order['RfidCode'] as String? ?? '').trim();
              final parentTid = (order['TidNumber'] as String? ?? '').trim();
              
              final finalRfid = rfid.isNotEmpty ? rfid : parentRfid;
              final finalTid = tid.isNotEmpty ? tid : parentTid;
              
              final searchKey = finalTid.isNotEmpty
                  ? finalTid
                  : (finalRfid.isNotEmpty ? finalRfid : code);

              results.add(SearchItem(
                epc: searchKey,
                itemCode: code,
                productName: prodName,
                rfid: finalRfid,
                tid: finalTid,
              ));
            }
          }
        }
      } else if (_selectedSearchType == 'Box') {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final dashboardViewModel = Provider.of<DashboardViewModel>(context, listen: false);
        final clientCode = dashboardViewModel.employee?.clientCode ?? '';
        if (clientCode.isNotEmpty) {
          final data = await apiService.getBoxDetailsByRfidCode(clientCode, trimmed);
          if (data != null && data['Success'] == true) {
            final boxes = data['Boxes'] as List? ?? [];
            final products = data['Products'] as List? ?? [];
            
            for (var entry in boxes) {
              final boxProducts = entry['Products'] as List? ?? [];
              for (var p in boxProducts) {
                final rfid = (p['RfidCode'] as String? ?? '').trim();
                final tid = (p['TidNumber'] as String? ?? '').trim();
                final hex = (p['HexCode'] as String? ?? '').trim();
                final code = (p['ItemCode'] as String? ?? '').trim();
                final prodName = (p['ProductName'] as String? ?? p['ProductTitle'] as String? ?? '').trim();
                
                final searchKey = tid.isNotEmpty ? tid : (hex.isNotEmpty ? hex : (rfid.isNotEmpty ? rfid : code));
                results.add(SearchItem(
                  epc: searchKey,
                  itemCode: code,
                  productName: prodName,
                  rfid: rfid,
                  tid: tid,
                  hex: hex,
                ));
              }
            }
            
            for (var p in products) {
              final rfid = (p['RfidCode'] as String? ?? '').trim();
              final tid = (p['TidNumber'] as String? ?? '').trim();
              final hex = (p['HexCode'] as String? ?? '').trim();
              final code = (p['ItemCode'] as String? ?? '').trim();
              final prodName = (p['ProductName'] as String? ?? p['ProductTitle'] as String? ?? '').trim();
              
              final searchKey = tid.isNotEmpty ? tid : (hex.isNotEmpty ? hex : (rfid.isNotEmpty ? rfid : code));
              results.add(SearchItem(
                epc: searchKey,
                itemCode: code,
                productName: prodName,
                rfid: rfid,
                tid: tid,
                hex: hex,
              ));
            }
          }
        }
      }

      setState(() {
        _searchItems = results;
        _rebuildTagIndex();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showToast(context.sRead.searchError(e));
    }
  }

  List<SearchItem> _getFilteredItems() {
    final query = _searchQuery.trim().toLowerCase();
    List<SearchItem> baseList;
    
    if (_listKey == 'unmatchedItems') {
      if (query.isNotEmpty) {
        baseList = _searchItems.where((item) {
          return item.itemCode.toLowerCase().contains(query) ||
              item.rfid.toLowerCase().contains(query) ||
              item.epc.toLowerCase().contains(query);
        }).toList();
      } else {
        baseList = List.from(_searchItems);
      }
    } else {
      baseList = List.from(_searchItems);
    }

    baseList.sort((a, b) {
      int cmp = b.proximityPercent.compareTo(a.proximityPercent);
      if (cmp != 0) return cmp;
      
      if (query.isNotEmpty) {
        final aExact = a.itemCode.toLowerCase() == query || a.rfid.toLowerCase() == query || a.epc.toLowerCase() == query;
        final bExact = b.itemCode.toLowerCase() == query || b.rfid.toLowerCase() == query || b.epc.toLowerCase() == query;
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;
      }
      return 0;
    });

    return baseList;
  }

  void _resetSearch() {
    _rfidService.stopScanning();
    _rfidService.clearSearchTags();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _isScanning = false;
      if (_listKey == 'normal') {
        _searchItems.clear();
      } else {
        // Reset proximity values in unmatched list
        _searchItems = _searchItems.map((i) => i.copyWith(rssi: '', proximityPercent: 0)).toList();
      }
    });
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isUnmatchedList = _listKey == 'unmatchedItems';
    final filteredItems = _getFilteredItems();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              isUnmatchedList ? s.searchUnmatched : s.searchAllItems,
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
            ),
            actions: [
              DropdownButton<int>(
                value: _selectedPower,
                dropdownColor: const Color(0xFF5231A7),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                underline: Container(),
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedPower = newValue);
                    _rfidService.setPower(newValue);
                    context.read<PrefService>().savePower(PrefService.keySearchCount, newValue);
                  }
                },
                items: [5, 10, 15, 20, 25, 30].map<DropdownMenuItem<int>>((int val) {
                  return DropdownMenuItem<int>(
                    value: val,
                    child: Text(s.powerLabel(val), style: GoogleFonts.poppins(color: Colors.white)),
                  );
                }).toList(),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Dropdown for search type (Normal mode only)
          if (!isUnmatchedList)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, top: 12.0, bottom: 4.0),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedSearchType,
                decoration: InputDecoration(
                  labelText: s.searchType,
                  labelStyle: GoogleFonts.poppins(fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'LabelStock', child: Text(s.labelStock, style: GoogleFonts.poppins(fontSize: 13))),
                  DropdownMenuItem(value: 'Order', child: Text(s.order, style: GoogleFonts.poppins(fontSize: 13))),
                  DropdownMenuItem(value: 'Box', child: Text(s.box, style: GoogleFonts.poppins(fontSize: 13))),
                ],
                onChanged: _isScanning
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() {
                            _selectedSearchType = val;
                            _searchQuery = '';
                            _searchController.clear();
                            _searchItems.clear();
                          });
                        }
                      },
              ),
            ),

          // Search Field
          Padding(
            padding: EdgeInsets.only(
              left: 12.0,
              right: 12.0,
              top: isUnmatchedList ? 12.0 : 4.0,
              bottom: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              enabled: !_isScanning,
              decoration: InputDecoration(
                labelText: isUnmatchedList
                    ? s.enterRfidItemcode
                    : (_selectedSearchType == 'Order'
                        ? s.enterRfidCustomOrderId
                        : (_selectedSearchType == 'Box'
                            ? s.enterRfidBoxRfid
                            : s.enterRfidItemcode)),
                labelStyle: GoogleFonts.poppins(fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _onQueryChanged,
              style: GoogleFonts.poppins(fontSize: 13),
            ),
          ),

          // Table Header
          Container(
            color: const Color(0xFF3B363E),
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _selectedSearchType == 'Order' && !isUnmatchedList
                  ? [
                      _buildHeaderCell(s.headerSno, 1),
                      _buildHeaderCell(s.lblRfid, 2),
                      _buildHeaderCell(s.progress, 3),
                      _buildHeaderCell(s.percent, 1),
                    ]
                  : [
                      _buildHeaderCell(s.headerSno, 1),
                      _buildHeaderCell(s.lblRfid, 2),
                      _buildHeaderCell(s.itemcode, 2),
                      _buildHeaderCell(s.progress, 3),
                      _buildHeaderCell(s.percent, 1),
                    ],
            ),
          ),

          // Results list or empty placeholder
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredItems.isEmpty
                    ? Center(
                        child: Text(
                          isUnmatchedList && _searchItems.isEmpty
                              ? s.noUnmatchedItemsToSearch
                              : s.typeRfidItemcodeToSearch,
                          style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                            ),
                            child: Row(
                              children: _selectedSearchType == 'Order' && !isUnmatchedList
                                  ? [
                                      _buildDataCell('${index + 1}', 1),
                                      _buildDataCell(item.rfid, 2),
                                      _buildProgressCell(item.proximityPercent, 3),
                                      _buildDataCell('${item.proximityPercent}%', 1),
                                    ]
                                  : [
                                      _buildDataCell('${index + 1}', 1),
                                      _buildDataCell(item.rfid, 2),
                                      _buildDataCell(item.itemCode, 2),
                                      _buildProgressCell(item.proximityPercent, 3),
                                      _buildDataCell('${item.proximityPercent}%', 1),
                                    ],
                            ),
                          );
                        },
                      ),
          ),

          // Bottom Navigation Bar
          ScanBottomBar(
            onSave: () {},
            onList: () {},
            onScan: _toggleScanning,
            onGscan: () {},
            onReset: _resetSearch,
            isScanning: _isScanning,
            isScreen: true,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDataCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text.isNotEmpty ? text : '-',
        style: GoogleFonts.poppins(fontSize: 11, color: Colors.black87),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildProgressCell(int proximity, int flex) {
    final value = proximity / 100.0;
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(getColorByPercentage(proximity)),
          ),
        ),
      ),
    );
  }
}
