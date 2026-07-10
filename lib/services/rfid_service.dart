import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'db_service.dart';

class RfidService {
  static final RfidService _instance = RfidService._internal();
  factory RfidService() => _instance;

  RfidService._internal() {
    _initChannels();
  }

  static const _methodChannel = MethodChannel('com.loyalstring.rfid/uhf');
  static const _eventChannel = EventChannel('com.loyalstring.rfid/tags');

  bool _isSupported = false;
  bool get isSupported => _isSupported;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _trayModeEnabled = false;
  bool get trayModeEnabled => _trayModeEnabled;

  bool _trayConnected = false;
  bool get trayConnected => _trayConnected;

  bool _r6ModeEnabled = false;
  bool get r6ModeEnabled => _r6ModeEnabled;

  bool _r6Connected = false;
  bool get r6Connected => _r6Connected;

  bool get bleReaderActive =>
      (_trayModeEnabled && _trayConnected) || (_r6ModeEnabled && _r6Connected);

  int _power = 5;
  int get power => _power;

  final _tagsController = StreamController<String>.broadcast();
  Stream<String> get tagsStream => _tagsController.stream;

  final _tagsWithRssiController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get tagsWithRssiStream => _tagsWithRssiController.stream;

  final _triggerController = StreamController<void>.broadcast();
  Stream<void> get triggerStream => _triggerController.stream;

  StreamSubscription? _eventSubscription;
  Timer? _simulationTimer;
  List<String> _simulatedTagsPool = [];
  int _simulationIndex = 0;

