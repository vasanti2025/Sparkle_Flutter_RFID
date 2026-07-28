import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared Poppins text styles (wraps [GoogleFonts.poppins]).
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
    return GoogleFonts.poppins(
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
