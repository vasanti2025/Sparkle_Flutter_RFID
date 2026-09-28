import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';
import '../../services/country_state_service.dart';
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
  final _countryManualCtrl = TextEditingController();
  final _stateManualCtrl = TextEditingController();

  String? _selectedCountry;
  String? _selectedState;
  List<String> _countries = const [];
  List<String> _states = const [];
  bool _loadingCountries = true;
  bool _loadingStates = false;
  bool _useManualLocation = false;

  static final _emailRe = RegExp(
    r'^[a-zA-Z0-9_+&*-]+(?:\.[a-zA-Z0-9_+&*-]+)*@(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,7}$',
  );
  static final _panRe = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
  static final _gstRe = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[A-Z0-9]{1}[A-Z]{1}[0-9]{1}$',
  );
  static final _nameDigitRe = RegExp(r'\d');

  @override
  void initState() {
    super.initState();
    _countryManualCtrl.addListener(_onManualCountryChanged);
    _loadCountries();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _panCtrl.dispose();
    _gstCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _countryManualCtrl.dispose();
    _stateManualCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    setState(() {
      _loadingCountries = true;
      _useManualLocation = false;
    });
    try {
      final countries = await CountryStateService.fetchCountries();
      if (!mounted) return;
      if (countries.isEmpty) {
        setState(() {
          _loadingCountries = false;
          _useManualLocation = true;
        });
        return;
      }
      final preferred = countries.contains('India') ? 'India' : countries.first;
      setState(() {
        _countries = countries;
        _selectedCountry = preferred;
        _loadingCountries = false;
      });
      _clipMobileToRule();
      await _loadStates(preferred);
    } catch (e) {
      debugPrint('AddCustomer loadCountries: $e');
      if (!mounted) return;
      setState(() {
        _loadingCountries = false;
        _useManualLocation = true;
      });
    }
  }

  Future<void> _loadStates(String country) async {
    setState(() {
      _loadingStates = true;
      _states = const [];
      _selectedState = null;
    });
    try {
      final states = await CountryStateService.fetchStates(country);
      if (!mounted) return;
      String? selected;
      if (states.isNotEmpty) {
        selected = country == 'India' && states.contains('Maharashtra')
            ? 'Maharashtra'
            : states.first;
      }
      setState(() {
        _states = states;
        _selectedState = selected;
        _loadingStates = false;
      });
      _clipMobileToRule();
    } catch (e) {
      debugPrint('AddCustomer loadStates: $e');
      if (!mounted) return;
      setState(() {
        _states = const [];
        _selectedState = null;
        _loadingStates = false;
      });
    }
  }

  String _countryForSave() {
    if (_useManualLocation) return _countryManualCtrl.text.trim();
    return _selectedCountry?.trim() ?? '';
  }

  String _stateForSave() {
    if (_useManualLocation) return _stateManualCtrl.text.trim();
    return _selectedState?.trim() ?? '';
  }

  _MobileRule _mobileRule() {
    return _MobileRule.forLocation(_countryForSave(), _stateForSave());
  }

  void _onManualCountryChanged() {
    if (!_useManualLocation) return;
    _clipMobileToRule();
    if (mounted) setState(() {});
  }

  void _clipMobileToRule() {
    final max = _mobileRule().max;
    final phone = _phoneCtrl.text;
    if (phone.length > max) {
      _phoneCtrl.value = TextEditingValue(
        text: phone.substring(0, max),
        selection: TextSelection.collapsed(offset: max),
      );
    }
  }

  String? _validateMobile(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return context.s.validationMobileRequired;
    final rule = _mobileRule();
    if (!RegExp(r'^\d+$').hasMatch(phone) ||
        phone.length < rule.min ||
        phone.length > rule.max) {
      return rule.min == rule.max
          ? 'Enter a valid ${rule.min}-digit mobile number'
          : 'Enter a valid ${rule.min}-${rule.max} digit mobile number';
    }
    return null;
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
                        key: ValueKey('mobile-${_mobileRule().min}-${_mobileRule().max}'),
                        controller: _phoneCtrl,
                        hintText: s.fieldMobileNumber,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_mobileRule().max),
                        ],
                        validator: _validateMobile,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildCountryField()),
                          const SizedBox(width: 8),
                          Expanded(child: _buildStateField()),
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
                            if (_countryForSave().isEmpty) return;
                            if (!_useManualLocation &&
                                _states.isNotEmpty &&
                                _stateForSave().isEmpty) {
                              return;
                            }
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
                              'CurrAddState': _stateForSave(),
                              'Country': _countryForSave(),
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
    Key? key,
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: key,
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

  Widget _buildCountryField() {
    if (_useManualLocation) {
      return _buildTextField(
        controller: _countryManualCtrl,
        hintText: 'Country *',
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Please select country';
          return null;
        },
      );
    }
    return FormField<String>(
      validator: (_) {
        if (_loadingCountries) return 'Loading countries…';
        if (_countryForSave().isEmpty) return 'Please select country';
        return null;
      },
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPickerBox(
              label: _loadingCountries
                  ? 'Loading countries…'
                  : (_selectedCountry ?? 'Country *'),
              hint: _selectedCountry == null,
              enabled: !_loadingCountries && _countries.isNotEmpty,
              loading: _loadingCountries,
              onTap: () async {
                final picked = await showScrollableOptionSheet<String>(
                  context: context,
                  title: 'Country',
                  options: _countries,
                  labelOf: (v) => v,
                  searchable: true,
                );
                if (picked == null || !mounted) return;
                setState(() => _selectedCountry = picked);
                field.didChange(picked);
                _clipMobileToRule();
                await _loadStates(picked);
              },
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  field.errorText!,
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[700]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStateField() {
    if (_useManualLocation) {
      return _buildTextField(
        controller: _stateManualCtrl,
        hintText: 'State',
      );
    }
    final noStates =
        !_loadingStates && _states.isEmpty && _selectedCountry != null;
    return FormField<String>(
      validator: (_) {
        if (_loadingStates) return 'Loading states…';
        if (!noStates && _states.isNotEmpty && _stateForSave().isEmpty) {
          return 'Please select state';
        }
        return null;
      },
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPickerBox(
              label: _loadingStates
                  ? 'Loading states…'
                  : (_selectedState ?? (noStates ? 'No states' : 'State *')),
              hint: _selectedState == null,
              enabled: !_loadingStates && _states.isNotEmpty,
              loading: _loadingStates,
              onTap: () async {
                final picked = await showScrollableOptionSheet<String>(
                  context: context,
                  title: 'State',
                  options: _states,
                  labelOf: (v) => v,
                  searchable: true,
                );
                if (picked == null || !mounted) return;
                setState(() => _selectedState = picked);
                field.didChange(picked);
                _clipMobileToRule();
              },
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  field.errorText!,
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[700]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPickerBox({
    required String label,
    required bool hint,
    required bool enabled,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: hint ? Colors.grey[500] : Colors.black,
                ),
              ),
            ),
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.arrow_drop_down, color: Colors.grey[700]),
          ],
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

/// National mobile digit lengths by country (Countries Now names / aliases).
/// State is accepted so rules can vary by state later; India is 10 in every state.
class _MobileRule {
  final int min;
  final int max;
  const _MobileRule(this.min, [int? max]) : max = max ?? min;

  static _MobileRule forLocation(String country, String state) {
    final c = country.trim().toLowerCase();
    if (c.isEmpty) return const _MobileRule(10);

    switch (c) {
      case 'india':
      case 'in':
        return const _MobileRule(10);
      case 'united kingdom':
      case 'uk':
      case 'great britain':
      case 'england':
      case 'scotland':
      case 'wales':
      case 'northern ireland':
        return const _MobileRule(11);
      case 'united states':
      case 'united states of america':
      case 'usa':
      case 'us':
      case 'canada':
      case 'pakistan':
      case 'bangladesh':
      case 'nepal':
      case 'saudi arabia':
      case 'egypt':
      case 'nigeria':
      case 'mexico':
      case 'argentina':
      case 'colombia':
      case 'philippines':
      case 'south korea':
      case 'korea':
      case 'japan':
      case 'italy':
      case 'spain':
      case 'russia':
      case 'turkey':
      case 'south africa':
        return const _MobileRule(10);
      case 'china':
        return const _MobileRule(11);
      case 'united arab emirates':
      case 'uae':
      case 'australia':
      case 'france':
      case 'new zealand':
      case 'sri lanka':
      case 'thailand':
      case 'malaysia':
      case 'israel':
      case 'jordan':
      case 'kenya':
      case 'ghana':
      case 'morocco':
      case 'chile':
      case 'peru':
        return const _MobileRule(9);
      case 'singapore':
      case 'hong kong':
      case 'qatar':
      case 'kuwait':
      case 'oman':
      case 'bahrain':
      case 'denmark':
      case 'norway':
        return const _MobileRule(8);
      case 'indonesia':
        return const _MobileRule(10, 12);
      case 'brazil':
        return const _MobileRule(10, 11);
      case 'vietnam':
        return const _MobileRule(9, 10);
      case 'ireland':
      case 'sweden':
      case 'finland':
        return const _MobileRule(9, 10);
      case 'germany':
        return const _MobileRule(10, 11);
      default:
        return const _MobileRule(7, 15);
    }
  }
}
