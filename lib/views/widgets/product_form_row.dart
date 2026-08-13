import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/app_dropdown.dart';

/// Label-left / value-right row matching Kotlin [FormRow] in AddProductScreen.
/// Dropdowns use a scrollable popup menu (not a bottom sheet), same as Sparkle.
class ProductFormRow extends StatefulWidget {
  final String label;
  final String value;
  final bool isDropdown;
  final List<String> options;
  final bool disabled;
  final bool readOnly;
  final TextInputType? keyboardType;
  final bool numericInput;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final VoidCallback? onTapWhenEmpty;
  /// When set, shows clear (if value) or QR scan icon (if empty) on text fields.
  final VoidCallback? onScanTap;
  /// Highlights the value box when this row is the active scan target.
  final bool isScanActive;
  final ValueChanged<bool>? onFocusChanged;

  const ProductFormRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.isDropdown = false,
    this.options = const [],
    this.disabled = false,
    this.readOnly = false,
    this.keyboardType,
    this.numericInput = false,
    this.hintText,
    this.onTapWhenEmpty,
    this.onScanTap,
    this.isScanActive = false,
    this.onFocusChanged,
  });

  @override
  State<ProductFormRow> createState() => ProductFormRowState();
}

class ProductFormRowState extends State<ProductFormRow> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _dropdownKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    _focusNode.addListener(_notifyFocusChanged);
  }

  void requestFieldFocus() {
    if (widget.readOnly || widget.disabled) return;
    _focusNode.requestFocus();
  }

  void _notifyFocusChanged() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
  }

  @override
  void didUpdateWidget(ProductFormRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _ctrl.text && (!_focusNode.hasFocus || widget.readOnly)) {
      _ctrl.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_notifyFocusChanged);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String get _placeholder {
    if (widget.hintText != null && widget.hintText!.isNotEmpty) {
      return widget.hintText!;
    }
    if (!widget.isDropdown) return 'Tap to enter…';
    return 'Select';
  }

  bool get _isNumericField => widget.numericInput;

  Future<void> _openDropdownPicker() async {
    if (widget.disabled) return;
    if (widget.options.isEmpty) {
      widget.onTapWhenEmpty?.call();
      return;
    }

    final box = _dropdownKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );

    final picked = await showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(
        maxHeight: kDropdownMenuMaxHeight,
        minWidth: box.size.width,
        maxWidth: math.max(box.size.width, 220),
      ),
      items: [
        for (final option in widget.options)
          PopupMenuItem<String>(
            value: option,
            height: 40,
            child: Text(
              option,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: option == widget.value ? FontWeight.w600 : FontWeight.normal,
                color: const Color(0xFF222222),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );

    if (picked != null && picked != widget.value) {
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 8,
            child: Text(
              widget.label,
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 12,
            child: Container(
              key: _dropdownKey,
              decoration: BoxDecoration(
                color: widget.disabled ? const Color(0xFFF5F5F5) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: widget.isScanActive
                    ? Border.all(color: const Color(0xFF5231A7), width: 1.5)
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              child: widget.isDropdown ? _buildDropdown() : _buildTextField(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown() {
    final display = widget.value.isNotEmpty ? widget.value : _placeholder;
    final hasValue = widget.value.isNotEmpty;
    final canPick = !widget.disabled && widget.options.isNotEmpty;

    return InkWell(
      onTap: canPick ? _openDropdownPicker : (widget.onTapWhenEmpty),
      child: Row(
        children: [
          Expanded(
            child: Text(
              display,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: hasValue ? Colors.black87 : Colors.grey,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasValue && !widget.disabled)
            GestureDetector(
              onTap: () => widget.onChanged(''),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.clear, size: 18, color: Colors.grey),
              ),
            ),
          Icon(
            Icons.arrow_drop_down,
            color: canPick ? Colors.black54 : Colors.grey.shade400,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField() {
    final showScan = widget.onScanTap != null && !widget.disabled && !widget.readOnly;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focusNode,
            readOnly: widget.readOnly || widget.disabled,
            keyboardType: widget.keyboardType ??
                (_isNumericField
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text),
            inputFormatters: _isNumericField
                ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
                : null,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: _placeholder,
              hintStyle: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: widget.onChanged,
          ),
        ),
        if (showScan)
          GestureDetector(
            onTap: () {
              if (widget.value.isNotEmpty) {
                widget.onChanged('');
              } else {
                widget.onScanTap!();
              }
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                widget.value.isNotEmpty ? Icons.clear : Icons.qr_code_scanner,
                size: 18,
                color: Colors.grey,
              ),
            ),
          ),
      ],
    );
  }
}
