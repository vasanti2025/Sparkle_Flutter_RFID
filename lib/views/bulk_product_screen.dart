import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../services/pref_service.dart';
import '../viewmodels/bulk_product_view_model.dart';
import 'widgets/product_form_widgets.dart';
import 'widgets/scan_bottom_bar.dart';

class BulkProductScreen extends StatefulWidget {
  const BulkProductScreen({super.key});

  @override
  State<BulkProductScreen> createState() => _BulkProductScreenState();
}

class _BulkProductScreenState extends State<BulkProductScreen> {
  String _category = '';
  String _product = '';
  String _design = '';
  bool _applyItemCodeToAll = false;
  bool _applyRfidToAll = false;
  int _power = 5;
  final Map<int, TextEditingController> _itemCodeCtrls = {};
  final Map<int, TextEditingController> _rfidCtrls = {};
  StreamSubscription<void>? _triggerSub;

  static const _typeKeys = {
    'Category': 'fieldCategory',
    'Product': 'fieldProduct',
    'Design': 'fieldDesign',
  };

  String _typeLabel(BuildContext context, String type) =>
      context.s.tr(_typeKeys[type] ?? type);

  @override
  void initState() {
    super.initState();
    _power = context.read<PrefService>().productPower;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<BulkProductViewModel>();
      vm.loadDropdowns();
      _triggerSub = vm.rfidService.triggerStream.listen((_) {
        if (!mounted) return;
        if (vm.isScanning) {
          vm.stopScanning();
        } else {
          _toggleGscan(vm);
        }
      });
    });
  }

  Future<void> _showAddDialog(String type, BulkProductViewModel vm) async {
    final s = context.sRead;
    final typeLabel = _typeLabel(context, type);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.tr('addType', args: {'type': typeLabel}), style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: s.tr('enterTypeName', args: {'type': typeLabel}),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.tr('addBtn'))),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      switch (type) {
        case 'Category':
          await vm.addLocalCategory(ctrl.text.trim());
          if (mounted) setState(() => _category = ctrl.text.trim());
          break;
        case 'Product':
          await vm.addLocalProduct(ctrl.text.trim());
          if (mounted) setState(() => _product = ctrl.text.trim());
          break;
        case 'Design':
          await vm.addLocalDesign(ctrl.text.trim());
          if (mounted) setState(() => _design = ctrl.text.trim());
          break;
      }
    }
    ctrl.dispose();
  }

  Future<void> _toggleGscan(BulkProductViewModel vm) async {
    if (vm.isScanning && vm.isBulkMode) {
      await vm.stopScanning();
      return;
    }
    if (vm.isScanning) await vm.stopScanning();
    vm.setBulkMode(true);
    final started = await vm.startScanning(power: _power);
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('failedToStartRfidScanner'))),
      );
    }
  }

  Future<void> _singleScan(BulkProductViewModel vm) async {
    if (vm.isScanning && !vm.isBulkMode) {
      await vm.stopScanning();
      return;
    }
    if (vm.isScanning) await vm.stopScanning();
    vm.setBulkMode(false);
    final started = await vm.startScanning(power: _power);
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('failedToStartRfidScanner'))),
      );
    }
  }

  Future<void> _save(BulkProductViewModel vm) async {
    if (_category.isEmpty || _product.isEmpty || _design.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('pleaseSelectCategoryProductDesign'))),
      );
      return;
    }

    for (final entry in _itemCodeCtrls.entries) {
      vm.setItemCode(entry.key, entry.value.text);
    }
    for (final entry in _rfidCtrls.entries) {
      vm.setRfidCode(entry.key, entry.value.text);
    }

    final ok = await vm.saveAllBulkProductRows(
      category: _category,
      product: _product,
      design: _design,
    );
    if (!mounted) return;
    final s = context.sRead;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('itemsSavedSuccessfully'))),
      );
      vm.resetScanResults();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('addScannedTagsBeforeSaving'))),
      );
    }
  }

  TextEditingController _itemCtrl(int index, BulkProductViewModel vm) {
    return _itemCodeCtrls.putIfAbsent(
      index,
      () => TextEditingController(text: vm.itemCodes[index] ?? ''),
    );
  }

  TextEditingController _rfidCtrl(int index, BulkProductViewModel vm) {
    return _rfidCtrls.putIfAbsent(
      index,
      () => TextEditingController(text: vm.rfidCodes[index] ?? ''),
    );
  }

  void _syncControllers(BulkProductViewModel vm) {
    while (_itemCodeCtrls.length > vm.scannedTags.length) {
      _itemCodeCtrls.remove(_itemCodeCtrls.keys.last)?.dispose();
    }
    while (_rfidCtrls.length > vm.scannedTags.length) {
      _rfidCtrls.remove(_rfidCtrls.keys.last)?.dispose();
    }
  }

  @override
  void dispose() {
    _triggerSub?.cancel();
    for (final c in _itemCodeCtrls.values) {
      c.dispose();
    }
    for (final c in _rfidCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _bulkCheckbox({required bool value, required ValueChanged<bool> onChanged}) {
    return SizedBox(
      height: 22,
      width: 22,
      child: Checkbox(
        activeColor: Colors.white,
        checkColor: Colors.grey[800],
        value: value,
        side: BorderSide(color: Colors.white.withValues(alpha: value ? 1 : 0.7), width: 1.5),
        onChanged: (v) => onChanged(v ?? false),
      ),
    );
  }

  Widget _headerCell(String label, {bool withCheckbox = false, bool? checkboxValue, ValueChanged<bool>? onCheckboxChanged}) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (withCheckbox) ...[
            _bulkCheckbox(value: checkboxValue ?? false, onChanged: onCheckboxChanged ?? (_) {}),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final vm = context.watch<BulkProductViewModel>();
    _syncControllers(vm);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: productGradientAppBar(
        context: context,
        title: s.tr('addBulkProducts'),
        showCounter: true,
        selectedCount: _power,
        onCountSelected: (v) {
          setState(() => _power = v);
          context.read<PrefService>().savePower(PrefService.keyProductCount, v);
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: FilterDropdown(
                    label: s.tr('fieldCategory'),
                    options: vm.categories,
                    selected: _category,
                    onSelected: (v) => setState(() => _category = v),
                    onAdd: () => _showAddDialog('Category', vm),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilterDropdown(
                    label: s.tr('fieldProduct'),
                    options: vm.products,
                    selected: _product,
                    onSelected: (v) => setState(() => _product = v),
                    onAdd: () => _showAddDialog('Product', vm),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilterDropdown(
                    label: s.tr('fieldDesign'),
                    options: vm.designs,
                    selected: _design,
                    onSelected: (v) => setState(() => _design = v),
                    onAdd: () => _showAddDialog('Design', vm),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.grey[800],
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    s.tr('headerSr'),
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
                _headerCell(
                  s.tr('itemCode'),
                  withCheckbox: true,
                  checkboxValue: _applyItemCodeToAll,
                  onCheckboxChanged: (v) => setState(() => _applyItemCodeToAll = v),
                ),
                _headerCell(
                  s.tr('rfidCode'),
                  withCheckbox: true,
                  checkboxValue: _applyRfidToAll,
                  onCheckboxChanged: (v) => setState(() => _applyRfidToAll = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: vm.scannedTags.isEmpty
                ? Center(
                    child: Text(s.tr('scanTagsToAddRows'), style: GoogleFonts.poppins(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: vm.scannedTags.length,
                    itemBuilder: (context, index) {
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 44,
                                  height: 36,
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey[800]),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SizedBox(
                                    height: 36,
                                    child: BulkInlineTextField(
                                      controller: _itemCtrl(index, vm),
                                      onChanged: (v) {
                                        final normalized = v.toUpperCase();
                                        vm.setItemCode(index, normalized);
                                        if (_applyItemCodeToAll) {
                                          for (var i = 0; i < vm.scannedTags.length; i++) {
                                            vm.setItemCode(i, normalized);
                                            _itemCtrl(i, vm).text = normalized;
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SizedBox(
                                    height: 36,
                                    child: BulkInlineTextField(
                                      controller: _rfidCtrl(index, vm),
                                      onChanged: (v) {
                                        final normalized = v.toUpperCase();
                                        vm.setRfidCode(index, normalized);
                                        if (_applyRfidToAll) {
                                          for (var i = 0; i < vm.scannedTags.length; i++) {
                                            vm.setRfidCode(i, normalized);
                                            _rfidCtrl(i, vm).text = normalized;
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 0.6, thickness: 0.6, color: Colors.grey[300]),
                        ],
                      );
                    },
                  ),
          ),
          ScanBottomBar(
            onSave: () => _save(vm),
            onList: () => Navigator.pushNamed(context, '/product_list'),
            onScan: () => _singleScan(vm),
            onGscan: () => _toggleGscan(vm),
            onReset: () {
              vm.stopScanning();
              vm.resetScanResults();
              for (final c in _itemCodeCtrls.values) {
                c.dispose();
              }
              for (final c in _rfidCtrls.values) {
                c.dispose();
              }
              _itemCodeCtrls.clear();
              _rfidCtrls.clear();
              setState(() {
                _applyItemCodeToAll = false;
                _applyRfidToAll = false;
              });
            },
            isScanning: vm.isScanning && !vm.isBulkMode,
            isBulkScanning: vm.isScanning && vm.isBulkMode,
          ),
        ],
      ),
    );
  }
}
