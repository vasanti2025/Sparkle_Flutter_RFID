import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../../models/stock_verification_report.dart';
import '../../services/consolidated_report_export_service.dart';
import '../../viewmodels/stock_verification_view_model.dart';
import 'widgets/consolidated_report_tree.dart';

class StockVerificationReportScreen extends StatefulWidget {
  const StockVerificationReportScreen({super.key});

  @override
  State<StockVerificationReportScreen> createState() => _StockVerificationReportScreenState();
}

class _StockVerificationReportScreenState extends State<StockVerificationReportScreen> {
  static const _gradient = LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]);

  /// INVENTORY = BatchWise, SCAN = Consolidated (same as Kotlin)
  String _reportType = 'INVENTORY';
  String _selectedDate = todayDateString();
  String _filterFromDate = todayDateString();
  String _filterToDate = todayDateString();
  int? _filterBranchId;
  int _exportProgress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final vm = context.read<StockVerificationViewModel>();
    await vm.loadBranches();
    if (_reportType == 'SCAN') {
      await vm.fetchConsolidatedReport(_selectedDate);
    } else {
      await vm.fetchSessions();
    }
  }

  Future<void> _onReportTypeChange(String type) async {
    setState(() => _reportType = type);
    final vm = context.read<StockVerificationViewModel>();
    if (type == 'SCAN') {
      await vm.fetchConsolidatedReport(_selectedDate);
    } else {
      await vm.fetchSessions();
    }
  }

  Future<void> _pickDate({required bool consolidated}) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(consolidated ? _selectedDate : _filterFromDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    if (consolidated) {
      setState(() => _selectedDate = dateStr);
      await context.read<StockVerificationViewModel>().fetchConsolidatedReport(dateStr);
    }
  }

  void _openBatchFilter() {
    final vm = context.read<StockVerificationViewModel>();
    showDialog(
      context: context,
      builder: (ctx) => _BatchFilterDialog(
        branches: vm.branches,
        fromDate: _filterFromDate,
        toDate: _filterToDate,
        selectedBranchId: _filterBranchId,
        onApply: (branchId, from, to) {
          setState(() {
            _filterBranchId = branchId;
            _filterFromDate = from;
            _filterToDate = to;
          });
          vm.filterSessions(branchId: branchId, fromDate: from, toDate: to);
        },
      ),
    );
  }

  void _navigateToDetail({
    required int branchId,
    int? categoryId,
    int? productId,
    int? designId,
    required String type,
  }) {
    Navigator.pushNamed(
      context,
      '/report_detail',
      arguments: {
        'branchId': branchId,
        'categoryId': categoryId ?? 0,
        'productId': productId ?? 0,
        'designId': designId ?? 0,
        'type': type,
        'date': _selectedDate,
      },
    );
  }

  Future<void> _exportConsolidated() async {
    final vm = context.read<StockVerificationViewModel>();
    if (vm.consolidatedReport == null) return;

    final sRead = context.sRead;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(sRead.exportingProgress(_exportProgress), style: GoogleFonts.poppins()),
          ],
        ),
      ),
    );

    final err = await vm.exportConsolidatedReport((count) {
      if (mounted) setState(() => _exportProgress = count);
    });

    if (mounted) Navigator.pop(context);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sRead.reportExportedSuccessfully)),
      );
    }
    setState(() => _exportProgress = 0);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockVerificationViewModel>();
    final s = context.s;
    final isBatch = _reportType == 'INVENTORY';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _gradient)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          s.stockVerificationReport,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (!isBatch && vm.consolidatedReport != null)
            IconButton(
              icon: vm.isExporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.file_download, color: Colors.white),
              tooltip: s.exportExcel,
              onPressed: vm.isExporting ? null : _exportConsolidated,
            ),
        ],
      ),
      body: Column(
        children: [
          _ReportTypeBar(
            reportType: _reportType,
            selectedDate: _selectedDate,
            showFilter: isBatch,
            showDate: !isBatch,
            onTypeChange: _onReportTypeChange,
            onFilter: _openBatchFilter,
            onDate: () => _pickDate(consolidated: true),
          ),
          Expanded(
            child: isBatch ? _buildBatchList(vm) : _buildConsolidatedList(vm),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchList(StockVerificationViewModel vm) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 620,
        child: Column(
          children: [
            const BatchHeaderRow(),
            Expanded(
              child: _buildBatchBody(vm),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchBody(StockVerificationViewModel vm) {
    switch (vm.sessionState) {
      case ReportLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case ReportLoadState.error:
        return Center(child: Text(vm.errorMessage ?? context.s.errorLoadingSessions));
      case ReportLoadState.success:
        final sessions = vm.sessionList?.sessions ?? [];
        if (sessions.isEmpty) {
          return Center(child: Text(context.s.noSessionsFound));
        }
        return ListView.builder(
          itemCount: sessions.length,
          cacheExtent: 500,
          itemBuilder: (context, index) {
            final session = sessions[index];
            return BatchSessionRow(
              session: session,
              onTap: () => Navigator.pushNamed(
                context,
                '/report_batch_details',
                arguments: {'scanBatchId': session.scanBatchId},
              ),
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildConsolidatedList(StockVerificationViewModel vm) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 360,
        child: Column(
          children: [
            const ConsolidatedHeaderRow(),
            Expanded(child: _buildConsolidatedBody(vm)),
          ],
        ),
      ),
    );
  }

  Widget _buildConsolidatedBody(StockVerificationViewModel vm) {
    switch (vm.consolidatedState) {
      case ReportLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case ReportLoadState.error:
        return Center(child: Text(vm.errorMessage ?? context.s.errorLoadingReport));
      case ReportLoadState.success:
        final branches = vm.consolidatedReport?.branches ?? [];
        if (branches.isEmpty) {
          return Center(child: Text(context.s.noDataForSelectedDate));
        }
        return ConsolidatedReportTree(
          branches: branches,
          selectedDate: _selectedDate,
          onBadgeTap: _navigateToDetail,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _ReportTypeBar extends StatelessWidget {
  final String reportType;
  final String selectedDate;
  final bool showFilter;
  final bool showDate;
  final ValueChanged<String> onTypeChange;
  final VoidCallback onFilter;
  final VoidCallback onDate;

  const _ReportTypeBar({
    required this.reportType,
    required this.selectedDate,
    required this.showFilter,
    required this.showDate,
    required this.onTypeChange,
    required this.onFilter,
    required this.onDate,
  });

  static const _gradient = LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _tab(context.s.batchWise, reportType == 'INVENTORY', () => onTypeChange('INVENTORY'))),
                const SizedBox(width: 8),
                Expanded(child: _tab(context.s.consolidated, reportType == 'SCAN', () => onTypeChange('SCAN'))),
              ],
            ),
          ),
          if (showFilter) ...[
            const SizedBox(width: 8),
            _actionBtn(onFilter, const Icon(Icons.filter_list, color: Colors.white, size: 20)),
          ],
          if (showDate) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onDate,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F4F4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD9D9D9)),
                ),
                child: Row(
                  children: [
                    Text(formatDisplayDate(selectedDate), style: GoogleFonts.poppins(fontSize: 12)),
                    const SizedBox(width: 4),
                    const Icon(Icons.date_range, size: 16, color: Color(0xFF666666)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return Material(
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected ? _gradient : null,
            color: selected ? null : const Color(0xFFF4F4F4),
            borderRadius: BorderRadius.circular(10),
            border: selected ? null : Border.all(color: const Color(0xFFD9D9D9)),
          ),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : const Color(0xFF222222),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(VoidCallback onTap, Widget child) {
    return Material(
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(10)),
          child: SizedBox(width: 46, height: 46, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _BatchFilterDialog extends StatefulWidget {
  final List<ReportBranchOption> branches;
  final String fromDate;
  final String toDate;
  final int? selectedBranchId;
  final void Function(int? branchId, String from, String to) onApply;

  const _BatchFilterDialog({
    required this.branches,
    required this.fromDate,
    required this.toDate,
    required this.selectedBranchId,
    required this.onApply,
  });

  @override
  State<_BatchFilterDialog> createState() => _BatchFilterDialogState();
}

class _BatchFilterDialogState extends State<_BatchFilterDialog> {
  late int? _branchId;
  late String _from;
  late String _to;

  @override
  void initState() {
    super.initState();
    _branchId = widget.selectedBranchId;
    _from = widget.fromDate;
    _to = widget.toDate;
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(isFrom ? _from : _to) ?? now;
    final fromMillis = DateTime.tryParse(_from)?.millisecondsSinceEpoch ?? 0;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now,
      selectableDayPredicate: isFrom
          ? null
          : (day) {
              final ms = day.millisecondsSinceEpoch;
              return ms >= fromMillis && ms <= now.millisecondsSinceEpoch;
            },
    );
    if (picked == null) return;
    final s = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (isFrom) {
        _from = s;
        if (_to.compareTo(_from) < 0) _to = s;
      } else {
        _to = s;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return AlertDialog(
      title: Text(s.filter, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.branch, style: GoogleFonts.poppins(fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int?>(
              value: _branchId,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(s.allBranches)),
                ...widget.branches.map((b) => DropdownMenuItem<int?>(value: b.id, child: Text(b.name))),
              ],
              onChanged: (v) => setState(() => _branchId = v),
            ),
            const SizedBox(height: 12),
            _dateField(s.fromDate, _from, () => _pickDate(true)),
            const SizedBox(height: 12),
            _dateField(s.toDate, _to, () => _pickDate(false)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5231A7)),
          onPressed: () {
            widget.onApply(_branchId, _from, _to);
            Navigator.pop(context);
          },
          child: Text(s.apply, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _dateField(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.date_range),
          isDense: true,
        ),
        child: Text(value, style: GoogleFonts.poppins(fontSize: 13)),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
