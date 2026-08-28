import 'dart:async';
import 'package:flutter/foundation.dart';

/// Coalesces high-frequency RFID tag events into batched callbacks (RFID handhelds).
class TagScanBatcher {
  final Duration flushInterval;
  final void Function(List<String> tags) onFlush;

  final Set<String> _pending = {};
  Timer? _timer;
  bool _disposed = false;

  TagScanBatcher({
    this.flushInterval = const Duration(milliseconds: 120),
    required this.onFlush,
  });

  void add(String rawTag) {
    if (_disposed) return;
    final tag = rawTag.trim();
    if (tag.isEmpty) return;
    _pending.add(tag);
    _timer ??= Timer(flushInterval, _flush);
  }

  void addAll(Iterable<String> tags) {
    for (final tag in tags) {
      add(tag);
    }
  }

  void flushNow() {
    _timer?.cancel();
    _timer = null;
    _flush();
  }

  /// Drop tags not yet flushed (used when GSCAN stops so totals freeze).
  void discardPending() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void _flush() {
    _timer = null;
    if (_disposed || _pending.isEmpty) return;
    final batch = _pending.toList(growable: false);
    _pending.clear();
    onFlush(batch);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}

/// Lets GSCAN screens freeze totals the moment the scanner stops.
mixin LiveScanGate on ChangeNotifier {
  bool _liveScanEnabled = false;
  bool get liveScanEnabled => _liveScanEnabled;

  void beginLiveScan() {
    _liveScanEnabled = true;
  }

  void abortLiveScan() {
    _liveScanEnabled = false;
  }

  bool acceptLiveScan(bool fromLiveScan) => !fromLiveScan || _liveScanEnabled;
}
