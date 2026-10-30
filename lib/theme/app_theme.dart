import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/app_dialogs.dart';

/// Sparkle RFID cosmetic palette. Layout stays the same; only paint changes.
class AppColors {
  AppColors._();

  static const Color ink = Color(0xFF1A1A1A);
  static const Color inkSoft = Color(0xFF3A3228);
  static const Color gold = Color(0xFFC4A35A);
  static const Color goldDeep = Color(0xFFA6853E);
  static const Color cream = Color(0xFFF6F4F0);
  static const Color line = Color(0xFFE6E1D8);

  static const LinearGradient inkGradient = LinearGradient(
    colors: [ink, inkSoft],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [gold, goldDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.cream,
    colorScheme: const ColorScheme.light(
      primary: AppColors.ink,
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      onSecondary: AppColors.ink,
      surface: AppColors.cream,
      onSurface: AppColors.ink,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: NoZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: NoZoomPageTransitionsBuilder(),
        TargetPlatform.linux: NoZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: NoZoomPageTransitionsBuilder(),
        TargetPlatform.windows: NoZoomPageTransitionsBuilder(),
        TargetPlatform.fuchsia: NoZoomPageTransitionsBuilder(),
      },
    ),
  );

  final textTheme = GoogleFonts.bodoniModaTextTheme(base.textTheme);
  final primaryTextTheme = GoogleFonts.bodoniModaTextTheme(base.primaryTextTheme);

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.ink,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: GoogleFonts.bodoniModa(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.gold),
    primaryIconTheme: const IconThemeData(color: Colors.white),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.gold),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.gold;
        return null;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
    ),
    dividerColor: AppColors.line,
  );
}
