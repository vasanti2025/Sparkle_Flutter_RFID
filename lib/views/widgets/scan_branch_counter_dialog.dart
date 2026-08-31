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
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _applyBranch(WholesaleBranch branch, SettingsViewModel vm) {
    _branch = branch;
    // Only counters registered for THIS DeviceId + this branch.
    final counters = vm.scanPopupCountersFor(branch.id, branchName: branch.name);
    _counter = counters.length == 1 ? counters.first : null;
  }

  Future<void> _load() async {
    final vm = context.read<SettingsViewModel>();
    // GetRFID by this handset DeviceId — branches/counters only if DeviceId matches.
    await vm.loadWholesaleMasters();
    if (!mounted) return;

    _deviceId = vm.stableDeviceId;
    final branches = vm.scanPopupBranches;
    final initial = widget.initial;

    WholesaleBranch? branch;
    if (initial != null && branches.isNotEmpty) {
      for (final b in branches) {
        final idMatch = initial.branchId > 0 && b.id == initial.branchId;
        final nameMatch = initial.branchName.isNotEmpty &&
            b.name.toLowerCase() == initial.branchName.toLowerCase();
        if (idMatch || nameMatch) {
          branch = b;
          break;
        }
      }
    }
    if (branch == null && branches.length == 1) {
      branch = branches.first;
    }

    WholesaleCounter? counter;
    if (branch != null) {
      final counters = vm.scanPopupCountersFor(branch.id, branchName: branch.name);
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
      if (counter == null && counters.length == 1) {
        counter = counters.first;
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
    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No branch for this DeviceId${_deviceId.isEmpty ? '' : ' ($_deviceId)'}',
          ),
        ),
      );
      return;
    }
    final picked = await showScrollableOptionSheet<WholesaleBranch>(
      context: context,
      options: branches,
      labelOf: (b) => b.name.isNotEmpty ? b.name : '${b.id}',
      title: context.sRead.selectBranch,
    );
    if (picked == null || !mounted) return;
    setState(() => _applyBranch(picked, vm));
  }

  Future<void> _pickCounter() async {
    final s = context.sRead;
    final vm = context.read<SettingsViewModel>();
    if (_branch == null || (_branch!.id <= 0 && _branch!.name.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.pleaseSelectBranch)));
      return;
    }
    final counters = vm.scanPopupCountersFor(
      _branch!.id,
      branchName: _branch!.name,
    );
    if (counters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No counter for this branch on DeviceId${_deviceId.isEmpty ? '' : ' ($_deviceId)'}',
          ),
        ),
      );
      return;
    }
    final picked = await showScrollableOptionSheet<WholesaleCounter>(
      context: context,
      options: counters,
      labelOf: (c) => c.name.isNotEmpty ? c.name : '${c.id}',
      title: s.selectCounter,
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
    final hasDeviceData = vm.hasDeviceAssignments;

    return AlertDialog(
      title: Text('${s.branch} / ${s.counter}', style: AppFonts.poppins(fontWeight: FontWeight.bold)),
      content: _loading || vm.loadingWholesale
          ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasDeviceData)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No branch/counter for this DeviceId. Save in Wholesale option first.',
                      style: AppFonts.poppins(fontSize: 12, color: Colors.red.shade700),
                    ),
                  ),
                _picker(s.branch, branchLabel, hasDeviceData ? _pickBranch : null),
                const SizedBox(height: 12),
                _picker(s.counter, counterLabel, hasDeviceData ? _pickCounter : null),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        TextButton(
          onPressed: _loading || vm.loadingWholesale || !hasDeviceData ? null : _confirm,
          child: Text(s.start),
        ),
      ],
    );
  }

  Widget _picker(String label, String value, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: Text(value, style: AppFonts.poppins(fontSize: 13)),
      ),
    );
  }
}
