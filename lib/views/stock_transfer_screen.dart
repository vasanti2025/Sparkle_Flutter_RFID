import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rfid_flutter/utils/app_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import '../utils/app_dropdown.dart';
import 'widgets/product_form_widgets.dart';
import 'widgets/scan_bottom_bar.dart';
import 'widgets/stock_transfer_dialogs.dart';

class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key});

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  final RfidService _rfid = RfidService();
  final TextEditingController _searchCtrl = TextEditingController();
  StreamSubscription<String>? _tagSub;
  StreamSubscription<void>? _triggerSub;

  final Set<String> _checkedKeys = {};
  bool _isBulkScanning = false;
  bool _isSingleScan = false;
  int _power = 10;
  final Map<String, String> _rfidToItemKey = {};
  String? _rfidIndexToken;
  Timer? _tagUiTimer;
  final Set<String> _pendingTagKeys = {};
  StockTransferViewModel? _vm;

  /// Sparkle: trim + uppercase + strip spaces before EPC/RFID match.
  static String _norm(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  @override
  void initState() {
    super.initState();
    _power = context.read<PrefService>().stockTransferPower;
    _vm = context.read<StockTransferViewModel>();
    _vm!.addListener(_onVmChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Refresh power in case Settings changed it while this route was under the stack.
      final savedPower = context.read<PrefService>().stockTransferPower.clamp(1, 30);
      if (savedPower != _power) {
        setState(() => _power = savedPower);
      }
      // Let the route fade finish before heavy stock load.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      // Reuse in-memory list when possible — avoid full DB reload every open.
      await _vm!.initialize(forceReload: false);
      if (!mounted) return;
      _syncRfidIndex(_vm!);
      _tagSub = _rfid.tagsStream.listen(_onTag);
      _triggerSub = _rfid.triggerStream.listen((_) {
        if (!mounted) return;
        // Hardware trigger = Gscan toggle (same as Sparkle onRfidKeyPressed).
        if (_rfid.isScanning) {
          unawaited(_stopScanning());
        } else {
          unawaited(_startGscan());
        }
      });
    });
  }

  @override
  void dispose() {
    _vm?.removeListener(_onVmChanged);
    _tagUiTimer?.cancel();
    _tagSub?.cancel();
    _triggerSub?.cancel();
    _searchCtrl.dispose();
    _rfid.stopScanning();
    super.dispose();
  }

  void _onVmChanged() {
    final vm = _vm;
    if (vm == null) return;
    _syncRfidIndex(vm);
  }

  void _syncRfidIndex(StockTransferViewModel vm) {
    // Match against From-filtered stock (Sparkle filteredStockItems), not only
    // category-narrowed displayItems — so Scan/Gscan can check the right rows.
    final token =
        '${vm.selectedFrom}|${vm.filteredItems.length}|${vm.appliedCategory}|${vm.appliedProduct}|${vm.appliedDesign}';
    if (_rfidIndexToken == token) return;
    _rfidIndexToken = token;
    _rfidToItemKey.clear();
    for (final item in vm.filteredItems) {
      final itemKey = vm.itemKey(item);
      if (itemKey.isEmpty) continue;
      void map(String raw) {
        final n = _norm(raw);
        if (n.isNotEmpty) _rfidToItemKey[n] = itemKey;
      }

      map(item.epc);
      map(item.rfid);
      map(item.itemCode);
    }
  }

  void _onTag(String epc) {
    // Only auto-check while an RFID session is active (Scan or Gscan).
    if (!_rfid.isScanning) return;
    final vm = context.read<StockTransferViewModel>();
    _syncRfidIndex(vm);
    final key = _rfidToItemKey[_norm(epc)];
    if (key == null || key.isEmpty || _checkedKeys.contains(key)) return;
    _pendingTagKeys.add(key);
    _tagUiTimer?.cancel();
    _tagUiTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || _pendingTagKeys.isEmpty) return;
      setState(() {
        _checkedKeys.addAll(_pendingTagKeys);
        _pendingTagKeys.clear();
      });
      // Single Scan: beep once on find (Sparkle startSingleScan playSound(1)).
      if (_isSingleScan) {
        unawaited(_rfid.playBeep());
        unawaited(_stopScanning());
      }
    });
  }

  Future<void> _stopScanning() async {
    await _rfid.stopScanning();
    if (mounted) {
      setState(() {
        _isBulkScanning = false;
        _isSingleScan = false;
      });
    }
  }

  /// Center Scan button — short inventory window @ power 20 (Sparkle).
  Future<void> _startSingleScan() async {
    if (_rfid.isScanning && !_isSingleScan) {
      await _stopScanning();
    }
    if (_rfid.isScanning && _isSingleScan) {
      await _stopScanning();
      return;
    }
    _isSingleScan = true;
    _isBulkScanning = false;
    final started = await _rfid.startScanning(power: 20, playStartSound: false);
    if (!mounted) return;
    setState(() {});
    if (!started) {
      setState(() => _isSingleScan = false);
      return;
    }
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted || !_isSingleScan) return;
      await _stopScanning();
    });
  }

  /// Gscan — continuous inventory @ stock-transfer power (Sparkle).
  Future<void> _startGscan() async {
    if (_rfid.isScanning && _isSingleScan) {
      await _stopScanning();
    }
    if (_isBulkScanning || (_rfid.isScanning && !_isSingleScan)) {
      await _stopScanning();
      return;
    }
    _isSingleScan = false;
    await _rfid.stopScanning();
    final started = await _rfid.startScanning(power: _power);
    if (mounted) {
      setState(() => _isBulkScanning = started);
    }
  }

  void _resetScan() {
    unawaited(_rfid.stopScanning());
    setState(() {
      _isBulkScanning = false;
      _isSingleScan = false;
      _checkedKeys.clear();
      _pendingTagKeys.clear();
    });
  }

  void _toggleCheck(String key) {
    setState(() {
      if (_checkedKeys.contains(key)) {
        _checkedKeys.remove(key);
      } else {
        _checkedKeys.add(key);
      }
    });
  }

  void _setSelectAll(List<BulkItem> rows, StockTransferViewModel vm, bool checked) {
    setState(() {
      _checkedKeys.clear();
      if (checked) {
        for (final item in rows) {
          final key = vm.itemKey(item);
          if (key.isNotEmpty) _checkedKeys.add(key);
        }
      }
    });
  }

  List<BulkItem> _selectedItems(StockTransferViewModel vm) {
    return vm.displayItems.where((i) => _checkedKeys.contains(vm.itemKey(i))).toList();
  }

  void _showFilterDialog(StockTransferViewModel vm) {
    final s = context.s;
    String draftCat = vm.appliedCategory ?? StockTransferViewModel.categoryPlaceholder;
    String draftProd = vm.appliedProduct ?? StockTransferViewModel.productPlaceholder;
    String draftDes = vm.appliedDesign ?? StockTransferViewModel.designPlaceholder;
    String displayCat(String v) => v == StockTransferViewModel.categoryPlaceholder ? s.tr('category') : v;
    String displayProd(String v) => v == StockTransferViewModel.productPlaceholder ? s.tr('product') : v;
    String displayDes(String v) => v == StockTransferViewModel.designPlaceholder ? s.tr('design') : v;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(s.tr('filter'), style: AppFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _filterPicker(
                  s.tr('category'),
                  displayCat(draftCat),
                  vm.distinctCategories,
                  (v) => setLocal(() {
                    draftCat = v;
                    draftProd = StockTransferViewModel.productPlaceholder;
                    draftDes = StockTransferViewModel.designPlaceholder;
                  }),
                ),
                const SizedBox(height: 8),
                _filterPicker(
                  s.tr('product'),
                  displayProd(draftProd),
                  draftCat == StockTransferViewModel.categoryPlaceholder
                      ? vm.filterProductsFor(null)
                      : vm.filterProductsFor(draftCat),
                  (v) => setLocal(() {
                    draftProd = v;
                    draftDes = StockTransferViewModel.designPlaceholder;
                  }),
                ),
                const SizedBox(height: 8),
                _filterPicker(
                  s.tr('design'),
                  displayDes(draftDes),
                  draftProd == StockTransferViewModel.productPlaceholder
                      ? vm.filterDesignsFor(
                          draftCat == StockTransferViewModel.categoryPlaceholder ? null : draftCat,
                          null,
                        )
                      : vm.filterDesignsFor(
                          draftCat == StockTransferViewModel.categoryPlaceholder ? null : draftCat,
                          draftProd,
                        ),
                  (v) => setLocal(() => draftDes = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await vm.clearAppliedFilters();
                if (ctx.mounted) {
                  setState(() => _checkedKeys.clear());
                  Navigator.pop(ctx);
                }
              },
              child: Text(s.tr('clearBtn')),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.tr('cancel'))),
            TextButton(
              onPressed: () {
                vm.applyCategoryProductDesignFilters(
                  category: draftCat == StockTransferViewModel.categoryPlaceholder ? null : draftCat,
                  product: draftProd == StockTransferViewModel.productPlaceholder ? null : draftProd,
                  design: draftDes == StockTransferViewModel.designPlaceholder ? null : draftDes,
                );
                setState(() => _checkedKeys.clear());
                Navigator.pop(ctx);
              },
              child: Text(s.tr('apply')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPicker(String label, String value, List<String> options, ValueChanged<String> onPick) {
    return InkWell(
      onTap: () async {
        if (options.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.sRead.tr('noItemsInCurrentScope'))),
          );
          return;
        }
        final picked = await showScrollableOptionSheet<String>(
          context: context,
          options: options,
          labelOf: (o) => o,
          title: label,
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: Text(value, style: AppFonts.poppins(fontSize: 13)),
      ),
    );
  }

  Future<void> _pickOption(String title, List<String> options, ValueChanged<String> onSelect) async {
    if (options.isEmpty) return;
    final picked = await showScrollableOptionSheet<String>(
      context: context,
      options: options,
      labelOf: (o) => o,
      title: title,
    );
    if (picked != null) onSelect(picked);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StockTransferViewModel>();
    final s = context.s;
    final selected = _selectedItems(vm);
    final totalGross = selected.fold(0.0, (sum, i) => sum + (double.tryParse(i.grossWeight) ?? 0));
    final totalNet = selected.fold(0.0, (sum, i) => sum + (double.tryParse(i.netWeight) ?? 0));

    final searchQuery = _searchCtrl.text.trim();
    final rows = searchQuery.isEmpty
        ? vm.displayItems
        : vm.searchItemCodeSuggestions(searchQuery);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: productGradientAppBar(
        context: context,
        title: s.stockTransfer,
        showCounter: true,
        selectedCount: _power,
        onCountSelected: (v) {
          setState(() => _power = v.clamp(1, 30));
          context.read<PrefService>().savePower(PrefService.keyStockTransferCount, v);
          unawaited(_rfid.setPower(v));
        },
      ),
      body: Column(
        children: [
          if (vm.isBootstrapping)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: vm.isLoading && vm.displayItems.isEmpty && !vm.isBootstrapping
                ? const Center(child: CircularProgressIndicator())
                : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(child: _gradientChip(
                        vm.selectedTransferType ?? s.tr('transferType'),
                        () {
                        _pickOption(s.tr('transferType'), vm.transferTypes.map((e) => e.transferType).toList(), (v) {
                          vm.selectTransferType(v);
                          setState(() => _checkedKeys.clear());
                        });
                      })),
                      const SizedBox(width: 6),
                      Expanded(child: _gradientChip(
                        vm.selectedFrom == StockTransferViewModel.fromPlaceholder ? s.tr('from') : vm.selectedFrom,
                        () {
                        _pickOption(s.tr('from'), vm.fromOptions, (v) async {
                          await vm.selectFrom(v);
                          setState(() => _checkedKeys.clear());
                        });
                      })),
                      const SizedBox(width: 6),
                      Expanded(child: _gradientChip(
                        vm.selectedTo == StockTransferViewModel.toPlaceholder ? s.tr('to') : vm.selectedTo,
                        () {
                        _pickOption(s.tr('to'), vm.toOptions, (v) async {
                          await vm.selectTo(v);
                        });
                      })),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Autocomplete<BulkItem>(
                          displayStringForOption: (item) =>
                              item.itemCode.trim().isNotEmpty ? item.itemCode : item.rfid,
                          optionsBuilder: (textEditingValue) {
                            return vm.searchItemCodeSuggestions(textEditingValue.text);
                          },
                          onSelected: (item) {
                            final key = vm.itemKey(item);
                            _searchCtrl.text =
                                item.itemCode.trim().isNotEmpty ? item.itemCode : item.rfid;
                            setState(() => _checkedKeys.add(key));
                          },
                          fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: textController,
                              focusNode: focusNode,
                              onChanged: (value) {
                                _searchCtrl.text = value;
                                final exact = vm.findExactItemCode(value);
                                if (exact != null) {
                                  _checkedKeys.add(vm.itemKey(exact));
                                }
                                setState(() {});
                              },
                              decoration: InputDecoration(
                                hintText: s.tr('itemCodeLabel'),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                suffixIcon: textController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          textController.clear();
                                          _searchCtrl.clear();
                                          setState(() {});
                                        },
                                      ),
                              ),
                              style: AppFonts.poppins(fontSize: 13),
                              onSubmitted: (_) => onFieldSubmitted(),
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                          option.itemCode,
                                          style: AppFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          option.productName,
                                          style: AppFonts.poppins(fontSize: 11),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () => onSelected(option),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.tune, color: Color(0xFF5231A7)), onPressed: () => _showFilterDialog(vm)),
                    ],
                  ),
                ),
                _tableHeader(
                  s,
                  selectAllChecked: rows.isNotEmpty &&
                      rows.every((i) => _checkedKeys.contains(vm.itemKey(i))),
                  onSelectAllChange: (checked) => _setSelectAll(rows, vm, checked),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    cacheExtent: 400,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = rows[index];
                      final key = vm.itemKey(item);
                      final checked = _checkedKeys.contains(key);
                      final code = item.itemCode.trim().isNotEmpty ? item.itemCode : item.rfid;
                      return RepaintBoundary(
                        child: InkWell(
                        onTap: () => _toggleCheck(key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(width: 28, child: Text('${index + 1}', style: _cell())),
                              Expanded(flex: 3, child: Text(item.productName, style: _cell(), maxLines: 2, overflow: TextOverflow.ellipsis)),
                              Expanded(flex: 2, child: Text(code, style: _cell(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Expanded(child: Text(item.grossWeight, style: _cell(), textAlign: TextAlign.center)),
                              Expanded(child: Text(item.netWeight, style: _cell(), textAlign: TextAlign.center)),
                              Checkbox(
                                value: checked,
                                activeColor: const Color(0xFF5231A7),
                                onChanged: (_) => _toggleCheck(key),
                              ),
                            ],
                          ),
                        ),
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
                      Text('${s.tr('totalQty')}: ${rows.length}', style: AppFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600)),
                      Text('${s.tr('selectedQty')}: ${selected.length}', style: AppFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600)),
                      Text('${s.tr('grossWt')}: ${totalGross.toStringAsFixed(2)}', style: AppFonts.poppins(fontSize: 11)),
                      Text('${s.tr('netWt')}: ${totalNet.toStringAsFixed(2)}', style: AppFonts.poppins(fontSize: 11)),
                    ],
                  ),
                ),
                ScanBottomBar(
                  isScreen: true,
                  isScanning: _rfid.isScanning && _isSingleScan,
                  isBulkScanning: _isBulkScanning || (_rfid.isScanning && !_isSingleScan),
                  onSave: () {
                    if ((vm.selectedFrom == StockTransferViewModel.fromPlaceholder) ||
                        vm.selectedFrom.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.tr('selectFromError'))),
                      );
                      return;
                    }
                    if ((vm.selectedTo == StockTransferViewModel.toPlaceholder) ||
                        vm.selectedTo.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.tr('selectToError'))),
                      );
                      return;
                    }
                    if (selected.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.tr('selectItemsToTransfer'))));
                      return;
                    }
                    vm.setPreviewItems(selected);
                    // Keep From/To names for submit entity resolution (Sparkle setPendingLocationNames).
                    Navigator.pushNamed(context, '/stock_transfer_preview').then((result) {
                      if (!mounted) return;
                      if (result == true) {
                        setState(() {
                          _checkedKeys.clear();
                          _pendingTagKeys.clear();
                        });
                      }
                    });
                  },
                  onList: () async {
                    final nav = Navigator.of(context);
                    final requestType = await showStockRequestPopup(context);
                    if (!mounted || requestType == null) return;
                    await nav.pushNamed(
                      '/stock_transfer_in_out',
                      arguments: {'requestType': requestType},
                    );
                  },
                  onScan: _startSingleScan,
                  onGscan: _startGscan,
                  onReset: _resetScan,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: AppFonts.poppins(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _tableHeader(
    dynamic s, {
    required bool selectAllChecked,
    required ValueChanged<bool> onSelectAllChange,
  }) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text(s.headerSr, style: _header())),
          Expanded(flex: 3, child: Text(s.tr('productName'), style: _header())),
          Expanded(flex: 2, child: Text(s.tr('itemCodeLabel'), style: _header())),
          Expanded(child: Text(s.tr('grossWt'), style: _header(), textAlign: TextAlign.center)),
          Expanded(child: Text(s.tr('netWt'), style: _header(), textAlign: TextAlign.center)),
          SizedBox(
            width: 42,
            child: Checkbox(
              value: selectAllChecked,
              onChanged: (v) => onSelectAllChange(v ?? false),
              activeColor: Colors.white,
              checkColor: Colors.black,
              side: const BorderSide(color: Colors.white),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _header() => AppFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10);
  TextStyle _cell() => AppFonts.poppins(fontSize: 10, color: Colors.black87);
}
