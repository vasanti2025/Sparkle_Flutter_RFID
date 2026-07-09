import 'package:flutter/material.dart';

/// Cached text styles for scroll/list hot paths — avoids per-cell GoogleFonts work.
class ListTextStyles {
  ListTextStyles._();

  static TextStyle? _cell;
  static TextStyle? _header;

  static TextStyle cell(BuildContext context) =>
      _cell ??= Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Colors.black87,
          ) ??
      const TextStyle(fontSize: 11, color: Colors.black87);

  static TextStyle header(BuildContext context) =>
      _header ??= Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ) ??
      const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87);
}
