import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../../models/stock_verification_report.dart';
import '../../viewmodels/stock_verification_view_model.dart';

class StockVerificationBatchDetailsScreen extends StatefulWidget {
  final String scanBatchId;

  const StockVerificationBatchDetailsScreen({super.key, required this.scanBatchId});

  @override
  State<StockVerificationBatchDetailsScreen> createState() => _StockVerificationBatchDetailsScreenState();
}

class _StockVerificationBatchDetailsScreenState extends State<StockVerificationBatchDetailsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<BatchReportItem>? _filteredMatched;
  List<BatchReportItem>? _filteredUnmatched;
  bool _filtering = false;
  String? _loadedBatchId;

  static const _cellStyle = TextStyle(fontSize: 11, color: Color(0xFF222222));
  static const _hdrStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF222222));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scanBatchId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.sRead.noItemsFound)),
        );
        return;
      }
      context.read<StockVerificationViewModel>().fetchBatchDetails(widget.scanBatchId);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), _applyFilter);
  }

  Future<void> _applyFilter() async {
    final vm = context.read<StockVerificationViewModel>();
    final data = vm.batchDetails;
    if (data == null || !mounted) return;

    final query = _searchCtrl.text;
    if (query.trim().isEmpty) {
      setState(() {
        _filteredMatched = null;
        _filteredUnmatched = null;
        _filtering = false;
      });
      return;
    }

    setState(() => _filtering = true);
    final matched = await vm.filterBatchItems(data.matchedList, query);
    final unmatched = await vm.filterBatchItems(data.unmatchedList, query);
    if (!mounted) return;
    setState(() {
      _filteredMatched = matched;
      _filteredUnmatched = unmatched;
      _filtering = false;
    });
  }

  Future<void> _exportExcel() async {
    final vm = context.read<StockVerificationViewModel>();
    final s = context.sRead;
    if (vm.batchDetails == null || vm.isExporting) return;

    var progress = 0;
    StateSetter? dialogSetState;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            dialogSetState = setDialogState;
            return PopScope(
              canPop: false,
              child: AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(s.exportingProgress(progress), style: GoogleFonts.poppins()),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final err = await vm.exportBatchDetails(
      scanBatchId: widget.scanBatchId,
      onProgress: (count) {
        progress = count;
        dialogSetState?.call(() {});
      },
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? s.reportExportedSuccessfully, style: GoogleFonts.poppins()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockVerificationViewModel>();
    final s = context.s;
    final canExport = vm.batchDetailsState == ReportLoadState.success && vm.batchDetails != null;

    if (vm.batchDetailsState == ReportLoadState.success &&
        vm.batchDetails != null &&
        _loadedBatchId != widget.scanBatchId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _loadedBatchId = widget.scanBatchId;
          _filteredMatched = null;
          _filteredUnmatched = null;
        });
      });
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
            vm.clearBatchDetails();
            Navigator.pop(context);
          },
        ),
        title: Text(
          s.batchDetails,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (canExport)
            IconButton(
              icon: vm.isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.file_download, color: Colors.white),
              tooltip: s.exportExcel,
              onPressed: vm.isExporting ? null : _exportExcel,
            ),
        ],
      ),
      body: _buildBody(vm),
    );
  }

  Widget _buildBody(StockVerificationViewModel vm) {
    final s = context.s;
    switch (vm.batchDetailsState) {
      case ReportLoadState.loading:
      case ReportLoadState.idle:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(s.loading, style: GoogleFonts.poppins(fontSize: 13)),
            ],
          ),
        );
      case ReportLoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(vm.errorMessage ?? s.error, textAlign: TextAlign.center, style: GoogleFonts.poppins()),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => vm.fetchBatchDetails(widget.scanBatchId),
                  child: Text(s.retry, style: GoogleFonts.poppins()),
                ),
              ],
            ),
          ),
        );
      case ReportLoadState.success:
        final data = vm.batchDetails!;
        final matched = _filteredMatched ?? data.matchedList;
        final unmatched = _filteredUnmatched ?? data.unmatchedList;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: s.searchItemProductRfidCategory,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filtering
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearchChanged('');
                              },
                            )),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                cacheExtent: 800,
                slivers: [
                  ..._sectionSlivers(
                    title: s.matchedItems,
                    color: const Color(0xFF2E7D32),
                    items: matched,
                    itemsLabel: s.itemsLabel,
                    emptyLabel: s.noItemsFound,
                    headers: [s.itemcode, s.product, s.branch, s.category, s.lblRfid],
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ..._sectionSlivers(
                    title: s.unmatchedItems,
                    color: const Color(0xFFC62828),
                    items: unmatched,
                    itemsLabel: s.itemsLabel,
                    emptyLabel: s.noItemsFound,
                    headers: [s.itemcode, s.product, s.branch, s.category, s.lblRfid],
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
          ],
        );
    }
  }

  List<Widget> _sectionSlivers({
    required String title,
    required Color color,
    required List<BatchReportItem> items,
    required String itemsLabel,
    required String emptyLabel,
    required List<String> headers,
  }) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text(
                  '${items.length} $itemsLabel',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ColoredBox(
            color: const Color(0xFFE0E0E0),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  for (final h in headers)
                    Expanded(child: Text(h, style: _hdrStyle, textAlign: TextAlign.center)),
                ],
              ),
            ),
          ),
        ),
      ),
      if (items.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: Text(emptyLabel, style: const TextStyle(color: Colors.grey))),
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverFixedExtentList(
            itemExtent: 40,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return ColoredBox(
                  color: index.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        _cell(item.itemCode ?? ''),
                        _cell(item.productName ?? 'N/A'),
                        _cell(item.branchName ?? 'N/A'),
                        _cell(item.categoryName ?? 'N/A'),
                        _cell(item.rfidCode ?? '-'),
                      ],
                    ),
                  ),
                );
              },
              childCount: items.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),
        ),
    ];
  }

  Widget _cell(String t) => Expanded(
        child: Text(
          t,
          style: _cellStyle,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}
