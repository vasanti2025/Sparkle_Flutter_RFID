import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Solid LED Tag light using [rfid_flutter_android] only.
///
/// Talks to the plugin UART channel (`setFilter` + `setInventoryMode`
/// `MODE_LED_TAG` = 14). Does not listen to the plugin tag stream, so the
/// app inventory callback, sound, and other scans stay on the existing reader.
class LedTagSolid {
  LedTagSolid._();

  static final LedTagSolid instance = LedTagSolid._();

  /// Chainway InventoryModeEntity.MODE_LED_TAG — demo "Solid", not blink (15).
  static const ledTagSolidMode = 14;

  static const _epcBank = 1;
  static const _maxFilters = 8;
  static const _channel = MethodChannel('rfid_flutter_android/uart');

  bool _ready = false;
  Future<void> _gate = Future<void>.value();

  /// Empty [epcs] clears the filter so every LED tag stays solid.
  /// Non-empty list lights only those chip EPCs (max 8, EPC bank, offset 32).
  Future<bool> turnSolid(List<String> epcs) {
    return _serialized(() async {
      if (!await _ensureReady()) return false;
      final chips = _chipEpcs(epcs);
      final filtered = chips.isEmpty ? await _clearFilter() : await _setEpcFilters(chips);
      if (!filtered) return false;
      return _setSolidMode();
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _gate.then((_) => action());
    _gate = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<bool> _ensureReady() async {
    if (_ready) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('init');
      // Shared UART singleton may already be open; the plugin still keeps the handle.
      final mode = await _channel.invokeMethod<dynamic>('getInventoryMode');
      _ready = ok == true || mode is Map;
      if (!_ready) {
        debugPrint('LedTagSolid: plugin UART init failed');
      }
      return _ready;
    } catch (e) {
      debugPrint('LedTagSolid: init failed: $e');
      _ready = false;
      return false;
    }
  }

  Future<bool> _setSolidMode() async {
    try {
      final ok = await _channel.invokeMethod<bool>('setInventoryMode', {
        'inventoryBank': ledTagSolidMode,
        'offset': 0,
        'length': 0,
      });
      debugPrint('LedTagSolid: MODE_LED_TAG solid => $ok');
      return ok == true;
    } catch (e) {
      debugPrint('LedTagSolid: solid mode failed: $e');
      return false;
    }
  }

  Future<bool> _clearFilter() async {
    try {
      final ok = await _channel.invokeMethod<bool>('setFilter', {
        'bank': _epcBank,
        'offset': 0,
        'length': 0,
        'data': '',
      });
      return ok == true;
    } catch (e) {
      debugPrint('LedTagSolid: clear filter failed: $e');
      return false;
    }
  }

  Future<bool> _setEpcFilters(List<String> epcs) async {
    final filters = [
      for (final epc in epcs)
        {
          'bank': _epcBank,
          'offset': 32,
          'length': epc.length * 4,
          'data': epc,
        },
    ];
    try {
      if (filters.length == 1) {
        final ok = await _channel.invokeMethod<bool>('setFilter', filters.first);
        return ok == true;
      }
      final ok = await _channel.invokeMethod<bool>('setFilters', {'filters': filters});
      return ok == true;
    } catch (e) {
      debugPrint('LedTagSolid: setFilter failed: $e');
      return false;
    }
  }

  /// 24/32-bit hex chip IDs only. Offset-32 filter matches the framework demo.
  List<String> _chipEpcs(List<String> raw) {
    final unique = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      final epc = value.trim().toUpperCase();
      if (epc.length != 24 && epc.length != 32) continue;
      if (!RegExp(r'^[0-9A-F]+$').hasMatch(epc)) continue;
      if (!seen.add(epc)) continue;
      unique.add(epc);
    }
    unique.sort((a, b) {
      int rank(String s) => s.length == 24 ? 2 : (s.length == 32 ? 1 : 0);
      final byRank = rank(b).compareTo(rank(a));
      if (byRank != 0) return byRank;
      return b.length.compareTo(a.length);
    });
    if (unique.length <= _maxFilters) return unique;
    return unique.sublist(0, _maxFilters);
  }
}
