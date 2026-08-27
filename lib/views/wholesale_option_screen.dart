import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../models/wholesale_master.dart';
import '../services/locale_service.dart';
import '../viewmodels/settings_view_model.dart';
import 'widgets/product_form_widgets.dart';

class WholesaleOptionScreen extends StatefulWidget {
  const WholesaleOptionScreen({super.key});

  @override
  State<WholesaleOptionScreen> createState() => _WholesaleOptionScreenState();
}

class _CounterEditors {
  final idCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  int id = 0;

  void apply(RfidDeviceAssignment assignment) {
    id = assignment.counterId;
    idCtrl.text = assignment.counterId > 0 ? '${assignment.counterId}' : '';
    nameCtrl.text = assignment.counterName;
  }

  void dispose() {
    idCtrl.dispose();
    nameCtrl.dispose();
  }
}

class _WholesaleOptionScreenState extends State<WholesaleOptionScreen> {
  final _deviceIdCtrl = TextEditingController();
  final _branchIdCtrl = TextEditingController();
  final _branchNameCtrl = TextEditingController();
  int _branchId = 0;
  final List<_CounterEditors> _counters = [];
  bool _bootstrapping = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _deviceIdCtrl.dispose();
    _branchIdCtrl.dispose();
    _branchNameCtrl.dispose();
    for (final row in _counters) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final vm = context.read<SettingsViewModel>();
    if (!vm.pref.isWholesaleLoginUser()) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _deviceIdCtrl.text = await vm.ensureDeviceId();
    await vm.loadWholesaleMasters();
    if (!mounted) return;
    _applyAssignments(vm.wholesaleAssignments);
    setState(() => _bootstrapping = false);
  }

  void _applyAssignments(List<RfidDeviceAssignment> assignments) {
    for (final row in _counters) {
      row.dispose();
    }
    _counters.clear();
    if (assignments.isEmpty) {
      _counters.add(_CounterEditors());
      return;
    }
    final first = assignments.first;
    _branchId = first.branchId;
    _branchIdCtrl.text = first.branchId > 0 ? '${first.branchId}' : '';
    _branchNameCtrl.text = first.branchName;
    for (final assignment in assignments) {
      _counters.add(_CounterEditors()..apply(assignment));
    }
  }

  void _selectBranch(WholesaleBranch branch) {
    setState(() {
      _branchId = branch.id;
      _branchIdCtrl.text = '${branch.id}';
      _branchNameCtrl.text = branch.name;
    });
  }

  void _selectCounter(_CounterEditors row, WholesaleCounter counter) {
    setState(() {
      row.id = counter.id;
      row.idCtrl.text = '${counter.id}';
      row.nameCtrl.text = counter.name;
    });
  }

  void _addCounter() {
    setState(() => _counters.add(_CounterEditors()));
  }

  void _removeCounter(int index) {
    if (_counters.length <= 1) return;
    setState(() => _counters.removeAt(index).dispose());
  }

  List<RfidDeviceAssignment> _buildAssignments() {
    final branchId = int.tryParse(_branchIdCtrl.text.trim()) ?? _branchId;
    final branchName = _branchNameCtrl.text.trim();
    return _counters
        .map((row) {
          return RfidDeviceAssignment(
            branchId: branchId,
            branchName: branchName,
            counterId: int.tryParse(row.idCtrl.text.trim()) ?? row.id,
            counterName: row.nameCtrl.text.trim(),
          );
        })
        .where((a) => a.hasCounter)
        .toList();
  }

  Future<void> _save() async {
    final s = context.sRead;
    final vm = context.read<SettingsViewModel>();
    final deviceId = _deviceIdCtrl.text.trim();
    final branchId = int.tryParse(_branchIdCtrl.text.trim()) ?? _branchId;
    final branchName = _branchNameCtrl.text.trim();
    if (deviceId.isEmpty) {
      _toast(s.pleaseEnterDeviceId);
      return;
    }
    if (branchId <= 0 && branchName.isEmpty) {
      _toast(s.pleaseSelectBranch);
      return;
    }
    final assignments = _buildAssignments();
    if (assignments.isEmpty) {
      _toast(s.pleaseAddAssignment);
      return;
    }
    final first = assignments.first;
    final ok = await vm.saveWholesaleOption(
      branchId: first.branchId,
      branchName: first.branchName,
      counterId: first.counterId,
      counterName: first.counterName,
      deviceId: deviceId,
      assignments: assignments,
    );
    if (!mounted) return;
    _toast(ok ? s.wholesaleSaved : s.wholesaleSaveFailed);
    if (ok) Navigator.pop(context);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    final s = locale.strings;
    final vm = context.watch<SettingsViewModel>();
    final branchId = int.tryParse(_branchIdCtrl.text.trim()) ?? _branchId;
    final counters = vm.countersForBranch(branchId > 0 ? branchId : null);

    return Directionality(
      textDirection: locale.textDirection,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: productGradientAppBar(context: context, title: s.wholesaleOption),
        body: _bootstrapping
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (vm.loadingWholesale) const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: ListView(
                          children: [
                            _SuggestField<WholesaleBranch>(
                              key: ValueKey('branch-$_branchId'),
                              label: s.branch,
                              hint: s.selectBranch,
                              controller: _branchNameCtrl,
                              options: vm.wholesaleBranches,
                              displayOf: (b) => b.name,
                              matches: (b, q) =>
                                  b.name.toLowerCase().contains(q) || b.id.toString().contains(q),
                              onSelected: _selectBranch,
                            ),
                            const SizedBox(height: 16),
                            ProductTextField(
                              label: s.branchId,
                              controller: _branchIdCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                _branchId = int.tryParse(value.trim()) ?? 0;
                              },
                            ),
                            const SizedBox(height: 16),
                            ProductTextField(
                              label: s.branchName,
                              controller: _branchNameCtrl,
                            ),
                            const SizedBox(height: 16),
                            ...List.generate(_counters.length, (index) {
                              final row = _counters[index];
                              return _CounterCard(
                                index: index,
                                row: row,
                                options: counters,
                                canRemove: _counters.length > 1,
                                onRemove: () => _removeCounter(index),
                                onSelectCounter: (counter) => _selectCounter(row, counter),
                              );
                            }),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _addCounter,
                                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF5231A7)),
                                label: Text(
                                  s.addCounter,
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFF5231A7),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ProductTextField(
                              label: s.deviceId,
                              controller: _deviceIdCtrl,
                              readOnly: true,
                            ),
                          ],
                        ),
                      ),
                      productGradientButton(
                        label: vm.savingWholesale ? s.loadingEllipsis : s.save,
                        onPressed: vm.savingWholesale || vm.loadingWholesale ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  final int index;
  final _CounterEditors row;
  final List<WholesaleCounter> options;
  final bool canRemove;
  final VoidCallback onRemove;
  final ValueChanged<WholesaleCounter> onSelectCounter;

  const _CounterCard({
    required this.index,
    required this.row,
    required this.options,
    required this.canRemove,
    required this.onRemove,
    required this.onSelectCounter,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${s.counter} ${index + 1}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              if (canRemove)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFD32940)),
                ),
            ],
          ),
          _SuggestField<WholesaleCounter>(
            key: ValueKey('counter-$index-${row.id}'),
            label: s.counter,
            hint: s.selectCounter,
            controller: row.nameCtrl,
            options: options,
            displayOf: (c) => c.name,
            matches: (c, q) =>
                c.name.toLowerCase().contains(q) || c.id.toString().contains(q),
            onSelected: onSelectCounter,
          ),
          const SizedBox(height: 12),
          ProductTextField(
            label: s.counterId,
            controller: row.idCtrl,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              row.id = int.tryParse(value.trim()) ?? 0;
            },
          ),
          const SizedBox(height: 12),
          ProductTextField(
            label: s.counterName,
            controller: row.nameCtrl,
          ),
        ],
      ),
    );
  }
}

