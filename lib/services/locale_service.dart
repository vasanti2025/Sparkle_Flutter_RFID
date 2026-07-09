import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import 'pref_service.dart';

class LocaleService extends ChangeNotifier {
  final PrefService _prefService;
  String _languageCode;

  LocaleService(this._prefService) : _languageCode = _prefService.getAppLanguage();

  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);
  AppStrings get strings => AppStrings.of(_languageCode);
  TextDirection get textDirection => _languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

  Future<void> setLanguage(String code) async {
    if (!AppStrings.supported.contains(code)) return;
    await _prefService.saveAppLanguage(code);
    _languageCode = code;
    notifyListeners();
  }
}
