import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared UI type. Renders Bodoni Moda. Method name stays so existing call sites keep working.
class AppFonts {
  AppFonts._();

  static TextStyle poppins({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.bodoniModa(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      decoration: decoration,
    );
  }
}
