import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n_extension.dart';
import '../models/order_item.dart';
import '../models/bulk_item.dart';
import '../services/rfid_service.dart';
import '../services/pref_service.dart';
import '../services/db_service.dart';
import '../viewmodels/order_view_model.dart';
import 'widgets/scan_bottom_bar.dart';
import 'widgets/order_details_dialog.dart';
import 'widgets/order_pdf.dart';
import 'widgets/add_customer_dialog.dart';
import 'widgets/order_bulk_details_dialog.dart';
import '../utils/tag_scan_batcher.dart';

// Brand gradient used across the screen (matches Sparkle Kotlin app).
const _brandGradient = LinearGradient(
  colors: [Color(0xFF5231A7), Color(0xFFD32940)],
);

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final _customerSearchCtrl = TextEditingController();
  final _itemCodeCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _itemCodeFocus = FocusNode();

  final _rfidService = RfidService();
  StreamSubscription? _rfidSubscription;
  StreamSubscription? _triggerSubscription;

  // Synced scroll controllers for the custom product table.
  final _tableHScroll = ScrollController();
  final _dataVScroll = ScrollController();
  final _actionVScroll = ScrollController();
  bool _syncingVScroll = false;

  bool _showSuggestions = false;
  bool _showItemSuggestions = false;
  int _power = 10; // Reader power (1-30), shown in the top-bar counter box
  bool _isSingleScan = false;

  // Item-code suggestion results (SQL search — no full inventory in RAM).
  List<BulkItem> _itemSuggestions = [];
  late final TagScanBatcher _tagBatcher;
  Timer? _suggestTimer;

  @override
  void initState() {
    super.initState();
    _power = context.read<PrefService>().orderPower;
    _tagBatcher = TagScanBatcher(
      onFlush: (tags) {
        if (!mounted || !_rfidService.isScanning) return;
        context.read<OrderViewModel>().processScannedTags(tags);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final vm = context.read<OrderViewModel>();
        await vm.loadMasterData();
        if (vm.isEditMode && vm.selectedCustomer != null) {
          final c = vm.selectedCustomer!;
          setState(() {
            _customerSearchCtrl.text = '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim();
          });
        }
      }
    });

    // Listen to Gscan / RFID sweeps (batched for handheld performance)
    _rfidSubscription = _rfidService.tagsStream.listen((epc) {
      if (!_rfidService.isScanning) return;
      _tagBatcher.add(epc);
      if (_isSingleScan) {
        _tagBatcher.flushNow();
        _isSingleScan = false;
        _toggleGscan(context.read<OrderViewModel>());
      }
    });

    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      if (mounted) {
        _isSingleScan = false;
        _toggleGscan(context.read<OrderViewModel>());
      }
    });

    // Keep the data rows and the fixed action column vertically aligned.
    _dataVScroll.addListener(() => _syncVScroll(_dataVScroll, _actionVScroll));
    _actionVScroll.addListener(() => _syncVScroll(_actionVScroll, _dataVScroll));
  }

  void _syncVScroll(ScrollController from, ScrollController to) {
    if (_syncingVScroll) return;
    if (!to.hasClients) return;
    if (to.offset == from.offset) return;
    _syncingVScroll = true;
    to.jumpTo(from.offset.clamp(
      to.position.minScrollExtent,
      to.position.maxScrollExtent,
    ));
    _syncingVScroll = false;
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
    _focusNode.dispose();
    _itemCodeFocus.dispose();
    _tableHScroll.dispose();
    _dataVScroll.dispose();
    _actionVScroll.dispose();
    super.dispose();
  }

  // Helper to construct image URL
  String _resolveImageUrl(String rawPath) {
    final baseUrl = context.read<PrefService>().getCustomApi() ?? 'https://rrgold.loyalstring.co.in/';
    var path = rawPath.trim();
    if (path.endsWith(',')) {
      path = path.substring(0, path.length - 1).trim();
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final imgList = path.split(',');
    final lastImg = imgList.isNotEmpty ? imgList.last.trim() : '';
    return '$baseUrl$lastImg';
  }

  // Dialog to Add a Customer Profile
  void _showAddCustomerDialog() {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) {
        return AddCustomerDialog(
          title: s.customerProfile,
          onSave: (req) async {
            final vm = context.read<OrderViewModel>();
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
              final msg = vm.lastCustomerWasOffline
                  ? s.customerAddedOffline
                  : s.customerAddedSuccessfully;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage ?? s.errorAddingCustomer)));
            }
          },
        );
      },
    );
  }

  // Dialog to Edit single item properties and trigger amount recalculations
  void _showItemEditDialog(OrderItem item, int index) {
    final vm = context.read<OrderViewModel>();
    showDialog(
      context: context,
      builder: (context) => OrderDetailsDialog(
        item: item,
        branches: vm.branches,
        dailyRates: vm.dailyRates,
        onSave: (updated) {
          vm.updateItem(index, updated);
        },
      ),
    );
  }

  // Dialog to update dates/remarks in bulk for all items
  void _showBulkEditDialog() {
    final vm = context.read<OrderViewModel>();
    final s = context.sRead;
    if (vm.productList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.addAtLeastOneItem)));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return OrderBulkDetailsDialog(
          branches: vm.branches,
          dailyRates: vm.dailyRates,
          onConfirm: (fields) {
            vm.updateAllItemsDetails(
              branchId: fields['branchId'],
              branchName: fields['branchName'],
              exhibition: fields['exhibition'],
              remark: fields['remark'],
              purity: fields['purity'],
              size: fields['size'],
              length: fields['length'],
              color: fields['color'],
              screw: fields['screw'],
              polish: fields['polish'],
              wastage: fields['wastage'],
              orderDate: fields['orderDate'],
              deliverDate: fields['deliverDate'],
            );
          },
        );
      },
    );
  }

  // PDF invoice view launcher
  Future<void> _generateAndShowPdf(Map<String, dynamic> orderRes) async {
    final vm = context.read<OrderViewModel>();
    await printCustomOrderPdf(
      context: context,
      orderRes: orderRes,
      baseUrl: vm.baseUrl,
    );
  }

  // Toggle simulation or hardware sweeps (Gscan)
  void _toggleGscan(OrderViewModel vm) async {
    if (_rfidService.isScanning) {
      await _rfidService.stopScanning();
      if (mounted) setState(() {});
      return;
    }

    if (!mounted) return;
    final db = context.read<DbService>();
    unawaited(_rfidService.prepareProductScanMatchSet(db));

    final started = await _rfidService.startScanning(power: _power);
    if (mounted) setState(() {});
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.failedToStartRfidScanner)),
      );
    }
  }

  // Wraps a child with a 1px gradient border + rounded corners (matches the
  // Kotlin `gradientBorderBox` / bordered input rows).
  Widget _gradientBorder({
    required Widget child,
    double radius = 10,
    Color fill = Colors.white,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: _brandGradient,
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

  // ---- Gradient top bar with numeric RFID power counter -------------------
  PreferredSizeWidget _buildGradientTopBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: _brandGradient)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          context.read<OrderViewModel>().clearEditMode();
          Navigator.pop(context);
        },
      ),
      title: Text(
        context.s.orderScreen,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        // White counter box showing selected power (1-30), like the Kotlin app.
        PopupMenuButton<int>(
          tooltip: context.s.rfidPower,
          color: Colors.white,
          constraints: const BoxConstraints(maxHeight: 320, minWidth: 60),
          onSelected: (val) {
            setState(() => _power = val);
            _rfidService.setPower(val);
            context.read<PrefService>().savePower(PrefService.keyOrderCount, val);
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
    );
  }

  // ---- Customer search input (gradient border + dropdown card) ------------
  Widget _buildCustomerInput(OrderViewModel vm) {
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
          if (_showSuggestions)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(minHeight: 0, maxHeight: 260),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(s.noItemsFound,
                          style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFEAEAEA)),
                      itemBuilder: (context, i) {
                        final c = visible[i];
                        final fullName = '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim();
                        final pending = (c.id ?? 0) < 0;
                        final label = pending ? '$fullName *' : fullName;
                        return InkWell(
                          onTap: () {
                            vm.setSelectedCustomer(c);
                            _customerSearchCtrl.text = fullName;
                            setState(() => _showSuggestions = false);
                            _focusNode.unfocus();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  // ---- RFID/Itemcode input + Order Details button -------------------------
  Widget _buildItemCodeRow(OrderViewModel vm) {
    final s = context.s;
    final query = _itemCodeCtrl.text.trim();
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
              // RFID / Itemcode field (weight 1.1)
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
              // Order Details button (weight 0.8)
              Expanded(
                flex: 8,
                child: GestureDetector(
                  onTap: _showBulkEditDialog,
                  child: _gradientBorder(
                    radius: 8,
                    child: SizedBox(
                      height: 35,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(s.orderDetails,
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

  // ---- Custom dark product table (header + rows + totals footer) ----------
  static const double _cellWidth = 70;
  static const double _actionWidth = 45;
  static const double _rowHeight = 34;
  static const double _headerHeight = 30;
  static const double _footerHeight = 34;

  Widget _tableCell(String text,
      {Color color = Colors.black54, FontWeight weight = FontWeight.normal, double width = _cellWidth}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(fontSize: 11, color: color, fontWeight: weight),
      ),
    );
  }

  Widget _buildProductTable(OrderViewModel vm) {
    final items = vm.productList;
    final s = context.s;
    final headers = [s.headerPName, s.itemcode, s.headerGwt, s.headerNwt, s.headerFwWt, s.colStoneAmt, s.colDiamondAmt, s.itemAmt, s.fieldRfidCode];
    final dataWidth = _cellWidth * 9;

    // Footer totals (mirrors the Kotlin OrderListTable footer row).
    double sum(String? Function(OrderItem) sel) =>
        items.fold(0.0, (s, it) => s + (double.tryParse(sel(it) ?? '') ?? 0.0));
    final totalGross = sum((it) => it.grWt);
    final totalNet = sum((it) => it.nWt);
    final totalFine = sum((it) => it.makingFixedWastage);
    final totalStone = sum((it) => it.stoneAmt);
    final totalDiamond = sum((it) => it.diamondAmt);
    final totalAmt = sum((it) => it.itemAmt);
    final totals = [
      s.total,
      '${items.length}',
      totalGross.toStringAsFixed(3),
      totalNet.toStringAsFixed(3),
      totalFine.toStringAsFixed(3),
      totalStone.toStringAsFixed(2),
      totalDiamond.toStringAsFixed(2),
      totalAmt.toStringAsFixed(2),
      totalAmt.toStringAsFixed(2),
    ];

    return Container(
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Horizontally scrollable data area (header + rows + footer together)
          Expanded(
            child: SingleChildScrollView(
              controller: _tableHScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: dataWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      height: _headerHeight,
                      color: const Color(0xFF2E2E2E),
                      child: Row(
                        children: headers
                            .map((h) => _tableCell(h, color: Colors.white, weight: FontWeight.w600))
                            .toList(),
                      ),
                    ),
                    // Data rows
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                              child: Text(s.noItemsAdded,
                                  style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13)),
                            )
                          : ListView.builder(
                              controller: _dataVScroll,
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              itemBuilder: (context, idx) {
                                final item = items[idx];
                                return InkWell(
                                  onTap: () => _showItemEditDialog(item, idx),
                                  child: Container(
                                    height: _rowHeight,
                                    color: idx % 2 == 0 ? const Color(0xFFF4F4F4) : Colors.white,
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      children: [
                                        _tableCell(item.productName),
                                        _tableCell(item.itemCode),
                                        _tableCell(item.grWt ?? ''),
                                        _tableCell(item.nWt ?? ''),
                                        _tableCell(item.finePlusWt ?? ''),
                                        _tableCell(item.stoneAmt ?? ''),
                                        _tableCell(item.diamondAmt),
                                        _tableCell(item.itemAmt ?? ''),
                                        _tableCell(item.rfidCode),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // Totals footer
                    Container(
                      height: _footerHeight,
                      color: const Color(0xFF2E2E2E),
                      child: Row(
                        children: totals
                            .map((t) => _tableCell(t, color: Colors.white, weight: FontWeight.bold))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Fixed action column
          SizedBox(
            width: _actionWidth,
            child: Column(
              children: [
                Container(
                  height: _headerHeight,
                  color: const Color(0xFF2E2E2E),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(s.action,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const SizedBox.shrink()
                      : ListView.builder(
                          controller: _actionVScroll,
                          padding: EdgeInsets.zero,
                          itemCount: items.length,
                          itemBuilder: (context, idx) {
                            return Container(
                              height: _rowHeight,
                              color: idx % 2 == 0 ? const Color(0xFFF4F4F4) : Colors.white,
                              alignment: Alignment.center,
                              child: InkWell(
                                onTap: () => _confirmDelete(vm, idx),
                                child: const Icon(Icons.delete, color: Colors.red, size: 18),
                              ),
                            );
                          },
                        ),
                ),
                Container(height: _footerHeight, color: const Color(0xFF2E2E2E)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(OrderViewModel vm, int idx) {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(s.deleteItem, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text(s.confirmDeleteItem, style: GoogleFonts.poppins()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel, style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                vm.deleteItem(idx);
                Navigator.pop(context);
              },
              child: Text(s.delete, style: GoogleFonts.poppins(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  // ---- GST summary row ----------------------------------------------------
  Widget _buildSummaryRow(OrderViewModel vm) {
    final s = context.s;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // GST checkbox inside a white box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: vm.isGstChecked,
                    activeColor: const Color(0xFF1565C0),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (val) {
                      if (val != null) vm.setGstChecked(val);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Text(s.gstLabel,
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black)),
              ],
            ),
          ),
          Text(s.totalAmount,
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
            child: Text(
              '₹ ${vm.getFinalTotal().toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: const Color(0xFF1565C0), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OrderViewModel>();

    return WillPopScope(
      onWillPop: () async {
        vm.clearEditMode();
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        // Keep the scan bottom bar pinned; the keyboard overlays the body
        // instead of pushing the bar up.
        resizeToAvoidBottomInset: false,
        appBar: _buildGradientTopBar(),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 4),
              _buildCustomerInput(vm),
            const SizedBox(height: 4),
            _buildItemCodeRow(vm),
            const SizedBox(height: 4),
            Expanded(child: _buildProductTable(vm)),
            _buildSummaryRow(vm),
          ],
        ),
      ),
      bottomNavigationBar: ScanBottomBar(
        // Center "Scan" button shows Stop only for a single-tag scan; the
        // "Gscan" button shows Stop for a continuous (bulk) scan.
        isScanning: _rfidService.isScanning && _isSingleScan,
        isBulkScanning: _rfidService.isScanning && !_isSingleScan,
        onSave: () async {
          final s = context.sRead;
          try {
            final res = await vm.submitCustomOrder();
            if (res != null) {
              final msg = vm.isOfflineMode || res['IsPendingSync'] == true
                  ? s.orderSavedOffline
                  : s.orderSavedSuccessfully;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              
              // Open invoice preview
              await _generateAndShowPdf(res);

              // Reset screen state
              vm.clearOrder();
              vm.clearEditMode();
              _customerSearchCtrl.clear();
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage ?? s.failedToSaveOrder)));
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
          }
        },
        onList: () {
          // Go to custom orders list history page
          Navigator.pushNamed(context, '/order_list');
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
          vm.clearOrder();
          _customerSearchCtrl.clear();
        },
      ),
    ),
  );
}
}
