import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../l10n/l10n_extension.dart';

class OrderBulkDetailsDialog extends StatefulWidget {
  final List<dynamic> branches;
  final List<dynamic> dailyRates;
  final Function(Map<String, dynamic> result) onConfirm;

  const OrderBulkDetailsDialog({
    super.key,
    required this.branches,
    required this.dailyRates,
    required this.onConfirm,
  });

  @override
  State<OrderBulkDetailsDialog> createState() => _OrderBulkDetailsDialogState();
}

class _OrderBulkDetailsDialogState extends State<OrderBulkDetailsDialog> {
  // Input fields
  final _exhibitionCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _finePerCtrl = TextEditingController();
  final _wastageCtrl = TextEditingController();

  // Dropdown states
  String _selectedBranchId = '';
  String _selectedBranchName = '';
  String _selectedPurity = '';
  String _typeOfColor = 'Yellow Gold';
  String _screwType = 'Type 1';
  String _polishType = 'High Polish';

  // Date states
  String _orderDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _deliverDate = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 7)));

  @override
  void initState() {
    super.initState();
    if (widget.branches.isNotEmpty) {
      final firstBranch = widget.branches.first;
      _selectedBranchId = (firstBranch['Id'] ?? 0).toString();
      _selectedBranchName = firstBranch['BranchName']?.toString() ?? '';
    }
    // Extract unique purity values
    final purityNames = widget.dailyRates
        .map((r) => (r['PurityName'] as String? ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (purityNames.isNotEmpty) {
      _selectedPurity = purityNames.first;
    }
  }

  @override
  void dispose() {
    _exhibitionCtrl.dispose();
    _remarkCtrl.dispose();
    _sizeCtrl.dispose();
    _lengthCtrl.dispose();
    _finePerCtrl.dispose();
    _wastageCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isOrderDate) async {
    final initialDate = isOrderDate ? DateTime.now() : DateTime.now().add(const Duration(days: 7));
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

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    // Extract unique purity values
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
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title Header Bar (Dark Gray)
            Container(
              height: 52,
              color: const Color(0xFF3A3A3A),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.receipt, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    s.orderDetails,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Scrollable Form Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Branch Dropdown
                    _buildDropdownRow(
                      label: s.branchName,
                      options: widget.branches,
                      selectedValue: _selectedBranchName,
                      getOptionLabel: (b) => b['BranchName']?.toString() ?? '',
                      onSelected: (selectedName) {
                        final b = widget.branches.firstWhere((x) => x['BranchName'] == selectedName);
                        setState(() {
                          _selectedBranchName = selectedName;
                          _selectedBranchId = (b['Id'] ?? 0).toString();
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Exhibition
                    _buildFieldRow(s.exhibition, _exhibitionCtrl, hint: s.enterExhibition),
                    const SizedBox(height: 8),

                    // Remark
                    _buildFieldRow(s.remark, _remarkCtrl, hint: s.enterRemark),
                    const SizedBox(height: 8),

                    // Purity Dropdown
                    _buildDropdownRow(
                      label: s.purity,
                      options: purityNames,
                      selectedValue: _selectedPurity,
                      getOptionLabel: (p) => p,
                      onSelected: (selectedPurity) {
                        setState(() => _selectedPurity = selectedPurity);
                      },
                    ),
                    const SizedBox(height: 8),

                    // Size
                    _buildFieldRow(s.size, _sizeCtrl, hint: s.enterSize),
                    const SizedBox(height: 8),

                    // Length
                    _buildFieldRow(s.length, _lengthCtrl, hint: s.enterLength),
                    const SizedBox(height: 8),

                    // Colors Dropdown
                    _buildDropdownRow(
                      label: s.colorType,
                      options: colorsList,
                      selectedValue: _typeOfColor,
                      getOptionLabel: (c) => c,
                      onSelected: (col) {
                        setState(() => _typeOfColor = col);
                      },
                    ),
                    const SizedBox(height: 8),

                    // Screw Dropdown
                    _buildDropdownRow(
                      label: s.screwType,
                      options: screwList,
                      selectedValue: _screwType,
                      getOptionLabel: (s) => s,
                      onSelected: (scr) {
                        setState(() => _screwType = scr);
                      },
                    ),
                    const SizedBox(height: 8),

                    // Polish Dropdown
                    _buildDropdownRow(
                      label: s.polishType,
                      options: polishList,
                      selectedValue: _polishType,
                      getOptionLabel: (p) => p,
                      onSelected: (pol) {
                        setState(() => _polishType = pol);
                      },
                    ),
                    const SizedBox(height: 8),

                    // Fine %
                    _buildFieldRow(s.finePercent, _finePerCtrl, hint: s.enterFinePercentage, isNumber: true),
                    const SizedBox(height: 8),

                    // Wastage %
                    _buildFieldRow(s.wastagePercent, _wastageCtrl, hint: s.enterWastage, isNumber: true),
                    const SizedBox(height: 8),

                    // Order Date
                    _buildDateRow(s.orderDate, _orderDate, () => _selectDate(context, true)),
                    const SizedBox(height: 8),

                    // Deliver Date
                    _buildDateRow(s.deliveryDate, _deliverDate, () => _selectDate(context, false)),
                  ],
                ),
              ),
            ),

            // Bottom Actions (Save / Cancel)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          s.cancel,
                          style: GoogleFonts.poppins(color: Colors.grey[700], fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          widget.onConfirm({
                            'branchId': _selectedBranchId,
                            'branchName': _selectedBranchName,
                            'exhibition': _exhibitionCtrl.text.trim(),
                            'remark': _remarkCtrl.text.trim(),
                            'purity': _selectedPurity,
                            'size': _sizeCtrl.text.trim(),
                            'length': _lengthCtrl.text.trim(),
                            'color': _typeOfColor,
                            'screw': _screwType,
                            'polish': _polishType,
                            'finePercentage': _finePerCtrl.text.trim(),
                            'wastage': _wastageCtrl.text.trim(),
                            'orderDate': _orderDate,
                            'deliverDate': _deliverDate,
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          s.save,
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
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

  Widget _buildFieldRow(String label, TextEditingController controller,
      {required String hint, bool isNumber = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: controller,
                keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: hint,
                  hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                ),
              ),
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
  }) {
    final optionStrings = options.map((o) => getOptionLabel(o).trim()).toList();
    final cleanSelected = selectedValue.trim();
    final s = context.s;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: cleanSelected.isEmpty || !optionStrings.contains(cleanSelected)
                      ? null
                      : cleanSelected,
                  isExpanded: true,
                  hint: Text(s.selectLabel(label), style: GoogleFonts.poppins(fontSize: 12)),
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
                  items: optionStrings.map((String opt) {
                    return DropdownMenuItem<String>(
                      value: opt,
                      child: Text(opt),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      onSelected(newValue);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow(String label, String value, VoidCallback onPick) {
    String displayDate = '';
    if (value.isNotEmpty) {
      try {
        final parsed = DateTime.parse(value);
        displayDate = DateFormat('dd-MM-yyyy').format(parsed);
      } catch (_) {
        displayDate = value;
      }
    }
    final s = context.s;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      displayDate.isEmpty ? s.selectDate : displayDate,
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
                    ),
                    const Icon(Icons.calendar_today, size: 14, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
