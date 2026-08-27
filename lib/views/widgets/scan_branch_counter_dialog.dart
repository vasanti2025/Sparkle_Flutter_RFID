import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n_extension.dart';
import '../../models/wholesale_master.dart';
import '../../utils/app_dropdown.dart';
import '../../utils/app_fonts.dart';
import '../../viewmodels/settings_view_model.dart';

Future<RfidDeviceAssignment?> showScanBranchCounterDialog({
  required BuildContext context,
  RfidDeviceAssignment? initial,
}) {
  return showAppDialog<RfidDeviceAssignment>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ScanBranchCounterDialog(initial: initial),
  );
}

class _ScanBranchCounterDialog extends StatefulWidget {
  final RfidDeviceAssignment? initial;

  const _ScanBranchCounterDialog({this.initial});

  @override
  State<_ScanBranchCounterDialog> createState() => _ScanBranchCounterDialogState();
}

class _ScanBranchCounterDialogState extends State<_ScanBranchCounterDialog> {
  WholesaleBranch? _branch;
  WholesaleCounter? _counter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final vm = context.read<SettingsViewModel>();
    await vm.loadWholesaleMasters();
    if (!mounted) return;

    final initial = widget.initial ??
        (vm.pref.getWholesaleAssignments().isNotEmpty
            ? vm.pref.getWholesaleAssignments().first
            : null);

    WholesaleBranch? branch;
    final branches = vm.scanPopupBranches;
    if (initial != null) {
      for (final b in branches) {
        if ((initial.branchId > 0 && b.id == initial.branchId) ||
            (initial.branchName.isNotEmpty &&
                b.name.toLowerCase() == initial.branchName.toLowerCase())) {
          branch = b;
          break;
        }
      }
    }

    WholesaleCounter? counter;
    final counters = vm.scanPopupCountersFor(branch?.id);
    if (initial != null) {
      for (final c in counters) {
        if ((initial.counterId > 0 && c.id == initial.counterId) ||
            (initial.counterName.isNotEmpty &&
                c.name.toLowerCase() == initial.counterName.toLowerCase())) {
          counter = c;
          break;
        }
      }
    }

    setState(() {
      _branch = branch;
      _counter = counter;
      _loading = false;
    });
  }

  Future<void> _pickBranch() async {
    final vm = context.read<SettingsViewModel>();
    final branches = vm.scanPopupBranches;
    if (branches.isEmpty) return;
    final picked = await showScrollableOptionSheet<WholesaleBranch>(
      context: context,
      options: branches,
      labelOf: (b) => b.name.isNotEmpty ? b.name : '${b.id}',
      title: context.sRead.selectBranch,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _branch = picked;
      if (_counter != null &&
          _counter!.branchId > 0 &&
          _counter!.branchId != picked.id) {
        _counter = null;
      }
    });
  }

  Future<void> _pickCounter() async {
    final vm = context.read<SettingsViewModel>();
    final counters = vm.scanPopupCountersFor(_branch?.id);
    if (counters.isEmpty) return;
    final picked = await showScrollableOptionSheet<WholesaleCounter>(
      context: context,
      options: counters,
      labelOf: (c) => c.name.isNotEmpty ? c.name : '${c.id}',
      title: context.sRead.selectCounter,
    );
    if (picked == null || !mounted) return;
    setState(() => _counter = picked);
  }

  void _confirm() {
    final s = context.sRead;
    if (_branch == null || (_branch!.id <= 0 && _branch!.name.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.pleaseSelectBranch)));
      return;
    }
    if (_counter == null || (_counter!.id <= 0 && _counter!.name.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.pleaseSelectCounter)));
      return;
    }
    Navigator.pop(
      context,
      RfidDeviceAssignment(
        branchId: _branch!.id,
        branchName: _branch!.name,
        counterId: _counter!.id,
        counterName: _counter!.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final vm = context.watch<SettingsViewModel>();
    final branchLabel = _branch == null
        ? s.selectBranch
        : (_branch!.name.isNotEmpty ? _branch!.name : '${_branch!.id}');
    final counterLabel = _counter == null
        ? s.selectCounter
        : (_counter!.name.isNotEmpty ? _counter!.name : '${_counter!.id}');

    return AlertDialog(
      title: Text('${s.branch} / ${s.counter}', style: AppFonts.poppins(fontWeight: FontWeight.bold)),
      content: _loading || vm.loadingWholesale
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _picker(s.branch, branchLabel, _pickBranch),
                const SizedBox(height: 12),
                _picker(s.counter, counterLabel, _pickCounter),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        TextButton(
          onPressed: _loading || vm.loadingWholesale ? null : _confirm,
          child: Text(s.start),
        ),
      ],
    );
  }

  Widget _picker(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: Text(value, style: AppFonts.poppins(fontSize: 13)),
      ),
    );
  }
}
