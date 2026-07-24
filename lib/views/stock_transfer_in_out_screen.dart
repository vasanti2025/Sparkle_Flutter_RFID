import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/stock_transfer_models.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import '../utils/app_dropdown.dart';
import 'widgets/product_form_widgets.dart';
import 'widgets/stock_transfer_dialogs.dart';

/// Same as Sparkle [StockInScreen] for In Request / Out Request.
class StockTransferInOutScreen extends StatefulWidget {
  final String requestType;

  const StockTransferInOutScreen({super.key, required this.requestType});

  @override
  State<StockTransferInOutScreen> createState() => _StockTransferInOutScreenState();
}

class _StockTransferInOutScreenState extends State<StockTransferInOutScreen> {
  /// Null / "Transfer Type" = no API type filter (same as Sparkle).
  String _selectedTransferTypeName = 'Transfer Type';
  String _selectedStatus = 'all';
  List<StockTransferInOutItem> _transfers = [];
  bool _loading = false;
  String? _error;

  static const double _srW = 40;
  static const double _colW = 90;
  static const double _actionW = 100;
  static const double _tableW = _srW + (_colW * 7) + _actionW;

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
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      int? typeId;
      if (_selectedTransferTypeName != 'Transfer Type') {
        typeId = vm.transferTypes
            .firstWhere(
              (t) => t.transferType.toLowerCase() == _selectedTransferTypeName.toLowerCase(),
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
      if (!_isOutRequest && item.isSelfApproval) return false;

      final matchesType = _selectedTransferTypeName == 'Transfer Type' ||
          item.stockTransferTypeName.toLowerCase() == _selectedTransferTypeName.toLowerCase();
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

  Future<void> _onTransferTypeSelected(String value) async {
    setState(() {
      _selectedTransferTypeName = value;
      _selectedStatus = 'all';
    });
    await _loadTransfers();
  }

  Future<void> _openStatusFilter() async {
    final picked = await showStockStatusFilterPopup(
      context,
      currentStatusKey: _selectedStatus,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedStatus = picked);
  }

  Future<void> _confirmDelete(StockTransferInOutItem item) async {
    final s = context.sRead;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(s.delete, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(s.tr('deleteTransferConfirm'), style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
      _ => () {
          final parts = <String>[
            if (item.pending > 0) 'P:${item.pending}',
            if (item.approved > 0) 'A:${item.approved}',
            if (item.rejected > 0) 'R:${item.rejected}',
            if (item.lost > 0) 'L:${item.lost}',
          ];
          return parts.isEmpty ? 'P:0' : parts.join(' ');
        }(),
    };
  }

  /// Transfer-type dropdown — same visual as Sparkle (fixed ~200dp + arrow).
  Widget _transferTypeDropdown(StockTransferViewModel vm, dynamic s) {
    final types = vm.transferTypes.map((e) => e.transferType).toList();
    final items = <String>['Transfer Type', ...types];

    return PopupMenuButton<String>(
      onSelected: _onTransferTypeSelected,
      offset: const Offset(0, 40),
      constraints: const BoxConstraints(
        minWidth: 200,
        maxWidth: 280,
        maxHeight: kDropdownMenuMaxHeight,
      ),
      itemBuilder: (context) {
        if (types.isEmpty) {
          return [
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                s.tr('noItemsInCurrentScope'),
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
              ),
            ),
          ];
        }
        return items
            .map(
              (name) => PopupMenuItem<String>(
                value: name,
                child: Text(
                  name == 'Transfer Type' ? s.tr('transferType') : name,
                  style: GoogleFonts.poppins(fontSize: 13),
                ),
              ),
            )
            .toList();
      },
      child: Container(
        width: 200,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedTransferTypeName == 'Transfer Type'
                    ? s.tr('transferType')
                    : _selectedTransferTypeName,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.black),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, double width, {bool header = false}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: GoogleFonts.poppins(
          color: header ? Colors.white : Colors.black87,
          fontWeight: header ? FontWeight.bold : FontWeight.normal,
          fontSize: 10,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _headerRow(dynamic s) {
    return Container(
      color: const Color(0xFF3C3C3C),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _cell(s.headerSr, _srW, header: true),
          _cell(s.tr('from'), _colW, header: true),
          _cell(s.tr('to'), _colW, header: true),
          _cell(s.tr('grossWt'), _colW, header: true),
          _cell(s.tr('netWt'), _colW, header: true),
          _cell(s.tr('transferBy'), _colW, header: true),
          _cell(s.tr('transferToCol'), _colW, header: true),
          _cell(s.tr('transferType'), _colW, header: true),
          _cell(_isOutRequest ? s.action : s.tr('status'), _actionW, header: true),
        ],
      ),
    );
  }

  Widget _dataRow(int index, StockTransferInOutItem item, String grossWt, String netWt) {
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
            'isSelfApproval': item.isSelfApproval,
          },
        ).then((_) => _loadTransfers());
      },
      child: Container(
        color: index.isEven ? Colors.white : const Color(0xFFF7F7F7),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _cell('${index + 1}', _srW),
            _cell(item.sourceName, _colW),
            _cell(item.destinationName, _colW),
            _cell(grossWt, _colW),
            _cell(netWt, _colW),
            _cell(item.transferByEmployee, _colW),
            _cell(item.transferToDisplay, _colW),
            _cell(item.stockTransferTypeName, _colW),
            SizedBox(
              width: _actionW,
              child: _isOutRequest
                  ? (item.isSelfApproval
                      ? Text(
                          _statusText(item),
                          style: GoogleFonts.poppins(fontSize: 10),
                          textAlign: TextAlign.center,
                        )
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _confirmDelete(item),
                        ))
                  : Text(
                      _statusText(item),
                      style: GoogleFonts.poppins(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockTransferViewModel>();
    final s = context.s;
    final rows = _filteredTransfers;
    final title = _isOutRequest ? s.tr('outRequest') : s.tr('inRequest');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: productGradientAppBar(
        context: context,
        title: '$title - ${s.tr('stockTransfers')}',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Always visible — same as Sparkle filter row (dropdown + tune).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                _transferTypeDropdown(vm, s),
                const Spacer(),
                IconButton(
                  tooltip: s.tr('statusFilter'),
                  icon: const Icon(Icons.tune, color: Color(0xFF3C3C3C)),
                  onPressed: _openStatusFilter,
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF5231A7))))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red), textAlign: TextAlign.center),
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _tableW,
                  child: Column(
                    children: [
                      _headerRow(s),
                      Expanded(
                        child: rows.isEmpty
                            ? Center(
                                child: Text(
                                  s.tr('noItemsInCurrentScope'),
                                  style: GoogleFonts.poppins(),
                                ),
                              )
                            : ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = rows[index];
                                  final first = item.labelledStockItems.isNotEmpty
                                      ? item.labelledStockItems.first
                                      : null;
                                  final grossWt = first?.grossWeight?.isNotEmpty == true
                                      ? first!.grossWeight!
                                      : item.totalGrossWt.toStringAsFixed(2);
                                  final netWt = first?.netWeight?.isNotEmpty == true
                                      ? first!.netWeight!
                                      : item.totalNetWt.toStringAsFixed(2);
                                  return _dataRow(index, item, grossWt, netWt);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
