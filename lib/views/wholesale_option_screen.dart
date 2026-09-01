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

class _CounterCheckItem {
  final WholesaleCounter counter;
  final bool assignedAlready;
  bool selected;

  _CounterCheckItem({
    required this.counter,
    required this.assignedAlready,
    required this.selected,
  });
}

class _WholesaleOptionScreenState extends State<WholesaleOptionScreen> {
  final _deviceIdCtrl = TextEditingController();
  final _branchIdCtrl = TextEditingController();
  final _branchNameCtrl = TextEditingController();
  int _branchId = 0;
  final List<_CounterCheckItem> _counters = [];
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
    _counters.clear();
    if (assignments.isEmpty) return;
    final first = assignments.first;
    _branchId = first.branchId;
    _branchIdCtrl.text = first.branchId > 0 ? '${first.branchId}' : '';
    _branchNameCtrl.text = first.branchName;
    _loadCountersForBranch(
      branchId: first.branchId,
      branchName: first.branchName,
    );
  }

  void _loadCountersForBranch({
    required int branchId,
    required String branchName,
  }) {
    final vm = context.read<SettingsViewModel>();
    _counters.clear();

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

    final master = vm.countersForBranch(
      branchId > 0 ? branchId : null,
      branchName: branchName,
    );

    if (master.isNotEmpty) {
      for (final counter in master) {
        final already = assignedIds.contains(counter.id) ||
            assignedNames.contains(counter.name.trim().toLowerCase());
        _counters.add(
          _CounterCheckItem(
            counter: counter,
            assignedAlready: already,
            selected: already, // already assigned stay checked
          ),
        );
      }
      debugPrint(
        'Wholesale checkbox counters: branchId=$branchId '
        'total=${master.length} assignedAlready=${assignedIds.length}',
      );
      return;
    }

    // Fallback: only DeviceId assignments.
    for (final a in assigned) {
      if (a.counterId <= 0 && a.counterName.trim().isEmpty) continue;
      _counters.add(
        _CounterCheckItem(
          counter: WholesaleCounter(
            id: a.counterId,
            name: a.counterName,
            branchId: a.branchId,
          ),
          assignedAlready: true,
          selected: true,
        ),
      );
    }
  }

  Future<void> _pickBranch() async {
    final s = context.sRead;
    final vm = context.read<SettingsViewModel>();
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
      _loadCountersForBranch(branchId: picked.id, branchName: picked.name);
    });
  }

  List<RfidDeviceAssignment> _buildSelectedAssignments({
    required int branchId,
    required String branchName,
  }) {
    return _counters
        .where((item) => item.selected && item.counter.id > 0)
        .map(
          (item) => RfidDeviceAssignment(
            branchId: branchId,
            branchName: branchName,
            counterId: item.counter.id,
            counterName: item.counter.name,
          ),
        )
        .toList();
  }

  Future<void> _assign() async {
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
      _toast(s.pleaseSelectBranch);
      return;
    }

    final assignments = _buildSelectedAssignments(
      branchId: branchId,
      branchName: branchName,
    );
    debugPrint('========== Wholesale UI ASSIGN (checkbox) ==========');
    debugPrint('deviceId=$deviceId branchId=$branchId');
    debugPrint(
      'selected=${assignments.map((a) => a.counterId).toList()} '
      'count=${assignments.length}',
    );

    if (assignments.isEmpty) {
      _toast(s.pleaseSelectCounter);
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
    if (ok) {
      // Refresh checkboxes so newly assigned show "Assigned already".
      setState(() {
        _loadCountersForBranch(branchId: branchId, branchName: branchName);
      });
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final s = context.sRead;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteBranch() async {
    final s = context.sRead;
    final vm = context.read<SettingsViewModel>();
    final branchId = int.tryParse(_branchIdCtrl.text.trim()) ?? _branchId;
    if (branchId <= 0) {
      _toast(s.pleaseSelectBranch);
      return;
    }
    final confirmed = await _confirmDelete(
      title: s.deleteBranch,
      message: s.confirmDeleteBranch,
    );
    if (!confirmed || !mounted) return;

    final ok = await vm.deleteWholesaleBranch(branchId);
    if (!mounted) return;
    _toast(ok ? s.branchDeletedSuccessfully : s.branchDeleteFailed);
    if (ok) {
      setState(() {
        _branchId = 0;
        _branchIdCtrl.clear();
        _branchNameCtrl.clear();
        _counters.clear();
      });
    }
  }

  Future<void> _deleteCounter(_CounterCheckItem item) async {
    final s = context.sRead;
    final vm = context.read<SettingsViewModel>();
    final counterId = item.counter.id;
    if (counterId <= 0) return;

    final confirmed = await _confirmDelete(
      title: s.deleteCounter,
      message: s.confirmDeleteCounter,
    );
    if (!confirmed || !mounted) return;

    final ok = await vm.deleteWholesaleCounter(counterId);
    if (!mounted) return;
    _toast(ok ? s.counterDeletedSuccessfully : s.counterDeleteFailed);
    if (ok) {
      setState(() {
        _loadCountersForBranch(
          branchId: _branchId,
          branchName: _branchNameCtrl.text.trim(),
        );
      });
    }
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
    final selectedCount = _counters.where((c) => c.selected).length;

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
                                  : (_branchId > 0
                                      ? '$_branchId'
                                      : s.selectBranch),
                              onTap: _pickBranch,
                              onDelete: _branchId > 0 &&
                                      !vm.savingWholesale &&
                                      !vm.loadingWholesale
                                  ? _deleteBranch
                                  : null,
                              deleteTooltip: s.deleteBranch,
                            ),
                            const SizedBox(height: 12),
                            ProductTextField(
                              label: s.branchId,
                              controller: _branchIdCtrl,
                              keyboardType: TextInputType.number,
                              readOnly: true,
                            ),
                            const SizedBox(height: 12),
                            ProductTextField(
                              label: s.branchName,
                              controller: _branchNameCtrl,
                              readOnly: true,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              s.counter,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selectedCount > 0
                                  ? '$selectedCount selected'
                                  : s.selectCounter,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_counters.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  _branchId > 0 || branchName.isNotEmpty
                                      ? 'No counters for this branch'
                                      : s.pleaseSelectBranch,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else
                              ...List.generate(_counters.length, (index) {
                                final item = _counters[index];
                                return _CounterCheckboxTile(
                                  item: item,
                                  onChanged: (checked) {
                                    setState(
                                      () => item.selected = checked ?? false,
                                    );
                                  },
                                  onDelete: vm.savingWholesale ||
                                          vm.loadingWholesale
                                      ? null
                                      : () => _deleteCounter(item),
                                );
                              }),
                            const SizedBox(height: 12),
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
                        onPressed:
                            vm.savingWholesale || vm.loadingWholesale
                                ? null
                                : _assign,
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
  final VoidCallback? onDelete;
  final String? deleteTooltip;

  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onDelete,
    this.deleteTooltip,
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
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onDelete != null)
                    IconButton(
                      tooltip: deleteTooltip,
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                    ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  const SizedBox(width: 4),
                ],
              ),
              suffixIconConstraints: BoxConstraints(
                minWidth: onDelete != null ? 72 : 40,
                minHeight: 40,
              ),
            ),
            child: Text(value, style: GoogleFonts.poppins(fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

class _CounterCheckboxTile extends StatelessWidget {
  final _CounterCheckItem item;
  final ValueChanged<bool?> onChanged;
  final VoidCallback? onDelete;

  const _CounterCheckboxTile({
    required this.item,
    required this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final counter = item.counter;
    final title = counter.name.isNotEmpty ? counter.name : '${counter.id}';
    final subtitle = counter.id > 0 ? 'ID: ${counter.id}' : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: item.selected ? const Color(0xFFF3EEFF) : const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.assignedAlready || item.selected
              ? const Color(0xFF5231A7)
              : const Color(0xFFE8E8E8),
        ),
      ),
      child: CheckboxListTile(
        value: item.selected,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: const Color(0xFF5231A7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        secondary: IconButton(
          tooltip: s.deleteCounter,
          onPressed: onDelete,
          icon: Icon(
            Icons.delete_outline,
            color: onDelete == null ? Colors.grey : Colors.red,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null)
              Text(
                subtitle,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade700),
              ),
            if (item.assignedAlready) ...[
              const SizedBox(height: 4),
              Text(
                'Assigned already',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5231A7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
