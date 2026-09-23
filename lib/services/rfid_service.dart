import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/bluetooth_permission_util.dart';
import 'db_service.dart';
import 'pref_service.dart';

class RfidService {
  static final RfidService _instance = RfidService._internal();
  factory RfidService() => _instance;

  RfidService._internal() {
    _readyFuture = _initChannels();
  }

  static const _methodChannel = MethodChannel('com.loyalstring.rfid/uhf');
  static const _eventChannel = EventChannel('com.loyalstring.rfid/tags');

  bool _isSupported = false;
  bool get isSupported => _isSupported;

  late final Future<void> _readyFuture;
  Future<void> get ready => _readyFuture;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _trayModeEnabled = false;
  bool get trayModeEnabled => _trayModeEnabled;

  bool _trayConnected = false;
  bool get trayConnected => _trayConnected;

  bool _trayConnecting = false;
  bool get trayConnecting => _trayConnecting;

  bool _r6ModeEnabled = false;
  bool get r6ModeEnabled => _r6ModeEnabled;

  bool _r6Connected = false;
  bool get r6Connected => _r6Connected;

  bool _r6Connecting = false;
  bool get r6Connecting => _r6Connecting;

  bool get bleReaderActive =>
      (_trayModeEnabled && _trayConnected) || (_r6ModeEnabled && _r6Connected);

  /// BLE tray reader only (not R6 handheld sled).
  bool get trayReaderActive => _trayModeEnabled && _trayConnected;

  int _power = 5;
  int get power => _power;

  final _tagsController = StreamController<String>.broadcast();
  Stream<String> get tagsStream => _tagsController.stream;

  final _tagsWithRssiController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get tagsWithRssiStream => _tagsWithRssiController.stream;

  final _triggerController = StreamController<void>.broadcast();
  Stream<void> get triggerStream => _triggerController.stream;

  final _barcodeController = StreamController<String>.broadcast();
  Stream<String> get barcodeStream => _barcodeController.stream;

  final _barcodeTriggerController = StreamController<void>.broadcast();
  Stream<void> get barcodeTriggerStream => _barcodeTriggerController.stream;

  StreamSubscription? _eventSubscription;
  Timer? _simulationTimer;
  List<String> _simulatedTagsPool = [];
  int _simulationIndex = 0;
  final List<VoidCallback> _connectionListeners = [];

  void addConnectionListener(VoidCallback listener) {
    if (!_connectionListeners.contains(listener)) {
      _connectionListeners.add(listener);
    }
  }

  void removeConnectionListener(VoidCallback listener) {
    _connectionListeners.remove(listener);
  }

  void _notifyConnectionListeners() {
    for (final listener in List<VoidCallback>.from(_connectionListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  Future<void> _initChannels() async {
    // Startup must NOT call initReader — Chainway UART init can block 1–2+ minutes.
    // Only probe support; hardware init happens lazily on first scan.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        _isSupported = await _methodChannel
            .invokeMethod<bool>('isSupported')
            .timeout(const Duration(milliseconds: 800), onTimeout: () => false) ??
            false;
        if (_isSupported) break;
      } catch (e) {
        debugPrint('RFID channel not ready (attempt ${attempt + 1}): $e');
        _isSupported = false;
      }
      await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
    }
    if (!_isSupported) {
      debugPrint('RFID Hardware check failed, using simulator fallback');
    }

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        try {
          if (event == 'TRIGGER_CLICK') {
            _triggerController.add(null);
          } else if (event == 'BARCODE_TRIGGER') {
            _barcodeTriggerController.add(null);
          } else if (event is String && event.startsWith('BARCODE:')) {
            final code = event.substring(8).trim();
            if (code.isNotEmpty) _barcodeController.add(code);
          } else if (event == 'TRAY_CONNECTED') {
            _trayConnected = true;
            _trayConnecting = false;
            _notifyConnectionListeners();
          } else if (event == 'TRAY_DISCONNECTED') {
            _trayConnected = false;
            _notifyConnectionListeners();
          } else if (event == 'R6_CONNECTED') {
            _r6Connected = true;
            _r6Connecting = false;
            _notifyConnectionListeners();
          } else if (event == 'R6_DISCONNECTED') {
            _r6Connected = false;
            _notifyConnectionListeners();
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
        } catch (e, st) {
          debugPrint('RFID event parse error: $e\n$st');
        }
      },
      onError: (err) {
        debugPrint('RFID Event Stream Error: $err');
      },
    );
  }

