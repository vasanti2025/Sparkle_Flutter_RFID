import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../services/locale_service.dart';
import 'app_strings.dart';

extension L10nBuildContext on BuildContext {
  AppStrings get s => watch<LocaleService>().strings;

  AppStrings get sRead => read<LocaleService>().strings;
}
