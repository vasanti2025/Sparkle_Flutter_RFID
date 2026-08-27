import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';
import '../../utils/app_dropdown.dart';

/// Add Customer Profile dialog — validation aligned with Sparkle
/// `CustomerNameInputData.AddCustomerDialog` (+ letters-only name).
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

  // Same patterns as Sparkle AddCustomerDialog.
  static final _phoneRe = RegExp(r'^[0-9]{10}$');
  static final _emailRe = RegExp(
    r'^[a-zA-Z0-9_+&*-]+(?:\.[a-zA-Z0-9_+&*-]+)*@(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,7}$',
  );
  static final _panRe = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
  static final _gstRe = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[A-Z0-9]{1}[A-Z]{1}[0-9]{1}$',
  );
  static final _nameDigitRe = RegExp(r'\d');

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
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
                        ],
                        validator: (v) {
                          final name = v?.trim() ?? '';
                          if (name.isEmpty) return s.validationNameRequired;
                          if (_nameDigitRe.hasMatch(name)) {
                            return s.validationNameLettersOnly;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _phoneCtrl,
                        hintText: s.fieldMobileNumber,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator: (v) {
                          final phone = v?.trim() ?? '';
                          if (phone.isEmpty) return s.validationMobileRequired;
                          if (!_phoneRe.hasMatch(phone)) {
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
                        validator: (v) {
                          final email = v?.trim() ?? '';
                          if (email.isNotEmpty && !_emailRe.hasMatch(email)) {
                            return s.validationEmailInvalid;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _panCtrl,
                        hintText: s.fieldPanNumber,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                          LengthLimitingTextInputFormatter(10),
                          _UpperCaseTextFormatter(),
                        ],
                        validator: (v) {
                          final pan = (v ?? '').trim().toUpperCase();
                          if (pan.isNotEmpty && !_panRe.hasMatch(pan)) {
                            return s.validationPanInvalid;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildTextField(
                        controller: _gstCtrl,
                        hintText: s.fieldGstNumber,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                          LengthLimitingTextInputFormatter(15),
                          _UpperCaseTextFormatter(),
                        ],
                        validator: (v) {
                          final gst = (v ?? '').trim().toUpperCase();
                          if (gst.isNotEmpty && !_gstRe.hasMatch(gst)) {
                            return s.validationGstInvalid;
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
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return s.validationCityRequired;
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

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
                          style: GoogleFonts.poppins(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.bold,
                          ),
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
                            final names = _nameCtrl.text.trim().split(RegExp(r'\s+'));
                            final first = names.first;
                            final last =
                                names.length > 1 ? names.sublist(1).join(' ') : '';

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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
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
        errorMaxLines: 2,
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
          menuMaxHeight: kDropdownMenuMaxHeight,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.black),
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
