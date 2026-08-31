import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../models/wholesale_master.dart';
import '../services/locale_service.dart';
import '../utils/app_dropdown.dart';
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
  bool isAssignedAlready = false;

  void apply(RfidDeviceAssignment assignment, {bool assignedAlready = false}) {
    id = assignment.counterId;
    idCtrl.text = assignment.counterId > 0 ? '${assignment.counterId}' : '';
    nameCtrl.text = assignment.counterName;
    isAssignedAlready = assignedAlready;
  }

  void applyCounter(WholesaleCounter counter, {bool assignedAlready = false}) {
    id = counter.id;
    idCtrl.text = counter.id > 0 ? '${counter.id}' : '';
    nameCtrl.text = counter.name;
    isAssignedAlready = assignedAlready;
  }

  void clear() {
    id = 0;
    idCtrl.clear();
    nameCtrl.clear();
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

  void _clearCounters() {
    for (final row in _counters) {
      row.dispose();
    }
    _counters.clear();
  }

  void _applyAssignments(List<RfidDeviceAssignment> assignments) {
    _clearCounters();
    if (assignments.isEmpty) {
      _counters.add(_CounterEditors());
      return;
    }
    final first = assignments.first;
    _branchId = first.branchId;
    _branchIdCtrl.text = first.branchId > 0 ? '${first.branchId}' : '';
    _branchNameCtrl.text = first.branchName;
    _setCountersForBranch(
      branchId: first.branchId,
      branchName: first.branchName,
    );
  }

  void _setCountersForBranch({
    required int branchId,
    required String branchName,
  }) {
    final vm = context.read<SettingsViewModel>();
    _clearCounters();

    final assigned = vm.assignmentsForBranch(
      branchId > 0 ? branchId : null,
      branchName: branchName,
    );
    final assignedIds = <int>{
      for (final a in assigned)
        if (a.counterId > 0) a.counterId,
    };
    final assignedNames = <String>{
      for (final a in assigned)
        if (a.counterName.trim().isNotEmpty) a.counterName.trim().toLowerCase(),
    };

    // Always show GetAllCounters for this branch; mark DeviceId-assigned ones.
    final master = vm.countersForBranch(
      branchId > 0 ? branchId : null,
      branchName: branchName,
    );
    if (master.isNotEmpty) {
      for (final counter in master) {
        final already = assignedIds.contains(counter.id) ||
            assignedNames.contains(counter.name.trim().toLowerCase());
        _counters.add(
          _CounterEditors()..applyCounter(counter, assignedAlready: already),
        );
      }
      // ignore: avoid_print
      print(
        'Wholesale auto-fill counters: branchId=$branchId '
        'total=${master.length} assignedAlready=${assignedIds.length}',
      );
      return;
    }

    // Fallback: only DeviceId assignments if master list empty.
    if (assigned.isNotEmpty) {
      for (final assignment in assigned) {
        _counters.add(
          _CounterEditors()..apply(assignment, assignedAlready: true),
        );
      }
      return;
    }

    _counters.add(_CounterEditors());
  }

  Future<void> _pickBranch() async {
    final s = context.sRead;
    final vm = context.read<SettingsViewModel>();
    // Full branch master so seller can assign a new branch to this DeviceId.
    final branches = vm.wholesaleBranches;
    if (branches.isEmpty) {
      _toast(s.pleaseSelectBranch);
      return;
    }
    final picked = await showScrollableOptionSheet<WholesaleBranch>(
      context: context,
      options: branches,
      labelOf: (b) => b.name.isNotEmpty ? b.name : '${b.id}',
      title: s.selectBranch,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _branchId = picked.id;
      _branchIdCtrl.text = picked.id > 0 ? '${picked.id}' : '';
      _branchNameCtrl.text = picked.name;
      // Auto-fill Counter1, Counter2, ... for this branch.
      _setCountersForBranch(branchId: picked.id, branchName: picked.name);
    });
  }

  Future<void> _pickCounter(_CounterEditors row) async {
    final s = context.sRead;
    final vm = context.read<SettingsViewModel>();
    final branchId = int.tryParse(_branchIdCtrl.text.trim()) ?? _branchId;
    final branchName = _branchNameCtrl.text.trim();
    if (branchId <= 0 && branchName.isEmpty) {
      _toast(s.pleaseSelectBranch);
      return;
    }
    final counters = vm.countersForBranch(
      branchId > 0 ? branchId : null,
      branchName: branchName,
    );
    if (counters.isEmpty) {
      _toast(s.pleaseSelectCounter);
      return;
    }
    final picked = await showScrollableOptionSheet<WholesaleCounter>(
      context: context,
      options: counters,
      labelOf: (c) => c.name.isNotEmpty ? c.name : '${c.id}',
      title: s.selectCounter,
    );
    if (picked == null || !mounted) return;
    setState(() => row.applyCounter(picked));
  }

  List<RfidDeviceAssignment> _buildAssignments({
    required int branchId,
    required String branchName,
    required List<WholesaleCounter> counterOptions,
  }) {
    final out = <RfidDeviceAssignment>[];
    for (var i = 0; i < _counters.length; i++) {
      final row = _counters[i];
      var counterId = int.tryParse(row.idCtrl.text.trim()) ?? row.id;
      final counterName = row.nameCtrl.text.trim();
      if (counterId <= 0 && counterName.isNotEmpty) {
        for (final c in counterOptions) {
          if (c.name.trim().toLowerCase() == counterName.toLowerCase()) {
            counterId = c.id;
            row.id = c.id;
            row.idCtrl.text = c.id > 0 ? '${c.id}' : '';
            break;
          }
        }
      }
      // ignore: avoid_print
      print(
        'Wholesale build row[$i] branchId=$branchId '
        'counterId=$counterId name=$counterName idCtrl=${row.idCtrl.text} row.id=${row.id}',
      );
      if (counterId <= 0 && counterName.isEmpty) continue;
      out.add(
        RfidDeviceAssignment(
          branchId: branchId,
          branchName: branchName,
          counterId: counterId,
          counterName: counterName,
        ),
      );
    }
    return out;
  }

  Future<void> _save() async {
    final s = context.sRead;
    final vm = context.read<SettingsViewModel>();
    final deviceId = _deviceIdCtrl.text.trim();
    var branchId = int.tryParse(_branchIdCtrl.text.trim()) ?? _branchId;
    final branchName = _branchNameCtrl.text.trim();
    if (deviceId.isEmpty) {
      _toast(s.pleaseEnterDeviceId);
      return;
    }
    if (branchId <= 0 && branchName.isEmpty) {
      _toast(s.pleaseSelectBranch);
      return;
    }
    // Resolve BranchId from name if missing — Assign API needs BranchId > 0.
    if (branchId <= 0 && branchName.isNotEmpty) {
      for (final b in vm.wholesaleBranches) {
        if (b.name.trim().toLowerCase() == branchName.toLowerCase()) {
          branchId = b.id;
          _branchId = b.id;
          _branchIdCtrl.text = '${b.id}';
          break;
        }
      }
    }
    if (branchId <= 0) {
      // ignore: avoid_print
      print('Wholesale _save blocked: BranchId is 0 (name=$branchName)');
      _toast(s.pleaseSelectBranch);
      return;
    }

    final counterOptions = vm.countersForBranch(branchId, branchName: branchName);
    final assignments = _buildAssignments(
      branchId: branchId,
      branchName: branchName,
      counterOptions: counterOptions,
    );
    // ignore: avoid_print
    print('========== Wholesale UI SAVE ==========');
    // ignore: avoid_print
    print('deviceId=$deviceId branchId=$branchId branchName=$branchName');
    // ignore: avoid_print
    print('counterRows=${_counters.length} builtAssignments=${assignments.length}');
    // ignore: avoid_print
    print(
      'assignments=${assignments.map((a) => '{b=${a.branchId},c=${a.counterId},${a.counterName}}').toList()}',
    );
    if (assignments.isEmpty) {
      _toast(s.pleaseAddAssignment);
      return;
    }
    final missingIds = assignments.where((a) => a.branchId <= 0 || a.counterId <= 0).toList();
    if (missingIds.isNotEmpty) {
      // ignore: avoid_print
      print(
        'Wholesale _save blocked: ${missingIds.length} rows missing BranchId/CounterId: '
        '${missingIds.map((a) => a.counterName).toList()}',
      );
      _toast('${s.pleaseAddAssignment} (Counter ID required)');
      return;
    }

    final first = assignments.first;
    final ok = await vm.saveWholesaleOption(
      branchId: branchId,
      branchName: branchName,
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
    final branchName = _branchNameCtrl.text.trim();

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
                            _PickerField(
                              label: s.branch,
                              value: branchName.isNotEmpty
                                  ? branchName
                                  : (_branchId > 0 ? '$_branchId' : s.selectBranch),
                              onTap: _pickBranch,
                            ),
                            const SizedBox(height: 16),
                            ProductTextField(
                              label: s.branchId,
                              controller: _branchIdCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final id = int.tryParse(value.trim()) ?? 0;
                                setState(() {
                                  _branchId = id;
                                  _setCountersForBranch(
                                    branchId: id,
                                    branchName: _branchNameCtrl.text.trim(),
                                  );
                                });
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
                              final branchId =
                                  int.tryParse(_branchIdCtrl.text.trim()) ?? _branchId;
                              return _CounterCard(
                                index: index,
                                row: row,
                                counterOptions: vm.countersForBranch(
                                  branchId > 0 ? branchId : null,
                                  branchName: branchName,
                                ),
                                onPickCounter: () => _pickCounter(row),
                              );
                            }),
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
                        label: vm.savingWholesale ? s.loadingEllipsis : s.assign,
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

class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
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
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
              suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
            ),
            child: Text(value, style: GoogleFonts.poppins(fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

class _CounterCard extends StatelessWidget {
  final int index;
  final _CounterEditors row;
  final List<WholesaleCounter> counterOptions;
  final VoidCallback onPickCounter;

  const _CounterCard({
    required this.index,
    required this.row,
    required this.counterOptions,
    required this.onPickCounter,
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
        border: Border.all(
          color: row.isAssignedAlready ? const Color(0xFF5231A7) : const Color(0xFFE8E8E8),
        ),
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
              if (row.isAssignedAlready)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5231A7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Assigned already',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF5231A7),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _EditableCounterField(
            label: s.counter,
            hint: s.selectCounter,
            controller: row.nameCtrl,
            onOpenList: onPickCounter,
            onChanged: (value) {
              // Keep name editable. If typed name matches a known counter, fill its Id.
              WholesaleCounter? match;
              final q = value.trim().toLowerCase();
              for (final c in counterOptions) {
                if (c.name.trim().toLowerCase() == q) {
                  match = c;
                  break;
                }
              }
              if (match != null) {
                row.id = match.id;
                row.idCtrl.text = match.id > 0 ? '${match.id}' : '';
              }
            },
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

/// Editable counter name field + dropdown button to pick from list.
class _EditableCounterField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onOpenList;
  final ValueChanged<String> onChanged;

  const _EditableCounterField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onOpenList,
    required this.onChanged,
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
        TextField(
          controller: controller,
          style: GoogleFonts.poppins(fontSize: 13),
          onChanged: onChanged,
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
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              onPressed: onOpenList,
            ),
          ),
        ),
      ],
    );
  }
}
