import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/order_item.dart';
import '../../l10n/l10n_extension.dart';

class OrderDetailsDialog extends StatefulWidget {
  final OrderItem item;
  final List<dynamic> branches;
  final List<dynamic> dailyRates;
  final Function(OrderItem) onSave;

  const OrderDetailsDialog({
    super.key,
    required this.item,
    required this.branches,
    required this.dailyRates,
    required this.onSave,
  });

  @override
  State<OrderDetailsDialog> createState() => _OrderDetailsDialogState();
}

class _OrderDetailsDialogState extends State<OrderDetailsDialog> {
  // Text Controllers
  late TextEditingController _totalWtCtrl;
  late TextEditingController _packingWtCtrl;
  late TextEditingController _grossWtCtrl;
  late TextEditingController _stoneWtCtrl;
  late TextEditingController _dimondWtCtrl;
  late TextEditingController _ratePerGramCtrl;
  late TextEditingController _stoneAmtCtrl;
  late TextEditingController _diamondAmtCtrl;
  late TextEditingController _exhibitionCtrl;
  late TextEditingController _remarkCtrl;
  late TextEditingController _sizeCtrl;
  late TextEditingController _lengthCtrl;
  late TextEditingController _finePerCtrl;
  late TextEditingController _wastageCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _hallmarkAmtCtrl;
  late TextEditingController _mrpCtrl;

  // Dropdown States
  late String _purity;
  late String _branchId;
  late String _branchName;
  late String _typeOfColor;
  late String _screwType;
  late String _polishType;
  late String _orderDate;
  late String _deliverDate;

  // Calculated Displays
  String _netWt = '0.000';
  String _finePlusWt = '0.000';
  String _itemAmt = '0.00';
  bool _grossHasFocus = false;

  final FocusNode _grossFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    final item = widget.item;

    // Initialize text values
    _totalWtCtrl = TextEditingController(text: item.totalWt);
    _packingWtCtrl = TextEditingController(text: item.packingWt);
    _grossWtCtrl = TextEditingController(text: item.grWt ?? '0.000');
    _stoneWtCtrl = TextEditingController(text: item.stoneWt);
    _dimondWtCtrl = TextEditingController(text: item.dimondWt);
    _ratePerGramCtrl = TextEditingController(text: item.todaysRate);
    _stoneAmtCtrl = TextEditingController(text: item.stoneAmt ?? '0.00');
    _diamondAmtCtrl = TextEditingController(text: item.diamondAmt);
    _exhibitionCtrl = TextEditingController(text: item.exhibition);
    _remarkCtrl = TextEditingController(text: item.remark);
    _sizeCtrl = TextEditingController(text: item.size);
    _lengthCtrl = TextEditingController(text: item.length);
    _finePerCtrl = TextEditingController(text: item.finePer);
    _wastageCtrl = TextEditingController(text: item.makingPercentage.isNotEmpty ? item.makingPercentage : item.wastage);
    _qtyCtrl = TextEditingController(text: item.qty.isEmpty || item.qty == '0' ? '1' : item.qty);
    _hallmarkAmtCtrl = TextEditingController(text: item.hallmarkAmt);
    _mrpCtrl = TextEditingController(text: item.mrp);

    // Initial dropdown setups
    _purity = item.purity;
    _branchId = item.branchId;
    _branchName = item.branchName;
    _typeOfColor = item.typeOfColor.isEmpty ? 'Yellow Gold' : item.typeOfColor;
    _screwType = item.screwType.isEmpty ? 'Type 1' : item.screwType;
    _polishType = item.polishType.isEmpty ? 'High Polish' : item.polishType;