  void _initChannels() async {
    try {
      _isSupported = await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
      if (_isSupported) {
        await _methodChannel.invokeMethod('initReader');
      }
    } catch (e) {
      debugPrint('RFID Hardware check failed, using simulator fallback: $e');
      _isSupported = false;
    }

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event == 'TRIGGER_CLICK') {
          _triggerController.add(null);
        } else if (event == 'TRAY_CONNECTED') {
          _trayConnected = true;
        } else if (event == 'TRAY_DISCONNECTED') {
          _trayConnected = false;
        } else if (event == 'R6_CONNECTED') {
          _r6Connected = true;
        } else if (event == 'R6_DISCONNECTED') {
          _r6Connected = false;
        } else if (event is String) {
          if (event.startsWith('BATCH:')) {
            final payload = event.substring(6);
            if (payload.isEmpty) return;
            for (final entry in payload.split('|')) {
              _emitParsedTag(entry);
            }
            return;
          }
          _emitParsedTag(event);
        }
      },
      onError: (err) {
        debugPrint('RFID Event Stream Error: $err');
      },
    );
  }

  void _emitParsedTag(String event) {
    if (event.contains(',')) {
      final parts = event.split(',');
      final epc = parts[0];
      final rssi = parts.length > 1 ? parts[1] : '';
      if (epc.isEmpty) return;
      _tagsController.add(epc);
      _tagsWithRssiController.add({'epc': epc, 'rssi': rssi});
    } else if (event.isNotEmpty) {
      _tagsController.add(event);
      _tagsWithRssiController.add({'epc': event, 'rssi': ''});
    }
  }

  /// Preload inventory keys on device before G-scan (native filters non-matching tags).
  Future<void> prepareProductScanMatchSet(DbService db) async {
    if (!_isSupported) return;
    await db.warmScanKeyIndex();
    final keys = db.scanKeysForNativeMatch();
    if (keys.isNotEmpty) {
      await setMatchEpcs(keys);
    } else {
      await clearMatchEpcs();
    }
  }

  Future<void> restoreTrayModeFromPrefs({
    required bool enabled,
    required String address,
  }) async {
    _trayModeEnabled = enabled;
    if (!_isSupported || !enabled || address.isEmpty) return;
    await applyTrayMode(enabled: true, address: address);
  }

  Future<void> restoreR6ModeFromPrefs({
    required bool enabled,
    required String address,
  }) async {
    _r6ModeEnabled = enabled;
    if (!_isSupported || !enabled || address.isEmpty) return;
    await applyR6Mode(enabled: true, address: address);
  }

  Future<bool> applyTrayMode({
    required bool enabled,
    String address = '',
  }) async {
    _trayModeEnabled = enabled;
    if (enabled) {
      _r6ModeEnabled = false;
      _r6Connected = false;
    }
    if (!_isSupported) return false;
    try {
      final status = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'setTrayMode',
        {'enabled': enabled, 'address': address},
      );
      _trayConnected = status?['connected'] == true;
      return true;
    } catch (e) {
      debugPrint('Error applying tray mode: $e');
      _trayConnected = false;
      return false;
    }
  }

  Future<bool> applyR6Mode({
    required bool enabled,
    String address = '',
  }) async {
    _r6ModeEnabled = enabled;
    if (enabled) {
      _trayModeEnabled = false;
      _trayConnected = false;
    }
    if (!_isSupported) return false;
    try {
      final status = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'setR6Mode',
        {'enabled': enabled, 'address': address},
      );
      _r6Connected = status?['connected'] == true;
      return true;
    } catch (e) {
      debugPrint('Error applying R6 mode: $e');
      _r6Connected = false;
      return false;
    }
  }

  Future<Map<String, dynamic>> getTrayStatus() async {
    if (!_isSupported) {
      return {'enabled': _trayModeEnabled, 'connected': false, 'address': ''};
    }
    try {
      final status = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getTrayStatus');
      _trayConnected = status?['connected'] == true;
      return {
        'enabled': status?['enabled'] == true,
        'connected': status?['connected'] == true,
        'address': status?['address']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('Error reading tray status: $e');
      return {'enabled': _trayModeEnabled, 'connected': _trayConnected, 'address': ''};
    }
  }

  Future<Map<String, dynamic>> getR6Status() async {
    if (!_isSupported) {
      return {'enabled': _r6ModeEnabled, 'connected': false, 'address': ''};
    }
    try {
      final status = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getR6Status');
      _r6Connected = status?['connected'] == true;
      return {
        'enabled': status?['enabled'] == true,
        'connected': status?['connected'] == true,
        'address': status?['address']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('Error reading R6 status: $e');
      return {'enabled': _r6ModeEnabled, 'connected': _r6Connected, 'address': ''};
    }
  }

  Future<List<Map<String, String>>> listBondedBluetoothDevices() async {
    if (!_isSupported) return const [];
    try {
      final list = await _methodChannel.invokeMethod<List<dynamic>>('listBondedBluetoothDevices');
      if (list == null) return const [];
      return list.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'name': map['name']?.toString() ?? 'Bluetooth Device',
          'address': map['address']?.toString() ?? '',
        };
      }).where((d) => d['address']!.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Error listing bonded Bluetooth devices: $e');
      return const [];
    }
  }

  Future<bool> setPower(int power) async {
    _power = power;
    if (_isSupported) {
      try {
        return await _methodChannel.invokeMethod<bool>('setPower', {'power': power}) ?? false;
      } catch (e) {
        debugPrint('Error setting native power: $e');
        return false;
      }
    }
    return true;
  }

  Future<bool> startScanning({
    int power = 5,
    List<String> simulatedScopeTags = const [],
    bool inventory = false,
  }) async {
    if (_isScanning) {
      await stopScanning();
    }
    _power = power;

    if (_isSupported) {
      try {
        // BLE tray/R6 require an active Bluetooth connection before scan.
        if (_trayModeEnabled) {
          final status = await getTrayStatus();
          if (status['connected'] != true) {
            debugPrint('Tray mode on but tray not connected — cannot start scan');
            return false;
          }
        }
        if (_r6ModeEnabled) {
          final status = await getR6Status();
          if (status['connected'] != true) {
            debugPrint('R6 mode on but R6 not connected — cannot start scan');
            return false;
          }
        }
        // Inventory screen prepares scope before calling; other screens need
        // a standard product-scan session (Order / Challan / Quotation / Search).
        if (!inventory) {
          await setInventoryScanMode(false);
        }
        await prepareForScan();
        await setPower(power);

        final started = await _methodChannel.invokeMethod<bool>('startScanning', {
              'power': power,
              'inventory': inventory,
            }) ??
            false;
        if (started) {
          _isScanning = true;
        }
        return started;
      } catch (e) {
        debugPrint('Error starting native scan: $e');
        return false;
      }
    } else {
      // Fallback to simulated scanning
      _isScanning = true;
      _simulatedTagsPool = List.from(simulatedScopeTags);
      _simulationIndex = 0;
      _startSimulation();
      return true;
    }
  }

  Future<bool> stopScanning() async {
    _isScanning = false;
    _simulationTimer?.cancel();
    _simulationTimer = null;

    if (_isSupported) {
      try {
        await clearMatchEpcs();
        final stopped = await _methodChannel.invokeMethod<bool>('stopScanning') ?? false;
        return stopped;
      } catch (e) {
        debugPrint('Error stopping native scan: $e');
        return false;
      }
    } else {
      return true;
    }
  }

  void _startSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!_isScanning) {
        timer.cancel();
        return;
      }
      
      // Simulate RSSI fluctuating between -75 and -45
      final random = DateTime.now().millisecond;
      final mockRssi = (-75 + (random % 31)).toString();

      if (_simulatedTagsPool.isEmpty) {
        final mockEpc = 'E2009876543210${100 + _simulationIndex}';
        _tagsController.add(mockEpc);
        _tagsWithRssiController.add({'epc': mockEpc, 'rssi': mockRssi});
        _simulationIndex++;
      } else {
        final mockEpc = _simulatedTagsPool[_simulationIndex % _simulatedTagsPool.length];
        _tagsController.add(mockEpc);
        _tagsWithRssiController.add({'epc': mockEpc, 'rssi': mockRssi});
        _simulationIndex++;
      }
    });
  }

  Future<bool> setSearchTags(List<String> tags) async {
    if (_isSupported) {
      try {
        return await _methodChannel.invokeMethod<bool>('setSearchTags', {'tags': tags}) ?? false;
      } catch (e) {
        debugPrint('Error setting search tags: $e');
        return false;
      }
    }
    return true;
  }

  Future<bool> setMatchEpcs(List<String> epcs) async {
    if (_isSupported) {
      try {
        // Binder transactions fail above ~1MB — cap native match set.
        const maxNativeMatchTags = 8000;
        final capped = epcs.length > maxNativeMatchTags
            ? epcs.sublist(0, maxNativeMatchTags)
            : epcs;
        return await _methodChannel.invokeMethod<bool>('setMatchEpcs', {'epcs': capped}) ?? false;
      } catch (e) {
        debugPrint('Error setting match EPCs: $e');
        return false;
      }
    }
    return true;
  }

  Future<bool> prepareForScan() async {
    if (_isSupported) {
      try {
        return await _methodChannel.invokeMethod<bool>('prepareForScan') ?? false;
      } catch (e) {
        debugPrint('Error prepareForScan: $e');
        return false;
      }
    }
    return true;
  }

  Future<bool> haltScan() async {
    if (_isSupported) {
      try {
        return await _methodChannel.invokeMethod<bool>('haltScan') ?? false;
      } catch (e) {
        debugPrint('Error haltScan: $e');
        return false;
      }
    }
    return true;
  }

  Future<bool> setInventoryScanMode(bool enabled) async {
    if (_isSupported) {
      try {
        return await _methodChannel.invokeMethod<bool>(
              'setInventoryScanMode',
              {'enabled': enabled},
            ) ??
            false;
      } catch (e) {
        debugPrint('Error setting inventory scan mode: $e');
        return false;
      }
    }
    return true;
  }

  Future<void> playBeep() async {
    if (_isSupported) {
      try {
        await _methodChannel.invokeMethod('playBeep');
      } catch (e) {
        debugPrint('Error playing beep: $e');
      }
    }
  }

  Future<bool> clearMatchEpcs() async {
    if (_isSupported) {
      try {
        return await _methodChannel.invokeMethod<bool>('clearMatchEpcs') ?? false;
      } catch (e) {
        debugPrint('Error clearing match EPCs: $e');
        return false;
      }
    }
    return true;
  }

  Future<void> preWarmReader() async {
    if (!_isSupported) return;
    try {
      await _methodChannel.invokeMethod('initReader');
    } catch (e) {
      debugPrint('Error pre-warming reader: $e');
    }
  }

  Future<bool> clearSearchTags() async {
    if (_isSupported) {
      try {
        return await _methodChannel.invokeMethod<bool>('clearSearchTags') ?? false;
      } catch (e) {
        debugPrint('Error clearing search tags: $e');
        return false;
      }
    }
    return true;
  }

  Future<bool> clearInventoryScope() async {
    if (_isSupported) {
      try {
        return await _methodChannel.invokeMethod<bool>('clearInventoryScope') ?? false;
      } catch (e) {
        debugPrint('Error clearing inventory scope: $e');
        return false;
      }
    }
    return true;
  }

  Future<bool> addInventoryScopeEpcs(List<String> epcs) async {
    if (_isSupported && epcs.isNotEmpty) {
      try {
        return await _methodChannel.invokeMethod<bool>(
              'addInventoryScopeEpcs',
              {'epcs': epcs},
            ) ??
            false;
      } catch (e) {
        debugPrint('Error adding inventory scope epcs: $e');
        return false;
      }
    }
    return true;
  }

  Future<void> setInventoryScopeEpcsBatched(List<String> epcs) async {
    await clearInventoryScope();
    const batchSize = 5000;
    for (var i = 0; i < epcs.length; i += batchSize) {
      final end = (i + batchSize < epcs.length) ? i + batchSize : epcs.length;
      await addInventoryScopeEpcs(epcs.sublist(i, end));
    }
  }

  void dispose() {
    stopScanning();
    _eventSubscription?.cancel();
    _tagsController.close();
    _tagsWithRssiController.close();
    _triggerController.close();
  }
}
