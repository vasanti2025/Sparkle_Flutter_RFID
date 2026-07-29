import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/stock_transfer_models.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import 'widgets/product_form_widgets.dart';

/// Same as Sparkle [StockTransferDetailScreen]: item list with checkboxes,
/// select-all, Approve / Reject / Lost (In Request, or Out Request self-approval).
class StockTransferDetailScreen extends StatefulWidget {
  final String requestType;
  final int transferId;
  final String transferTypeName;
  final List<LabelledStockItem> items;
  final bool isSelfApproval;

  const StockTransferDetailScreen({
    super.key,
    required this.requestType,
    required this.transferId,
    required this.transferTypeName,
    required this.items,
    this.isSelfApproval = false,
  });

  @override
  State<StockTransferDetailScreen> createState() => _StockTransferDetailScreenState();
}

class _StockTransferDetailScreenState extends State<StockTransferDetailScreen> {
  String _selectedStatus = 'pending';
  final Set<int> _selectedIds = {};
  late List<LabelledStockItem> _items;
  bool _busy = false;
  bool _loadingItems = false;

  /// Sparkle allowApprovalActions.
  bool get _canApprove =>
      widget.requestType == 'In Request' ||
      (widget.requestType == 'Out Request' && widget.isSelfApproval);

  /// Sparkle showAllDetailItems — Out Request self-approval shows every line.
  bool get _showAllItems =>
      widget.requestType == 'Out Request' && widget.isSelfApproval;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    if (_showAllItems) {
      _selectedStatus = 'all';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureItemsLoaded());
  }

  Future<void> _ensureItemsLoaded() async {
    if (_items.isNotEmpty || widget.transferId <= 0) return;
    setState(() => _loadingItems = true);
    final vm = context.read<StockTransferViewModel>();
    final list = await vm.fetchInOutRequests(requestType: widget.requestType);
    if (!mounted) return;
    final match = list.where((t) => t.id == widget.transferId).toList();
    final resolved = match.isNotEmpty ? match.first.labelledStockItems : <LabelledStockItem>[];
    setState(() {
      _items = List.from(resolved);
      _loadingItems = false;
    });
  }

  List<LabelledStockItem> get _filteredItems {
    if (_showAllItems) return _items;
    return _items.where((item) {
      final status = item.requestStatus;
      return switch (_selectedStatus) {
        'pending' => status == null || status == 0,
        'approved' => status == 1,
        'rejected' => status == 2,
        'lost' => status == 3,
        _ => true,
      };
    }).toList();
  }

  int _selectionId(LabelledStockItem item) => item.approveId;

  bool get _allFilteredSelected {
    final rows = _filteredItems.where((e) => e.approveId > 0).toList();
    if (rows.isEmpty) return false;
    return rows.every((e) => _selectedIds.contains(e.approveId));
  }

  void _toggleSelectAll(bool? checked) {
    final rows = _filteredItems.where((e) => e.approveId > 0);
    setState(() {
      _selectedIds.clear();
      if (checked == true) {
        for (final item in rows) {
          _selectedIds.add(item.approveId);
        }
      }
    });
  }

  void _showStatusFilter() {
    final s = context.sRead;
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
              selected: _selectedStatus == entry.key,
              onTap: () {
                setState(() {
                  _selectedStatus = entry.key;
                  _selectedIds.clear();
                });
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _processSelected(int statusType, String actionLabel) async {
    final s = context.sRead;
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('selectAtLeastOneItem'))),
      );
      return;
    }
    final selectedItems = _items.where((i) => _selectedIds.contains(i.approveId)).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('selectAtLeastOneItem'))),
      );
      return;
    }

    setState(() => _busy = true);
    final vm = context.read<StockTransferViewModel>();
    final msg = await vm.approveRejectTransfer(
      items: selectedItems,
      requestTyp: widget.requestType,
      statusType: statusType,
    );
    if (!mounted) return;

    final ok = msg != null && !msg.toLowerCase().contains('fail');
    setState(() {
      _busy = false;
      if (ok) {
        _items = _items.map((item) {
          if (!_selectedIds.contains(item.approveId)) return item;
          return LabelledStockItem(
            id: item.id,
            transferItemId: item.transferItemId,
            itemCode: item.itemCode,
            rfidCode: item.rfidCode,
            requestStatus: statusType,
            productName: item.productName,
            categoryName: item.categoryName,
            branchName: item.branchName,
            grossWeight: item.grossWeight,
            netWeight: item.netWeight,
          );
        }).toList();
        _selectedIds.clear();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg ?? actionLabel)),
    );

    // Sparkle: after Out Request approve, leave detail so list refreshes.
    if (ok && widget.requestType == 'Out Request' && statusType == 1) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final rows = _filteredItems;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: productGradientAppBar(context: context, title: s.tr('transferDetails')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.transferTypeName.isEmpty ? s.tr('transferType') : widget.transferTypeName,
                      style: GoogleFonts.poppins(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
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
          Container(
            color: const Color(0xFF3C3C3C),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                SizedBox(width: 36, child: Text(s.headerSr, style: _header(), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(s.tr('category'), style: _header(), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(s.tr('itemCodeLabel'), style: _header(), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(s.branch, style: _header(), textAlign: TextAlign.center)),
                Expanded(child: Text(s.tr('grossWt'), style: _header(), textAlign: TextAlign.center)),
                Expanded(child: Text(s.tr('netWt'), style: _header(), textAlign: TextAlign.center)),
                if (_canApprove)
                  SizedBox(
                    width: 48,
                    child: Checkbox(
                      value: _allFilteredSelected,
                      onChanged: _busy || rows.isEmpty ? null : _toggleSelectAll,
                      side: const BorderSide(color: Colors.white),
                      checkColor: const Color(0xFF3C3C3C),
                      fillColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return Colors.white;
                        return Colors.transparent;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loadingItems
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF5231A7)))
                : rows.isEmpty
                    ? Center(
                        child: Text(
                          _items.isEmpty ? s.loading : s.tr('noItemsInCurrentScope'),
                          style: GoogleFonts.poppins(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFE0E0E0)),
                        itemBuilder: (context, index) {
                          final item = rows[index];
                          final id = _selectionId(item);
                          final canSelect = _canApprove && id > 0;
                          final checked = _selectedIds.contains(id);
                          final code = (item.itemCode?.trim().isNotEmpty ?? false)
                              ? item.itemCode!
                              : (item.rfidCode ?? '-');
                          final category = (item.categoryName?.trim().isNotEmpty ?? false)
                              ? item.categoryName!
                              : (item.productName ?? '-');
                          return Container(
                            color: index.isEven ? Colors.white : const Color(0xFFF7F7F7),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Text('${index + 1}', style: _cell(), textAlign: TextAlign.center),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    category,
                                    style: _cell(),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    code,
                                    style: _cell(),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    item.branchName?.isNotEmpty == true ? item.branchName! : '-',
                                    style: _cell(),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item.grossWeight ?? '-',
                                    style: _cell(),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item.netWeight ?? '-',
                                    style: _cell(),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (_canApprove)
                                  SizedBox(
                                    width: 48,
                                    child: Checkbox(
                                      value: checked,
                                      activeColor: const Color(0xFF5231A7),
                                      onChanged: (_busy || !canSelect)
                                          ? null
                                          : (v) {
                                              setState(() {
                                                if (v == true) {
                                                  _selectedIds.add(id);
                                                } else {
                                                  _selectedIds.remove(id);
                                                }
                                              });
                                            },
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          if (_canApprove)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _gradientBtn(
                        s.tr('approve'),
                        Icons.check_circle_outline,
                        _busy ? null : () => _processSelected(1, s.tr('approve')),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _gradientBtn(
                        s.tr('reject'),
                        Icons.cancel_outlined,
                        _busy ? null : () => _processSelected(2, s.tr('reject')),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _gradientBtn(
                        s.tr('lost'),
                        Icons.report_gmailerrorred_outlined,
                        _busy ? null : () => _processSelected(3, s.tr('lost')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gradientBtn(String label, IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Ink(
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _header() => GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10);
  TextStyle _cell() => GoogleFonts.poppins(fontSize: 10, color: Colors.black87);
}
