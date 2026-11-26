import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../utils/app_fonts.dart';
import '../utils/scan_key.dart';

/// Customer-facing totals for the Bluetooth tray.
/// Opens only from the drawer. Starts a scan only when this screen is
/// showing and the tray is already connected, and stops only that scan.
class TrayViewScreen extends StatefulWidget {
  const TrayViewScreen({super.key});

  @override
  State<TrayViewScreen> createState() => _TrayViewScreenState();
}

class _TrayOnTray {
  _TrayOnTray(this.item) : lastSeenMs = DateTime.now().millisecondsSinceEpoch;

  final BulkItem item;
  int lastSeenMs;
}

class _TrayViewScreenState extends State<TrayViewScreen> {
  final RfidService _rfid = RfidService();
  final DbService _db = DbService();

  StreamSubscription<String>? _tagsSub;
  Timer? _presenceTimer;
  final Map<String, _TrayOnTray> _onTray = {};
  final Set<String> _lookupPending = {};

  bool _weStartedScan = false;
  bool _startInFlight = false;
  bool _refreshing = false;
  bool _linkReady = false;
  bool _closed = false;
  double _gross = 0;
  double _net = 0;
  int _pieces = 0;

  @override
  void initState() {
    super.initState();
    _rfid.addConnectionListener(_onConnection);
    _tagsSub = _rfid.tagsStream.listen(_onTag);
    _presenceTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _dropLeftTags();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshLink());
    });
  }

  @override
  void dispose() {
    _closed = true;
    _rfid.removeConnectionListener(_onConnection);
    _tagsSub?.cancel();
    _presenceTimer?.cancel();
    if (_weStartedScan) {
      _weStartedScan = false;
      unawaited(_rfid.stopScanning());
    }
    super.dispose();
  }

  void _onConnection() {
    if (!mounted || _closed) return;
    unawaited(_refreshLink());
  }

  /// Android can already hold the tray while the reader flag is still false.
  /// That is the "Bluetooth connected, Tray View says Not connected" case.
  Future<void> _refreshLink() async {
    if (_closed || !mounted || _refreshing) return;
    _refreshing = true;
    try {
      final prefs = context.read<PrefService>();
      var status = await _rfid.getTrayStatus();
      final saved = prefs.getTrayDeviceAddress().trim();
      final modeOn = prefs.isTrayModeEnabled() ||
          status['enabled'] == true ||
          _rfid.trayModeEnabled;
      if (modeOn && saved.isNotEmpty && status['enabled'] != true) {
        await _rfid.applyTrayMode(enabled: true, address: saved);
        if (_closed || !mounted) return;
        status = await _rfid.getTrayStatus();
      }
      final ready = status['connected'] == true ||
          status['osLinked'] == true ||
          status['connecting'] == true ||
          _rfid.trayReaderActive ||
          (modeOn && saved.isNotEmpty);
      if (_closed || !mounted) return;
      if (!ready) {
        _onTray.clear();
        _recompute();
      }
      setState(() => _linkReady = ready);
      if (ready) {
        await _startIfTray();
      } else if (_weStartedScan) {
        _weStartedScan = false;
        await _rfid.stopScanning();
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _startIfTray() async {
    if (_closed || !mounted || !_linkReady) return;
    if (_rfid.isScanning || _startInFlight) return;
    _startInFlight = true;
    try {
      final power = context.read<PrefService>().inventoryPower;
      var started = await _rfid.startInventoryScanning(power: power);
      if (!started && !_closed && mounted && _linkReady && !_rfid.isScanning) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (_closed || !mounted || !_linkReady || _rfid.isScanning) return;
        started = await _rfid.startInventoryScanning(power: power);
      }
      if (_closed) {
        if (started) await _rfid.stopScanning();
        return;
      }
      _weStartedScan = started;
      if (mounted) setState(() {});
    } finally {
      _startInFlight = false;
    }
  }

  void _onTag(String raw) {
    if (_closed || !_linkReady) return;
    final key = normalizeScanKey(raw);
    if (key.isEmpty) return;
    final known = _onTray[key];
    if (known != null) {
      known.lastSeenMs = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    if (!_lookupPending.add(key)) return;
    unawaited(_resolve(key));
  }

  Future<void> _resolve(String key) async {
    try {
      final item = await _db.findBulkItemByScanKey(key);
      if (_closed || item == null || !_linkReady) return;
      final id = _itemKey(item);
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = _onTray[id];
      if (existing != null) {
        existing.lastSeenMs = now;
        _onTray[key] = existing;
        return;
      }
      final row = _TrayOnTray(item)..lastSeenMs = now;
      _onTray[id] = row;
      _onTray[key] = row;
      _recompute();
      if (mounted) setState(() {});
    } finally {
      _lookupPending.remove(key);
    }
  }

  String _itemKey(BulkItem item) {
    final code = normalizeScanKey(item.itemCode);
    if (code.isNotEmpty) return 'code:$code';
    final rfid = normalizeScanKey(item.rfid);
    if (rfid.isNotEmpty) return 'rfid:$rfid';
    final epc = normalizeScanKey(item.epc);
    if (epc.isNotEmpty) return 'epc:$epc';
    return 'id:${item.bulkItemId}';
  }

  void _dropLeftTags() {
    if (_closed || _onTray.isEmpty || !_rfid.isScanning) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = <String>[];
    final seenItems = <_TrayOnTray>{};
    for (final entry in _onTray.entries) {
      if (!seenItems.add(entry.value)) continue;
      if (now - entry.value.lastSeenMs >= 3000) stale.add(entry.key);
    }
    if (stale.isEmpty) return;
    final drop = stale.map((key) => _onTray[key]).toSet();
    _onTray.removeWhere((_, row) => drop.contains(row));
    _recompute();
    if (mounted) setState(() {});
  }

  void _recompute() {
    final rows = <_TrayOnTray>{};
    for (final row in _onTray.values) {
      rows.add(row);
    }
    var gross = 0.0;
    var net = 0.0;
    var pieces = 0;
    for (final row in rows) {
      gross += _weight(row.item.grossWeight);
      net += _weight(row.item.netWeight);
      final pcs = row.item.pcs;
      pieces += pcs > 0 ? pcs : 1;
    }
    _gross = gross;
    _net = net;
    _pieces = pieces;
  }

  double _weight(String raw) => double.tryParse(raw.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final connected = _linkReady || _rfid.trayReaderActive;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
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
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              s.trayView,
              style: AppFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: connected
            ? _Totals(
                landscape: landscape,
                grossLabel: s.totalGrossWt,
                netLabel: s.totalNetWt,
                piecesLabel: s.totalPieces,
                gross: _gross,
                net: _net,
                pieces: _pieces,
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    s.trayNotConnected,
                    textAlign: TextAlign.center,
                    style: AppFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.landscape,
    required this.grossLabel,
    required this.netLabel,
    required this.piecesLabel,
    required this.gross,
    required this.net,
    required this.pieces,
  });

  final bool landscape;
  final String grossLabel;
  final String netLabel;
  final String piecesLabel;
  final double gross;
  final double net;
  final int pieces;

  @override
  Widget build(BuildContext context) {
    final figures = [
      _Figure(label: grossLabel, value: gross.toStringAsFixed(3)),
      _Figure(label: netLabel, value: net.toStringAsFixed(3)),
      _Figure(label: piecesLabel, value: '$pieces'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = landscape || constraints.maxWidth > constraints.maxHeight;
        final valueSize = wide ? 40.0 : 48.0;
        final labelSize = wide ? 16.0 : 18.0;
        final gap = wide ? 8.0 : 28.0;
        final board = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final figure in figures)
                    Expanded(
                      child: figure.copyWith(
                        valueSize: valueSize,
                        labelSize: labelSize,
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < figures.length; i++) ...[
                    if (i > 0) SizedBox(height: gap),
                    figures[i].copyWith(
                      valueSize: valueSize,
                      labelSize: labelSize,
                    ),
                  ],
                ],
              );
        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 16 : 24,
              vertical: wide ? 8 : 16,
            ),
            child: board,
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.valueSize = 48,
    this.labelSize = 18,
  });

  final String label;
  final String value;
  final double valueSize;
  final double labelSize;

  _Figure copyWith({double? valueSize, double? labelSize}) {
    return _Figure(
      label: label,
      value: value,
      valueSize: valueSize ?? this.valueSize,
      labelSize: labelSize ?? this.labelSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: AppFonts.poppins(
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
              height: 1.05,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.poppins(
            fontSize: labelSize,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF5231A7),
          ),
        ),
      ],
    );
  }
}
