import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../../models/stock_verification_report.dart';
import '../../services/consolidated_report_export_service.dart';
import '../../viewmodels/stock_verification_view_model.dart';

class StockVerificationDetailScreen extends StatefulWidget {
  final int branchId;
  final int categoryId;
  final int productId;
  final int designId;
  final String type;
  final String date;

  const StockVerificationDetailScreen({
    super.key,
    required this.branchId,
    required this.categoryId,
    required this.productId,
    required this.designId,
    required this.type,
    required this.date,
  });

  @override
  State<StockVerificationDetailScreen> createState() => _StockVerificationDetailScreenState();
}

class _StockVerificationDetailScreenState extends State<StockVerificationDetailScreen> {
  final _searchCtrl = TextEditingController();
  List<ReportItem> _displayItems = [];
  Timer? _debounce;
  bool _filtering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    _searchCtrl.addListener(_onSearchChanged);
  }

  Future<void> _fetch() async {
    final vm = context.read<StockVerificationViewModel>();
    await vm.fetchDetailItems(
      branchId: widget.branchId,
      type: widget.type,
      date: widget.date,
      categoryId: widget.categoryId > 0 ? widget.categoryId : null,
      productId: widget.productId > 0 ? widget.productId : null,
      designId: widget.designId > 0 ? widget.designId : null,
    );
    if (mounted) {
      setState(() => _displayItems = vm.detailItems);
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final vm = context.read<StockVerificationViewModel>();
      final query = _searchCtrl.text;
      if (query.isEmpty) {
        if (mounted) setState(() => _displayItems = vm.detailItems);
        return;
      }
      if (mounted) setState(() => _filtering = true);
      final filtered = await ConsolidatedReportExportService.filterItems(vm.detailItems, query);
      if (mounted) {
        setState(() {
          _displayItems = filtered;
          _filtering = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  static const _colW = 90.0;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockVerificationViewModel>();
    final s = context.s;

    String titleText = '';
    if (widget.type == 'Matched') {
      titleText = s.matchedItems;
    } else if (widget.type == 'Unmatched') {
      titleText = s.unmatchedItems;
    } else {
      titleText = s.totalItems(vm.detailItems.length);
    }

    return Scaffold(
      backgroundColor: Colors.white,
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
            vm.clearDetailItems();
            Navigator.pop(context);
          },
        ),
        title: Text(
          titleText,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: s.searchItemRfidProduct,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchCtrl.clear())
                    : (_filtering ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))) : null),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildList(vm)),
        ],
      ),
    );
  }

  Widget _buildList(StockVerificationViewModel vm) {
    final s = context.s;
    switch (vm.detailState) {
      case ReportLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case ReportLoadState.error:
        return Center(child: Text(vm.errorMessage ?? 'Error loading data'));
      case ReportLoadState.success:
        if (_displayItems.isEmpty) {
          return Center(child: Text(s.noItemsFound));
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _colW * 7,
            child: Column(
              children: [
                Container(
                  color: const Color(0xFF212121),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _hdr(s.item),
                      _hdr(s.lblRfid),
                      _hdr(s.category),
                      _hdr(s.product),
                      _hdr(s.headerGwt),
                      _hdr(s.headerNwt),
                      _hdr(s.status),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _displayItems.length,
                    cacheExtent: 800,
                    itemExtent: 42,
                    itemBuilder: (context, index) {
                      final item = _displayItems[index];
                      return Container(
                        color: index.isEven ? const Color(0xFFF4F4F4) : Colors.white,
                        child: Row(
                          children: [
                            _cell(item.itemCode),
                            _cell(item.rfidCode),
                            _cell(item.categoryName),
                            _cell(item.productName),
                            _cell(item.grossWeight?.toString()),
                            _cell(item.netWeight?.toString()),
                            _cell(item.status),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _hdr(String t) => SizedBox(
        width: _colW,
        child: Text(t, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
      );

  Widget _cell(String? v) => SizedBox(
        width: _colW,
        child: Text(v ?? '-', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}
