import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Label-left / value-right row matching Kotlin [FormRow] in AddProductScreen.
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
  });

  @override
  State<ProductFormRow> createState() => _ProductFormRowState();
}

class _ProductFormRowState extends State<ProductFormRow> {
  late TextEditingController _ctrl;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
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

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.5,
            minChildSize: 0.25,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      widget.label,
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: widget.options.length,
                      itemBuilder: (context, index) {
                        final option = widget.options[index];
                        final selected = option == widget.value;
                        return ListTile(
                          title: Text(
                            option,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          trailing: selected ? const Icon(Icons.check, color: Color(0xFF5231A7)) : null,
                          onTap: () => Navigator.pop(ctx, option),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
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
              decoration: BoxDecoration(
                color: widget.disabled ? const Color(0xFFF5F5F5) : Colors.white,
                borderRadius: BorderRadius.circular(6),
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
    return TextField(
      controller: _ctrl,
      focusNode: _focusNode,
      readOnly: widget.readOnly || widget.disabled,
      keyboardType: widget.keyboardType ?? (_isNumericField ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text),
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
    );
  }
}
