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
import '../viewmodels/delivery_challan_view_model.dart';
import 'widgets/scan_bottom_bar.dart';
import 'widgets/delivery_challan_pdf.dart';
import 'widgets/delivery_challan_fields_dialog.dart';
import 'widgets/add_customer_dialog.dart';
import '../utils/tag_scan_batcher.dart';
import 'widgets/challan_details_dialog.dart';

class DeliveryChallanScreen extends StatefulWidget {
  const DeliveryChallanScreen({super.key});

  @override
  State<DeliveryChallanScreen> createState() => _DeliveryChallanScreenState();
}

class _DeliveryChallanScreenState extends State<DeliveryChallanScreen> {
  final RfidService _rfidService = RfidService();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _customerSearchCtrl = TextEditingController();
  final TextEditingController _itemCodeCtrl = TextEditingController();
  final FocusNode _itemCodeFocus = FocusNode();
  StreamSubscription? _rfidSubscription;
  StreamSubscription? _triggerSubscription;
  bool _showSuggestions = false;
  bool _showItemSuggestions = false;
  int _power = 30; // Default dBm reader power
  bool _isSingleScan = false;

  List<BulkItem> _itemSuggestions = [];
  late final TagScanBatcher _tagBatcher;
  Timer? _suggestTimer;

  // Scroll synchronization controllers for locked spreadsheet view
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
        context.read<DeliveryChallanViewModel>().processScannedTags(tags);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<DeliveryChallanViewModel>();
      vm.loadMasterData();
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
        _toggleGscan(context.read<DeliveryChallanViewModel>());
      }
    });

    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      if (mounted) {
        _isSingleScan = false;
        _toggleGscan(context.read<DeliveryChallanViewModel>());
      }
    });

    // Vertical scrolls synchronization
    _leftVScroll.addListener(() {
      if (_activeVScrollController == _leftVScroll) {
        if (_dataVScroll.hasClients) _dataVScroll.jumpTo(_leftVScroll.offset);
        if (_actionVScroll.hasClients) _actionVScroll.jumpTo(_leftVScroll.offset);
      }
    });
    _dataVScroll.addListener(() {
      if (_activeVScrollController == _dataVScroll) {
        if (_leftVScroll.hasClients) _leftVScroll.jumpTo(_dataVScroll.offset);
        if (_actionVScroll.hasClients) _actionVScroll.jumpTo(_dataVScroll.offset);
      }
    });
    _actionVScroll.addListener(() {
      if (_activeVScrollController == _actionVScroll) {
        if (_leftVScroll.hasClients) _leftVScroll.jumpTo(_actionVScroll.offset);
        if (_dataVScroll.hasClients) _dataVScroll.jumpTo(_actionVScroll.offset);
      }
    });
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

  void _toggleGscan(DeliveryChallanViewModel vm) async {
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


  Widget _gradientBorder({
    required Widget child,
    double radius = 10,
    Color fill = Colors.white,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5231A7), Color(0xFFD32940)],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius - 1),
        ),
        child: child,
      ),
    );
  }

  void _showInvoiceFieldsDialog(DeliveryChallanViewModel vm) {
    showDialog(
      context: context,
      builder: (context) {
        return DeliveryChallanFieldsDialog(
          branches: vm.branches,
          customers: vm.customers,
          initialBranchId: vm.selectedBranchId,
          initialBranchName: vm.selectedBranchName,
          initialDate: vm.selectedDate,
          initialSalesman: vm.selectedSalesmanName,
          onConfirm: (fields) {
            vm.setChallanFields(
              branchName: fields['branchName'],
              branchId: fields['branchId'],
              date: fields['date'],
              salesmanName: fields['salesmanName'],
            );
          },
        );
      },
    );
  }

  // Rich per-item editor matching the Kotlin Delivery Challan dialog.
  void _showItemEditDialog(int index, ChallanDetailsModel item, DeliveryChallanViewModel vm) {
    showDialog(
      context: context,
      builder: (context) => ChallanDetailsDialog(
        item: item,
        branches: vm.branches,
        dailyRates: vm.dailyRates,
        onSave: (updated) => vm.updateProductItemDetails(index, updated),
      ),
    );
  }

  // Add a customer profile, mirroring the Order screen flow.
  void _showAddCustomerDialog() {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) {
        return AddCustomerDialog(
          title: s.customerProfile,
          onSave: (req) async {
            final vm = context.read<DeliveryChallanViewModel>();
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
              'Id': 0
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

  void _confirmDeleteChallanItem(DeliveryChallanViewModel vm, int idx) {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(s.deleteItem, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text(s.confirmDeleteChallanItem, style: GoogleFonts.poppins()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel, style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                vm.removeProductItem(idx);
                Navigator.pop(context);
              },
              child: Text(s.delete, style: GoogleFonts.poppins(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Widget _tableCell(String text,
      {Color color = Colors.black54, FontWeight weight = FontWeight.normal, double width = 80}) {
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

  Widget _buildCustomerInput(DeliveryChallanViewModel vm) {
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
                        onChanged: (v) => setState(() => _showSuggestions = true),
                      ),
                    ),
                    if (_customerSearchCtrl.text.isEmpty)
                      InkWell(
                        onTap: _showAddCustomerDialog,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.add, color: Colors.grey, size: 18),
                        ),
                      )
                    else
                      InkWell(
                        onTap: () {
                          _customerSearchCtrl.clear();
                          vm.setSelectedCustomer(null);
                          setState(() => _showSuggestions = false);
                          _focusNode.unfocus();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.clear, color: Colors.grey, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_showSuggestions && visible.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(minHeight: 0, maxHeight: 260),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final c = visible[i];
                    final name = '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim();
                    return ListTile(
                      hoverColor: Colors.grey[100],
                      title: Text(name.isEmpty ? s.unknown : name,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(s.mobileGstLabel(c.mobile ?? '-', c.gstNo ?? '-'),
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
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
            ),
        ],
      ),
    );
  }

  // RFID/Itemcode input with auto-suggestion dropdown + Challan Fields button
  // (mirrors the Order screen item entry).
  Widget _buildItemCodeRow(DeliveryChallanViewModel vm) {
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
                  onTap: () => _showInvoiceFieldsDialog(vm),
                  child: _gradientBorder(
                    radius: 8,
                    child: SizedBox(
                      height: 35,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(s.challanFields,
                              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
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
                      child: Text(display,
                          style: GoogleFonts.poppins(fontSize: 13, color: Colors.black)),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductTable(DeliveryChallanViewModel vm) {
    final s = context.s;
    final items = vm.productList;

    // Column widths
    const double colName = 100;
    const double colItemcode = 80;
    const double colGwt = 70;
    const double colNwt = 70;
    const double colRate = 80;
    const double colMaking = 85;
    const double colStone = 80;
    const double colDiamond = 85;
    const double colAmount = 90;
    const double colFine = 70;
    const double colRfid = 95;

    const double scrollableWidth = colName +
        colItemcode +
        colGwt +
        colNwt +
        colRate +
        colMaking +
        colStone +
        colDiamond +
        colAmount +
        colFine +
        colRfid;

    // Totals calculations
    double sum(double Function(ChallanDetailsModel) sel) =>
        items.fold(0.0, (s, it) => s + sel(it));

    final totalGross = sum((it) => double.tryParse(it.grossWt) ?? 0.0);
    final totalNet = sum((it) => double.tryParse(it.netWt) ?? 0.0);
    final totalStone = sum((it) => double.tryParse(it.stoneAmount) ?? 0.0);
    final totalDiamond = sum((it) => double.tryParse(it.totalDiamondAmount) ?? 0.0);
    final totalAmt = sum((it) => double.tryParse(it.amount) ?? 0.0);
    final totalFine = sum((it) => double.tryParse(it.fineWastageWt) ?? 0.0);

    return Container(
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Locked Column (S.No)
          SizedBox(
            width: 45,
            child: Column(
              children: [
                // Header
                Container(
                  height: 40,
                  color: const Color(0xFF2E2E2E),
                  alignment: Alignment.center,
                  child: Text(
                    s.headerSno,
                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                // Rows
                Expanded(
                  child: items.isEmpty
                      ? const SizedBox.shrink()
                      : Listener(
                          onPointerDown: (_) => _activeVScrollController = _leftVScroll,
                          child: ListView.builder(
                            controller: _leftVScroll,
                            padding: EdgeInsets.zero,
                            itemCount: items.length,
                            itemBuilder: (context, idx) {
                              return Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: idx % 2 == 0 ? const Color(0xFFF4F4F4) : Colors.white,
                                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${idx + 1}',
                                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.black87),
                                ),
                              );
                            },
                          ),
                        ),
                ),
                // Footer
                Container(
                  height: 34,
                  color: const Color(0xFF2E2E2E),
                  alignment: Alignment.center,
                  child: Text(
                    s.total,
                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Middle Scrollable Area
          Expanded(
            child: SingleChildScrollView(
              controller: _tableHScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: scrollableWidth,
                child: Column(
                  children: [
                    // Header Row
                    Container(
                      height: 40,
                      color: const Color(0xFF2E2E2E),
                      child: Row(
                        children: [
                          _tableCell(s.itemName, color: Colors.white, weight: FontWeight.bold, width: colName),
                          _tableCell(s.itemCode, color: Colors.white, weight: FontWeight.bold, width: colItemcode),
                          _tableCell(s.grossWt, color: Colors.white, weight: FontWeight.bold, width: colGwt),
                          _tableCell(s.colNetWt, color: Colors.white, weight: FontWeight.bold, width: colNwt),
                          _tableCell(s.rate, color: Colors.white, weight: FontWeight.bold, width: colRate),
                          _tableCell(s.makingChg, color: Colors.white, weight: FontWeight.bold, width: colMaking),
                          _tableCell(s.colStoneAmt, color: Colors.white, weight: FontWeight.bold, width: colStone),
                          _tableCell(s.colDiamondAmt, color: Colors.white, weight: FontWeight.bold, width: colDiamond),
                          _tableCell(s.amount, color: Colors.white, weight: FontWeight.bold, width: colAmount),
                          _tableCell(s.fineWt, color: Colors.white, weight: FontWeight.bold, width: colFine),
                          _tableCell(s.lblRfid, color: Colors.white, weight: FontWeight.bold, width: colRfid),
                        ],
                      ),
                    ),
                    // Data Rows
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                              child: Text(
                                s.noItemsAdded,
                                style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13),
                              ),
                            )
                          : Listener(
                              onPointerDown: (_) => _activeVScrollController = _dataVScroll,
                              child: ListView.builder(
                                controller: _dataVScroll,
                                padding: EdgeInsets.zero,
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
                                        _tableCell(item.productName, width: colName, weight: FontWeight.bold, color: Colors.black87),
                                        _tableCell(item.itemCode, width: colItemcode),
                                        _tableCell(item.grossWt, width: colGwt),
                                        _tableCell(item.netWt, width: colNwt),
                                        _tableCell('₹${item.metalRate}', width: colRate),
                                        _tableCell('₹${item.makingCharg}', width: colMaking),
                                        _tableCell('₹${item.stoneAmount}', width: colStone),
                                        _tableCell('₹${item.totalDiamondAmount}', width: colDiamond),
                                        _tableCell('₹${item.amount}', width: colAmount, color: const Color(0xFF1565C0), weight: FontWeight.bold),
                                        _tableCell(item.fineWastageWt, width: colFine),
                                        _tableCell(item.rfidCode, width: colRfid),
                                      ],
                                    ),
                                  ),
                                  );
                                },
                              ),
                            ),
                    ),
                    // Footer Row
                    Container(
                      height: 34,
                      color: const Color(0xFF2E2E2E),
                      child: Row(
                        children: [
                          _tableCell('', width: colName),
                          _tableCell('${items.length} ${s.headerPcs}', color: Colors.white, weight: FontWeight.bold, width: colItemcode),
                          _tableCell(totalGross.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colGwt),
                          _tableCell(totalNet.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colNwt),
                          _tableCell('', width: colRate),
                          _tableCell('', width: colMaking),
                          _tableCell('₹${totalStone.toStringAsFixed(2)}', color: Colors.white, weight: FontWeight.bold, width: colStone),
                          _tableCell('₹${totalDiamond.toStringAsFixed(2)}', color: Colors.white, weight: FontWeight.bold, width: colDiamond),
                          _tableCell('₹${totalAmt.toStringAsFixed(2)}', color: Colors.white, weight: FontWeight.bold, width: colAmount),
                          _tableCell(totalFine.toStringAsFixed(3), color: Colors.white, weight: FontWeight.bold, width: colFine),
                          _tableCell('', width: colRfid),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Right Locked Column (Action)
          SizedBox(
            width: 75,
            child: Column(
              children: [
                // Header
                Container(
                  height: 40,
                  color: const Color(0xFF2E2E2E),
                  alignment: Alignment.center,
                  child: Text(
                    s.action,
                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                // Rows
                Expanded(
                  child: items.isEmpty
                      ? const SizedBox.shrink()
                      : Listener(
                          onPointerDown: (_) => _activeVScrollController = _actionVScroll,
                          child: ListView.builder(
                            controller: _actionVScroll,
                            padding: EdgeInsets.zero,
                            itemCount: items.length,
                            itemBuilder: (context, idx) {
                              return Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: idx % 2 == 0 ? const Color(0xFFF4F4F4) : Colors.white,
                                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _confirmDeleteChallanItem(vm, idx),
                                      child: const Icon(Icons.delete, color: Colors.red, size: 18),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
                // Footer
                Container(
                  height: 34,
                  color: const Color(0xFF2E2E2E),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DeliveryChallanViewModel>();
    final s = context.s;
    final isEditMode = vm.selectedChallan != null;

    return Scaffold(
      backgroundColor: Colors.white,
      // Keep the scan bottom bar pinned; the keyboard overlays the body
      // instead of pushing the bar up.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            vm.clearChallan();
            Navigator.pop(context);
          },
        ),
        title: Text(
          isEditMode ? s.editDeliveryChallan : s.createDeliveryChallan,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // White counter box showing selected power (1-30), like the Kotlin app.
          PopupMenuButton<int>(
            tooltip: s.rfidPower,
            color: Colors.white,
            constraints: const BoxConstraints(maxHeight: 320, minWidth: 60),
            onSelected: (val) {
              setState(() => _power = val);
              _rfidService.setPower(val);
            },
            itemBuilder: (context) => List.generate(30, (i) => i + 1)
                .map((p) => PopupMenuItem<int>(
                      value: p,
                      height: 36,
                      child: Text('$p', style: GoogleFonts.poppins(fontSize: 14)),
                    ))
                .toList(),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$_power',
                style: GoogleFonts.poppins(
                  color: Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
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

            // Spreadsheet of Active Products inside Challan
            Expanded(
              child: _buildProductTable(vm),
            ),

            // Bottom GST & Total Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: vm.isGstChecked,
                          activeColor: const Color(0xFF5231A7),
                          onChanged: (val) {
                            if (val != null) vm.setGstChecked(val);
                          },
                        ),
                        Text(
                          s.gstLabel,
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text('${s.totalAmount}: ', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          '₹${vm.getFinalTotal().toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF5231A7), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ScanBottomBar(
        // Center "Scan" button shows Stop only for a single-tag scan; the
        // "Gscan" button shows Stop for a continuous (bulk) scan.
        isScanning: _rfidService.isScanning && _isSingleScan,
        isBulkScanning: _rfidService.isScanning && !_isSingleScan,
        isEditMode: isEditMode,
        onSave: () async {
          final s = context.sRead;
          try {
            final res = isEditMode
                ? await vm.updateDeliveryChallan()
                : await vm.submitDeliveryChallan();

            if (res != null && res != false) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(isEditMode ? s.challanUpdatedSuccessfully : s.challanSavedSuccessfully)),
              );

              // Extract response challan model for print preview
              final savedChallan = isEditMode
                  ? vm.selectedChallan!
                  : DeliveryChallanModel.fromJson(res as Map<String, dynamic>);

              await printDeliveryChallanPdf(
                context: context,
                challan: savedChallan,
                orgName: '',
              );

              vm.clearChallan();
              _customerSearchCtrl.clear();
              Navigator.pop(context); // Go back to list
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(vm.errorMessage ?? s.failedToSubmitChallan)),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
          }
        },
        onList: () {
          vm.clearChallan();
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
          vm.clearChallan();
          _customerSearchCtrl.clear();
        },
      ),
    );
  }
}
