import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../services/pref_service.dart';
import '../utils/barcode_scan_mixin.dart';
import '../viewmodels/bulk_product_view_model.dart';
import 'widgets/product_form_widgets.dart';
import 'widgets/scan_bottom_bar.dart';

class BulkProductScreen extends StatefulWidget {
  const BulkProductScreen({super.key});

  @override
  State<BulkProductScreen> createState() => _BulkProductScreenState();
}

class _BulkProductScreenState extends State<BulkProductScreen> with BarcodeScanMixin {
  String _category = '';
  String _product = '';
  String _design = '';
  String? _addFor;
  bool _applyItemCodeToAll = false;
  bool _applyRfidToAll = false;
  int _power = 5;
  bool _scanBusy = false;
  bool _fillingAll = false;
  int _lastTriggerMs = 0;
  final Map<int, TextEditingController> _itemCodeCtrls = {};
  final Map<int, TextEditingController> _rfidCtrls = {};
  StreamSubscription<void>? _triggerSub;
  BulkProductViewModel? _vm;

  static final TextStyle _rowStyle = GoogleFonts.bodoniModa(fontSize: 11, color: const Color(0xFF424242));
  static final TextStyle _headerStyle = GoogleFonts.bodoniModa(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white);
  static final TextStyle _emptyStyle = GoogleFonts.bodoniModa(color: Colors.grey);

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final vm = context.read<BulkProductViewModel>();
      _vm = vm;
      if (vm.isScanning) {
        await vm.stopScanning();
      }
      unawaited(vm.loadDropdowns());
      bindBarcodeScanner();
      _triggerSub = vm.rfidService.triggerStream.listen((_) {
        if (!mounted || _scanBusy) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastTriggerMs < 300) return;
        _lastTriggerMs = now;
        final currentVm = context.read<BulkProductViewModel>();
        if (currentVm.isScanning) {
          unawaited(_stopAllScan(currentVm));
        } else {
          unawaited(_toggleGscan(currentVm));
        }
      });
    });
  }

  Future<void> _stopAllScan(BulkProductViewModel vm) async {
    if (_scanBusy) return;
    _scanBusy = true;
    try {
      await vm.stopScanning();
      vm.setBulkMode(false);
    } finally {
      _scanBusy = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void onBarcodeScanned(String code) {
    final vm = _vm;
    if (vm == null || !mounted) return;
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return;

    final count = vm.tagCount;
    var index = vm.lastClickedIndex ?? -1;
    if (index < 0 || (count > 0 && index >= count)) {
      index = 0;
      for (var i = 0; i < count; i++) {
        final current = (_rfidCtrls[i]?.text ?? vm.rfidCodes[i] ?? '').trim();
        if (current.isEmpty) {
          index = i;
          break;
        }
      }
    }
    final target = index;
    vm.setLastClickedIndex(target);
    final ctrl = _rfidCtrls[target];
    if (ctrl != null && ctrl.text != normalized) {
      ctrl.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    _applyRfid(vm, target, normalized);
    unawaited(barcodeRfid.stopBarcodeScan());
  }

  void _openAddDialog(String type) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _addFor = type);
    });
  }

  Future<void> _commitAdd(String name, BulkProductViewModel vm) async {
    final type = _addFor;
    if (type == null) return;
    setState(() => _addFor = null);
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      switch (type) {
        case 'Category':
          await vm.addLocalCategory(trimmed);
          if (mounted) setState(() => _category = trimmed);
          break;
        case 'Product':
          await vm.addLocalProduct(trimmed);
          if (mounted) setState(() => _product = trimmed);
          break;
        case 'Design':
          await vm.addLocalDesign(trimmed);
          if (mounted) setState(() => _design = trimmed);
          break;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('enterTypeName', args: {'type': _typeLabel(context, type)}))),
      );
    }
  }

  Future<void> _toggleGscan(BulkProductViewModel vm) async {
    if (_scanBusy) return;

    if (vm.isScanning && vm.isBulkMode) {
      await _stopAllScan(vm);
      return;
    }

    _scanBusy = true;
    if (mounted) setState(() {});
    try {
      if (vm.isScanning) await vm.stopScanning();
      vm.setBulkMode(true);
      final started = await vm.startScanning(power: _power);
      if (!started && mounted) {
        vm.setBulkMode(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.sRead.tr('failedToStartRfidScanner'))),
        );
      }
    } finally {
      _scanBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _singleScan(BulkProductViewModel vm) async {
    if (_scanBusy) return;

    if (vm.isScanning && !vm.isBulkMode) {
      await _stopAllScan(vm);
      return;
    }

    _scanBusy = true;
    if (mounted) setState(() {});
    try {
      if (vm.isScanning) await vm.stopScanning();
      vm.setBulkMode(false);
      final started = await vm.startScanning(power: _power, playStartSound: false);
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.sRead.tr('failedToStartRfidScanner'))),
        );
      }
    } finally {
      _scanBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _resetAll(BulkProductViewModel vm) async {
    if (_scanBusy) return;
    _scanBusy = true;
    if (mounted) setState(() {});
    try {
      await vm.resetScanResults();
      for (final c in _itemCodeCtrls.values) {
        c.dispose();
      }
      for (final c in _rfidCtrls.values) {
        c.dispose();
      }
      _itemCodeCtrls.clear();
      _rfidCtrls.clear();
      if (mounted) {
        setState(() {
          _applyItemCodeToAll = false;
          _applyRfidToAll = false;
        });
      }
    } finally {
      _scanBusy = false;
      if (mounted) setState(() {});
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
      await vm.resetScanResults();
      for (final c in _itemCodeCtrls.values) {
        c.dispose();
      }
      for (final c in _rfidCtrls.values) {
        c.dispose();
      }
      _itemCodeCtrls.clear();
      _rfidCtrls.clear();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('addScannedTagsBeforeSaving'))),
      );
    }
  }

  void _applyItemCode(BulkProductViewModel vm, int index, String value) {
    if (_fillingAll) return;
    final normalized = value.toUpperCase();
    vm.setItemCode(index, normalized);
    if (!_applyItemCodeToAll) return;
    _fillingAll = true;
    final count = vm.tagCount;
    for (var i = 0; i < count; i++) {
      vm.setItemCode(i, normalized);
    }
    for (final entry in _itemCodeCtrls.entries) {
      if (entry.value.text != normalized) entry.value.text = normalized;
    }
    _fillingAll = false;
  }

  void _applyRfid(BulkProductViewModel vm, int index, String value) {
    if (_fillingAll) return;
    final normalized = value.toUpperCase();
    vm.setRfidCode(index, normalized);
    if (!_applyRfidToAll) return;
    _fillingAll = true;
    final count = vm.tagCount;
    for (var i = 0; i < count; i++) {
      vm.setRfidCode(i, normalized);
    }
    for (final entry in _rfidCtrls.entries) {
      if (entry.value.text != normalized) entry.value.text = normalized;
    }
    _fillingAll = false;
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
    final count = vm.tagCount;
    if (_itemCodeCtrls.length <= count && _rfidCtrls.length <= count) return;
    while (_itemCodeCtrls.length > count) {
      _itemCodeCtrls.remove(_itemCodeCtrls.keys.last)?.dispose();
    }
    while (_rfidCtrls.length > count) {
      _rfidCtrls.remove(_rfidCtrls.keys.last)?.dispose();
    }
  }

  @override
  void dispose() {
    unbindBarcodeScanner();
    _triggerSub?.cancel();
    unawaited(_vm?.stopScanning());
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
              style: _headerStyle,
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

    return Scaffold(
      backgroundColor: const Color(0xFFF6F4F0),
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
      body: Stack(
        children: [
          Column(
            children: [
              Selector<BulkProductViewModel, int>(
                selector: (_, vm) => vm.dropdownVersion,
                builder: (context, _, child) {
                  final vm = context.read<BulkProductViewModel>();
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilterDropdown(
                            label: s.tr('fieldCategory'),
                            options: vm.categories,
                            selected: _category,
                            onSelected: (v) => setState(() => _category = v),
                            onAdd: () => _openAddDialog('Category'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilterDropdown(
                            label: s.tr('fieldProduct'),
                            options: vm.products,
                            selected: _product,
                            onSelected: (v) => setState(() => _product = v),
                            onAdd: () => _openAddDialog('Product'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilterDropdown(
                            label: s.tr('fieldDesign'),
                            options: vm.designs,
                            selected: _design,
                            onSelected: (v) => setState(() => _design = v),
                            onAdd: () => _openAddDialog('Design'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
                    style: _headerStyle,
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
            child: Selector<BulkProductViewModel, int>(
              selector: (_, vm) => vm.listVersion,
              builder: (context, _, child) {
                final vm = context.read<BulkProductViewModel>();
                _syncControllers(vm);
                if (vm.tagCount == 0) {
                  return Center(child: Text(s.tr('scanTagsToAddRows'), style: _emptyStyle));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemExtent: 40,
                  itemCount: vm.tagCount,
                  itemBuilder: (context, index) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text('${index + 1}', style: _rowStyle, textAlign: TextAlign.center),
                            ),
                            Expanded(
                              child: BulkInlineTextField(
                                controller: _itemCtrl(index, vm),
                                onFocus: () => vm.setLastClickedIndex(index),
                                onChanged: (v) => _applyItemCode(vm, index, v),
                              ),
                            ),
                            Expanded(
                              child: BulkInlineTextField(
                                controller: _rfidCtrl(index, vm),
                                onFocus: () => vm.setLastClickedIndex(index),
                                onChanged: (v) => _applyRfid(vm, index, v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Selector<BulkProductViewModel, (bool, bool)>(
            selector: (_, vm) => (vm.isScanning, vm.isBulkMode),
            builder: (context, flags, child) {
              final vm = context.read<BulkProductViewModel>();
              return ScanBottomBar(
                onSave: () => _save(vm),
                onList: () => Navigator.pushNamed(context, '/product_list'),
                onScan: () => unawaited(_singleScan(vm)),
                onGscan: () => unawaited(_toggleGscan(vm)),
                onReset: () => unawaited(_resetAll(vm)),
                isScanning: flags.$1 && !flags.$2,
                isBulkScanning: flags.$1 && flags.$2,
              );
            },
          ),
        ],
      ),
          if (_addFor != null)
            _BulkAddNameDialog(
              heading: context.s.tr('addType', args: {'type': _typeLabel(context, _addFor!)}),
              hint: context.s.tr('enterTypeName', args: {'type': _typeLabel(context, _addFor!)}),
              addLabel: context.s.tr('addBtn'),
              cancelLabel: context.s.tr('cancel'),
              onDismiss: () => setState(() => _addFor = null),
              onAdd: (name) => unawaited(_commitAdd(name, context.read<BulkProductViewModel>())),
            ),
        ],
      ),
    );
  }
}

class _BulkAddNameDialog extends StatefulWidget {
  final String heading;
  final String hint;
  final String addLabel;
  final String cancelLabel;
  final VoidCallback onDismiss;
  final ValueChanged<String> onAdd;

  const _BulkAddNameDialog({
    required this.heading,
    required this.hint,
    required this.addLabel,
    required this.cancelLabel,
    required this.onDismiss,
    required this.onAdd,
  });

  @override
  State<_BulkAddNameDialog> createState() => _BulkAddNameDialogState();
}

class _BulkAddNameDialogState extends State<_BulkAddNameDialog> {
  final TextEditingController _ctrl = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = true);
      return;
    }
    widget.onAdd(name);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Material(
        color: const Color(0x8A000000),
        child: Center(
          child: AlertDialog(
            title: Text(widget.heading, style: GoogleFonts.bodoniModa(fontWeight: FontWeight.bold)),
            content: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_error) setState(() => _error = false);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: widget.hint,
                errorText: _error ? widget.hint : null,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(onPressed: widget.onDismiss, child: Text(widget.cancelLabel)),
              TextButton(onPressed: _submit, child: Text(widget.addLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
