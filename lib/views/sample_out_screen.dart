import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../models/delivery_challan.dart';
import '../models/bulk_item.dart';
import '../services/rfid_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../viewmodels/sample_out_view_model.dart';
import 'widgets/scan_bottom_bar.dart';
import 'widgets/sample_out_fields_dialog.dart';
import 'widgets/add_customer_dialog.dart';
import 'widgets/challan_details_dialog.dart';
import '../utils/tag_scan_batcher.dart';
import 'widgets/sample_print_pdf.dart';

class SampleOutScreen extends StatefulWidget {
  const SampleOutScreen({super.key});

  @override
  State<SampleOutScreen> createState() => _SampleOutScreenState();
}

class _SampleOutScreenState extends State<SampleOutScreen> {
  final RfidService _rfidService = RfidService();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _customerSearchCtrl = TextEditingController();
  final TextEditingController _itemCodeCtrl = TextEditingController();
  final FocusNode _itemCodeFocus = FocusNode();
  StreamSubscription? _rfidSubscription;
  StreamSubscription? _triggerSubscription;
  bool _showSuggestions = false;
  bool _showItemSuggestions = false;
  int _power = 30;
  bool _isSingleScan = false;
  List<BulkItem> _itemSuggestions = [];
  late final TagScanBatcher _tagBatcher;
  Timer? _suggestTimer;

  final ScrollController _leftVScroll = ScrollController();
  final ScrollController _dataVScroll = ScrollController();
  final ScrollController _actionVScroll = ScrollController();
  final ScrollController _tableHScroll = ScrollController();
  ScrollController? _activeVScrollController;

