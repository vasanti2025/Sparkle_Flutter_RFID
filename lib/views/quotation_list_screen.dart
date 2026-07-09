import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../viewmodels/quotation_view_model.dart';
import 'widgets/spreadsheet_list_view.dart';

class QuotationListScreen extends StatefulWidget {
  const QuotationListScreen({super.key});

  @override
  State<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends State<QuotationListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuotationViewModel>().fetchQuotationsHistory();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _editQuotation(Map<String, dynamic> quotation) {
    context.read<QuotationViewModel>().setQuotationForEditing(quotation);
    Navigator.pushNamed(context, '/quotation');
  }

  double _sumItems(Map<String, dynamic> q, String key) {
    final items = q['QuotationItem'] as List? ?? [];
    double total = 0;
    for (final it in items) {
      total += double.tryParse((it as Map)[key]?.toString() ?? '') ?? 0.0;
    }
    return total;
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      return DateFormat('dd-MM-yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  String _customerName(Map<String, dynamic> q) {
    if (q['CustomerName']?.toString().trim().isNotEmpty ?? false) {
      return q['CustomerName'].toString();
    }
    return '${q['FirstName'] ?? ''} ${q['LastName'] ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuotationViewModel>();
    final s = context.s;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = vm.quotationsHistory.where((q) {
      final qNo = q['QuotationNo']?.toString().toLowerCase() ?? '';
      final custName = (q['CustomerName']?.toString() ?? q['FirstName']?.toString() ?? '').toLowerCase();
      return qNo.contains(query) || custName.contains(query);
    }).toList()
      ..sort((a, b) => ((b['Id'] as int?) ?? 0).compareTo((a['Id'] as int?) ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
          ),
        ),
        title: Text(
          s.quotationList,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              context.read<QuotationViewModel>().clearEditMode();
              Navigator.pushNamed(context, '/quotation');
            },
          ),
        ],
      ),
      body: Column(
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
                      hintText: s.searchQuotationHint,
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
          Expanded(
            child: vm.isHistoryLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF5231A7)))
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : _buildSpreadsheetView(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final s = context.s;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            s.noQuotationsFound,
            style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSpreadsheetView(List<dynamic> list) {
    final s = context.s;
    return SpreadsheetListView(
      rowCount: list.length,
      actionWidth: 70,
      columns: [
        SpreadsheetColumnDef(
          header: s.headerQNo,
          width: 90,
          valueBuilder: (i) => (list[i] as Map)['QuotationNo']?.toString() ?? '-',
        ),
        SpreadsheetColumnDef(
          header: s.date,
          width: 90,
          valueBuilder: (i) {
            final q = list[i] as Map<String, dynamic>;
            return _formatDate(q['QuotationDate'] ?? q['CreatedOn'] ?? q['Date']);
          },
        ),
        SpreadsheetColumnDef(
          header: s.customerName,
          width: 150,
          alignLeft: true,
          maxLines: 2,
          valueBuilder: (i) {
            final name = _customerName(list[i] as Map<String, dynamic>);
            return name.isEmpty ? s.walkInCustomer : name;
          },
        ),
        SpreadsheetColumnDef(
          header: s.qty,
          width: 55,
          valueBuilder: (i) => (list[i] as Map)['Qty']?.toString() ?? '0',
        ),
        SpreadsheetColumnDef(
          header: s.headerGrossWt,
          width: 70,
          valueBuilder: (i) {
            final q = list[i] as Map<String, dynamic>;
            final gWt = double.tryParse(q['GrossWt']?.toString() ?? '') ?? _sumItems(q, 'GrossWt');
            return gWt.toStringAsFixed(3);
          },
        ),
        SpreadsheetColumnDef(
          header: s.headerStoneWt,
          width: 70,
          valueBuilder: (i) {
            final q = list[i] as Map<String, dynamic>;
            final sWt = double.tryParse(q['StoneWt']?.toString() ?? '') ?? _sumItems(q, 'StoneWt');
            return sWt.toStringAsFixed(3);
          },
        ),
        SpreadsheetColumnDef(
          header: s.headerDiamondWt,
          width: 75,
          valueBuilder: (i) {
            final q = list[i] as Map<String, dynamic>;
            final dWt = double.tryParse(q['TotalDiamondWeight']?.toString() ?? '') ?? _sumItems(q, 'DiamondWeight');
            return dWt.toStringAsFixed(3);
          },
        ),
        SpreadsheetColumnDef(
          header: s.headerNetWt,
          width: 70,
          valueBuilder: (i) {
            final q = list[i] as Map<String, dynamic>;
            final nWt = double.tryParse(q['NetWt']?.toString() ?? '') ?? _sumItems(q, 'NetWt');
            return nWt.toStringAsFixed(3);
          },
        ),
        SpreadsheetColumnDef(
          header: s.headerTaxAmt,
          width: 85,
          valueBuilder: (i) => (list[i] as Map)['TotalGSTAmount']?.toString() ?? '0.00',
        ),
        SpreadsheetColumnDef(
          header: s.headerTotalAmt,
          width: 95,
          valueBuilder: (i) => '₹${(list[i] as Map)['TotalAmount'] ?? "0.00"}',
        ),
      ],
      actionBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _editQuotation(list[index] as Map<String, dynamic>),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit, size: 14, color: Colors.blue),
          ),
        );
      },
    );
  }
}