class _SuggestField<T extends Object> extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final List<T> options;
  final String Function(T option) displayOf;
  final bool Function(T option, String query) matches;
  final ValueChanged<T> onSelected;

  const _SuggestField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.options,
    required this.displayOf,
    required this.matches,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        const SizedBox(height: 4),
        Autocomplete<T>(
          key: ValueKey('${label}_${controller.text}'),
          initialValue: TextEditingValue(
            text: controller.text,
            selection: TextSelection.collapsed(offset: controller.text.length),
          ),
          displayStringForOption: displayOf,
          optionsBuilder: (value) {
            final query = value.text.trim().toLowerCase();
            if (query.isEmpty) return options.take(20);
            return options.where((o) => matches(o, query)).take(20);
          },
          onSelected: (option) {
            controller.text = displayOf(option);
            onSelected(option);
          },
          fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textController,
              focusNode: focusNode,
              onSubmitted: (_) => onFieldSubmitted(),
              onChanged: (value) => controller.text = value,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ),
            );
          },
          optionsViewBuilder: (context, onSelectedOption, opts) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, maxWidth: 420),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: opts.length,
                    itemBuilder: (context, index) {
                      final option = opts.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(displayOf(option), style: GoogleFonts.poppins(fontSize: 13)),
                        onTap: () => onSelectedOption(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