  Future<bool> ensureReady() async {
    await _readyFuture;
    return _isSupported;
  }

  /// Open Chainway barcode decoder (idempotent).
  Future<bool> openBarcode() async {
    await ensureReady();
    if (!_isSupported) return false;
    try {
      return await _methodChannel.invokeMethod<bool>('openBarcode') ?? false;
    } catch (e) {
      debugPrint('openBarcode error: $e');
      return false;
    }
  }

  /// Start hardware barcode scan (same as Sparkle BulkViewModel.startBarcodeScanning).
  Future<bool> startBarcodeScan() async {
    await ensureReady();
    if (!_isSupported) return false;
    try {
      await openBarcode();
      return await _methodChannel.invokeMethod<bool>('startBarcodeScan') ?? false;
    } catch (e) {
      debugPrint('startBarcodeScan error: $e');
      return false;
    }
  }

  Future<void> stopBarcodeScan() async {
    if (!_isSupported) return;
    try {
      await _methodChannel.invokeMethod('stopBarcodeScan');
    } catch (e) {
      debugPrint('stopBarcodeScan error: $e');
    }
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
    await ensureReady();
    if (!_isSupported || !enabled || address.isEmpty) return;
    await applyTrayMode(enabled: true, address: address);
    // Native connect is async; startScanning finishes GATT. Don't block 12s here.
    await waitForBleConnection(isR6: false, timeout: const Duration(seconds: 2));
  }

  Future<void> restoreR6ModeFromPrefs({
    required bool enabled,
    required String address,
  }) async {
    _r6ModeEnabled = enabled;
    await ensureReady();
    if (!_isSupported || !enabled || address.isEmpty) return;
    await applyR6Mode(enabled: true, address: address);
    await waitForBleConnection(isR6: true, timeout: const Duration(seconds: 2));
  }

