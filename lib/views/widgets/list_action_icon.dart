import 'package:flutter/material.dart';

/// Sparkle list-row action tint (gray-black — Quotation/Challan/Sample use 0xFF37474F).
const Color kListActionIconColor = Color(0xFF37474F);

/// Flat edit/print/delete icon like Sparkle lists (no colored circle badges).
Widget listActionIcon({
  required IconData icon,
  required VoidCallback onTap,
  double size = 18,
  Color color = kListActionIconColor,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Icon(icon, size: size, color: color),
    ),
  );
}
