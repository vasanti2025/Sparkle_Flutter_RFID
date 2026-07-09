import 'dart:async';

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
