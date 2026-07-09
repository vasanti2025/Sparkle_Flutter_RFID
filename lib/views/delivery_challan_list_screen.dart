import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/l10n_extension.dart';
import '../viewmodels/delivery_challan_view_model.dart';
import '../models/delivery_challan.dart';
import 'widgets/delivery_challan_pdf.dart';
import 'widgets/spreadsheet_list_view.dart';

class DeliveryChallanListScreen extends StatefulWidget {
  const DeliveryChallanListScreen({super.key});

  @override
  State<DeliveryChallanListScreen> createState() => _DeliveryChallanListScreenState();
}

class _DeliveryChallanListScreenState extends State<DeliveryChallanListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeliveryChallanViewModel>().loadChallanList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _editChallan(DeliveryChallanModel challan) {
    context.read<DeliveryChallanViewModel>().setSelectedChallan(challan);
    Navigator.pushNamed(context, '/delivery_challan');
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return DateFormat('dd-MM-yyyy').format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<DeliveryChallanViewModel>();
    final s = context.s;
    final challans = viewModel.challans;
    final isLoading = viewModel.isListLoading;

    final query = _searchController.text.trim().toLowerCase();
    final List<DeliveryChallanModel> filteredChallans = query.isEmpty
        ? List.from(challans)
        : challans.where((c) {
            return (c.challanNo?.toLowerCase().contains(query) ?? false) ||
                (c.customerName?.toLowerCase().contains(query) ?? false) ||
                (c.invoiceNo?.toLowerCase().contains(query) ?? false);
          }).toList();

    filteredChallans.sort((a, b) => b.id.compareTo(a.id));

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
              s.deliveryChallanList,
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: () {
                  viewModel.clearChallan();
                  Navigator.pushNamed(context, '/delivery_challan');
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => viewModel.fetchAllChallans(),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() {}),
                      style: GoogleFonts.poppins(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: s.searchChallanHint,
                        hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400]),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _searchController.clear()),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredChallans.isEmpty
                      ? _buildEmptyState()
                      : _buildSpreadsheetView(filteredChallans),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final s = context.s;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            s.noChallansFound,
            style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            s.createChallanHint,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildSpreadsheetView(List<DeliveryChallanModel> list) {
    final s = context.s;
    return SpreadsheetListView(
      rowCount: list.length,
      columns: [
        SpreadsheetColumnDef(
          header: s.headerChallanNo,
          width: 80,
          valueBuilder: (i) => list[i].challanNo ?? list[i].invoiceNo ?? '-',
        ),
        SpreadsheetColumnDef(
          header: s.date,
          width: 90,
          valueBuilder: (i) => _formatDate(list[i].createdOn),
        ),
        SpreadsheetColumnDef(
          header: s.headerCustomer,
          width: 150,
          alignLeft: true,
          maxLines: 2,
          valueBuilder: (i) => list[i].customerName ?? s.walkInCustomer,
        ),
        SpreadsheetColumnDef(
          header: s.qty,
          width: 55,
          valueBuilder: (i) => list[i].qty ?? '0',
        ),
        SpreadsheetColumnDef(
          header: s.headerGrossWt,
          width: 70,
          valueBuilder: (i) => list[i].grossWt ?? '0.000',
        ),
        SpreadsheetColumnDef(
          header: s.headerStoneWt,
          width: 70,
          valueBuilder: (i) => list[i].stoneWt ?? '0.000',
        ),
        SpreadsheetColumnDef(
          header: s.headerDiamondWt,
          width: 75,
          valueBuilder: (i) => list[i].totalDiamondWeight ?? '0.000',
        ),
        SpreadsheetColumnDef(
          header: s.headerNetWt,
          width: 70,
          valueBuilder: (i) => list[i].netWt ?? '0.000',
        ),
        SpreadsheetColumnDef(
          header: s.headerFineWt,
          width: 70,
          valueBuilder: (i) => list[i].totalFineMetal ?? '0.000',
        ),
        SpreadsheetColumnDef(
          header: s.headerTaxAmt,
          width: 85,
          valueBuilder: (i) => list[i].totalGSTAmount ?? '0.00',
        ),
        SpreadsheetColumnDef(
          header: s.headerTotalAmt,
          width: 95,
          valueBuilder: (i) => '₹${list[i].totalAmount ?? "0.00"}',
        ),
        SpreadsheetColumnDef(
          header: s.branch,
          width: 100,
          valueBuilder: (i) => list[i].branchId.toString(),
        ),
      ],
      actionBuilder: (context, index) {
        final challan = list[index];
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _actionIcon(Icons.edit, Colors.blue, () => _editChallan(challan)),
            const SizedBox(width: 8),
            _actionIcon(Icons.print, Colors.red, () async {
              await printDeliveryChallanPdf(
                context: context,
                challan: challan,
                orgName: '',
              );
            }),
          ],
        );
      },
    );
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}
