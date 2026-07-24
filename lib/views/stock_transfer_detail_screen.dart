import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/stock_transfer_models.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import 'widgets/product_form_widgets.dart';

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

  /// In Request always; Out Request only for self-approval (same as Sparkle).
  bool get _canApprove =>
      widget.requestType == 'In Request' ||
      (widget.requestType == 'Out Request' && widget.isSelfApproval);

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    if (widget.requestType == 'Out Request' && widget.isSelfApproval) {
      _selectedStatus = 'all';
    }
  }

  List<LabelledStockItem> get _filteredItems {
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

  Future<void> _processSelected(int statusType, String actionLabel) async {
    final s = context.s;
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('selectAtLeastOneItem'))),
      );
      return;
    }
    final selectedItems = _items.where((i) => _selectedIds.contains(i.approveId)).toList();
    setState(() => _busy = true);
    final vm = context.read<StockTransferViewModel>();
    final msg = await vm.approveRejectTransfer(
      items: selectedItems,
      requestTyp: widget.requestType,
      statusType: statusType,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (msg != null) {
        _items = _items.map((item) {
          if (!_selectedIds.contains(item.approveId)) return item;
          return LabelledStockItem(
            id: item.id,
            transferItemId: item.transferItemId,
            itemCode: item.itemCode,
            rfidCode: item.rfidCode,
            requestStatus: statusType,
            productName: item.productName,
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
                      widget.transferTypeName,
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
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                if (_canApprove) const SizedBox(width: 42),
                SizedBox(width: 28, child: Text(s.headerSr, style: _header())),
                Expanded(flex: 3, child: Text(s.tr('productName'), style: _header())),
                Expanded(flex: 2, child: Text(s.tr('itemCodeLabel'), style: _header())),
                Expanded(child: Text(s.tr('grossWt'), style: _header(), textAlign: TextAlign.center)),
                Expanded(child: Text(s.tr('netWt'), style: _header(), textAlign: TextAlign.center)),
                Expanded(child: Text(s.tr('status'), style: _header(), textAlign: TextAlign.center)),
              ],
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
                      final id = item.approveId > 0 ? item.approveId : index;
                      final checked = _selectedIds.contains(id);
                      final code = (item.itemCode?.trim().isNotEmpty ?? false)
                          ? item.itemCode!
                          : (item.rfidCode ?? '-');
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            if (_canApprove)
                              Checkbox(
                                value: checked,
                                onChanged: _busy
                                    ? null
                                    : (_) {
                                        setState(() {
                                          if (checked) {
                                            _selectedIds.remove(id);
                                          } else {
                                            _selectedIds.add(id);
                                          }
                                        });
                                      },
                              ),
                            SizedBox(width: 28, child: Text('${index + 1}', style: _cell())),
                            Expanded(
                              flex: 3,
                              child: Text(
                                item.productName ?? '-',
                                style: _cell(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(code, style: _cell(), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            Expanded(
                              child: Text(item.grossWeight ?? '-', style: _cell(), textAlign: TextAlign.center),
                            ),
                            Expanded(
                              child: Text(item.netWeight ?? '-', style: _cell(), textAlign: TextAlign.center),
                            ),
                            Expanded(
                              child: Text(
                                transferStatusLabel(item.requestStatus, pending: s.tr('pending')),
                                style: _cell(),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (_canApprove)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: _gradientBtn(
                      s.tr('approve'),
                      _busy ? null : () => _processSelected(1, s.tr('approve')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _gradientBtn(
                      s.tr('reject'),
                      _busy ? null : () => _processSelected(2, s.tr('reject')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _gradientBtn(
                      s.tr('lost'),
                      _busy ? null : () => _processSelected(3, s.tr('lost')),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _gradientBtn(String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  TextStyle _header() => GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10);
  TextStyle _cell() => GoogleFonts.poppins(fontSize: 10, color: Colors.black87);
}