    // Dates setup
    _orderDate = item.orderDate.isEmpty ? DateFormat('yyyy-MM-dd').format(DateTime.now()) : item.orderDate;
    _deliverDate = item.deliverDate.isEmpty ? DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 7))) : item.deliverDate;

    // Add recalculation listeners
    _totalWtCtrl.addListener(_onFieldChanged);
    _packingWtCtrl.addListener(_onFieldChanged);
    _grossWtCtrl.addListener(_onFieldChanged);
    _stoneWtCtrl.addListener(_onFieldChanged);
    _dimondWtCtrl.addListener(_onFieldChanged);
    _ratePerGramCtrl.addListener(_onFieldChanged);
    _stoneAmtCtrl.addListener(_onFieldChanged);
    _diamondAmtCtrl.addListener(_onFieldChanged);
    _finePerCtrl.addListener(_onFieldChanged);
    _wastageCtrl.addListener(_onFieldChanged);
    _hallmarkAmtCtrl.addListener(_onFieldChanged);
    _mrpCtrl.addListener(_onFieldChanged);

    _grossFocusNode.addListener(() {
      setState(() {
        _grossHasFocus = _grossFocusNode.hasFocus;
      });
      if (!_grossFocusNode.hasFocus) {
        final parsed = double.tryParse(_grossWtCtrl.text) ?? 0.0;
        _grossWtCtrl.text = parsed.toStringAsFixed(3);
        recalcAll();
      }
    });

    // Run initial recalc
    recalcAll();
  }

  void _onFieldChanged() {
    recalcAll();
  }

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
    _exhibitionCtrl.dispose();
    _remarkCtrl.dispose();
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

    final double gross = autoGross ? (totalParsed - packing).clamp(0.0, double.infinity) : grossInput.clamp(0.0, double.infinity);

    if (autoGross) {
      final newGrossStr = gross.toStringAsFixed(3);
      if (_grossWtCtrl.text != newGrossStr) {
        _grossWtCtrl.text = newGrossStr;
      }
    }

    final double stone = double.tryParse(_stoneWtCtrl.text.trim()) ?? 0.0;
    final double diamond = double.tryParse(_dimondWtCtrl.text.trim()) ?? 0.0;
    final double net = (gross - stone - diamond).clamp(0.0, double.infinity);
    
    // Updates
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

  Future<void> _selectDate(BuildContext context, bool isOrderDate) async {
    final initialDate = DateTime.tryParse(isOrderDate ? _orderDate : _deliverDate) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        final formatted = DateFormat('yyyy-MM-dd').format(picked);
        if (isOrderDate) {
          _orderDate = formatted;
        } else {
          _deliverDate = formatted;
        }
      });
    }
  }

  void _onPurityChanged(String newPurity) {
    setState(() {
      _purity = newPurity;
    });

    // Check rate in dailyRates list
    final match = widget.dailyRates.firstWhere(
      (r) => (r['PurityName'] as String? ?? '').trim().toUpperCase() == newPurity.trim().toUpperCase(),
      orElse: () => null,
    );
    if (match != null) {
      final rateStr = match['Rate']?.toString() ?? '0.0';
      _ratePerGramCtrl.text = rateStr;
      recalcAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    // Extract unique Purity list
    final purityNames = widget.dailyRates
        .map((r) => (r['PurityName'] as String? ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    // Dropdown constants
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
            // Header Bar
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    s.customOrderFields,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Dialog Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Item image if URL exists
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

                    // Branch Dropdown
                    _buildDropdownRow(
                      label: s.branchName,
                      options: widget.branches,
                      selectedValue: _branchName,
                      getOptionLabel: (b) => b['BranchName']?.toString() ?? '',
                      onSelected: (selectedName) {
                        final b = widget.branches.firstWhere((x) => x['BranchName'] == selectedName);
                        setState(() {
                          _branchName = selectedName;
                          _branchId = (b['Id'] ?? 0).toString();
                        });
                      },
                    ),

                    _buildDisplayRow(s.productName, widget.item.productName),
                    _buildDisplayRow(s.itemCode, widget.item.itemCode),

                    _buildFieldRow(s.totalWeight, _totalWtCtrl),
                    _buildFieldRow(s.packingWt, _packingWtCtrl),
                    _buildFieldRow(s.colGrossWt, _grossWtCtrl, focusNode: _grossFocusNode),
                    _buildFieldRow(s.colStoneWt, _stoneWtCtrl),
                    _buildFieldRow(s.colDiamondWt, _dimondWtCtrl),

                    _buildDisplayRow(s.fieldNetWeight, _netWt),

                    _buildFieldRow(s.ratePerGram, _ratePerGramCtrl),
                    _buildFieldRow(s.colStoneAmt, _stoneAmtCtrl),
                    _buildFieldRow(s.colDiamondAmt, _diamondAmtCtrl),
                    _buildFieldRow(s.exhibition, _exhibitionCtrl, keyboardType: TextInputType.text),
                    _buildFieldRow(s.remark, _remarkCtrl, keyboardType: TextInputType.text),

                    _buildDisplayRow(s.skuCode, widget.item.sku),

                    // Purity Dropdown
                    _buildDropdownRow(
                      label: s.purity,
                      options: purityNames,
                      selectedValue: _purity,
                      getOptionLabel: (p) => p,
                      onSelected: _onPurityChanged,
                    ),

                    _buildFieldRow(s.size, _sizeCtrl, keyboardType: TextInputType.text),
                    _buildFieldRow(s.length, _lengthCtrl, keyboardType: TextInputType.text),

                    // Colors dropdown
                    _buildDropdownRow(
                      label: s.colors,
                      options: colorsList,
                      selectedValue: _typeOfColor,
                      getOptionLabel: (c) => c,
                      onSelected: (val) => setState(() => _typeOfColor = val),
                    ),

                    // Screw Type
                    _buildDropdownRow(
                      label: s.screwType,
                      options: screwList,
                      selectedValue: _screwType,
                      getOptionLabel: (s) => s,
                      onSelected: (val) => setState(() => _screwType = val),
                    ),

                    // Polish Type
                    _buildDropdownRow(
                      label: s.polishType,
                      options: polishList,
                      selectedValue: _polishType,
                      getOptionLabel: (p) => p,
                      onSelected: (val) => setState(() => _polishType = val),
                    ),

                    _buildFieldRow(s.finePercent, _finePerCtrl),
                    _buildFieldRow(s.wastagePercent, _wastageCtrl),

                    // Dates Pickers
                    _buildDateRow(s.orderDate, _orderDate, () => _selectDate(context, true)),
                    _buildDateRow(s.deliveryDate, _deliverDate, () => _selectDate(context, false)),

                    _buildFieldRow(s.qty, _qtyCtrl),
                    _buildFieldRow(s.hallmarkAmt, _hallmarkAmtCtrl),
                    _buildFieldRow(s.mrp, _mrpCtrl),

                    _buildDisplayRow(s.finePlusWt, _finePlusWt),
                    _buildDisplayRow(s.itemAmt, '₹$_itemAmt'),
                  ],
                ),
              ),
            ),

            // Bottom Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        s.cancel,
                        style: GoogleFonts.poppins(color: Colors.grey[700], fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          // Final recalc before saving
                          recalcAll();

                          final updated = widget.item.copyWith(
                            branchId: _branchId,
                            branchName: _branchName,
                            exhibition: _exhibitionCtrl.text.trim(),
                            remark: _remarkCtrl.text.trim(),
                            purity: _purity,
                            size: _sizeCtrl.text.trim(),
                            length: _lengthCtrl.text.trim(),
                            typeOfColor: _typeOfColor,
                            screwType: _screwType,
                            polishType: _polishType,
                            finePer: _finePerCtrl.text.trim(),
                            wastage: _wastageCtrl.text.trim(),
                            makingPercentage: _wastageCtrl.text.trim(),
                            orderDate: _orderDate,
                            deliverDate: _deliverDate,
                            totalWt: _totalWtCtrl.text.trim(),
                            packingWt: _packingWtCtrl.text.trim(),
                            grWt: _grossWtCtrl.text.trim(),
                            stoneWt: _stoneWtCtrl.text.trim(),
                            dimondWt: _dimondWtCtrl.text.trim(),
                            nWt: _netWt,
                            todaysRate: _ratePerGramCtrl.text.trim(),
                            stoneAmt: _stoneAmtCtrl.text.trim(),
                            diamondAmt: _diamondAmtCtrl.text.trim(),
                            hallmarkAmt: _hallmarkAmtCtrl.text.trim(),
                            mrp: _mrpCtrl.text.trim(),
                            qty: _qtyCtrl.text.trim(),
                            finePlusWt: _finePlusWt,
                            itemAmt: _itemAmt,
                            netAmt: _itemAmt,
                          );

                          widget.onSave(updated);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          s.save,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

  Widget _buildFieldRow(String label, TextEditingController controller, {bool enabled = true, FocusNode? focusNode, TextInputType keyboardType = const TextInputType.numberWithOptions(decimal: true)}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
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
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
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
    bool enabled = true,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 3,
            child: enabled
                ? DropdownButtonHideUnderline(
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
                        return DropdownMenuItem<String>(
                          value: labelVal,
                          child: Text(labelVal),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          onSelected(newValue);
                        }
                      },
                    ),
                  )
                : Text(
                    selectedValue,
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow(String label, String value, VoidCallback onPick) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: onPick,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value.isEmpty ? 'Select Date' : value,
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.black, fontWeight: FontWeight.w500),
                  ),
                  const Icon(Icons.calendar_today, size: 16, color: Colors.black54),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
