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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StockVerificationViewModel>().fetchBatchDetails(widget.scanBatchId);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<BatchReportItem> _filterItems(List<BatchReportItem> items, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((item) {
      return (item.itemCode ?? '').toLowerCase().contains(q) ||
          (item.productName ?? '').toLowerCase().contains(q) ||
          (item.branchName ?? '').toLowerCase().contains(q) ||
          (item.categoryName ?? '').toLowerCase().contains(q) ||
          (item.rfidCode ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockVerificationViewModel>();
    final s = context.s;

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
      ),
      body: _buildBody(vm),
    );
  }

  Widget _buildBody(StockVerificationViewModel vm) {
    final s = context.s;
    switch (vm.batchDetailsState) {
      case ReportLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case ReportLoadState.error:
        return Center(child: Text(vm.errorMessage ?? 'Error'));
      case ReportLoadState.success:
        final data = vm.batchDetails!;
        final query = _searchCtrl.text;
        final matched = _filterItems(data.matchedList, query);
        final unmatched = _filterItems(data.unmatchedList, query);

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.searchItemProductRfidCategory,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            _BatchSection(
              title: s.matchedItems,
              color: const Color(0xFF2E7D32),
              items: matched,
            ),
            const SizedBox(height: 12),
            _BatchSection(
              title: s.unmatchedItems,
              color: const Color(0xFFC62828),
              items: unmatched,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _BatchSection extends StatelessWidget {
  final String title;
  final Color color;
  final List<BatchReportItem> items;

  const _BatchSection({
    required this.title,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Card(
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: color.withValues(alpha: 0.1),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text('${items.length} ${s.itemsLabel}', style: GoogleFonts.poppins(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Container(
            color: const Color(0xFFE0E0E0),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _hdr(s.itemcode, 1.2),
                _hdr(s.product, 1.3),
                _hdr(s.branch, 1),
                _hdr(s.category, 1.1),
                _hdr(s.lblRfid, 1),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: Text(s.noItemsFound, style: GoogleFonts.poppins(color: Colors.grey))),
            )
          else
            SizedBox(
              height: 400,
              child: ListView.builder(
                itemCount: items.length,
                cacheExtent: 300,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      children: [
                        _cell(item.itemCode ?? '', 1.2),
                        _cell(item.productName ?? 'N/A', 1.3),
                        _cell(item.branchName ?? 'N/A', 1),
                        _cell(item.categoryName ?? 'N/A', 1.1),
                        _cell(item.rfidCode ?? '-', 1),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _hdr(String t, double flex) => Expanded(
        flex: (flex * 10).round(),
        child: Text(t, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      );

  Widget _cell(String t, double flex) => Expanded(
        flex: (flex * 10).round(),
        child: Text(t, style: GoogleFonts.poppins(fontSize: 11), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
      );
}
