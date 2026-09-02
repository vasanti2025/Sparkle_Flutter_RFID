import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';
import '../../utils/app_dropdown.dart';

const brandGradient = LinearGradient(
  colors: [Color(0xFF5231A7), Color(0xFFD32940)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const actionGradient = LinearGradient(
  colors: [Color(0xFF3053F0), Color(0xFFE82E5A)],
);

/// Matches Kotlin [FilterDropdown] — gradient stroke, compact height, popup under the field.
class FilterDropdown extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onAdd;

  const FilterDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.onAdd,
  });

  static const _addValue = '__ADD_NEW__';

  List<String> get _uniqueOptions {
    final seen = <String>{};
    final unique = <String>[];
    for (final option in options) {
      final name = option.trim();
      if (name.isEmpty || name == _addValue) continue;
      if (seen.add(name)) unique.add(name);
    }
    return unique;
  }

  @override
  Widget build(BuildContext context) {
    final unique = _uniqueOptions;
    final display = selected.isNotEmpty ? selected : label;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        gradient: actionGradient,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(1),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return PopupMenuButton<String>(
              tooltip: label,
              padding: EdgeInsets.zero,
              offset: const Offset(0, 4),
              position: PopupMenuPosition.under,
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                maxWidth: math.max(constraints.maxWidth, 180),
                maxHeight: kDropdownMenuMaxHeight,
              ),
              onSelected: (value) {
                if (value == _addValue) {
                  onAdd();
                } else {
                  onSelected(value);
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem<String>(
                  value: _addValue,
                  height: 40,
                  child: Text(
                    '➕ Add New',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF3053F0),
                    ),
                  ),
                ),
                if (unique.isNotEmpty) const PopupMenuDivider(),
                for (final option in unique)
                  PopupMenuItem<String>(
                    value: option,
                    height: 40,
                    child: Text(
                      option,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: option == selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        display,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: Colors.grey[400], size: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Borderless inline table cell — matches Kotlin BasicTextField in bulk rows.
class BulkInlineTextField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final TextAlign textAlign;

  const BulkInlineTextField({
    super.key,
    required this.controller,
    this.onChanged,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textAlign: textAlign,
      style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF424242)),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
      ),
    );
  }
}

class ProductDropdownField extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback? onAdd;
  final bool enabled;

  const ProductDropdownField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.onAdd,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade400),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    menuMaxHeight: kDropdownMenuMaxHeight,
                    value: selected.isEmpty ? null : selected,
                    hint: Text(s.selectOption(label), style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
                    items: options
                        .map((o) => DropdownMenuItem(value: o, child: Text(o, style: GoogleFonts.poppins(fontSize: 13))))
                        .toList(),
                    onChanged: enabled
                        ? (v) {
                            if (v != null) onSelected(v);
                          }
                        : null,
                  ),
                ),
              ),
              if (onAdd != null)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF5231A7), size: 20),
                  onPressed: onAdd,
                  tooltip: 'Add $label',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProductTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final bool readOnly;
  final ValueChanged<String>? onChanged;

  const ProductTextField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }
}

PreferredSizeWidget productGradientAppBar({
  required BuildContext context,
  required String title,
  VoidCallback? onBack,
  bool showCounter = false,
  int selectedCount = 5,
  ValueChanged<int>? onCountSelected,
}) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(kToolbarHeight),
    child: Container(
      decoration: const BoxDecoration(gradient: brandGradient),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: onBack ?? () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20),
          overflow: TextOverflow.ellipsis,
        ),
        actions: showCounter && onCountSelected != null
            ? [
                _ScanPowerCounter(
                  selectedCount: selectedCount,
                  onCountSelected: onCountSelected,
                ),
              ]
            : null,
      ),
    ),
  );
}

class _ScanPowerCounter extends StatelessWidget {
  final int selectedCount;
  final ValueChanged<int> onCountSelected;

  const _ScanPowerCounter({
    required this.selectedCount,
    required this.onCountSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      offset: const Offset(0, 48),
      constraints: kPopupMenuConstraints,
      onSelected: onCountSelected,
      itemBuilder: (ctx) => List.generate(
        30,
        (i) => PopupMenuItem(value: i + 1, child: Text('${i + 1}', style: GoogleFonts.poppins())),
      ),
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          '$selectedCount',
          style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }
}

Widget productGradientButton({
  required String label,
  required VoidCallback? onPressed,
  double height = 48,
}) {
  return Container(
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: onPressed == null
          ? null
          : const LinearGradient(colors: [Color(0xFF3053F0), Color(0xFFE82E5A)]),
      color: onPressed == null ? Colors.grey.shade300 : null,
    ),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
    ),
  );
}