  @override
  void initState() {
    super.initState();
    _tagBatcher = TagScanBatcher(
      onFlush: (tags) {
        if (!mounted || !_rfidService.isScanning) return;
        context.read<SampleOutViewModel>().processScannedTags(tags);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<SampleOutViewModel>();
      if (vm.customers.isEmpty) {
        await vm.loadMasterData();
      }
      if (vm.selectedCustomer != null) {
        _customerSearchCtrl.text =
            '${vm.selectedCustomer!.firstName ?? ''} ${vm.selectedCustomer!.lastName ?? ''}'.trim();
      }
    });

    _rfidSubscription = _rfidService.tagsStream.listen((epc) {
      if (!_rfidService.isScanning) return;
      _tagBatcher.add(epc);
      if (_isSingleScan) {
        _tagBatcher.flushNow();
        _isSingleScan = false;
        _toggleGscan(context.read<SampleOutViewModel>());
      }
    });

    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      if (mounted) {
        _isSingleScan = false;
        _toggleGscan(context.read<SampleOutViewModel>());
      }
    });

    _leftVScroll.addListener(_syncLeft);
    _dataVScroll.addListener(_syncData);
    _actionVScroll.addListener(_syncAction);
  }

  void _syncLeft() {
    if (_activeVScrollController == _leftVScroll) {
      if (_dataVScroll.hasClients) _dataVScroll.jumpTo(_leftVScroll.offset);
      if (_actionVScroll.hasClients) _actionVScroll.jumpTo(_leftVScroll.offset);
    }
  }

  void _syncData() {
    if (_activeVScrollController == _dataVScroll) {
      if (_leftVScroll.hasClients) _leftVScroll.jumpTo(_dataVScroll.offset);
      if (_actionVScroll.hasClients) _actionVScroll.jumpTo(_dataVScroll.offset);
    }
  }

  void _syncAction() {
    if (_activeVScrollController == _actionVScroll) {
      if (_leftVScroll.hasClients) _leftVScroll.jumpTo(_actionVScroll.offset);
      if (_dataVScroll.hasClients) _dataVScroll.jumpTo(_actionVScroll.offset);
    }
  }

  @override
  void dispose() {
    _tagBatcher.dispose();
    _suggestTimer?.cancel();
    _rfidSubscription?.cancel();
    _triggerSubscription?.cancel();
    _rfidService.stopScanning();
    _customerSearchCtrl.dispose();
    _itemCodeCtrl.dispose();
    _itemCodeFocus.dispose();
    _focusNode.dispose();
    _leftVScroll.dispose();
    _dataVScroll.dispose();
    _actionVScroll.dispose();
    _tableHScroll.dispose();
    super.dispose();
  }

  void _toggleGscan(SampleOutViewModel vm) async {
    if (_rfidService.isScanning) {
      await _rfidService.stopScanning();
      if (mounted) setState(() {});
      return;
    }

    await _rfidService.prepareProductScanMatchSet(context.read<DbService>());
    final started = await _rfidService.startScanning(power: _power);
    if (mounted) setState(() {});
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.failedToStartRfidScanner)),
      );
    }
  }

  Widget _gradientBorder({required Widget child, double radius = 10, Color fill = Colors.white}) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(radius - 1)),
        child: child,
      ),
    );
  }

  void _showFieldsDialog(SampleOutViewModel vm) {
    showDialog(
      context: context,
      builder: (context) => SampleOutFieldsDialog(
        initialDate: vm.selectedDate,
        initialReturnDate: vm.returnDate,
        initialDescription: vm.description,
        onConfirm: (fields) {
          vm.setSampleOutFields(
            date: fields['date'] ?? '',
            returnDate: fields['returnDate'] ?? '',
            description: fields['description'] ?? '',
          );
        },
      ),
    );
  }

  void _showItemEditDialog(int index, ChallanDetailsModel item, SampleOutViewModel vm) {
    showDialog(
      context: context,
      builder: (context) => ChallanDetailsDialog(
        item: item,
        branches: const [],
        dailyRates: vm.dailyRates,
        onSave: (updated) => vm.updateProductItemDetails(index, updated),
      ),
    );
  }

  void _showAddCustomerDialog() {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) {
        return AddCustomerDialog(
          title: s.customerProfile,
          onSave: (req) async {
            final vm = context.read<SampleOutViewModel>();
            final cc = context.read<PrefService>().getEmployee()?.clientCode ?? '';
            final payload = {
              'FirstName': req['FirstName'],
              'MiddleName': '',
              'LastName': req['LastName'],
              'Email': req['Email'],
              'CustomerLoginId': req['Email'],
              'Password': '',
              'Gender': '',
              'CustomerSlabId': 0,
              'CreditPeriodId': 0,
              'RateOfInterestId': 0,
              'Mobile': req['Mobile'],
              'OnlineStatus': 'Active',
              'DateOfBirth': '',
              'AdvanceAmount': '0',
              'BalanceAmount': '0',
              'CurrAddStreet': req['PerAddStreet'],
              'Area': '',
              'PerAddTown': '',
              'City': req['City'],
              'CurrAddState': req['CurrAddState'],
              'CurrAddPincode': '',
              'PerAddStreet': '',
              'PerAddState': '',
              'PerAddPincode': '',
              'Country': req['Country'],
              'PerAddCountry': '',
              'AadharNo': '',
              'Discount': '0',
              'CreditPeriod': '0',
              'PanNo': req['PanNo'],
              'FineGold': '0',
              'FineSilver': '0',
              'GstNo': req['GstNo'],
              'ClientCode': cc,
              'VendorId': 0,
              'Remark': '',
              'AddToVendor': false,
              'Id': 0,
            };
            final success = await vm.addCustomerProfile(payload);
            if (!mounted) return;
            if (success) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.customerAddedSuccessfully)));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage ?? s.errorAddingCustomer)));
            }
          },
        );
      },
    );
  }

  void _confirmDeleteItem(SampleOutViewModel vm, int idx) {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(s.deleteItem, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(s.removeItemFromSampleOut, style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel, style: GoogleFonts.poppins(color: Colors.grey))),
          TextButton(
            onPressed: () {
              vm.removeProductItem(idx);
              Navigator.pop(context);
            },
            child: Text(s.delete, style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _tableCell(String text, {Color color = Colors.black54, FontWeight weight = FontWeight.normal, double width = 80}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(fontSize: 11, color: color, fontWeight: weight),
      ),
    );
  }

  Widget _buildCustomerInput(SampleOutViewModel vm) {
    final s = context.s;
    final query = _customerSearchCtrl.text.toLowerCase().trim();
    final visible = vm.customers.where((c) {
      final fullName = '${c.firstName ?? ''} ${c.lastName ?? ''}'.toLowerCase();
      return query.isEmpty || fullName.contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _gradientBorder(
            child: SizedBox(
              height: 35,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _customerSearchCtrl,
                        focusNode: _focusNode,
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: s.enterCustomerName,
                          hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                        ),
                        onChanged: (_) => setState(() => _showSuggestions = true),
                      ),
                    ),
                    if (_customerSearchCtrl.text.isEmpty)
                      InkWell(
                        onTap: _showAddCustomerDialog,
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add, color: Colors.grey, size: 18)),
                      )
                    else
                      InkWell(
                        onTap: () {
                          _customerSearchCtrl.clear();
                          vm.setSelectedCustomer(null);
                          setState(() => _showSuggestions = false);
                          _focusNode.unfocus();
                        },
                        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.clear, color: Colors.grey, size: 18)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_showSuggestions && visible.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final c = visible[i];
                  final name = '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim();
                  return ListTile(
                    title: Text(name.isEmpty ? s.unknown : name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(s.mobileGstLabel(c.mobile ?? '-', c.gstNo ?? '-'), style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
                    onTap: () {
                      _customerSearchCtrl.text = name;
                      vm.setSelectedCustomer(c);
                      setState(() => _showSuggestions = false);
                      _focusNode.unfocus();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemCodeRow(SampleOutViewModel vm) {
    final s = context.s;
    final suggestions = _itemSuggestions;

    Future<void> addByCode(String code) async {
      final error = await vm.addProductByCodeOrRfid(code);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      } else {
        _itemCodeCtrl.clear();
        setState(() => _showItemSuggestions = false);
        _itemCodeFocus.unfocus();
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 11,
                child: _gradientBorder(
                  child: SizedBox(
                    height: 35,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _itemCodeCtrl,
                              focusNode: _itemCodeFocus,
                              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: s.enterRfidItemcode,
                                hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                              ),
                              onChanged: (v) {
                                _suggestTimer?.cancel();
                                if (v.trim().isEmpty) {
                                  setState(() {
                                    _itemSuggestions = [];
                                    _showItemSuggestions = false;
                                  });
                                  return;
                                }
                                _suggestTimer = Timer(const Duration(milliseconds: 250), () async {
                                  final results = await context
                                      .read<DbService>()
                                      .searchBulkItemsByCodePrefix(v, limit: 100);
                                  if (!mounted) return;
                                  setState(() {
                                    _itemSuggestions = results;
                                    _showItemSuggestions = results.isNotEmpty;
                                  });
                                });
                              },
                              onSubmitted: addByCode,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              if (_itemCodeCtrl.text.isNotEmpty) {
                                _itemCodeCtrl.clear();
                                setState(() => _showItemSuggestions = false);
                              } else {
                                addByCode(_itemCodeCtrl.text);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                _itemCodeCtrl.text.isNotEmpty ? Icons.clear : Icons.qr_code_scanner,
                                color: Colors.grey,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 8,
                child: GestureDetector(
                  onTap: () => _showFieldsDialog(vm),
                  child: _gradientBorder(
                    radius: 8,
                    child: SizedBox(
                      height: 35,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(s.sampleOutFields, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                          const SizedBox(width: 4),
                          const Icon(Icons.tune, size: 20, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showItemSuggestions && suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 3))],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: suggestions.length,
                itemBuilder: (context, i) {
                  final b = suggestions[i];
                  final display = b.itemCode.isNotEmpty ? b.itemCode : (b.rfid.isNotEmpty ? b.rfid : b.itemCode);
                  return InkWell(
                    onTap: () => addByCode(display),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(display, style: GoogleFonts.poppins(fontSize: 13, color: Colors.black)),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductTable(SampleOutViewModel vm) {
    final s = context.s;
    final items = vm.productList;

    const colItemcode = 90.0;
    const colTWt = 60.0;
    const colGwt = 60.0;
    const colSwt = 60.0;
    const colDwt = 60.0;
    const colNwt = 60.0;
    const colFwWt = 70.0;
    const colQty = 50.0;
    const colPcs = 50.0;

    const scrollableWidth = colItemcode + colTWt + colGwt + colSwt + colDwt + colNwt + colFwWt + colQty + colPcs;

    double sum(String Function(ChallanDetailsModel) sel) =>
        items.fold(0.0, (s, it) => s + (double.tryParse(sel(it)) ?? 0.0));

    final totalTWt = sum((it) => it.totalWt);
    final totalGross = sum((it) => it.grossWt);
    final totalStone = sum((it) => it.totalStoneWeight.isNotEmpty ? it.totalStoneWeight : it.stoneAmt);
    final totalDiamond = sum((it) => it.diamondWt.isNotEmpty ? it.diamondWt : it.totalDiamondWeight);
    final totalNet = sum((it) => it.netWt);
    final totalFine = sum((it) => it.fineWastageWt);
    final totalQty = items.fold(0, (s, it) => s + (it.qty <= 0 ? 1 : it.qty));
    final totalPcs = items.fold(0, (s, it) => s + it.pcs);

    return Container(
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 45,
            child: Column(
              children: [
                Container(
                  height: 40,
                  color: const Color(0xFF2E2E2E),
                  alignment: Alignment.center,
                  child: Text(s.headerSno, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const SizedBox.shrink()
                      : Listener(
                          onPointerDown: (_) => _activeVScrollController = _leftVScroll,
                          child: ListView.builder(
                            controller: _leftVScroll,
                            itemCount: items.length,
                            itemBuilder: (context, idx) => Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: idx % 2 == 0 ? const Color(0xFFF4F4F4) : Colors.white,
                                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                              ),
                              alignment: Alignment.center,
                              child: Text('${idx + 1}', style: GoogleFonts.poppins(fontSize: 11)),
                            ),
                          ),
                        ),
                ),
                Container(
                  height: 34,
                  color: const Color(0xFF2E2E2E),
                  alignment: Alignment.center,
                  child: Text(s.total, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _tableHScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: scrollableWidth,
                child: Column(
                  children: [
                    Container(
                      height: 40,
                      color: const Color(0xFF2E2E2E),
                      child: Row(
                        children: [
                          _tableCell(s.itemcode, color: Colors.white, weight: FontWeight.bold, width: colItemcode),
                          _tableCell(s.headerTWt, color: Colors.white, weight: FontWeight.bold, width: colTWt),
                          _tableCell(s.headerGwt, color: Colors.white, weight: FontWeight.bold, width: colGwt),
                          _tableCell(s.headerSwt, color: Colors.white, weight: FontWeight.bold, width: colSwt),
                          _tableCell(s.headerDwt, color: Colors.white, weight: FontWeight.bold, width: colDwt),
                          _tableCell(s.headerNwt, color: Colors.white, weight: FontWeight.bold, width: colNwt),
                          _tableCell(s.headerFwWt, color: Colors.white, weight: FontWeight.bold, width: colFwWt),
                          _tableCell(s.headerQty, color: Colors.white, weight: FontWeight.bold, width: colQty),
                          _tableCell(s.headerPcs, color: Colors.white, weight: FontWeight.bold, width: colPcs),
                        ],
                      ),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? Center(child: Text(s.noItemsAdded, style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13)))
                          : Listener(
                              onPointerDown: (_) => _activeVScrollController = _dataVScroll,
                              child: ListView.builder(
                                controller: _dataVScroll,
                                itemCount: items.length,
                                itemBuilder: (context, idx) {
                                  final item = items[idx];
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _showItemEditDialog(idx, item, vm),
                                    child: Container(
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: idx % 2 == 0 ? const Color(0xFFF4F4F4) : Colors.white,
                                        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                      ),
                                      child: Row(
                                        children: [
                                          _tableCell(item.itemCode, width: colItemcode, weight: FontWeight.bold, color: Colors.black87),
                                          _tableCell(item.totalWt, width: colTWt),
                                          _tableCell(item.grossWt, width: colGwt),
                                          _tableCell(item.totalStoneWeight.isNotEmpty ? item.totalStoneWeight : item.stoneAmt, width: colSwt),
                                          _tableCell(item.diamondWt.isNotEmpty ? item.diamondWt : item.totalDiamondWeight, width: colDwt),
                                          _tableCell(item.netWt, width: colNwt),
                                          _tableCell(item.fineWastageWt, width: colFwWt),
                                          _tableCell('${item.qty <= 0 ? 1 : item.qty}', width: colQty),
                                          _tableCell('${item.pcs}', width: colPcs),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                    Container(
                      height: 34,
                      color: const Color(0xFF2E2E2E),
                      child: Row(
                        children: [
                          _tableCell('${items.length} ${s.itemsLabel}', color: Colors.white, weight: FontWeight.bold, width: colItemcode),
                          _tableCell(totalTWt.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colTWt),
                          _tableCell(totalGross.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colGwt),
                          _tableCell(totalStone.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colSwt),
                          _tableCell(totalDiamond.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colDwt),
                          _tableCell(totalNet.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colNwt),
                          _tableCell(totalFine.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colFwWt),
                          _tableCell('$totalQty', color: Colors.white, weight: FontWeight.bold, width: colQty),
                          _tableCell('$totalPcs', color: Colors.white, weight: FontWeight.bold, width: colPcs),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 75,
            child: Column(
              children: [
                Container(
                  height: 40,
                  color: const Color(0xFF2E2E2E),
                  alignment: Alignment.center,
                  child: Text(s.action, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const SizedBox.shrink()
                      : Listener(
                          onPointerDown: (_) => _activeVScrollController = _actionVScroll,
                          child: ListView.builder(
                            controller: _actionVScroll,
                            itemCount: items.length,
                            itemBuilder: (context, idx) => Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: idx % 2 == 0 ? const Color(0xFFF4F4F4) : Colors.white,
                                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                              ),
                              child: Center(
                                child: GestureDetector(
                                  onTap: () => _confirmDeleteItem(vm, idx),
                                  child: const Icon(Icons.delete, color: Colors.red, size: 18),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                Container(height: 34, color: const Color(0xFF2E2E2E)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SampleOutViewModel>();
    final s = context.s;
    final isEditMode = vm.selectedSampleOut != null;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            vm.clearSampleOut();
            Navigator.pop(context);
          },
        ),
        title: Text(
          isEditMode ? s.editSampleOut : s.createSampleOut,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: s.rfidPower,
            color: Colors.white,
            constraints: const BoxConstraints(maxHeight: 320, minWidth: 60),
            onSelected: (val) {
              setState(() => _power = val);
              _rfidService.setPower(val);
            },
            itemBuilder: (context) => List.generate(30, (i) => i + 1)
                .map((p) => PopupMenuItem<int>(value: p, height: 36, child: Text(s.powerLabel(p), style: GoogleFonts.poppins(fontSize: 14))))
                .toList(),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Text('$_power', style: GoogleFonts.poppins(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 4),
            _buildCustomerInput(vm),
            const SizedBox(height: 4),
            _buildItemCodeRow(vm),
            const SizedBox(height: 4),
            Expanded(child: _buildProductTable(vm)),
          ],
        ),
      ),
      bottomNavigationBar: ScanBottomBar(
        isScanning: _rfidService.isScanning && _isSingleScan,
        isBulkScanning: _rfidService.isScanning && !_isSingleScan,
        isEditMode: isEditMode,
        onSave: () async {
          final sRead = context.sRead;
          try {
            final isEditMode = vm.selectedSampleOut != null;
            if (isEditMode) {
              final success = await vm.updateSampleOutRecord();
              if (!mounted) return;
              if (success) {
                final printData = vm.buildSampleOutPrintData(
                  sampleOutNo: vm.selectedSampleOut?.sampleOutNo ?? '',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(sRead.sampleOutUpdatedSuccessfully)),
                );
                await printSamplePrintPdf(context: context, data: printData);
                if (!mounted) return;
                vm.clearSampleOut();
                _customerSearchCtrl.clear();
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(vm.errorMessage ?? sRead.failedToUpdateSampleOut)),
                );
              }
              return;
            }

            final response = await vm.submitSampleOut();
            if (!mounted) return;
            if (response != null) {
              final sampleNo = response['SampleOutNo']?.toString() ?? '';
              final printData = vm.buildSampleOutPrintData(
                sampleOutNo: sampleNo,
                apiResponse: response,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(sRead.sampleOutSavedSuccessfully)),
              );
              await printSamplePrintPdf(context: context, data: printData);
              if (!mounted) return;
              vm.clearSampleOut();
              _customerSearchCtrl.clear();
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(vm.errorMessage ?? sRead.failedToSaveSampleOut)),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
          }
        },
        onList: () {
          vm.clearSampleOut();
          Navigator.pop(context);
        },
        onScan: () async {
          if (_rfidService.isScanning && !_isSingleScan) {
            await _rfidService.stopScanning();
            if (mounted) setState(() {});
            _isSingleScan = true;
            _toggleGscan(vm);
            return;
          }
          if (_rfidService.isScanning) {
            _isSingleScan = false;
            _toggleGscan(vm);
          } else {
            _isSingleScan = true;
            _toggleGscan(vm);
          }
        },
        onGscan: () async {
          if (_rfidService.isScanning && _isSingleScan) {
            await _rfidService.stopScanning();
            if (mounted) setState(() {});
            _isSingleScan = false;
            _toggleGscan(vm);
            return;
          }
          _isSingleScan = false;
          _toggleGscan(vm);
        },
        onReset: () {
          vm.clearSampleOut();
          _customerSearchCtrl.clear();
        },
      ),
    );
  }
}
