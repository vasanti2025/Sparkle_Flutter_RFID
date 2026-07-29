import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../models/user_permission.dart';
import '../services/pref_service.dart';
import '../utils/app_dropdown.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import 'widgets/product_form_widgets.dart';

/// Same as Sparkle [StockTransferPreviewScreen]: Transfer opens Transfer Details popup,
/// OK calls AddStockTransfer (same-user vs branch-to-branch other-user).
class StockTransferPreviewScreen extends StatefulWidget {
  const StockTransferPreviewScreen({super.key});

  @override
  State<StockTransferPreviewScreen> createState() => _StockTransferPreviewScreenState();
}

class _StockTransferPreviewScreenState extends State<StockTransferPreviewScreen> {
  final Set<String> _removeKeys = {};
  final TextEditingController _remarkCtrl = TextEditingController();

  /// Sparkle `showTransferPopup`
  bool _showTransferPopup = false;
  bool _submitting = false;
  String _transferredBy = '';
  String? _transferredToEmployeeId; // EmployeeId string for branch-to-branch

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pref = context.read<PrefService>();
      final employee = pref.getEmployee();
      setState(() {
        _transferredBy = employee?.userName ??
            employee?.firstName ??
            employee?.lastName ??
            context.sRead.tr('admin');
      });
      final vm = context.read<StockTransferViewModel>();
      if (vm.allEmployees.isEmpty) {
        vm.loadUserPermissions();
      }
    });
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    super.dispose();
  }

  String _itemKey(BulkItem item) {
    final code = item.itemCode.trim();
    return code.isNotEmpty ? code : item.rfid.trim();
  }

  void _toggleRemove(String key) {
    setState(() {
      if (_removeKeys.contains(key)) {
        _removeKeys.remove(key);
      } else {
        _removeKeys.add(key);
      }
    });
  }

  void _toggleSelectAll(List<BulkItem> items, bool? checked) {
    setState(() {
      _removeKeys.clear();
      if (checked == true) {
        for (final item in items) {
          _removeKeys.add(_itemKey(item));
        }
      }
    });
  }

  /// Sparkle: Transfer click → show TransferDetailsDialogNew immediately.
  void _openTransferPopup(StockTransferViewModel vm) {
    setState(() {
      _showTransferPopup = true;
      _transferredToEmployeeId = null;
      _remarkCtrl.clear();
      _submitting = false;
    });
    if (vm.isBranchToBranch && vm.allEmployees.isEmpty) {
      vm.loadUserPermissions();
    }
  }

  void _closeTransferPopup() {
    if (_submitting) return;
    setState(() => _showTransferPopup = false);
  }

  Future<void> _onTransferOk(StockTransferViewModel vm) async {
    final s = context.sRead;
    if (vm.isBranchToBranch &&
        (_transferredToEmployeeId == null || _transferredToEmployeeId!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('selectEmployeeError'))),
      );
      return;
    }

    setState(() => _submitting = true);
    final ok = await vm.submitTransfer(
      transferToEmployee: _transferredToEmployeeId ?? '',
      remarks: _remarkCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      setState(() => _showTransferPopup = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('transferSuccess'))),
      );
      final nav = Navigator.of(context);
      nav.pop(true);
      // Brief delay so backend commit is visible to GetAllStockTransfers.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await nav.pushNamed(
        '/stock_transfer_in_out',
        arguments: {'requestType': 'Out Request'},
      );
    } else {
      final msg = vm.transferStatusMessage?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((msg != null && msg.isNotEmpty) ? msg : s.tr('transferFailed'))),
      );
    }
  }

  Future<void> _pickEmployee(List<UserPermission> employees) async {
    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('selectEmployeeError'))),
      );
      return;
    }
    final picked = await showScrollableOptionSheet<UserPermission>(
      context: context,
      options: employees,
      labelOf: (e) => '${e.displayName} (${e.employeeId})',
      title: context.sRead.tr('selectEmployee'),
    );
    if (picked != null && mounted) {
      setState(() => _transferredToEmployeeId = picked.employeeId.toString());
    }
  }

  String _employeeLabel(List<UserPermission> employees) {
    final id = _transferredToEmployeeId;
    if (id == null || id.isEmpty) return context.sRead.tr('selectEmployee');
    for (final e in employees) {
      if (e.employeeId.toString() == id) return e.displayName;
    }
    return id;
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF3F51B5)]),
              borderRadius: BorderRadius.circular(10),
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
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransferDetailsPopup(
    StockTransferViewModel vm,
    List<UserPermission> employees,
  ) {
    final s = context.s;
    return Material(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB71C1C), Color(0xFF3F51B5)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.tr('transferDetails'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _readOnlyRow(s.tr('transferredBy'), _transferredBy),
                if (vm.isBranchToBranch) ...[
                  const SizedBox(height: 10),
                  _dropdownRow(
                    label: s.tr('transferredTo'),
                    value: _employeeLabel(employees),
                    isPlaceholder: _transferredToEmployeeId == null,
                    onTap: () => _pickEmployee(employees),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  color: const Color(0xFFF3F3F3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    s.remark,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(color: Colors.black54, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _remarkCtrl,
                  maxLines: 5,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    hintText: s.tr('remarkHint'),
                    filled: true,
                    fillColor: const Color(0xFFF7F7F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(2),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _gradientButton(
                        s.tr('cancel'),
                        _submitting ? null : _closeTransferPopup,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _gradientButton(
                        s.tr('ok'),
                        _submitting ? null : () => _onTransferOk(vm),
                        loading: _submitting,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _readOnlyRow(String label, String value) {
    return Row(
      children: [
        Expanded(child: _labelBox(label)),
        const SizedBox(width: 8),
        Expanded(child: _valueBox(value)),
      ],
    );
  }

  Widget _dropdownRow({
    required String label,
    required String value,
    required bool isPlaceholder,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Expanded(child: _labelBox(label)),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: isPlaceholder ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.black54),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _labelBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: GoogleFonts.poppins(color: Colors.black54, fontSize: 14)),
    );
  }

  Widget _valueBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAEAEA),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: GoogleFonts.poppins(color: Colors.grey, fontSize: 14)),
    );
  }

  Widget _gradientButton(String text, VoidCallback? onTap, {bool loading = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: onTap == null && !loading
              ? null
              : const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF3F51B5)]),
          color: onTap == null && !loading ? Colors.grey.shade400 : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                text,
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockTransferViewModel>();
    final s = context.s;
    final items = vm.previewItems;
    final selectedRemove = items.where((i) => _removeKeys.contains(_itemKey(i))).toList();
    final totalGross =
        selectedRemove.fold(0.0, (sum, i) => sum + (double.tryParse(i.grossWeight) ?? 0));
    final totalNet =
        selectedRemove.fold(0.0, (sum, i) => sum + (double.tryParse(i.netWeight) ?? 0));
    final allChecked =
        items.isNotEmpty && items.every((i) => _removeKeys.contains(_itemKey(i)));
    final employees = vm.isBranchToBranch
        ? vm.employeesForDestinationBranch(vm.destinationBranchId)
        : const <UserPermission>[];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: productGradientAppBar(context: context, title: s.tr('transferPreview')),
      body: Stack(
        children: [
          Column(
            children: [
              if (items.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      s.tr('selectItemsToTransfer'),
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                )
              else ...[
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Checkbox(
                          value: allChecked,
                          onChanged: (v) => _toggleSelectAll(items, v),
                          fillColor: WidgetStateProperty.all(Colors.white),
                          checkColor: Colors.black,
                        ),
                      ),
                      Expanded(flex: 3, child: Text(s.tr('productName'), style: _header())),
                      Expanded(flex: 2, child: Text(s.tr('itemCodeLabel'), style: _header())),
                      Expanded(
                        child: Text(s.tr('grossWt'), style: _header(), textAlign: TextAlign.center),
                      ),
                      Expanded(
                        child: Text(s.tr('netWt'), style: _header(), textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final key = _itemKey(item);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              child: Checkbox(
                                value: _removeKeys.contains(key),
                                onChanged: (_) => _toggleRemove(key),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                item.productName,
                                style: _cell(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                item.rfid.isNotEmpty ? item.rfid : item.itemCode,
                                style: _cell(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.grossWeight,
                                style: _cell(),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.netWeight,
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
              ],
              Container(
                color: Colors.grey[100],
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${s.tr('totalQty')}: ${items.length}',
                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${s.tr('selectedQty')}: ${selectedRemove.length}',
                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${s.tr('grossWt')}: ${totalGross.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(fontSize: 11),
                    ),
                    Text(
                      '${s.tr('netWt')}: ${totalNet.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(fontSize: 11),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    children: [
                      _actionButton(
                        label: s.transfer,
                        icon: Icons.compare_arrows,
                        onTap: items.isEmpty ? () {} : () => _openTransferPopup(vm),
                      ),
                      const SizedBox(width: 6),
                      _actionButton(
                        label: s.tr('inRequest'),
                        icon: Icons.arrow_downward,
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/stock_transfer_in_out',
                          arguments: {'requestType': 'In Request'},
                        ),
                      ),
                      const SizedBox(width: 6),
                      _actionButton(
                        label: s.tr('outRequest'),
                        icon: Icons.arrow_upward,
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/stock_transfer_in_out',
                          arguments: {'requestType': 'Out Request'},
                        ),
                      ),
                      const SizedBox(width: 6),
                      _actionButton(
                        label: s.delete,
                        icon: Icons.delete_outline,
                        onTap: () {
                          if (_removeKeys.isEmpty) return;
                          vm.removePreviewItemsByKeys(_removeKeys);
                          setState(() => _removeKeys.clear());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Sparkle `if (showTransferPopup) TransferDetailsDialogNew(...)`
          if (_showTransferPopup) _buildTransferDetailsPopup(vm, employees),
        ],
      ),
    );
  }

  TextStyle _header() =>
      GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10);
  TextStyle _cell() => GoogleFonts.poppins(fontSize: 10, color: Colors.black87);
}
