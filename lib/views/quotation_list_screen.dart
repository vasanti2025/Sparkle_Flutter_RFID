import 'package:flutter/material.dart';
import 'package:rfid_flutter/utils/app_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../services/pref_service.dart';
import '../utils/nav_perf.dart';
import '../viewmodels/quotation_view_model.dart';
import 'widgets/list_action_icon.dart';
import 'widgets/quotation_pdf.dart';
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
      if (!mounted) return;
      runAfterRouteSettled(context, () {
        if (!mounted) return;
        context.read<QuotationViewModel>().fetchQuotationsHistory(
              forceNetwork: true,
            );
      });
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
    final text = raw.toString().trim();
    if (text.isEmpty) return '';
    try {
      return DateFormat('dd-MM-yyyy').format(DateTime.parse(text));
    } catch (_) {
      // API sometimes returns already-formatted or date-only prefixes.
      if (text.length >= 10 && text.contains('-')) {
        try {
          return DateFormat('dd-MM-yyyy').format(DateTime.parse(text.substring(0, 10)));
        } catch (_) {}
      }
      return text;
    }
  }

  /// Quotation list shows a single Date = QuotationDate.
  String _quotationDate(Map<String, dynamic> q) {
    return _formatDate(q['QuotationDate'] ?? q['Date'] ?? q['CreatedOn']);
  }

  /// Description column: item remarks / Description (Sparkle header_description).
  String _description(Map<String, dynamic> q) {
    final top = (q['Remark'] ?? q['Remarks'] ?? q['Description'])?.toString().trim() ?? '';
    final parts = <String>{};
    if (top.isNotEmpty) parts.add(top);
    final items = q['QuotationItem'] as List? ?? [];
    for (final it in items) {
      if (it is! Map) continue;
      final remark = (it['Remark'] ?? it['Description'] ?? it['Remarks'])?.toString().trim() ?? '';
      if (remark.isNotEmpty) parts.add(remark);
    }
    return parts.join(', ');
  }

  /// Same as Sparkle QuotationList / Order list: prefer nested Customer, then flat fields.
  String _customerName(Map<String, dynamic> q) {
    final cust = q['Customer'];
    if (cust is Map) {
      final nested = '${cust['FirstName'] ?? ''} ${cust['LastName'] ?? ''}'.trim();
      if (nested.isNotEmpty) return nested;
    }
    final topName = q['CustomerName']?.toString().trim() ?? '';
    if (topName.isNotEmpty) return topName;
    return '${q['FirstName'] ?? ''} ${q['LastName'] ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuotationViewModel>();
    final s = context.s;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = vm.quotationsHistory.where((q) {
      if (q is! Map) return false;
      final map = Map<String, dynamic>.from(q);
      final qNo = map['QuotationNo']?.toString().toLowerCase() ?? '';
      final custName = _customerName(map).toLowerCase();
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
          style: AppFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
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
                    style: AppFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: s.searchQuotationHint,
                      hintStyle: AppFonts.poppins(fontSize: 13, color: Colors.grey[400]),
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
            child: Column(
              children: [
                if (vm.isHistoryLoading && filtered.isNotEmpty)
                  const LinearProgressIndicator(minHeight: 2, color: Color(0xFF5231A7)),
                Expanded(
                  child: vm.isHistoryLoading && filtered.isEmpty
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF5231A7)))
                      : filtered.isEmpty
                          ? _buildEmptyState()
                          : _buildSpreadsheetView(filtered),
                ),
              ],
            ),
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
            style: AppFonts.poppins(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500),
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
          header: s.description,
          width: 140,
          alignLeft: true,
          maxLines: 2,
          valueBuilder: (i) => _description(list[i] as Map<String, dynamic>),
        ),
        SpreadsheetColumnDef(
          header: s.date,
          width: 100,
          valueBuilder: (i) => _quotationDate(list[i] as Map<String, dynamic>),
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
        final quotation = list[index] as Map<String, dynamic>;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            listActionIcon(icon: Icons.edit, onTap: () => _editQuotation(quotation)),
            listActionIcon(
              icon: Icons.print,
              onTap: () async {
                final prefs = await PrefService.init();
                if (!context.mounted) return;
                await printQuotationPdf(
                  context: context,
                  quotation: quotation,
                  orgName: prefs.getOrganisationName() ?? '',
                );
              },
            ),
          ],
        );
      },
    );
  }
}
