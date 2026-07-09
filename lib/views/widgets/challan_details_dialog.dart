import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/delivery_challan.dart';
import '../../l10n/l10n_extension.dart';

/// Rich per-item editor for a Delivery Challan line item, mirroring the Kotlin
/// `DeliveryChallanDialogEditAndDisplay` composable and the Flutter
/// `OrderDetailsDialog` look & feel.
class ChallanDetailsDialog extends StatefulWidget {
  final ChallanDetailsModel item;
  final List<dynamic> branches;
  final List<dynamic> dailyRates;
  final Function(ChallanDetailsModel) onSave;

  const ChallanDetailsDialog({
    super.key,
    required this.item,
    required this.branches,
    required this.dailyRates,
    required this.onSave,
  });

  @override
  State<ChallanDetailsDialog> createState() => _ChallanDetailsDialogState();
}

class _ChallanDetailsDialogState extends State<ChallanDetailsDialog> {
  late TextEditingController _totalWtCtrl;
  late TextEditingController _packingWtCtrl;
  late TextEditingController _grossWtCtrl;
  late TextEditingController _stoneWtCtrl;
  late TextEditingController _dimondWtCtrl;
  late TextEditingController _ratePerGramCtrl;
  late TextEditingController _stoneAmtCtrl;
  late TextEditingController _diamondAmtCtrl;
  late TextEditingController _sizeCtrl;
  late TextEditingController _lengthCtrl;
  late TextEditingController _finePerCtrl;
  late TextEditingController _wastageCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _hallmarkAmtCtrl;
  late TextEditingController _mrpCtrl;

  late String _purity;
  late String _typeOfColor;
  late String _screwType;
  late String _polishType;

  String _netWt = '0.000';
  String _finePlusWt = '0.000';
  String _itemAmt = '0.00';
  bool _grossHasFocus = false;

  final FocusNode _grossFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _totalWtCtrl = TextEditingController(text: item.totalWt);
    _packingWtCtrl = TextEditingController(text: item.packingWeight);
    _grossWtCtrl = TextEditingController(text: item.grossWt);
    _stoneWtCtrl = TextEditingController(text: item.totalStoneWeight);
    _dimondWtCtrl = TextEditingController(text: item.totalDiamondWeight);
    _ratePerGramCtrl = TextEditingController(
        text: item.ratePerGram != '0.0' ? item.ratePerGram : item.metalRate);
    _stoneAmtCtrl = TextEditingController(
        text: item.stoneAmount != '0.0' ? item.stoneAmount : item.stoneAmt);
    _diamondAmtCtrl = TextEditingController(
        text: item.totalDiamondAmount != '0.0' ? item.totalDiamondAmount : item.diamondAmt);
    _sizeCtrl = TextEditingController(text: item.size);
    _lengthCtrl = TextEditingController(text: '');
    _finePerCtrl = TextEditingController(
        text: item.finePercentage != '0.0' ? item.finePercentage : item.finePer);
    _wastageCtrl = TextEditingController(
        text: item.makingFixedWastage != '0.0' ? item.makingFixedWastage : item.fixWastage);
    _qtyCtrl = TextEditingController(text: item.qty <= 0 ? '1' : item.qty.toString());
    _hallmarkAmtCtrl = TextEditingController(text: item.hallmarkAmount);
    _mrpCtrl = TextEditingController(text: item.mrp);

    _purity = item.purity;
    _typeOfColor = item.diamondColour.isEmpty ? 'Yellow Gold' : item.diamondColour;
    _screwType = 'Type 1';
    _polishType = 'High Polish';

    for (final c in [
      _totalWtCtrl,
      _packingWtCtrl,
      _grossWtCtrl,
      _stoneWtCtrl,
      _dimondWtCtrl,
      _ratePerGramCtrl,
      _stoneAmtCtrl,
      _diamondAmtCtrl,
      _finePerCtrl,
      _wastageCtrl,
      _hallmarkAmtCtrl,
      _mrpCtrl,
    ]) {
      c.addListener(_onFieldChanged);
    }

    _grossFocusNode.addListener(() {
      setState(() => _grossHasFocus = _grossFocusNode.hasFocus);
      if (!_grossFocusNode.hasFocus) {
        final parsed = double.tryParse(_grossWtCtrl.text) ?? 0.0;
        _grossWtCtrl.text = parsed.toStringAsFixed(3);
        recalcAll();
      }
    });

