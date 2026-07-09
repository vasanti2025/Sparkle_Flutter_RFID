import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/stock_transfer_models.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import 'widgets/product_form_widgets.dart';

class StockTransferInOutScreen extends StatefulWidget {
  final String requestType;

  const StockTransferInOutScreen({super.key, required this.requestType});

  @override
  State<StockTransferInOutScreen> createState() => _StockTransferInOutScreenState();
}

class _StockTransferInOutScreenState extends State<StockTransferInOutScreen> {
  String? _selectedTransferTypeName;
  String _selectedStatus = 'all';
  List<StockTransferInOutItem> _transfers = [];
  bool _loading = false;
  String? _error;

  bool get _isOutRequest => widget.requestType == 'Out Request';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final vm = context.read<StockTransferViewModel>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await vm.ensureTransferTypesLoaded();
      if (vm.allEmployees.isEmpty) {
        await vm.loadUserPermissions();
      }
      await _loadTransfers(showLoader: false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTransfers({bool showLoader = true}) async {
    final vm = context.read<StockTransferViewModel>();
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      int? typeId;
      if (_selectedTransferTypeName != null) {
        typeId = vm.transferTypes
            .firstWhere(
              (t) => t.transferType.toLowerCase() == _selectedTransferTypeName!.toLowerCase(),
              orElse: () => TransferType(id: -1, transferType: '', clientCode: ''),
            )
            .id;
        if (typeId == -1) typeId = null;
      }
      final list = await vm.fetchInOutRequests(
        requestType: widget.requestType,
        transferTypeFilterId: typeId,
      );
      if (mounted) setState(() => _transfers = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted && showLoader) setState(() => _loading = false);
    }
  }

  List<StockTransferInOutItem> get _filteredTransfers {
    return _transfers.where((item) {
      final matchesType = _selectedTransferTypeName == null ||
          item.stockTransferTypeName.toLowerCase() == _selectedTransferTypeName!.toLowerCase();
      final matchesStatus = switch (_selectedStatus) {
        'pending' => item.pending > 0,
        'approved' => item.approved > 0,
        'rejected' => item.rejected > 0,
        'lost' => item.lost > 0,
        _ => true,
      };
      return matchesType && matchesStatus;
    }).toList();
  }

  Future<void> _pickTransferType(StockTransferViewModel vm) async {
    if (vm.transferTypes.isEmpty) {
      await vm.ensureTransferTypesLoaded();
      if (!mounted) return;
      if (vm.transferTypes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.tr('transferFailed'))),
        );
        return;
      }
    }
    final transferTypeLabel = context.s.tr('transferType');
    final options = [transferTypeLabel, ...vm.transferTypes.map((e) => e.transferType)];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: options
              .map(
                (o) => ListTile(
                  title: Text(o, style: GoogleFonts.poppins()),
                  onTap: () => Navigator.pop(c, o),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedTransferTypeName = picked == transferTypeLabel ? null : picked);
    await _loadTransfers();
  }

  void _showStatusFilter() {
    final s = context.s;
    final options = <MapEntry<String, String>>[
      MapEntry('all', s.all),
      MapEntry('pending', s.tr('pending')),
      MapEntry('approved', s.tr('approved')),
      MapEntry('rejected', s.tr('rejected')),
      MapEntry('lost', s.tr('lost')),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.tr('statusFilter'), style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((entry) {
            return ListTile(
              title: Text(entry.value, style: GoogleFonts.poppins()),
              onTap: () {
                setState(() => _selectedStatus = entry.key);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(StockTransferInOutItem item) async {
    final s = context.s;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.delete, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(s.tr('deleteTransferConfirm'), style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final vm = context.read<StockTransferViewModel>();
    final msg = await vm.cancelTransfer(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg ?? s.tr('transferFailed'))),
    );
    await _loadTransfers();
  }

  String _statusText(StockTransferInOutItem item) {
    return switch (_selectedStatus) {
      'pending' => 'P: ${item.pending}',
      'approved' => 'A: ${item.approved}',
      'rejected' => 'R: ${item.rejected}',
      'lost' => 'L: ${item.lost}',
      _ => 'P:${item.pending}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockTransferViewModel>();
    final s = context.s;
    final rows = _filteredTransfers;
    final title = _isOutRequest ? s.tr('outRequest') : s.tr('inRequest');
    final transferTypeLabel = _selectedTransferTypeName ?? s.tr('transferType');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: productGradientAppBar(context: context, title: '$title - ${s.tr('stockTransfers')}'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.white,
                    child: InkWell(
                      onTap: _loading ? null : () => _pickTransferType(vm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F8F8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF3C3C3C), width: 1),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                transferTypeLabel,
                                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Color(0xFF3C3C3C)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune, color: Color(0xFF3C3C3C)),
                  onPressed: _showStatusFilter,
                ),
              ],
            ),
          ),
          if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (!_loading && _error != null)
            Expanded(child: Center(child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red)))),
          if (!_loading && _error == null) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                color: const Color(0xFF3C3C3C),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _headerCell(s.headerSr, 40),
                    _headerCell(s.tr('from'), 90),
                    _headerCell(s.tr('to'), 90),
                    _headerCell(s.tr('grossWt'), 90),
                    _headerCell(s.tr('netWt'), 90),
                    _headerCell(s.tr('transferBy'), 90),
                    _headerCell(s.tr('transferToCol'), 90),
                    _headerCell(s.tr('transferType'), 90),
                    _headerCell(_isOutRequest ? s.action : s.tr('status'), 100),
                  ],
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(s.tr('noItemsInCurrentScope'), style: GoogleFonts.poppins()))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        final first = item.labelledStockItems.isNotEmpty ? item.labelledStockItems.first : null;
                        final grossWt = first?.grossWeight?.isNotEmpty == true
                            ? first!.grossWeight!
                            : item.totalGrossWt.toStringAsFixed(2);
                        final netWt = first?.netWeight?.isNotEmpty == true
                            ? first!.netWeight!
                            : item.totalNetWt.toStringAsFixed(2);
                        return InkWell(
                          onTap: () {
                            if (item.labelledStockItems.isEmpty) return;
                            Navigator.pushNamed(
                              context,
                              '/stock_transfer_detail',
                              arguments: {
                                'requestType': widget.requestType,
                                'transferId': item.id,
                                'transferTypeName': item.stockTransferTypeName,
                                'items': item.labelledStockItems,
                              },
                            ).then((_) => _loadTransfers());
                          },
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _dataCell('${index + 1}', 40),
                                _dataCell(item.sourceName, 90),
                                _dataCell(item.destinationName, 90),
                                _dataCell(grossWt, 90),
                                _dataCell(netWt, 90),
                                _dataCell(item.transferByEmployee, 90),
                                _dataCell(item.transferedToBranch, 90),
                                _dataCell(item.stockTransferTypeName, 90),
                                _isOutRequest
                                    ? SizedBox(
                                        width: 100,
                                        child: IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                                          onPressed: () => _confirmDelete(item),
                                        ),
                                      )
                                    : _dataCell(_statusText(item), 100),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(text, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center),
    );
  }

  Widget _dataCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(text, style: GoogleFonts.poppins(fontSize: 10), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
