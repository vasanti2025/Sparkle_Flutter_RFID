import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';
import '../../models/user_permission.dart';

Future<bool?> showStockTransferSubmitDialog({
  required BuildContext context,
  required bool isBranchToBranch,
  required String transferredBy,
  required List<UserPermission> employees,
  required Future<bool> Function(String transferToEmployeeId, String remarks) onSubmit,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _StockTransferSubmitDialog(
      isBranchToBranch: isBranchToBranch,
      transferredBy: transferredBy,
      employees: employees,
      onSubmit: onSubmit,
    ),
  );
}

class _StockTransferSubmitDialog extends StatefulWidget {
  final bool isBranchToBranch;
  final String transferredBy;
  final List<UserPermission> employees;
  final Future<bool> Function(String transferToEmployeeId, String remarks) onSubmit;

  const _StockTransferSubmitDialog({
    required this.isBranchToBranch,
    required this.transferredBy,
    required this.employees,
    required this.onSubmit,
  });

  @override
  State<_StockTransferSubmitDialog> createState() => _StockTransferSubmitDialogState();
}

class _StockTransferSubmitDialogState extends State<_StockTransferSubmitDialog> {
  final TextEditingController _remarksCtrl = TextEditingController();
  String? _selectedEmployeeId;
  bool _submitting = false;

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  String _employeeLabel(String? id) {
    if (id == null || id.isEmpty) return context.s.tr('selectEmployee');
    for (final e in widget.employees) {
      if (e.employeeId.toString() == id) return e.displayName;
    }
    return id;
  }

  Future<void> _pickEmployee() async {
    if (widget.employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.s.tr('selectEmployee'))),
      );
      return;
    }
    final picked = await showModalBottomSheet<UserPermission>(
      context: context,
      builder: (c) => ListView(
        children: widget.employees
            .map(
              (e) => ListTile(
                title: Text('${e.displayName} (${e.employeeId})', style: GoogleFonts.poppins()),
                onTap: () => Navigator.pop(c, e),
              ),
            )
            .toList(),
      ),
    );
    if (picked != null) {
      setState(() => _selectedEmployeeId = picked.employeeId.toString());
    }
  }

  Future<void> _handleOk() async {
    final s = context.s;
    if (widget.isBranchToBranch && (_selectedEmployeeId == null || _selectedEmployeeId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.tr('selectEmployeeError'))),
      );
      return;
    }
    setState(() => _submitting = true);
    final ok = await widget.onSubmit(
      widget.isBranchToBranch ? _selectedEmployeeId! : '',
      _remarksCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF3F51B5)]),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                s.tr('transferDetails'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            _readOnlyRow(s.tr('transferredBy'), widget.transferredBy),
            if (widget.isBranchToBranch) ...[
              const SizedBox(height: 10),
              _dropdownRow(
                label: s.tr('transferredTo'),
                value: _employeeLabel(_selectedEmployeeId),
                isPlaceholder: _selectedEmployeeId == null,
                onTap: _pickEmployee,
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
              controller: _remarksCtrl,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: s.remark,
                filled: true,
                fillColor: const Color(0xFFF7F7F7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(10),
              ),
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _gradientButton(s.tr('cancel'), () => Navigator.pop(context, false))),
                const SizedBox(width: 12),
                Expanded(
                  child: _gradientButton(
                    s.tr('ok'),
                    _submitting ? null : _handleOk,
                    loading: _submitting,
                  ),
                ),
              ],
            ),
          ],
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
          color: onTap == null && !loading ? Colors.grey : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(text, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
