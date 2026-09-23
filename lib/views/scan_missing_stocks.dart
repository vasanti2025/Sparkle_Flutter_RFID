import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rfid_flutter/utils/app_fonts.dart';

import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../models/wholesale_master.dart';
import '../services/api_service.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../utils/product_image.dart';
import '../utils/scan_key.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/product_view_model.dart';
import '../viewmodels/settings_view_model.dart';
import 'widgets/scan_bottom_bar.dart';
import 'widgets/scan_branch_counter_dialog.dart';

class _MissingRow {
  _MissingRow(this.item);
  final BulkItem item;
  bool matched = false;
  List<String>? _keys;
  double? _gross;

  List<String> get keys {
    if (_keys != null) return _keys!;
    final out = <String>{};
    void add(String raw) => addScanKeyVariants(raw, out.add);
    add(item.epc);
    add(item.rfid);
    add(item.tid);
    add(item.itemCode);
    _keys = out.toList();
    return _keys!;
  }

  double get grossWt => _gross ??= double.tryParse(item.grossWeight) ?? 0.0;
}

class ScanMissingStocksScreen extends StatefulWidget {
  const ScanMissingStocksScreen({super.key});

  @override
  State<ScanMissingStocksScreen> createState() => _ScanMissingStocksScreenState();
}

class _ScanMissingStocksScreenState extends State<ScanMissingStocksScreen> {
  final RfidService _rfid = RfidService();
  StreamSubscription? _tagsSub;
  StreamSubscription? _triggerSub;

  final List<_MissingRow> _rows = [];
  final Map<String, int> _keyToIndex = {};
  final Set<String> _matchedKeys = {};

  bool _loading = true;
  bool _saving = false;
  bool _scanning = false;
  bool _scanStartInProgress = false;
  String? _error;
  String _branchName = '';
  int _branchId = 0;
  int _counterId = 0;
  String _counterName = '';
  bool _branchPromptOpen = false;
  int _power = 30;
  int _lastTriggerMs = 0;
  int _lastUiMs = 0;

  int get _matchedCount => _rows.where((r) => r.matched).length;

