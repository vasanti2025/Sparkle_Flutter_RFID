import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';

class AddCustomerDialog extends StatefulWidget {
  final String title;
  final Function(Map<String, dynamic> req) onSave;

  const AddCustomerDialog({
    super.key,
    required this.title,
    required this.onSave,
  });

  @override
  State<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<AddCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  String _selectedCountry = 'India';
  String _selectedState = 'Maharashtra';

  final List<String> _countries = ['India', 'USA', 'UK', 'Canada'];
  final List<String> _states = [
    'Andhra Pradesh', 'Bihar', 'Goa', 'Gujarat', 'Karnataka',
    'Kerala', 'Maharashtra', 'Rajasthan', 'Tamil Nadu', 'Telangana'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _panCtrl.dispose();
    _gstCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
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
              color: const Color(0xFF2E2E2E),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.person_add, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Form Fields
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: _nameCtrl,
                        hintText: s.fieldCustomerName,
                        validator: (v) => v == null || v.trim().isEmpty ? s.validationNameRequired : null,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _phoneCtrl,
                        hintText: s.fieldMobileNumber,
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return s.validationMobileRequired;
                          if (v.trim().length != 10 || double.tryParse(v.trim()) == null) {
                            return s.validationMobileDigits;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _emailCtrl,
                        hintText: s.fieldEmailAddress,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _panCtrl,
                        hintText: s.fieldPanNumber,
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) {
                          if (v != null && v.isNotEmpty && v.trim().length != 10) {
                            return s.validationPanDigits;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _gstCtrl,
                        hintText: s.fieldGstNumber,
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) {
                          if (v != null && v.isNotEmpty && v.trim().length != 15) {
                            return s.validationGstDigits;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _streetCtrl,
                        hintText: s.fieldStreetAddress,
                      ),
                      const SizedBox(height: 10),

                      // Dropdown Row (Country & State)
                      Row(
                        children: [
                          Expanded(
                            child: _buildDropdownField(
                              value: _selectedCountry,
                              items: _countries,
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedCountry = v);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildDropdownField(
                              value: _selectedState,
                              items: _states,
                              onChanged: (v) {
                                if (v != null) setState(() => _selectedState = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      _buildTextField(
                        controller: _cityCtrl,
                        hintText: s.fieldCity,
                      ),
                    ],
                  ),
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
                          if (_formKey.currentState?.validate() ?? false) {
                            final names = _nameCtrl.text.trim().split(' ');
                            final first = names.first;
                            final last = names.length > 1 ? names.sublist(1).join(' ') : '';

                            final req = {
                              'FirstName': first,
                              'LastName': last,
                              'Mobile': _phoneCtrl.text.trim(),
                              'Email': _emailCtrl.text.trim(),
                              'PanNo': _panCtrl.text.trim().toUpperCase(),
                              'GstNo': _gstCtrl.text.trim().toUpperCase(),
                              'PerAddStreet': _streetCtrl.text.trim(),
                              'City': _cityCtrl.text.trim(),
                              'CurrAddState': _selectedState,
                              'Country': _selectedCountry,
                            };
                            widget.onSave(req);
                          }
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
