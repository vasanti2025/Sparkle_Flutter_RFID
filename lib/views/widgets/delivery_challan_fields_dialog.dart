import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/customer.dart';
import '../../l10n/l10n_extension.dart';

class DeliveryChallanFieldsDialog extends StatefulWidget {
  final List<dynamic> branches;
  final List<CustomerModel> customers;
  final String initialBranchId;
  final String initialBranchName;
  final String initialDate;
  final String initialSalesman;
  final Function(Map<String, dynamic> result) onConfirm;

  const DeliveryChallanFieldsDialog({
    super.key,
    required this.branches,
    required this.customers,
    required this.initialBranchId,
    required this.initialBranchName,
    required this.initialDate,
    required this.initialSalesman,
    required this.onConfirm,
  });

  @override
  State<DeliveryChallanFieldsDialog> createState() => _DeliveryChallanFieldsDialogState();
}

class _DeliveryChallanFieldsDialogState extends State<DeliveryChallanFieldsDialog> {
  late String _selectedBranchId;
  late String _selectedBranchName;
  late String _date;
  late String _salesmanName;

  final _fineCtrl = TextEditingController();
  final _wastageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.initialBranchId;
    _selectedBranchName = widget.initialBranchName;
    _date = widget.initialDate;
    _salesmanName = widget.initialSalesman;
  }

  @override
  void dispose() {
    _fineCtrl.dispose();
    _wastageCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final parsedDate = DateTime.tryParse(_date) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: parsedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _date = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
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
            // Dark Header
            Container(
              height: 56,
              color: const Color(0xFF3A3A3A),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    s.customOrderFields,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
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
                    // Select Branch Dropdown
                    _buildDropdownRow(
                      label: s.selectBranch,
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
                    const SizedBox(height: 10),

                    // Date Picker Input
                    _buildDateRow(s.date, _date, () => _selectDate(context)),
                    const SizedBox(height: 10),

                    // Fine %
                    _buildFieldRow(s.finePercent, _fineCtrl),
                    const SizedBox(height: 10),

                    // Wastage
                    _buildFieldRow(s.wastagePercent, _wastageCtrl),
                    const SizedBox(height: 10),

                    // Salesman Dropdown
                    _buildDropdownRow(
                      label: s.salesman,
                      options: widget.customers,
                      selectedValue: _salesmanName,
                      getOptionLabel: (c) => '${c.firstName ?? ''} ${c.lastName ?? ''}'.trim(),
                      onSelected: (selectedName) {
                        setState(() => _salesmanName = selectedName);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
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
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          if (_selectedBranchName.isEmpty || _date.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.pleaseSelectBranchAndDate)),
                            );
                            return;
                          }
                          widget.onConfirm({
                            'branchName': _selectedBranchName,
                            'branchId': _selectedBranchId,
                            'date': _date,
                            'fine': _fineCtrl.text.trim(),
                            'wastage': _wastageCtrl.text.trim(),
                            'salesmanName': _salesmanName,
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          s.confirm,
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

  Widget _buildFieldRow(String label, TextEditingController controller) {
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
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
    // Check if selected value matches option label lists, if not clear selection value
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
