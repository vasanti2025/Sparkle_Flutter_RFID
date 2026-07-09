import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';

const brandGradient = LinearGradient(
  colors: [Color(0xFF5231A7), Color(0xFFD32940)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const actionGradient = LinearGradient(
  colors: [Color(0xFF3053F0), Color(0xFFE82E5A)],
);

/// Matches Kotlin [FilterDropdown] — gradient stroke, compact height, transparent fill.
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        gradient: actionGradient,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: selected.isEmpty ? null : selected,
            hint: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            icon: Icon(Icons.arrow_drop_down, color: Colors.grey[400], size: 20),
            items: [
              ...options.map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, style: GoogleFonts.poppins(fontSize: 12), overflow: TextOverflow.ellipsis),
                ),
              ),
              DropdownMenuItem(
                value: 'ADD_NEW',
                child: Text(
                  '➕ Add New',
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF3053F0)),
                ),
              ),
            ],
            onChanged: (v) {
              if (v == 'ADD_NEW') {
                onAdd();
              } else if (v != null) {
                onSelected(v);
              }
            },
          ),
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
