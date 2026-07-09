import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/sample_out.dart';
import '../viewmodels/sample_out_view_model.dart';
import 'widgets/spreadsheet_list_view.dart';

class SampleOutListScreen extends StatefulWidget {
  const SampleOutListScreen({super.key});

  @override
  State<SampleOutListScreen> createState() => _SampleOutListScreenState();
}

class _SampleOutListScreenState extends State<SampleOutListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SampleOutViewModel>().loadSampleOutList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  String _productNames(SampleOutModel item) {
    return item.issueItems
        .map((e) {
          final name = e['ProductName']?.toString() ?? '';
          if (name.isNotEmpty) return name;
          final design = e['DesignName']?.toString() ?? '';
          if (design.isNotEmpty) return design;
          return e['ItemCode']?.toString() ?? '';
        })
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  void _editSampleOut(SampleOutModel item) {
    context.read<SampleOutViewModel>().setSelectedSampleOut(item);
    Navigator.pushNamed(context, '/sample_out');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SampleOutViewModel>();
    final s = context.s;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = vm.sampleOutList.where((item) {
      if (query.isEmpty) return true;
      return item.sampleOutNo.toLowerCase().contains(query) ||
          item.customerName.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => b.id.compareTo(a.id));

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
              s.sampleOutList,
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: () {
                  vm.clearSampleOut();
                  Navigator.pushNamed(context, '/sample_out');
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => vm.fetchAllSampleOut(),
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
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: InputDecoration(
                  hintText: s.searchSampleOutHint,
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
            const Divider(height: 1),
            Expanded(
              child: vm.isListLoading && filtered.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? _buildEmptyState()
                      : _buildSpreadsheet(filtered),
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
          Icon(Icons.logout, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            s.noSampleOutRecordsFound,
            style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            s.createSampleOutHint,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildSpreadsheet(List<SampleOutModel> list) {
    final s = context.s;
    return SpreadsheetListView(
      rowCount: list.length,
      actionHeader: s.action,
      columns: [
        SpreadsheetColumnDef(
          header: s.headerSoNo,
          width: 70,
          valueBuilder: (i) => list[i].sampleOutNo,
        ),
        SpreadsheetColumnDef(
          header: s.headerCustomer,
          width: 110,
          alignLeft: true,
          maxLines: 2,
          valueBuilder: (i) => list[i].customerName,
        ),
        SpreadsheetColumnDef(
          header: s.date,
          width: 90,
          valueBuilder: (i) => _formatDate(list[i].date.isNotEmpty ? list[i].date : list[i].createdOn),
        ),
        SpreadsheetColumnDef(
          header: s.returnTitle,
          width: 90,
          valueBuilder: (i) => _formatDate(list[i].returnDate),
        ),
        SpreadsheetColumnDef(
          header: s.description,
          width: 100,
          alignLeft: true,
          maxLines: 2,
          valueBuilder: (i) => list[i].description,
        ),
        SpreadsheetColumnDef(
          header: s.product,
          width: 130,
          alignLeft: true,
          maxLines: 2,
          valueBuilder: (i) => _productNames(list[i]),
        ),
        SpreadsheetColumnDef(
          header: s.headerTWt,
          width: 70,
          valueBuilder: (i) => list[i].totalWt,
        ),
        SpreadsheetColumnDef(
          header: s.headerGwt,
          width: 70,
          valueBuilder: (i) => list[i].totalGrossWt,
        ),
        SpreadsheetColumnDef(
          header: s.headerSwt,
          width: 70,
          valueBuilder: (i) => list[i].totalStoneWeight,
        ),
        SpreadsheetColumnDef(
          header: s.headerDwt,
          width: 70,
          valueBuilder: (i) => list[i].totalDiamondWeight,
        ),
        SpreadsheetColumnDef(
          header: s.headerQty,
          width: 50,
          valueBuilder: (i) => '${list[i].quantity}',
        ),
      ],
      actionBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _editSampleOut(list[index]),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF5231A7).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.edit, size: 14, color: Color(0xFF5231A7)),
          ),
        );
      },
    );
  }
}