  Future<List<Map<String, String>>> listSystemConnectedBluetoothDevices() async {
    await ensureReady();
    if (!_isSupported) return const [];
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    try {
      final list = await _methodChannel.invokeMethod<List<dynamic>>(
        'listSystemConnectedBluetoothDevices',
      );
      if (list == null) return const [];
      return list.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'name': map['name']?.toString() ?? 'Bluetooth Device',
          'address': map['address']?.toString() ?? '',
        };
      }).where((d) => d['address']!.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Error listing system-connected Bluetooth devices: $e');
      return const [];
    }
  }

  bool _looksLikeAccessory(String name) {
    final n = name.toUpperCase().replaceAll(' ', '');
    return n.contains('HEADSET') ||
        n.contains('HEADPHONE') ||
        n.contains('AIRPOD') ||
        n.contains('WATCH') ||
        n.contains('SPEAKER') ||
        n.contains('PRINTER') ||
        n.contains('MOUSE') ||
        n.contains('KEYBOARD') ||
        n.contains('BUDS') ||
        n.contains('EARPHONE');
  }

  bool _looksLikeR6(String name) {
    final n = name.toUpperCase().replaceAll(' ', '');
    if (_looksLikeAccessory(name)) return false;
    return n.contains('R6');
  }

  bool _looksLikeTray(String name) {
    final n = name.toUpperCase().replaceAll(' ', '');
    if (_looksLikeAccessory(name) || _looksLikeR6(name)) return false;
    return n.contains('TRAY') ||
        n.contains('UHF') ||
        n.contains('RFID') ||
        n.contains('R2000') ||
        n.contains('CHAINWAY') ||
        n.contains('IMINI') ||
        n.contains('RPAN') ||
        n.contains('R-PAN') ||
        n.contains('BLE') ||
        n.contains('READER');
  }

  Future<bool> _tryAttachTrayDevice(Map<String, String> device, PrefService prefs) async {
    final address = device['address'] ?? '';
    final name = device['name'] ?? 'Bluetooth Device';
    if (address.isEmpty) return false;
    await prefs.saveTrayDevice(name: name, address: address);
    await prefs.setTrayModeEnabled(true);
    await applyTrayMode(enabled: true, address: address);
    final ok = await waitForBleConnection(isR6: false, timeout: const Duration(seconds: 14));
    debugPrint('Tray attach $name ($address) connected=$ok');
    if (ok) {
      _trayConnected = true;
      _trayModeEnabled = true;
      _notifyConnectionListeners();
    }
    return ok;
  }

  Future<bool>? _autoAttachFuture;

  /// Use a Chainway tray/R6 that is already connected in Android Bluetooth
  /// settings. Does not open an in-app pair dialog and does not probe
  /// headphones or other bonded accessories.
  Future<bool> autoAttachSystemBluetoothReader() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    if (_trayConnected || _r6Connected) return true;
    _autoAttachFuture ??= _autoAttachSystemBluetoothReader();
    try {
      return await _autoAttachFuture!;
    } finally {
      // Keep the in-flight attach if tray/R6 mode was applied — re-running
      // probe used to call applyTrayMode(false) and drop GATT.
      if (!_trayConnected &&
          !_r6Connected &&
          !_trayModeEnabled &&
          !_r6ModeEnabled) {
        _autoAttachFuture = null;
      }
    }
  }

  Future<bool> _autoAttachSystemBluetoothReader() async {
    await ensureReady();
    if (!_isSupported) return false;

    final prefs = PrefService.instanceOrNull ?? await PrefService.init();
    if (_trayConnected || _r6Connected) return true;

    if (!await hasBluetoothPermissions()) {
      await requestBluetoothPermissions();
    }

    var connected = await listSystemConnectedBluetoothDevices();
    if (connected.isEmpty) {
      await requestBluetoothPermissions();
      connected = await listSystemConnectedBluetoothDevices();
    }

    bool osConnected(String mac) {
      final target = mac.trim().toUpperCase();
      if (target.isEmpty) return false;
      return connected.any((d) => (d['address'] ?? '').toUpperCase() == target);
    }

    if (prefs.isR6ModeEnabled()) {
      final address = prefs.getR6DeviceAddress().trim();
      if (address.isNotEmpty && osConnected(address)) {
        await restoreR6ModeFromPrefs(enabled: true, address: address);
        // Native startScanning completes GATT. Do not probe other devices.
        return _r6Connected || _r6ModeEnabled;
      }
    }

    final savedTray = prefs.getTrayDeviceAddress().trim();
    if (savedTray.isNotEmpty && osConnected(savedTray)) {
      await restoreTrayModeFromPrefs(enabled: true, address: savedTray);
      // Never applyTrayMode(false) after a saved address — that race made
      // inventory start only on some taps after Android Bluetooth connect.
      return _trayConnected || _trayModeEnabled;
    }

    Map<String, String>? chosen;
    var asR6 = false;
    for (final device in connected) {
      if (_looksLikeR6(device['name'] ?? '')) {
        chosen = device;
        asR6 = true;
        break;
      }
    }
    if (chosen == null) {
      for (final device in connected) {
        if (_looksLikeTray(device['name'] ?? '')) {
          chosen = device;
          break;
        }
      }
    }
    if (chosen == null) {
      final savedR6 = prefs.getR6DeviceAddress().trim().toUpperCase();
      for (final device in connected) {
        final address = (device['address'] ?? '').toUpperCase();
        if (address.isEmpty) continue;
        if (address == savedR6) {
          chosen = device;
          asR6 = true;
          break;
        }
        if (address == savedTray.toUpperCase() && savedTray.isNotEmpty) {
          chosen = device;
          break;
        }
      }
    }

    if (asR6 && chosen != null) {
      final address = chosen['address'] ?? '';
      final name = chosen['name'] ?? 'Bluetooth Device';
      if (address.isEmpty) return false;
      await prefs.saveR6Device(name: name, address: address);
      await prefs.setR6ModeEnabled(true);
      await applyR6Mode(enabled: true, address: address);
      final ok = await waitForBleConnection(isR6: true, timeout: const Duration(seconds: 12));
      debugPrint('R6 auto-attached from Android Bluetooth: $name ($address) connected=$ok');
      return ok;
    }

    if (chosen != null) {
      final ok = await _tryAttachTrayDevice(chosen, prefs);
      if (ok || _trayModeEnabled) return _trayConnected || _trayModeEnabled;
    }

    // Android Settings can show the tray as connected even when the name is
    // generic. Probe only currently linked non-accessory devices as tray.
    final candidates = connected
        .where((d) => !_looksLikeAccessory(d['name'] ?? ''))
        .where((d) => (d['address'] ?? '').isNotEmpty)
        .toList();
    for (final device in candidates.take(3)) {
      if (_looksLikeR6(device['name'] ?? '')) continue;
      final ok = await _tryAttachTrayDevice(device, prefs);
      if (ok) return true;
      final status = await getTrayStatus();
      if (status['connected'] == true || status['connecting'] == true) {
        return true;
      }
      await applyTrayMode(enabled: false);
    }
    return _trayConnected || _trayModeEnabled;
  }

  /// Auto-detect a Chainway tray reader that is already paired/connected at
  /// the Android system Bluetooth level, without requiring the user to first
  /// open in-app Settings and pick a device manually.
  Future<Map<String, String>?> tryAutoDiscoverTrayDevice({
    Duration perDeviceTimeout = const Duration(seconds: 6),
    int maxCandidates = 3,
  }) async {
    final attached = await autoAttachSystemBluetoothReader();
    if (!attached) return null;
    if (_r6Connected) {
      final prefs = PrefService.instanceOrNull ?? await PrefService.init();
      return {
        'name': prefs.getR6DeviceName(),
        'address': prefs.getR6DeviceAddress(),
      };
    }
    final prefs = PrefService.instanceOrNull ?? await PrefService.init();
    final address = prefs.getTrayDeviceAddress();
    if (address.isEmpty) return null;
    return {
      'name': prefs.getTrayDeviceName(),
      'address': address,
    };
  }

  Future<bool> applyTrayMode({
    required bool enabled,
    String address = '',
  }) async {
    await ensureReady();
    if (enabled && address.isNotEmpty && _isSupported) {
      try {
        final current = await getTrayStatus();
        final nativeAddr = current['address']?.toString().trim() ?? '';
        if (current['enabled'] == true &&
            nativeAddr.toLowerCase() == address.toLowerCase() &&
            (current['connected'] == true || current['connecting'] == true)) {
          _trayModeEnabled = true;
          _r6ModeEnabled = false;
          _r6Connected = false;
          _trayConnected = current['connected'] == true;
          _trayConnecting = current['connecting'] == true;
          if (_trayConnected) {
            _notifyConnectionListeners();
          }
          return true;
        }
      } catch (_) {}
    }
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
      _trayConnecting = status?['connecting'] == true;
      if (_trayConnected) {
        _trayConnecting = false;
        _notifyConnectionListeners();
      }
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
    await ensureReady();
    if (enabled && address.isNotEmpty && _isSupported) {
      try {
        final current = await getR6Status();
        final nativeAddr = current['address']?.toString().trim() ?? '';
        if (current['enabled'] == true &&
            nativeAddr.toLowerCase() == address.toLowerCase() &&
            (current['connected'] == true || current['connecting'] == true)) {
          _r6ModeEnabled = true;
          _trayModeEnabled = false;
          _trayConnected = false;
          _r6Connected = current['connected'] == true;
          _r6Connecting = current['connecting'] == true;
          if (_r6Connected) {
            _r6Connecting = false;
          }
          _notifyConnectionListeners();
          return true;
        }
      } catch (_) {}
    }
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
      _r6Connecting = status?['connecting'] == true;
      if (_r6Connected) {
        _r6Connecting = false;
      }
      _notifyConnectionListeners();
      return true;
    } catch (e) {
      debugPrint('Error applying R6 mode: $e');
      _r6Connected = false;
      _r6Connecting = false;
      return false;
    }
  }

  /// Poll native connection after setTrayMode / setR6Mode (BLE connect is async).
  Future<bool> waitForBleConnection({
    required bool isR6,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = isR6 ? await getR6Status() : await getTrayStatus();
      if (status['connected'] == true) {
        return true;
      }
      // Stay patient while GATT handshake is in flight (avoids cancelOpen loops).
      await Future<void>.delayed(
        status['connecting'] == true
            ? const Duration(milliseconds: 600)
            : const Duration(milliseconds: 400),
      );
    }
    return false;
  }

  Future<Map<String, dynamic>> getTrayStatus() async {
    if (!_isSupported) {
      return {
        'enabled': _trayModeEnabled,
        'connected': false,
        'connecting': false,
        'address': '',
      };
    }
    try {
      final status = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getTrayStatus');
      _trayConnected = status?['connected'] == true;
      _trayConnecting = status?['connecting'] == true;
      _trayModeEnabled = status?['enabled'] == true || _trayModeEnabled;
      return {
        'enabled': status?['enabled'] == true,
        'connected': status?['connected'] == true,
        'connecting': status?['connecting'] == true,
        'address': status?['address']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('Error reading tray status: $e');
      return {
        'enabled': _trayModeEnabled,
        'connected': _trayConnected,
        'connecting': false,
        'address': '',
      };
    }
  }

  Future<Map<String, dynamic>> getR6Status() async {
    if (!_isSupported) {
      return {
        'enabled': _r6ModeEnabled,
        'connected': false,
        'address': '',
        'connecting': false,
      };
    }
    try {
      final status = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getR6Status');
      _r6Connected = status?['connected'] == true;
      _r6Connecting = status?['connecting'] == true;
      if (_r6Connected) _r6Connecting = false;
      return {
        'enabled': status?['enabled'] == true,
        'connected': status?['connected'] == true,
        'address': status?['address']?.toString() ?? '',
        'connecting': status?['connecting'] == true,
      };
    } catch (e) {
      debugPrint('Error reading R6 status: $e');
      return {
        'enabled': _r6ModeEnabled,
        'connected': _r6Connected,
        'address': '',
        'connecting': false,
      };
    }
  }

  Future<List<Map<String, String>>> listBondedBluetoothDevices() async {
    await ensureReady();
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

  /// Ensures Chainway R6 BLE is connected using saved prefs address.
  /// Does not affect tray / UART gun paths.
  Future<bool> _ensureR6ReadyForScan() async {
    final prefs = await PrefService.init();
    final prefsR6 = prefs.isR6ModeEnabled();
    if (!prefsR6 && !_r6ModeEnabled) {
      return true; // R6 not in use
    }

    _r6ModeEnabled = true;
    _trayModeEnabled = false;

    var status = await getR6Status();
    if (status['connected'] == true) {
      _r6Connected = true;
      _r6Connecting = false;
      _notifyConnectionListeners();
      return true;
    }

    var address = status['address']?.toString().trim() ?? '';
    if (address.isEmpty) {
      address = prefs.getR6DeviceAddress().trim();
    }
    if (address.isEmpty) {
      debugPrint('R6 mode on but no device address saved');
      return false;
    }

    // Kick native connect once if idle. Native startScanning does the real
    // connectAndWait (with pre-scan retry).
    final alreadyEnabled = status['enabled'] == true;
    final nativeAddr = status['address']?.toString().trim() ?? '';
    final sameDevice = nativeAddr.toLowerCase() == address.toLowerCase();
    // Kick native connect only if mode is off or the MAC changed. A second
    // apply while GATT is opening drops the first link (intermittent scan).
    if (!alreadyEnabled || !sameDevice) {
      await applyR6Mode(enabled: true, address: address);
    }

    final ok = await waitForBleConnection(
      isR6: true,
      timeout: const Duration(seconds: 12),
    );
    _r6Connected = ok;
    if (ok) {
      _notifyConnectionListeners();
    } else {
      debugPrint('R6 BLE not ready yet for $address — native will connectAndWait');
    }
    // Return true so inventory still reaches native R6 connectAndWait path.
    return true;
  }

  /// Apply saved tray BLE mode before Scan Display inventory.
  /// Does not change R6 sled or UART handheld behavior.
  Future<void> _ensureTrayReadyForInventoryScan() async {
    final prefs = PrefService.instanceOrNull ?? await PrefService.init();
    if (prefs.isR6ModeEnabled() || _r6ModeEnabled) return;
    if (!prefs.isTrayModeEnabled() && !_trayModeEnabled) {
      await autoAttachSystemBluetoothReader();
    }
    if (prefs.isR6ModeEnabled() || _r6ModeEnabled) return;
    if (!prefs.isTrayModeEnabled() && !_trayModeEnabled) return;

    _trayModeEnabled = true;
    var status = await getTrayStatus();
    if (status['connected'] == true) {
      _trayConnected = true;
      _trayConnecting = false;
      return;
    }

    var address = status['address']?.toString().trim() ?? '';
    if (address.isEmpty) {
      address = prefs.getTrayDeviceAddress().trim();
    }
    if (address.isEmpty) {
      debugPrint('Tray mode on but no device address saved');
      return;
    }

    final alreadyEnabled = status['enabled'] == true;
    final nativeAddr = status['address']?.toString().trim() ?? '';
    final sameDevice = nativeAddr.toLowerCase() == address.toLowerCase();
    if (!alreadyEnabled || !sameDevice) {
      await applyTrayMode(enabled: true, address: address);
    }

    final ok = await waitForBleConnection(
      isR6: false,
      timeout: const Duration(seconds: 12),
    );
    _trayConnected = ok;
    if (ok) {
      _notifyConnectionListeners();
    } else {
      debugPrint('Tray BLE not ready yet for $address — native will connectAndWait');
    }
  }

  Future<bool> startScanning({
    int power = 5,
    List<String> simulatedScopeTags = const [],
    bool inventory = false,
    bool playStartSound = true,
    List<String>? searchTags,
  }) async {
    _power = power;
    await ensureReady();

    if (!_isSupported) {
      _isScanning = true;
      _simulatedTagsPool = List.from(simulatedScopeTags);
      _simulationIndex = 0;
      _startSimulation();
      return true;
    }

    try {
      // Mandate a brief cool-down delay before starting to ensure UHF UART settles down.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      if (_isScanning) {
        await stopScanning();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      await autoAttachSystemBluetoothReader();

      // BLE tray: native startScanning runs connectAndWait. Re-applying tray
      // mode here starts a second GATT open and makes scan start only sometimes.
      if (_trayModeEnabled) {
        final status = await getTrayStatus();
        if (status['connected'] != true && status['connecting'] == true) {
          await waitForBleConnection(isR6: false, timeout: const Duration(seconds: 8));
        }
      }

      // R6 sled: prefer connected, but always hand off to native startScanning
      // which performs connectAndWait / initialize (Dart wait alone is not enough).
      if (_r6ModeEnabled || (await PrefService.init()).isR6ModeEnabled()) {
        final r6Ok = await _ensureR6ReadyForScan();
        if (!r6Ok) {
          debugPrint('R6 not connected yet — native startScanning will retry BLE connect');
        }
      }

      // Large unmatched lists are preloaded on native. Re-sending 50k tags on
      // every Start blocked the channel and looked like a scanner failure.
      if (searchTags != null &&
          searchTags.isNotEmpty &&
          searchTags.length <= 2000) {
        await setSearchTags(searchTags);
      }
      await prepareForScan();
      await setInventoryScanMode(inventory);

      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
          await prepareForScan();
        }

        _isScanning = true;
        final started = await _methodChannel.invokeMethod<bool>('startScanning', {
              'power': power,
              'inventory': inventory,
              'playStartSound': playStartSound,
            }) ??
            false;
        if (started) {
          if (_r6ModeEnabled) {
            _r6Connected = true;
          }
          return true;
        }
        _isScanning = false;
      }
      return false;
    } catch (e) {
      debugPrint('Error starting native scan: $e');
      _isScanning = false;
      return false;
    }
  }

  /// Search / Unmatched Search — do not block UART behind tray/R6/tag-list work.
  Future<bool> startSearchScanning({
    required int power,
    List<String>? searchTags,
    List<String>? ledEpcs,
    String ledMode = 'epc',
  }) async {
    _power = power;
    await ensureReady();

    if (!_isSupported) {
      _isScanning = true;
      _simulatedTagsPool = List.from(searchTags ?? const <String>[]);
      _simulationIndex = 0;
      _startSimulation();
      return true;
    }

    try {
      if (_isScanning) {
        await stopScanning();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      await autoAttachSystemBluetoothReader();
      if (searchTags != null &&
          searchTags.isNotEmpty &&
          searchTags.length <= 2000) {
        await setSearchTags(searchTags);
      }
      await setSearchLedEpcs(ledEpcs ?? const <String>[]);
      await prepareForScan();
      await setInventoryScanMode(false);
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          try {
            await _methodChannel.invokeMethod<bool>('stopScanning');
          } catch (_) {}
          await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
          await prepareForScan();
        }
        _isScanning = true;
        final started = await _methodChannel.invokeMethod<bool>('startScanning', {
              'power': power,
              'inventory': false,
              'playStartSound': false,
              'ledMode': ledMode,
            }) ??
            false;
        if (started) return true;
        _isScanning = false;
      }
      return false;
    } catch (e) {
      debugPrint('Error starting search scan: $e');
      _isScanning = false;
      return false;
    }
  }

  /// Scan Display inventory start — minimal handoff (mirrors Sparkle).
  /// Avoids prefs/R6 probes, setPower UART race, and heavy Dart prep before start.
  Future<bool> startInventoryScanning({required int power}) async {
    _power = power;
    await ensureReady();

    if (!_isSupported) {
      _isScanning = true;
      _simulatedTagsPool = const [];
      _simulationIndex = 0;
      _startSimulation();
      return true;
    }

    try {
      if (_isScanning) {
        await stopScanning();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      // Apply BLE mode from Android Bluetooth / saved prefs so Scan Display
      // uses tray or R6 when that reader is already connected at OS level.
      await autoAttachSystemBluetoothReader();
      final prefs = PrefService.instanceOrNull ?? await PrefService.init();
      if (prefs.isR6ModeEnabled() || _r6ModeEnabled) {
        await _ensureR6ReadyForScan();
      } else {
        await _ensureTrayReadyForInventoryScan();
      }
      await _methodChannel.invokeMethod<bool>('prepareForScan');
      await setInventoryScanMode(true);
      await clearMatchEpcs();
      await clearInventoryScope();

      final attempts = (_trayModeEnabled || _r6ModeEnabled) ? 2 : 4;
      for (var attempt = 0; attempt < attempts; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
          await _methodChannel.invokeMethod<bool>('prepareForScan');
          await setInventoryScanMode(true);
        }
        final started = await _methodChannel.invokeMethod<bool>('startScanning', {
              'power': power,
              'inventory': true,
              'playStartSound': true,
            }) ??
            false;
        if (started) {
          _isScanning = true;
          if (_trayModeEnabled) {
            _trayConnected = true;
            _notifyConnectionListeners();
          } else if (_r6ModeEnabled) {
            _r6Connected = true;
            _r6Connecting = false;
            _notifyConnectionListeners();
          }
          return true;
        }
        try {
          await _methodChannel.invokeMethod<bool>('stopScanning');
        } catch (_) {}
        _isScanning = false;
      }
      return false;
    } catch (e) {
      debugPrint('Error startInventoryScanning: $e');
      _isScanning = false;
      return false;
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

  Future<bool> setSearchLedEpcs(List<String> tags) async {
    if (!_isSupported) return true;
    try {
      return await _methodChannel.invokeMethod<bool>(
            'setSearchLedEpcs',
            {'tags': tags},
          ) ??
          false;
    } catch (e) {
      debugPrint('Error setting search LED epcs: $e');
      return false;
    }
  }

  Future<bool> setSearchTags(List<String> tags) async {
    if (!_isSupported) return true;
    // Binder transactions fail above ~1MB — send large unmatched lists in chunks.
    const chunk = 1500;
    try {
      if (tags.length <= chunk) {
        return await _methodChannel.invokeMethod<bool>(
              'setSearchTags',
              {'tags': tags},
            ) ??
            false;
      }
      final firstEnd = chunk < tags.length ? chunk : tags.length;
      final firstOk = await _methodChannel.invokeMethod<bool>(
            'setSearchTags',
            {'tags': tags.sublist(0, firstEnd)},
          ) ??
          false;
      if (!firstOk) return false;
      for (var i = firstEnd; i < tags.length; i += chunk) {
        final end = (i + chunk < tags.length) ? i + chunk : tags.length;
        await _methodChannel.invokeMethod<bool>(
          'addSearchTags',
          {'tags': tags.sublist(i, end)},
        );
        if (i > 0 && (i - firstEnd) % (chunk * 4) == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      return true;
    } catch (e) {
      debugPrint('Error setting search tags: $e');
      return false;
    }
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
        // Permit scan only. Do not initReader here — an 8s timeout left UART
        // init running while startScanning raced it and failed.
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

  /// Sparkle RFIDReaderManager.playSound(id) — search RSSI buckets use 1–5.
  Future<void> playSound(int id, {int loop = 0}) async {
    if (!_isSupported) return;
    try {
      await _methodChannel.invokeMethod('playSound', {'id': id, 'loop': loop});
    } catch (e) {
      debugPrint('Error playSound: $e');
    }
  }

  Future<void> stopSound([int? id]) async {
    if (!_isSupported) return;
    try {
      await _methodChannel.invokeMethod('stopSound', id == null ? <String, dynamic>{} : {'id': id});
    } catch (e) {
      debugPrint('Error stopSound: $e');
    }
  }

  /// Scan Display: loop sound as soon as user taps Scan (before hardware is ready).
  Future<void> startInventorySound() async {
    if (!_isSupported) return;
    try {
      await _methodChannel.invokeMethod('startInventorySound');
    } catch (e) {
      debugPrint('Error starting inventory sound: $e');
    }
  }

  Future<void> stopInventorySound() async {
    if (!_isSupported) return;
    try {
      await _methodChannel.invokeMethod('stopInventorySound');
    } catch (e) {
      debugPrint('Error stopping inventory sound: $e');
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
      await _methodChannel
          .invokeMethod('initReader')
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (e) {
      debugPrint('preWarmReader: $e');
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
    await ensureReady();
    final prefs = await PrefService.init();
    // BLE readers filter in Dart; skip slow native scope upload.
    if (prefs.isTrayModeEnabled() || prefs.isR6ModeEnabled()) {
      await clearInventoryScope();
      return;
    }
    if (epcs.isEmpty) {
      await clearInventoryScope();
      return;
    }
    if (!_isSupported) return;

    const batchSize = 10000;
    try {
      if (epcs.length <= batchSize) {
        await _methodChannel.invokeMethod<bool>(
          'setInventoryScopeEpcs',
          {'epcs': epcs},
        );
        return;
      }
      await clearInventoryScope();
      for (var i = 0; i < epcs.length; i += batchSize) {
        final end = (i + batchSize < epcs.length) ? i + batchSize : epcs.length;
        final batch = epcs.sublist(i, end);
        if (i == 0) {
          await _methodChannel.invokeMethod<bool>(
            'setInventoryScopeEpcs',
            {'epcs': batch},
          );
        } else {
          await addInventoryScopeEpcs(batch);
        }
      }
    } catch (e) {
      debugPrint('Error setting inventory scope epcs: $e');
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