  @override
  void initState() {
    super.initState();
    _power = context.read<PrefService>().inventoryPower.clamp(1, 30);
    _rfid.preWarmReader();
    _rfid.clearSearchTags();
    _tagsSub = _rfid.tagsStream.listen(_onTag);
    _triggerSub = _rfid.triggerStream.listen((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      _toggleScan();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadMissingStocks());
    });
  }

  @override
  void dispose() {
    _tagsSub?.cancel();
    _triggerSub?.cancel();
    _rfid.stopScanning();
    super.dispose();
  }

  void _applyLocation(RfidDeviceAssignment loc) {
    _branchId = loc.branchId;
    _branchName =
        loc.branchName.trim().isNotEmpty ? loc.branchName.trim() : '${loc.branchId}';
    _counterId = loc.counterId;
    _counterName = loc.counterName.trim();
  }

  Future<bool> _ensureWholesaleBranch({bool promptIfMissing = true}) async {
    final pref = context.read<PrefService>();
    final settings = context.read<SettingsViewModel>();

    if (!pref.isWholesaleLoginUser()) {
      final emp = context.read<DashboardViewModel>().employee;
      _branchId = pref.getBranchId();
      if (_branchId <= 0) _branchId = emp?.defaultBranchId ?? 0;
      _branchName = (emp?.branchName ?? '').trim();
      if (_branchName.isEmpty && _branchId > 0) _branchName = '$_branchId';
      return _branchId > 0;
    }

    await settings.ensureDeviceId();
    await settings.loadWholesaleMasters();
    if (!mounted) return false;

    final assigned = settings.assignedBranchesForDevice;
    if (!settings.hasDeviceAssignments || assigned.isEmpty) {
      if (promptIfMissing) await _alertSelectWholesaleFirst();
      _branchId = 0;
      _branchName = '';
      return false;
    }

    final lastId = settings.lastSelectedWholesaleBranchId;
    final lastName = settings.lastSelectedWholesaleBranchName.trim();
    WholesaleBranch? match;
    for (final b in assigned) {
      if (lastId > 0 && b.id == lastId) {
        match = b;
        break;
      }
      if (lastName.isNotEmpty &&
          b.name.trim().toLowerCase() == lastName.toLowerCase()) {
        match = b;
        break;
      }
    }

    if (match == null) {
      if (!promptIfMissing) {
        _branchId = 0;
        _branchName = '';
        return false;
      }
      final picked = await _promptSelectAssignedBranch();
      if (picked == null || !mounted) return false;
      _applyLocation(picked);
      return _branchId > 0 || _branchName.isNotEmpty;
    }

    _branchId = match.id;
    _branchName = match.name.trim().isNotEmpty ? match.name.trim() : '${match.id}';
    _counterId = pref.getWholesaleCounterId();
    _counterName = pref.getWholesaleCounterName().trim();
    if (_counterId <= 0 && _counterName.isEmpty) {
      final counters =
          settings.scanPopupCountersFor(match.id, branchName: match.name);
      if (counters.length == 1) {
        _counterId = counters.first.id;
        _counterName = counters.first.name;
      }
    }
    return true;
  }

  Future<void> _alertSelectWholesaleFirst() async {
    if (!mounted) return;
    final s = context.sRead;
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.wholesaleOption, style: AppFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(s.scanAddWholesaleBranchCounter, style: AppFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.ok)),
        ],
      ),
    );
  }

  Future<RfidDeviceAssignment?> _promptSelectAssignedBranch() async {
    if (!mounted || _branchPromptOpen) return null;
    _branchPromptOpen = true;
    try {
      final s = context.sRead;
      final go = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.selectBranch, style: AppFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text(s.pleaseSelectBranch, style: AppFonts.poppins(fontSize: 14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.ok)),
          ],
        ),
      );
      if (go != true || !mounted) return null;
      return showScanBranchCounterDialog(context: context);
    } finally {
      _branchPromptOpen = false;
    }
  }

  Future<void> _onBranchBarTap() async {
    if (_saving || _scanning) return;
    final pref = context.read<PrefService>();
    if (!pref.isWholesaleLoginUser()) return;
    final picked = await showScanBranchCounterDialog(
      context: context,
      initial: (_branchId > 0 || _branchName.isNotEmpty)
          ? RfidDeviceAssignment(
              branchId: _branchId,
              branchName: _branchName,
              counterId: _counterId,
              counterName: _counterName,
            )
          : null,
    );
    if (picked == null || !mounted) return;
    _applyLocation(picked);
    await _loadMissingStocks(skipBranchPrompt: true);
  }

  Future<void> _loadMissingStocks({bool skipBranchPrompt = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final needBranch = _branchId <= 0 && _branchName.isEmpty;
    if (!skipBranchPrompt || needBranch) {
      final ok = await _ensureWholesaleBranch(promptIfMissing: !skipBranchPrompt);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _loading = false;
          _rows.clear();
          _error = context.sRead.pleaseSelectBranch;
        });
        return;
      }
    }
    final emp = context.read<DashboardViewModel>().employee;
    final clientCode = emp?.clientCode ?? '';
    if (clientCode.isEmpty) {
      setState(() {
        _loading = false;
        _error = context.sRead.errorSessionExpired;
        _rows.clear();
      });
      return;
    }

    try {
      final api = context.read<ApiService>();
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final raw = await api.getStockTakingUnmatchedList(
        clientCode: clientCode,
        branchAddress: _branchId > 0 ? '$_branchId' : '',
        stockTakingDate: date,
      );
      final next = <_MissingRow>[];
      final seen = <String>{};
      for (final row in raw) {
        if (row is! Map) continue;
        final item = BulkItem.fromApi(Map<String, dynamic>.from(row));
        final key = (item.epc.isNotEmpty
                ? item.epc
                : (item.rfid.isNotEmpty ? item.rfid : item.itemCode))
            .trim()
            .toUpperCase();
        if (key.isEmpty || !seen.add(key)) continue;
        next.add(_MissingRow(item));
      }
      _rebuildLookup(next);
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(next);
        _matchedKeys.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows.clear();
        _matchedKeys.clear();
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _rebuildLookup(List<_MissingRow> rows) {
    _keyToIndex.clear();
    for (var i = 0; i < rows.length; i++) {
      for (final key in rows[i].keys) {
        _keyToIndex.putIfAbsent(key, () => i);
      }
    }
  }

  void _onTag(String tag) {
    if (!_scanning || !mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final scanned = normalizeScanKey(tag);
    if (scanned.isEmpty) return;
    if (_matchedKeys.contains(scanned)) return;

    int? index = _keyToIndex[scanned];
    if (index == null) {
      final stripped = stripScanKey00(scanned);
      index = _keyToIndex[stripped];
      if (index == null && stripped != scanned) {
        index = _keyToIndex['00$stripped'];
      }
    }
    if (index == null || index >= _rows.length) return;

    final row = _rows[index];
    if (row.matched) return;
    row.matched = true;
    for (final key in row.keys) {
      _matchedKeys.add(key);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastUiMs >= 80) {
      _lastUiMs = now;
      setState(() {});
    } else {
      setState(() {});
    }
  }

  void _toggleScan() {
    if (_saving || _loading) return;
    if (_branchId <= 0 && _branchName.isEmpty) {
      unawaited(() async {
        final ok = await _ensureWholesaleBranch(promptIfMissing: true);
        if (!ok || !mounted) return;
        if (_rows.isEmpty) await _loadMissingStocks(skipBranchPrompt: true);
        if (mounted && !_scanning) unawaited(_startScan());
      }());
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTriggerMs < 300) return;
    _lastTriggerMs = now;
    if (_scanStartInProgress) return;
    if (_scanning) {
      unawaited(_stopScan());
    } else {
      unawaited(_startScan());
    }
  }

  Future<void> _startScan() async {
    if (_rows.isEmpty) {
      _toast(context.sRead.noMissingStocks);
      return;
    }
    if (_scanning || _scanStartInProgress) return;
    _scanStartInProgress = true;
    if (mounted) setState(() => _scanning = true);
    try {
      final started = await _rfid.startInventoryScanning(power: _power);
      if (!mounted) return;
      if (!started) {
        setState(() => _scanning = false);
        await _rfid.stopInventorySound();
        await _rfid.haltScan();
        _toast(context.sRead.failedToStartRfidScanner);
      }
    } finally {
      _scanStartInProgress = false;
    }
  }

  Future<void> _stopScan() async {
    await _rfid.stopScanning();
    await _rfid.stopInventorySound();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_branchId <= 0 && _branchName.isEmpty) {
      final ok = await _ensureWholesaleBranch(promptIfMissing: true);
      if (!ok || !mounted) return;
    }
    if (_rows.isEmpty) {
      _toast(context.sRead.noMissingStocks);
      return;
    }
    await _stopScan();
    setState(() => _saving = true);

    final viewModel = context.read<ProductViewModel>();
    final emp = context.read<DashboardViewModel>().employee;
    final clientCode = emp?.clientCode ?? '';
    if (clientCode.isEmpty) {
      setState(() => _saving = false);
      _toast(context.sRead.errorSessionExpired);
      return;
    }

    try {
      final payload = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final row in _rows) {
        final code = row.item.itemCode.trim();
        if (code.isEmpty) continue;
        final dedupe = (row.item.epc.trim().isNotEmpty ? row.item.epc : code)
            .trim()
            .toUpperCase();
        if (dedupe.isEmpty || !seen.add(dedupe)) continue;
        payload.add({
          'ItemCode': code,
          'Status': row.matched ? 'match' : 'unmatch',
          'GrossWeight': row.grossWt,
          'NetWeight': double.tryParse(row.item.netWeight) ?? 0.0,
          'Quantity': 1,
          'CounterName': row.item.counterName,
          'CategoryName': row.item.category,
          'ProductName': row.item.productName,
          'DesignName': row.item.design,
          'PurityName': row.item.purity,
          'CompanyName': '',
          'BranchName': row.item.branchName.isNotEmpty ? row.item.branchName : _branchName,
          'CounterId': row.item.counterId,
          'CategoryId': row.item.categoryId,
          'ProductId': row.item.productId,
          'DesignId': row.item.designId,
          'PurityId': row.item.purityId,
          'CompanyId': 0,
          'BranchId': row.item.branchId > 0 ? row.item.branchId : _branchId,
        });
      }

      final settings = context.read<SettingsViewModel>();
      String? deviceCode;
      if (context.read<PrefService>().isWholesaleLoginUser()) {
        deviceCode = (await settings.ensureDeviceId()).trim();
      }
      final success = await viewModel.uploadVerification(
        clientCode: clientCode,
        items: payload,
        counterId: _counterId > 0 ? _counterId : null,
        counterName: _counterName.isNotEmpty ? _counterName : null,
        branchId: _branchId > 0 ? _branchId : null,
        branchName: _branchName.isNotEmpty ? _branchName : null,
        deviceCode: deviceCode,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (success) {
        _toast(context.sRead.stockVerificationUploaded);
        await _loadMissingStocks();
      } else {
        _toast(context.sRead.verificationUploadFailed(viewModel.errorMessage ?? ''));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context.sRead.verificationUploadFailed(e.toString()));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: AppFonts.poppins()), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final totalWt = _rows.fold<double>(0, (sum, r) => sum + r.grossWt);
    final matchedWt = _rows.where((r) => r.matched).fold<double>(0, (sum, r) => sum + r.grossWt);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () async {
                if (_scanning) await _stopScan();
                if (context.mounted) Navigator.pop(context);
              },
            ),
            title: Text(
              s.scanMissingStocks,
              style: AppFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          GestureDetector(
            onTap: _onBranchBarTap,
            child: Container(
              width: double.infinity,
              color: const Color(0xFFF5F3F3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _branchName.isNotEmpty
                          ? '${s.branch}: $_branchName'
                          : s.pleaseSelectBranch,
                      style: AppFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF3B363E),
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Color(0xFF3B363E)),
                ],
              ),
            ),
          ),
          _headerRow(s),
          Expanded(child: _buildList(s)),
          _summaryRow(
            total: _rows.length,
            matched: _matchedCount,
            totalWt: totalWt,
            matchedWt: matchedWt,
            s: s,
          ),
        ],
      ),
      bottomNavigationBar: ScanBottomBarMissingStocks(
        onSave: _save,
        onScan: _toggleScan,
        isScanning: _scanning,
        scanEnabled: !_saving && !_loading,
        saveEnabled: !_saving && !_loading && _rows.isNotEmpty,
      ),
    );
  }

  Widget _headerRow(dynamic s) {
    return Container(
      color: const Color(0xFF3B363E),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          _hCell(s.fieldDesign, 28),
          _hCell(s.rfidNo, 18),
          _hCell(s.itemcode, 17),
          _hCell(s.colGrossWt, 17),
          _hCell(s.status, 10, center: true),
        ],
      ),
    );
  }

  Widget _hCell(String text, int flex, {bool center = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: AppFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildList(dynamic s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF5231A7)));
    }
    if (_error != null && _rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: AppFonts.poppins(color: Colors.grey[700])),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_remove, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(s.noMissingStocks, style: AppFonts.poppins(fontSize: 14, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          itemCount: _rows.length,
          itemBuilder: (context, i) => _itemRow(_rows[i]),
        ),
        if (_saving)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x8AFFFFFF),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF5231A7))),
            ),
          ),
      ],
    );
  }

  Widget _itemRow(_MissingRow row) {
    final item = row.item;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: row.matched ? const Color(0xFFE8F5E9) : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 36,
              height: 36,
              child: ColoredBox(
                color: Colors.grey.shade100,
                child: ProductImage.fromBulkItem(item, iconSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 28,
            child: Text(
              item.design.isNotEmpty ? item.design : (item.productName.isNotEmpty ? item.productName : '-'),
              style: AppFonts.poppins(fontSize: 10.5, color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              item.rfid.isNotEmpty ? item.rfid : '-',
              style: AppFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 17,
            child: Text(
              item.itemCode.isNotEmpty ? item.itemCode : '-',
              style: AppFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 17,
            child: Text(
              row.grossWt.toStringAsFixed(3),
              style: AppFonts.poppins(fontSize: 10.5, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            flex: 10,
            child: Center(
              child: Icon(
                row.matched ? Icons.check_circle : Icons.cancel,
                color: row.matched ? Colors.green : Colors.red,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow({
    required int total,
    required int matched,
    required double totalWt,
    required double matchedWt,
    required dynamic s,
  }) {
    return Container(
      color: const Color(0xFF3B363E),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 28,
            child: Text(s.total, style: AppFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 18,
            child: Text('$total', textAlign: TextAlign.center, style: AppFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 17,
            child: Text(totalWt.toStringAsFixed(3), style: AppFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 17,
            child: Text('$matched', textAlign: TextAlign.center, style: AppFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 10,
            child: Text(matchedWt.toStringAsFixed(3), style: AppFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
