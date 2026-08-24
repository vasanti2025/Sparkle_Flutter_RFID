import 'dart:async';

import '../services/rfid_service.dart';

/// Default quiet period after the last new tray tag before auto-stop.
const kTrayScanSettleMs = 1500;

/// Inventory / scan-display: stop when every in-scope tag seen on the tray
/// is matched, not when the full list scope is matched.
class TrayInventoryScanSession {
  final Set<String> seenInScope = {};
  int _lastNewEpcMs = 0;

  void reset() {
    seenInScope.clear();
    _lastNewEpcMs = 0;
  }

  void recordInScope(String epc, Set<String> scopeEpcs) {
    final key = epc.trim().toUpperCase();
    if (key.isEmpty || !scopeEpcs.contains(key)) return;
    if (seenInScope.add(key)) {
      _lastNewEpcMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  /// Large-catalog mode: tag already verified in DB scope — no in-memory scope set.
  void recordInScopeTag(String epc) {
    final key = epc.trim().toUpperCase();
    if (key.isEmpty) return;
    if (seenInScope.add(key)) {
      _lastNewEpcMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  bool shouldStop(Set<String> matchedEpcs, {int settleMs = kTrayScanSettleMs}) {
    if (seenInScope.isEmpty) return false;
    if (!seenInScope.every(matchedEpcs.contains)) return false;
    return DateTime.now().millisecondsSinceEpoch - _lastNewEpcMs >= settleMs;
  }
}

/// Gscan / product screens: stop when every tag seen on the tray was handled
/// (found in DB or matched to the active document scope).
class TrayGscanSession {
  final Set<String> seen = {};
  final Set<String> handled = {};
  int _lastNewSeenMs = 0;

  void reset() {
    seen.clear();
    handled.clear();
    _lastNewSeenMs = 0;
  }

  void recordSeen(String epc) {
    final key = epc.trim().toUpperCase();
    if (key.isEmpty) return;
    if (seen.add(key)) {
      _lastNewSeenMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  void recordHandled(String epc) {
    final key = epc.trim().toUpperCase();
    if (key.isNotEmpty) handled.add(key);
  }

  bool shouldStop({int settleMs = kTrayScanSettleMs}) {
    if (seen.isEmpty) return false;
    if (!seen.every(handled.contains)) return false;
    return DateTime.now().millisecondsSinceEpoch - _lastNewSeenMs >= settleMs;
  }
}

/// Shared helper for order / challan / quotation gscan screens.
class TrayGscanAutoStopController {
  TrayGscanAutoStopController({
    required this.rfidService,
    required this.onStop,
  });

  final RfidService rfidService;
  final Future<void> Function() onStop;
  final TrayGscanSession session = TrayGscanSession();

  bool get isActive => rfidService.trayReaderActive;

  void onScanStarted() => session.reset();

  void afterBatch(List<String> tags, bool Function(String tag) isHandled) {
    if (!isActive || !rfidService.isScanning) return;
    for (final tag in tags) {
      session.recordSeen(tag);
      if (isHandled(tag)) session.recordHandled(tag);
    }
    if (session.shouldStop()) {
      unawaited(onStop());
    }
  }
}
