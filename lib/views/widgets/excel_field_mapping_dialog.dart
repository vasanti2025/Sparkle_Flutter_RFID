import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../services/excel_product_service.dart';
import '../../l10n/l10n_extension.dart';

/// Matches Kotlin [TableMappingScreen] / [MappingDialogWrapper].
class ExcelFieldMappingDialog extends StatefulWidget {
  final List<String> excelColumns;
  final void Function(Map<String, String> mapping) onImport;
  final VoidCallback onDismiss;

  const ExcelFieldMappingDialog({
    super.key,
    required this.excelColumns,
    required this.onImport,
    required this.onDismiss,
  });

  @override
  State<ExcelFieldMappingDialog> createState() => _ExcelFieldMappingDialogState();
}

class _ExcelFieldMappingDialogState extends State<ExcelFieldMappingDialog> {
  final Map<String, String> _mapping = {};

  static const _labelStyle = TextStyle(fontSize: 12, color: Color(0xFF1F2937), fontFamily: 'Poppins');
  static const _headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Poppins');
  static const _hintStyle = TextStyle(fontSize: 11, color: Color(0xFF9AA0A6), fontFamily: 'Poppins');

  Map<String, List<String>> _availableOptionsByField() {
    final used = _mapping.values.where((v) => v.isNotEmpty).toSet();
    final result = <String, List<String>>{};
    for (final fieldKey in ExcelProductService.importFieldKeys) {
      final selected = _mapping[fieldKey] ?? '';
      result[fieldKey] = widget.excelColumns
          .where((c) => c == selected || !used.contains(c))
          .toList(growable: false);
    }
    return result;
  }

  void _onFieldSelected(String fieldKey, String value) {
    setState(() => _mapping[fieldKey] = value);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final scrollHeight = math.min(400.0, screenHeight * 0.5);
    final availableByField = _availableOptionsByField();
    final fieldKeys = ExcelProductService.importFieldKeys;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: screenHeight * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF3053F0), Color(0xFFE82E5A)]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.tableView,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Poppins'),
                  ),
                  Text(
                    s.selectTableViewFields,
                    style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.2, fontFamily: 'Poppins'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: scrollHeight,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F5F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(s.mainFields, style: _headerStyle, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s.selectSheetFields, style: _headerStyle, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: fieldKeys.length,
                      itemExtent: 44,
                      itemBuilder: (context, index) {
                        final fieldKey = fieldKeys[index];
                        return _MappingFieldRow(
                          label: ExcelProductService.importFieldLabels[fieldKey] ?? fieldKey,
                          selected: _mapping[fieldKey] ?? '',
                          options: availableByField[fieldKey] ?? const [],
                          onSelected: (v) => _onFieldSelected(fieldKey, v),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _actionBtn(s.cancel, widget.onDismiss),
                  const SizedBox(width: 16),
                  _actionBtn(s.import, () => widget.onImport(Map<String, String>.from(_mapping))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(String label, VoidCallback onTap) {
    return SizedBox(
      width: 100,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(colors: [Color(0xFF3053F0), Color(0xFFE82E5A)]),
        ),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: EdgeInsets.zero,
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Poppins')),
        ),
      ),
    );
  }
}

class _MappingFieldRow extends StatelessWidget {
  final String label;
  final String selected;
  final List<String> options;
  final ValueChanged<String> onSelected;

  const _MappingFieldRow({
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 40,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label, style: _ExcelFieldMappingDialogState._labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: selected.isNotEmpty ? selected : null,
                hint: Text(s.mapColumn, style: _ExcelFieldMappingDialogState._hintStyle, overflow: TextOverflow.ellipsis),
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                items: options
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, style: _ExcelFieldMappingDialogState._labelStyle, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onSelected(v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}