import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../l10n/l10n_extension.dart';

class SampleOutFieldsDialog extends StatefulWidget {
  final String initialDate;
  final String initialReturnDate;
  final String initialDescription;
  final Function(Map<String, String> result) onConfirm;

  const SampleOutFieldsDialog({
    super.key,
    required this.initialDate,
    required this.initialReturnDate,
    required this.initialDescription,
    required this.onConfirm,
  });

  @override
  State<SampleOutFieldsDialog> createState() => _SampleOutFieldsDialogState();
}

class _SampleOutFieldsDialogState extends State<SampleOutFieldsDialog> {
  late String _date;
  late String _returnDate;
  late final TextEditingController _descriptionCtrl;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate.isNotEmpty
        ? widget.initialDate
        : DateFormat('yyyy-MM-dd').format(DateTime.now());
    _returnDate = widget.initialReturnDate.isNotEmpty ? widget.initialReturnDate : _date;
    _descriptionCtrl = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isReturn) async {
    final initial = DateTime.tryParse(isReturn ? _returnDate : _date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        final formatted = DateFormat('yyyy-MM-dd').format(picked);
        if (isReturn) {
          _returnDate = formatted;
        } else {
          _date = formatted;
        }
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                ),
              ),
              child: Text(
                s.customOrderFields,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dateField(s.date, _date, () => _pickDate(false)),
                  const SizedBox(height: 12),
                  _dateField(s.returnTitle, _returnDate, () => _pickDate(true)),
                  const SizedBox(height: 12),
                  Text(s.description, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _descriptionCtrl,
                    maxLines: 3,
                    style: GoogleFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: s.enterDescription,
                      hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(s.cancel, style: GoogleFonts.poppins()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5231A7),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            widget.onConfirm({
                              'date': _date,
                              'returnDate': _returnDate,
                              'description': _descriptionCtrl.text.trim(),
                            });
                            Navigator.pop(context);
                          },
                          child: Text(s.confirm, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField(String label, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value, style: GoogleFonts.poppins(fontSize: 13)),
                ),
                const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