    recalcAll();
  }

  void _onFieldChanged() => recalcAll();

  @override
  void dispose() {
    _totalWtCtrl.dispose();
    _packingWtCtrl.dispose();
    _grossWtCtrl.dispose();
    _stoneWtCtrl.dispose();
    _dimondWtCtrl.dispose();
    _ratePerGramCtrl.dispose();
    _stoneAmtCtrl.dispose();
    _diamondAmtCtrl.dispose();
    _sizeCtrl.dispose();
    _lengthCtrl.dispose();
    _finePerCtrl.dispose();
    _wastageCtrl.dispose();
    _qtyCtrl.dispose();
    _hallmarkAmtCtrl.dispose();
    _mrpCtrl.dispose();
    _grossFocusNode.dispose();
    super.dispose();
  }

  void recalcAll() {
    final double? totalParsed = double.tryParse(_totalWtCtrl.text.trim());
    final double packing = double.tryParse(_packingWtCtrl.text.trim()) ?? 0.0;
    final double grossInput = double.tryParse(_grossWtCtrl.text.trim()) ?? 0.0;

    final bool autoGross = (totalParsed != null && totalParsed > 0.0 && !_grossHasFocus);
    final double gross = autoGross
        ? (totalParsed - packing).clamp(0.0, double.infinity)
        : grossInput.clamp(0.0, double.infinity);

    if (autoGross) {
      final newGrossStr = gross.toStringAsFixed(3);
      if (_grossWtCtrl.text != newGrossStr) {
        _grossWtCtrl.text = newGrossStr;
      }
    }

    final double stone = double.tryParse(_stoneWtCtrl.text.trim()) ?? 0.0;
    final double diamond = double.tryParse(_dimondWtCtrl.text.trim()) ?? 0.0;
    final double net = (gross - stone - diamond).clamp(0.0, double.infinity);
    _netWt = net.toStringAsFixed(3);

    final double fineP = double.tryParse(_finePerCtrl.text.trim()) ?? 0.0;
    final double wastP = double.tryParse(_wastageCtrl.text.trim()) ?? 0.0;
    _finePlusWt = (net * ((fineP + wastP) / 100.0)).clamp(0.0, double.infinity).toStringAsFixed(3);

    final double rate = double.tryParse(_ratePerGramCtrl.text.trim()) ?? 0.0;
    final double hallmark = double.tryParse(_hallmarkAmtCtrl.text.trim()) ?? 0.0;
    final double stoneAmount = double.tryParse(_stoneAmtCtrl.text.trim()) ?? 0.0;
    final double diamondAmount = double.tryParse(_diamondAmtCtrl.text.trim()) ?? 0.0;

    final double baseAmt = (net * rate) + hallmark + stoneAmount + diamondAmount;
    final double mrpVal = double.tryParse(_mrpCtrl.text.trim()) ?? 0.0;

    if (mounted) {
      setState(() {
        _itemAmt = mrpVal > 0.0 ? mrpVal.toStringAsFixed(2) : baseAmt.toStringAsFixed(2);
      });
    }
  }

  void _onPurityChanged(String newPurity) {
    setState(() => _purity = newPurity);
    final match = widget.dailyRates.firstWhere(
      (r) => (r['PurityName'] as String? ?? '').trim().toUpperCase() == newPurity.trim().toUpperCase(),
      orElse: () => null,
    );
    if (match != null) {
      _ratePerGramCtrl.text = match['Rate']?.toString() ?? '0.0';
      recalcAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final purityNames = widget.dailyRates
        .map((r) => (r['PurityName'] as String? ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    final colorsList = ["Yellow Gold", "White Gold", "Rose Gold", "Green Gold", "Black Gold", "Blue Gold", "Purple Gold"];
    final screwList = ["Type 1", "Type 2", "Type 3"];
    final polishList = ["High Polish", "Matte Finish", "Satin Finish", "Hammered"];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    s.customOrderFields,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (widget.item.image.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          height: 120,
                          color: const Color(0xFFF5F5F5),
                          alignment: Alignment.center,
                          child: Image.network(
                            widget.item.image,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.image, size: 48, color: Colors.grey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildDisplayRow(s.productName, widget.item.productName),
                    _buildDisplayRow(s.itemCode, widget.item.itemCode),
                    _buildDisplayRow(s.skuCode, widget.item.sku),
                    _buildDropdownRow(
                      label: s.purity,
                      options: purityNames,
                      selectedValue: _purity,
                      getOptionLabel: (p) => p,
                      onSelected: _onPurityChanged,
                    ),
                    _buildFieldRow(s.totalWeight, _totalWtCtrl),
                    _buildFieldRow(s.packingWt, _packingWtCtrl),
                    _buildFieldRow(s.colGrossWt, _grossWtCtrl, focusNode: _grossFocusNode),
                    _buildFieldRow(s.colStoneWt, _stoneWtCtrl),
                    _buildFieldRow(s.colDiamondWt, _dimondWtCtrl),
                    _buildFieldRow(s.colStoneAmt, _stoneAmtCtrl),
                    _buildFieldRow(s.colDiamondAmt, _diamondAmtCtrl),
                    _buildDisplayRow(s.fieldNetWeight, _netWt),
                    _buildFieldRow(s.size, _sizeCtrl, keyboardType: TextInputType.text),
                    _buildFieldRow(s.length, _lengthCtrl, keyboardType: TextInputType.text),
                    _buildDropdownRow(
                      label: s.colorType,
                      options: colorsList,
                      selectedValue: _typeOfColor,
                      getOptionLabel: (c) => c,
                      onSelected: (val) => setState(() => _typeOfColor = val),
                    ),
                    _buildDropdownRow(
                      label: s.screwType,
                      options: screwList,
                      selectedValue: _screwType,
                      getOptionLabel: (s) => s,
                      onSelected: (val) => setState(() => _screwType = val),
                    ),
                    _buildDropdownRow(
                      label: s.polishType,
                      options: polishList,
                      selectedValue: _polishType,
                      getOptionLabel: (p) => p,
                      onSelected: (val) => setState(() => _polishType = val),
                    ),
                    _buildFieldRow(s.ratePerGram, _ratePerGramCtrl),
                    _buildFieldRow(s.finePercent, _finePerCtrl),
                    _buildFieldRow(s.wastagePercent, _wastageCtrl),
                    _buildFieldRow(s.qty, _qtyCtrl),
                    _buildFieldRow(s.hallmarkAmt, _hallmarkAmtCtrl),
                    _buildFieldRow(s.mrp, _mrpCtrl),
                    _buildDisplayRow(s.finePlusWt, _finePlusWt),
                    _buildDisplayRow(s.itemAmt, '₹$_itemAmt'),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(s.cancel,
                          style: GoogleFonts.poppins(color: Colors.grey[700], fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: _onSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(s.save,
                            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onSave() {
    recalcAll();
    final rateStr = _ratePerGramCtrl.text.trim();
    final stoneAmtStr = _stoneAmtCtrl.text.trim();
    final diamondAmtStr = _diamondAmtCtrl.text.trim();
    final wastageStr = _wastageCtrl.text.trim();

    final double net = double.tryParse(_netWt) ?? 0.0;
    final double rate = double.tryParse(rateStr) ?? 0.0;
    final double metalAmt = net * rate;

    final updated = widget.item.copyWith(
      purity: _purity,
      size: _sizeCtrl.text.trim(),
      diamondColour: _typeOfColor,
      totalWt: _totalWtCtrl.text.trim(),
      packingWeight: _packingWtCtrl.text.trim(),
      grossWt: _grossWtCtrl.text.trim(),
      totalStoneWeight: _stoneWtCtrl.text.trim(),
      totalDiamondWeight: _dimondWtCtrl.text.trim(),
      netWt: _netWt,
      ratePerGram: rateStr,
      metalRate: rateStr,
      totayRate: rateStr,
      metalAmount: metalAmt.toStringAsFixed(2),
      stoneAmount: stoneAmtStr,
      stoneAmt: stoneAmtStr,
      totalStoneAmount: stoneAmtStr,
      totalDiamondAmount: diamondAmtStr,
      diamondAmt: diamondAmtStr,
      finePercentage: _finePerCtrl.text.trim(),
      finePer: _finePerCtrl.text.trim(),
      makingFixedWastage: wastageStr,
      fixWastage: wastageStr,
      fineWastageWt: _finePlusWt,
      fineWt: _finePlusWt,
      hallmarkAmount: _hallmarkAmtCtrl.text.trim(),
      mrp: _mrpCtrl.text.trim(),
      quantity: _qtyCtrl.text.trim(),
      qty: int.tryParse(_qtyCtrl.text.trim()) ?? 1,
      amount: _itemAmt,
      itemAmount: _itemAmt,
      totalItemAmount: _itemAmt,
      netAmount: _itemAmt,
      totalAmount: _itemAmt,
    );

    widget.onSave(updated);
    Navigator.pop(context);
  }

  Widget _buildFieldRow(String label, TextEditingController controller,
      {bool enabled = true,
      FocusNode? focusNode,
      TextInputType keyboardType = const TextInputType.numberWithOptions(decimal: true)}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              enabled: enabled,
              focusNode: focusNode,
              keyboardType: keyboardType,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(value,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow<T>({
    required String label,
    required List<T> options,
    required String selectedValue,
    required String Function(T) getOptionLabel,
    required Function(String) onSelected,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedValue.isEmpty || !options.map((o) => getOptionLabel(o)).contains(selectedValue)
                    ? null
                    : selectedValue,
                isExpanded: true,
                hint: Text(context.s.selectOption(label), style: GoogleFonts.poppins(fontSize: 13)),
                icon: const Icon(Icons.arrow_drop_down),
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
                items: options.map((T option) {
                  final labelVal = getOptionLabel(option);
                  return DropdownMenuItem<String>(value: labelVal, child: Text(labelVal));
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) onSelected(newValue);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
