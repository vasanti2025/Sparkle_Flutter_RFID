import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../services/pref_service.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import 'widgets/product_form_widgets.dart';
import 'widgets/stock_transfer_submit_dialog.dart';

class StockTransferPreviewScreen extends StatefulWidget {
  const StockTransferPreviewScreen({super.key});

  @override
  State<StockTransferPreviewScreen> createState() => _StockTransferPreviewScreenState();
}

class _StockTransferPreviewScreenState extends State<StockTransferPreviewScreen> {
  final Set<String> _removeKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<StockTransferViewModel>();
      if (vm.allEmployees.isEmpty) {
        vm.loadUserPermissions();
      }
    });
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

  Future<void> _showTransferDialog(StockTransferViewModel vm) async {
    final s = context.s;
    final employee = context.read<PrefService>().getEmployee();
    final transferredBy = employee?.userName ??
        employee?.firstName ??
        employee?.lastName ??
        s.tr('admin');
    final employees = vm.employeesForDestinationBranch(vm.destinationBranchId);

    final ok = await showStockTransferSubmitDialog(
      context: context,
      isBranchToBranch: vm.isBranchToBranch,
      transferredBy: transferredBy,
      employees: employees,
      onSubmit: (transferToEmployeeId, remarks) async {
        final destBranch = vm.destinationBranchId?.toString() ??
            employee?.defaultBranchId.toString() ??
            '';
        return vm.submitTransfer(
          transferByEmployee: transferredBy,
          transferToEmployee: transferToEmployeeId,
          transferedToBranch: destBranch,
          receivedByEmployee: '',
          remarks: remarks,
        );
      },
    );
    if (!mounted) return;
    if (ok == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('transferSuccess'))),
      );
      Navigator.pop(context);
    } else if (ok == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('transferFailed'))),
      );
    }
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
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
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
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
    final totalGross = selectedRemove.fold(0.0, (sum, i) => sum + (double.tryParse(i.grossWeight) ?? 0));
    final totalNet = selectedRemove.fold(0.0, (sum, i) => sum + (double.tryParse(i.netWeight) ?? 0));
    final allChecked = items.isNotEmpty && items.every((i) => _removeKeys.contains(_itemKey(i)));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: productGradientAppBar(context: context, title: s.tr('transferPreview')),
      body: items.isEmpty
          ? Center(child: Text(s.tr('selectItemsToTransfer'), style: GoogleFonts.poppins()))
          : Column(
              children: [
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
                      Expanded(child: Text(s.tr('grossWt'), style: _header(), textAlign: TextAlign.center)),
                      Expanded(child: Text(s.tr('netWt'), style: _header(), textAlign: TextAlign.center)),
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
                            Expanded(flex: 3, child: Text(item.productName, style: _cell(), maxLines: 2, overflow: TextOverflow.ellipsis)),
                            Expanded(flex: 2, child: Text(item.rfid.isNotEmpty ? item.rfid : item.itemCode, style: _cell(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Expanded(child: Text(item.grossWeight, style: _cell(), textAlign: TextAlign.center)),
                            Expanded(child: Text(item.netWeight, style: _cell(), textAlign: TextAlign.center)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  color: Colors.grey[100],
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${s.tr('totalQty')}: ${items.length}', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600)),
                      Text('${s.tr('selectedQty')}: ${selectedRemove.length}', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600)),
                      Text('${s.tr('grossWt')}: ${totalGross.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 11)),
                      Text('${s.tr('netWt')}: ${totalNet.toStringAsFixed(2)}', style: GoogleFonts.poppins(fontSize: 11)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    children: [
                      _actionButton(
                        label: s.transfer,
                        icon: Icons.compare_arrows,
                        onTap: () => _showTransferDialog(vm),
                      ),
                      _actionButton(
                        label: s.tr('inRequest'),
                        icon: Icons.arrow_downward,
                        onTap: () => Navigator.pushNamed(context, '/stock_transfer_in_out', arguments: {'requestType': 'In Request'}),
                      ),
                      _actionButton(
                        label: s.tr('outRequest'),
                        icon: Icons.arrow_upward,
                        onTap: () => Navigator.pushNamed(context, '/stock_transfer_in_out', arguments: {'requestType': 'Out Request'}),
                      ),
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
              ],
            ),
    );
  }

  TextStyle _header() => GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10);
  TextStyle _cell() => GoogleFonts.poppins(fontSize: 10, color: Colors.black87);
}
