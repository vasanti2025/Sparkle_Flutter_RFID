import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/sample_in.dart';
import '../viewmodels/sample_in_view_model.dart';
import 'widgets/spreadsheet_list_view.dart';

class SampleInListScreen extends StatefulWidget {
  const SampleInListScreen({super.key});

  @override
  State<SampleInListScreen> createState() => _SampleInListScreenState();
}

class _SampleInListScreenState extends State<SampleInListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SampleInViewModel>().loadSampleInList();
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

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SampleInViewModel>();
    final s = context.s;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = vm.sampleInList.where((item) {
      if (query.isEmpty) return true;
      return item.sampleOutNo.toLowerCase().contains(query) ||
          item.customerName.toLowerCase().contains(query) ||
          item.productName.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => b.id.compareTo(a.id));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(s.sampleInList, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
            actions: [
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: () {
                  vm.clearSampleIn();
                  Navigator.pushNamed(context, '/sample_in');
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => vm.fetchAllSampleIn(),
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
                  hintText: s.searchSoNoCustomerProduct,
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
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login, size: 80, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(s.noSampleInRecordsFound, style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                            ],
                          ),
                        )
                      : _buildSpreadsheet(filtered),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpreadsheet(List<SampleInModel> list) {
    final s = context.s;
    return SpreadsheetListView(
      rowCount: list.length,
      actionWidth: 70,
      columns: [
        SpreadsheetColumnDef(header: s.headerSoNo, width: 70, valueBuilder: (i) => list[i].sampleOutNo),
        SpreadsheetColumnDef(header: s.headerCustName, width: 110, alignLeft: true, maxLines: 2, valueBuilder: (i) => list[i].customerName),
        SpreadsheetColumnDef(header: s.date, width: 90, valueBuilder: (i) => _formatDate(list[i].createdOn)),
        SpreadsheetColumnDef(header: s.headerRDate, width: 90, valueBuilder: (i) => _formatDate(list[i].sampleInDate)),
        SpreadsheetColumnDef(header: s.description, width: 100, alignLeft: true, maxLines: 2, valueBuilder: (i) => list[i].description),
        SpreadsheetColumnDef(header: s.headerPName, width: 130, alignLeft: true, maxLines: 2, valueBuilder: (i) => list[i].productName),
        SpreadsheetColumnDef(header: s.headerTWt, width: 70, valueBuilder: (i) => list[i].totalWt),
        SpreadsheetColumnDef(header: s.headerGwt, width: 70, valueBuilder: (i) => list[i].grossWt),
        SpreadsheetColumnDef(header: s.headerSwt, width: 70, valueBuilder: (i) => list[i].stoneWeight),
        SpreadsheetColumnDef(header: s.headerDwt, width: 70, valueBuilder: (i) => list[i].diamondWeight),
        SpreadsheetColumnDef(header: s.headerQty, width: 50, valueBuilder: (i) => '${list[i].quantity}'),
      ],
      actionBuilder: (context, index) => const Icon(Icons.print, size: 18, color: Color(0xFF37474F)),
    );
  }
}
