import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/excel_product_service.dart';
import '../../services/pref_service.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/l10n_extension.dart';
import '../../utils/app_dropdown.dart';

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
  final TextEditingController _templateNameController = TextEditingController();
  Map<String, Map<String, String>> _templates = {};
  String? _selectedTemplate;
  String? _statusMessage;
  bool _statusError = false;

  static const _labelStyle = TextStyle(fontSize: 12, color: Color(0xFF1F2937), fontFamily: 'Poppins');
  static const _headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Poppins');
  static const _hintStyle = TextStyle(fontSize: 11, color: Color(0xFF9AA0A6), fontFamily: 'Poppins');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pref = context.read<PrefService>();
      _templates = pref.getImportMappingTemplates();
      final last = pref.getLastImportMappingTemplateName();
      if (last != null) {
        _applyTemplate(last, showMessage: false);
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _templateNameController.dispose();
    super.dispose();
  }

  Map<String, String> _columnLookup() {
    final map = <String, String>{};
    for (final column in widget.excelColumns) {
      map[column] = column;
      map[column.trim().toLowerCase()] = column;
    }
    return map;
  }

  int _applyTemplate(String name, {bool showMessage = true}) {
    final saved = _templates[name];
    if (saved == null) return 0;
    final lookup = _columnLookup();
    final used = <String>{};
    final next = <String, String>{};
    for (final entry in saved.entries) {
      if (!ExcelProductService.importFieldKeys.contains(entry.key)) continue;
      final column = lookup[entry.value] ?? lookup[entry.value.trim().toLowerCase()];
      if (column == null || column.isEmpty || used.contains(column)) continue;
      used.add(column);
      next[entry.key] = column;
    }
    setState(() {
      _mapping
        ..clear()
        ..addAll(next);
      _selectedTemplate = next.isEmpty ? null : name;
      if (next.isNotEmpty) {
        _templateNameController.text = name;
      }
      if (showMessage) {
        _statusError = next.isEmpty;
        _statusMessage = next.isEmpty
            ? context.sRead.noMatchingColumnsInFile
            : context.sRead.templateApplied;
      }
    });
    if (next.isNotEmpty) {
      context.read<PrefService>().setLastImportMappingTemplateName(name);
    }
    return next.length;
  }

  Future<void> _saveTemplate() async {
    final s = context.sRead;
    final name = _templateNameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _statusError = true;
        _statusMessage = s.enterTemplateNameFirst;
      });
      return;
    }
    if (_mapping.isEmpty) {
      setState(() {
        _statusError = true;
        _statusMessage = s.mapColumnsToSaveTemplate;
      });
      return;
    }
    final pref = context.read<PrefService>();
    await pref.saveImportMappingTemplate(name, _mapping);
    if (!mounted) return;
    setState(() {
      _templates = pref.getImportMappingTemplates();
      _selectedTemplate = name;
      _statusError = false;
      _statusMessage = s.templateSaved;
    });
  }

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
    setState(() {
      if (value.isEmpty) {
        _mapping.remove(fieldKey);
      } else {
        _mapping[fieldKey] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final media = MediaQuery.of(context);
    const insetV = 8.0;
    final maxDialogHeight =
        (media.size.height - media.viewInsets.bottom - insetV * 2).clamp(240.0, media.size.height);
    final availableByField = _availableOptionsByField();
    final fieldKeys = ExcelProductService.importFieldKeys;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      child: SizedBox(
        width: math.min(560, media.size.width - 24),
        height: maxDialogHeight,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF3053F0), Color(0xFFE82E5A)]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.tableView,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Poppins'),
                  ),
                  Text(
                    s.selectTableViewFields,
                    style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.2, fontFamily: 'Poppins'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _buildTemplateSection(s),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 5),
              child: Container(
                height: 36,
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
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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

  static const _controlHeight = 44.0;

  Widget _buildTemplateSection(AppStrings s) {
    final names = _templates.keys.toList()..sort();
    final selected = (_selectedTemplate != null && _templates.containsKey(_selectedTemplate))
        ? _selectedTemplate
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _controlHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _templateBox(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      isDense: true,
                      menuMaxHeight: kDropdownMenuMaxHeight,
                      value: selected,
                      hint: Text(
                        s.selectMappingTemplateHint,
                        style: _hintStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                      icon: const Icon(Icons.arrow_drop_down, size: 22),
                      style: _labelStyle,
                      items: names
                          .map(
                            (name) => DropdownMenuItem(
                              value: name,
                              child: Text(name, style: _labelStyle, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (name) {
                        if (name == null || name.isEmpty) return;
                        _applyTemplate(name);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: _templateBox(
                  child: TextField(
                    controller: _templateNameController,
                    style: _labelStyle,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saveTemplate(),
                    decoration: InputDecoration(
                      hintText: s.enterTemplateName,
                      hintStyle: _hintStyle,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: _controlHeight,
                width: 72,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(colors: [Color(0xFF3053F0), Color(0xFFE82E5A)]),
                  ),
                  child: ElevatedButton(
                    onPressed: _saveTemplate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size(72, _controlHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      s.save,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'Poppins'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_statusMessage != null && _statusMessage!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _statusMessage!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Poppins',
              color: _statusError ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
            ),
          ),
        ],
      ],
    );
  }

  Widget _templateBox({required Widget child}) {
    return Container(
      height: _controlHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
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
                menuMaxHeight: kDropdownMenuMaxHeight,
                value: selected.isNotEmpty ? selected : null,
                hint: Text(s.mapColumn, style: _ExcelFieldMappingDialogState._hintStyle, overflow: TextOverflow.ellipsis),
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                items: [
                  // Allow clearing a mapped column (not mandatory once selected).
                  if (selected.isNotEmpty)
                    DropdownMenuItem<String>(
                      value: '',
                      child: Text(
                        s.mapColumn,
                        style: _ExcelFieldMappingDialogState._hintStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ...options.map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c, style: _ExcelFieldMappingDialogState._labelStyle, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => onSelected(v ?? ''),
              ),
            ),
          ),
        ),
      ],
    );
  }
}