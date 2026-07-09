import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../viewmodels/product_view_model.dart';
import '../viewmodels/single_product_view_model.dart';
import '../utils/tag_scan_batcher.dart';
import 'widgets/product_form_row.dart';
import 'widgets/product_form_widgets.dart';
import 'widgets/scan_bottom_bar.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _rfidService = RfidService();
  StreamSubscription<String>? _tagSub;
  StreamSubscription<void>? _triggerSub;

  final Map<String, String> _fields = {};
  bool _isScanning = false;
  bool _isBulkScanning = false;
  int _power = 5;
  late final TagScanBatcher _tagBatcher;

  static const _fieldOrder = [
    'EPC',
    'Vendor',
    'SKU',
    'RFID Code',
    'Category',
    'Product',
    'Design',
    'Purity',
    'Gross Weight',
    'Stone Weight',
    'Diamond Weight',
    'Net Weight',
    'Making/Gram',
    'Making %',
    'Fix Making',
    'Fix Wastage',
    'Stone Amount',
    'Diamond Amount',
  ];

  static const _fieldLabelKeys = {
    'EPC': 'fieldEpc',
    'Vendor': 'fieldVendor',
    'SKU': 'fieldSku',
    'RFID Code': 'fieldRfidCode',
    'Category': 'fieldCategory',
    'Product': 'fieldProduct',
    'Design': 'fieldDesign',
    'Purity': 'fieldPurity',
    'Gross Weight': 'fieldGrossWeight',
    'Stone Weight': 'fieldStoneWeight',
    'Diamond Weight': 'fieldDiamondWeight',
    'Net Weight': 'fieldNetWeight',
    'Making/Gram': 'fieldMakingGram',
    'Making %': 'fieldMakingPercent',
    'Fix Making': 'fieldFixMaking',
    'Fix Wastage': 'fieldFixWastage',
    'Stone Amount': 'fieldStoneAmount',
    'Diamond Amount': 'fieldDiamondAmount',
  };

  String _displayLabel(BuildContext context, String field) =>
      context.s.tr(_fieldLabelKeys[field] ?? field);

  static const _dropdowns = {'Vendor', 'SKU', 'Category', 'Product', 'Design', 'Purity'};

  @override
  void initState() {
    super.initState();
    _power = context.read<PrefService>().productPower;
    _tagBatcher = TagScanBatcher(
      onFlush: (tags) {
        if (!mounted || tags.isEmpty) return;
        setState(() => _updateField('EPC', tags.last.trim().toUpperCase()));
        if (_isBulkScanning) return;
        _stopScanning();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SingleProductViewModel>().loadMasterData();
    });
    _tagSub = _rfidService.tagsStream.listen((epc) {
      if (epc.trim().isEmpty || !mounted) return;
      _tagBatcher.add(epc);
      if (!_isBulkScanning) {
        _tagBatcher.flushNow();
      }
    });
    _triggerSub = _rfidService.triggerStream.listen((_) {
      if (!mounted) return;
      if (_rfidService.isScanning) {
        _stopScanning();
      } else {
        _startGscan();
      }
    });
  }

  @override
  void dispose() {
    _tagBatcher.dispose();
    _tagSub?.cancel();
    _triggerSub?.cancel();
    _rfidService.stopScanning();
    super.dispose();
  }

  String _get(String label) => _fields[label] ?? '';

  void _updateField(String label, String value) {
    _fields[label] = value;

    if (label == 'RFID Code') {
      _fields[label] = value.toUpperCase();
    }

    if (label == 'Gross Weight' || label == 'Stone Weight' || label == 'Diamond Weight') {
      _recalculateNetWeight();
    }

    if (label == 'Vendor') _fields['SKU'] = '';
    if (label == 'Category') {
      _fields['Product'] = '';
      _fields['Design'] = '';
      _fields['Purity'] = '';
    }
    if (label == 'Product') {
      _fields['Design'] = '';
      _fields['Purity'] = '';
    }
    if (label == 'Design') _fields['Purity'] = '';
  }

  bool get _skuLocked => _get('SKU').isNotEmpty;

  List<String> _optionsFor(String label, SingleProductViewModel vm) {
    List<String> raw;
    switch (label) {
      case 'Vendor':
        raw = vm.vendors.map((v) => v.name).where((n) => n.isNotEmpty).toList();
        break;
      case 'SKU':
        if (_get('Vendor').isEmpty) return [];
        raw = vm.skusForVendor(_get('Vendor')).map((s) => s.sku).where((n) => n.isNotEmpty).toList();
        break;
      case 'Category':
        raw = vm.categories.map((c) => c.name).where((n) => n.isNotEmpty).toList();
        break;
      case 'Product':
        if (_get('Category').isEmpty) return [];
        final catId = vm.categoryByName(_get('Category'))?.id ?? 0;
        raw = vm.productsForCategory(catId).map((p) => p.name).where((n) => n.isNotEmpty).toList();
        break;
      case 'Design':
        if (_get('Product').isEmpty) return [];
        final prodId = vm.productByName(_get('Product'))?.id ?? 0;
        raw = vm.designsForProduct(prodId).map((d) => d.name).where((n) => n.isNotEmpty).toList();
        break;
      case 'Purity':
        if (_get('Design').isEmpty) return [];
        final catId = vm.categoryByName(_get('Category'))?.id ?? 0;
        raw = vm.puritiesForCategory(catId).map((p) => p.name).where((n) => n.isNotEmpty).toList();
        break;
      default:
        return [];
    }
    return raw.toSet().toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void _applySku(SingleProductViewModel vm, String skuName) {
    final sku = vm.skuByName(skuName, vendorName: _get('Vendor'));
    if (sku == null) return;
    for (final c in vm.categories) {
      if (c.id == sku.categoryId) _fields['Category'] = c.name;
    }
    for (final p in vm.products) {
      if (p.id == sku.productId) _fields['Product'] = p.name;
    }
    for (final d in vm.designs) {
      if (d.id == sku.designId) _fields['Design'] = d.name;
    }
    for (final p in vm.purities) {
      if (p.id == sku.purityId) _fields['Purity'] = p.name;
    }
  }

  void _recalculateNetWeight() {
    _fields['Net Weight'] = SingleProductViewModel.calculateNetWeight(
      _get('Gross Weight'),
      _get('Stone Weight'),
      _get('Diamond Weight'),
    );
  }

  void _showDropdownHint(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _emptyDropdownHint(String label, BuildContext context) {
    final s = context.s;
    switch (label) {
      case 'SKU':
        if (_get('Vendor').isEmpty) return s.tr('selectVendorFirst');
        return s.tr('noItemsInCurrentScope');
      case 'Product':
        return s.categoryFirst;
      case 'Design':
        return s.productFirst;
      case 'Purity':
        return s.designFirst;
      default:
        return s.select;
    }
  }

  Future<void> _stopScanning() async {
    await _rfidService.stopScanning();
    if (mounted) {
      setState(() {
        _isScanning = false;
        _isBulkScanning = false;
      });
    }
  }

  Future<void> _startSingleScan() async {
    if (_isScanning && !_isBulkScanning) {
      await _stopScanning();
      return;
    }
    if (_isScanning) await _rfidService.stopScanning();
    _isBulkScanning = false;
    final started = await _rfidService.startScanning(power: _power);
    if (mounted) {
      setState(() => _isScanning = started);
    }
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('failedToStartRfidScanner'))),
      );
    }
  }

  Future<void> _startGscan() async {
    if (_isScanning && _isBulkScanning) {
      await _stopScanning();
      return;
    }
    if (_isScanning) await _rfidService.stopScanning();
    _isBulkScanning = true;
    final started = await _rfidService.startScanning(power: _power);
    if (mounted) {
      setState(() => _isScanning = started);
    }
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('failedToStartRfidScanner'))),
      );
    }
  }

  void _resetForm() {
    _stopScanning();
    setState(() {
      _fields.clear();
      _isBulkScanning = false;
    });
  }

  Future<void> _save(SingleProductViewModel vm) async {
    _recalculateNetWeight();
    final cat = vm.categoryByName(_get('Category'));
    final prod = vm.productByName(_get('Product'));
    final des = vm.designByName(_get('Design'));
    final pur = vm.purityByName(_get('Purity'));
    final ven = vm.vendorByName(_get('Vendor'));
    final sku = vm.skuByName(_get('SKU'), vendorName: _get('Vendor'));

    if (cat == null || prod == null || des == null || pur == null || ven == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('pleaseSelectVendorCategoryProductDesignPurity'))),
      );
      return;
    }
    if (_get('EPC').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.sRead.tr('epcRequired'))),
      );
      return;
    }

    final ok = await vm.saveProduct(
      categoryId: cat.id,
      productId: prod.id,
      designId: des.id,
      vendorId: ven.id,
      purityId: pur.id,
      rfidCode: _get('RFID Code').trim(),
      epc: _get('EPC').trim().toUpperCase(),
      grossWt: _get('Gross Weight').trim(),
      stoneWt: _get('Stone Weight').trim(),
      netWt: _get('Net Weight').trim(),
      diamondWt: _get('Diamond Weight').trim(),
      makingPerc: _get('Making %').trim(),
      makingGm: _get('Making/Gram').trim(),
      fixMaking: _get('Fix Making').trim(),
      fixWastage: _get('Fix Wastage').trim(),
      stoneAmt: _get('Stone Amount').trim(),
      diamondAmt: _get('Diamond Amount').trim(),
      sku: sku,
    );

    if (!mounted) return;
    final s = context.sRead;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? (vm.message ?? s.tr('saved')) : (vm.error ?? s.tr('saveFailed')))),
    );

    if (ok) {
      context.read<ProductViewModel>().syncProducts();
      _resetForm();
    }
  }

  TextInputType? _keyboardFor(String label) {
    if (label.contains('Weight') || label.contains('Amount') || label.contains('Wastage') || label.contains('Making')) {
      return const TextInputType.numberWithOptions(decimal: true);
    }
    return TextInputType.text;
  }

  bool _isNumericField(String label) {
    return label.contains('Weight') ||
        label.contains('Amount') ||
        label.contains('Wastage') ||
        label.contains('Making');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final vm = context.watch<SingleProductViewModel>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: productGradientAppBar(context: context, title: s.tr('addSingleProduct')),
      body: Column(
        children: [
          if (vm.loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: vm.categories.isEmpty && vm.error != null && !vm.loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(vm.error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => vm.loadMasterData(),
                          child: Text(s.retry),
                        ),
                      ],
                    ),
                  )
                : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _fieldOrder.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final label = _fieldOrder[index];
                      final isDropdown = _dropdowns.contains(label);
                      final disabled = _skuLocked && {'Category', 'Product', 'Design'}.contains(label);
                      final readOnly = label == 'Net Weight';

                      String hintText = '';
                      if (isDropdown) {
                        if (label == 'Product') {
                          hintText = s.categoryFirst;
                        } else if (label == 'Design') {
                          hintText = s.productFirst;
                        } else if (label == 'Purity') {
                          hintText = s.designFirst;
                        } else {
                          hintText = s.select;
                        }
                      } else {
                        hintText = s.tapToEnter;
                      }

                      return ProductFormRow(
                        key: ValueKey(label),
                        label: _displayLabel(context, label),
                        value: _get(label),
                        isDropdown: isDropdown,
                        options: _optionsFor(label, vm),
                        disabled: disabled,
                        readOnly: readOnly,
                        keyboardType: _keyboardFor(label),
                        numericInput: _isNumericField(label),
                        hintText: hintText,
                        onTapWhenEmpty: isDropdown
                            ? () {
                                final msg = _emptyDropdownHint(label, context);
                                if (msg != null) _showDropdownHint(msg);
                              }
                            : null,
                        onChanged: (v) {
                          setState(() {
                            _updateField(label, v);
                            if (label == 'SKU' && v.isNotEmpty) {
                              _applySku(vm, v);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                ScanBottomBar(
                  onSave: () => _save(vm),
                  onList: () => Navigator.pushNamed(context, '/product_list'),
                  onScan: _startSingleScan,
                  onGscan: _startGscan,
                  onReset: _resetForm,
                  isScanning: _isScanning && !_isBulkScanning,
                  isBulkScanning: _isScanning && _isBulkScanning,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
