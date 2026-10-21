import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../services/rfid_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../services/api_service.dart';
import '../utils/tag_scan_batcher.dart';
import '../utils/app_dropdown.dart';
import '../utils/app_dialogs.dart';
import '../utils/barcode_scan_mixin.dart';
import '../utils/user_facing_error.dart';
import 'widgets/scan_bottom_bar.dart';

class DesktopTag {
  final String epc;
  String rfidCode;
  DesktopTag({required this.epc, required this.rfidCode});
}

class ScanToDesktopScreen extends StatefulWidget {
  const ScanToDesktopScreen({super.key});

  @override
  State<ScanToDesktopScreen> createState() => _ScanToDesktopScreenState();
}

class _ScanToDesktopScreenState extends State<ScanToDesktopScreen> {
  final RfidService _rfidService = RfidService();
  StreamSubscription? _tagsSubscription;
  StreamSubscription? _triggerSubscription;

  bool _isScanning = false;
  int _selectedPower = 5;

  final List<DesktopTag> _desktopScans = [];
  final Set<String> _seenEpcs = {};
  HttpServer? _server;
  final Set<WebSocket> _desktopSockets = {};
  Timer? _serverRetry;
  bool _closingServer = false;
  /// Full scan JSON for HTTP /rfid-data. Local WiFi Mode also pushes this live over WebSocket.
  String _localWifiJson = '{}';

  String _shortDeviceId = '';
  bool _isLoading = false;
  bool _isSingleScan = false;
  bool _tagScannedInSession = false;
  bool _scanBusy = false;
  int _scanGeneration = 0;
  int _lastTriggerMs = 0;
  Timer? _singleScanTimer;
  late final TagScanBatcher _tagBatcher;
  final List<DesktopTag> _pendingTags = [];
  Timer? _uiFlushTimer;
  bool _assignRfidDialogOpen = false;

  String shortSerial(String? serial) {
    if (serial == null || serial.isEmpty) return 'A';
    if (serial.length < 2) return 'A$serial';
    final lastTwo = serial.substring(serial.length - 2);
    return 'A$lastTwo';
  }

  String formatCurrentDateTime() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final sec = now.second.toString().padLeft(2, '0');
    return "$y-$m-${d}T$h:$min:$sec";
  }

  @override
  void initState() {
    super.initState();
    _selectedPower = context.read<PrefService>().productPower;
    _tagBatcher = TagScanBatcher(
      flushInterval: const Duration(milliseconds: 120),
      onFlush: (tags) => _processTagBatch(tags),
    );
    _initDeviceAndServer();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_rfidService.isScanning) {
        await _stopScanning();
      }
    });
    
    // Subscribe to RFID scanned tag events
    _tagsSubscription = _rfidService.tagsStream.listen((tag) {
      if (!_rfidService.isScanning && !_isScanning) return;
      _tagBatcher.add(tag);
      if (_isSingleScan) _tagBatcher.flushNow();
    });
    
    // Subscribe to gun key triggers
    _triggerSubscription = _rfidService.triggerStream.listen((_) {
      if (!mounted || _scanBusy || _assignRfidDialogOpen) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastTriggerMs < 300) return;
      _lastTriggerMs = now;
      _handleHardwareTrigger();
    });
  }

  @override
  void dispose() {
    _tagsSubscription?.cancel();
    _triggerSubscription?.cancel();
    _singleScanTimer?.cancel();
    _uiFlushTimer?.cancel();
    _tagBatcher.dispose();
    _closingServer = true;
    _serverRetry?.cancel();
    unawaited(_stopScanning());
    unawaited(_stopWebServer());
    super.dispose();
  }

  Future<void> _initDeviceAndServer() async {
    final pref = context.read<PrefService>();
    String devId = pref.getDeviceId();
    if (devId.isEmpty) {
      final rand = Random.secure();
      final values = List<int>.generate(16, (i) => rand.nextInt(256));
      devId = values.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
      await pref.saveDeviceId(devId);
    }
    debugPrint('Stable Device ID: $devId');
    _shortDeviceId = shortSerial(devId);

    // Local server first so Scan and Local WiFi Save work even when the API is slow or offline.
    await _initIpAndServer();
    if (!mounted) return;

    final employee = pref.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    if (clientCode.isEmpty) return;
    unawaited(ApiService(pref).addDeviceId(clientCode, _shortDeviceId));
    if (!pref.isLocalWifiModeEnabled()) {
      unawaited(_loadScannedDataFromServer());
    }
  }

  Future<void> _loadScannedDataFromServer() async {
    final pref = context.read<PrefService>();
    final employee = pref.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    if (clientCode.isEmpty || _shortDeviceId.isEmpty || !mounted) return;

    try {
      final api = ApiService(pref);
      final response = await api.getAllScantoDesktop(clientCode);
      if (!mounted || response == null || response['success'] != true) return;
      final rawList = response['data'] as List?;
      if (rawList == null) return;
      var added = false;
      for (final rawItem in rawList) {
        if (rawItem is! Map) continue;
        final devId = rawItem['DeviceId']?.toString().trim() ?? '';
        if (devId.toLowerCase() != _shortDeviceId.toLowerCase()) continue;
        final epc = (rawItem['TIDValue']?.toString() ?? '').trim().toUpperCase();
        if (epc.isEmpty || !_seenEpcs.add(epc)) continue;
        _desktopScans.add(DesktopTag(
          epc: epc,
          rfidCode: rawItem['RFIDCode']?.toString() ?? '',
        ));
        added = true;
      }
      if (added && mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading scanned data: $e');
    }
  }

  Future<void> _initIpAndServer() async {
    await _startWebServer();
  }

  Future<void> _startWebServer() async {
    if (_closingServer || _server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080, shared: true);
      _server!.listen(
        _onLocalRequest,
        onError: (Object e) {
          debugPrint('Local HTTP server error: $e');
        },
        onDone: () {
          _server = null;
          if (!_closingServer) _scheduleServerRestart();
        },
      );
      debugPrint('Local HTTP server started on port 8080');
    } catch (e) {
      debugPrint('Failed to start HTTP server: $e');
      _server = null;
      if (!_closingServer) _scheduleServerRestart();
    }
  }

  void _scheduleServerRestart() {
    if (_closingServer) return;
    _serverRetry?.cancel();
    _serverRetry = Timer(const Duration(seconds: 2), () {
      if (!_closingServer) unawaited(_startWebServer());
    });
  }

  Future<void> _onLocalRequest(HttpRequest request) async {
    try {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await _acceptDesktopSocket(request);
        return;
      }
      if (request.uri.path == '/rfid-data') {
        request.response
          ..headers.contentType = ContentType.json
          ..headers.add('Access-Control-Allow-Origin', '*')
          ..write(_localWifiJson);
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<html><body><h2>RFID Local Server Running</h2>'
            '<p>HTTP: <b>/rfid-data</b></p>'
            '<p>WebSocket: <b>/rfid-ws</b></p></body></html>',
          );
      }
      await request.response.close();
    } catch (e) {
      debugPrint('Local HTTP request failed: $e');
    }
  }

  Future<void> _acceptDesktopSocket(HttpRequest request) async {
    final path = request.uri.path;
    if (path != '/rfid-ws' && path != '/rfid-data') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _desktopSockets.add(socket);
    if (_localWifiLive()) {
      _sendSocket(socket, _syncMessage());
    }
    socket.listen(
      (_) {},
      onDone: () => _desktopSockets.remove(socket),
      onError: (Object e) {
        _desktopSockets.remove(socket);
        debugPrint('Desktop WebSocket closed: $e');
      },
      cancelOnError: true,
    );
  }

  void _sendSocket(WebSocket socket, String message) {
    try {
      socket.add(message);
    } catch (e) {
      _desktopSockets.remove(socket);
      debugPrint('Desktop WebSocket send failed: $e');
    }
  }

  void _broadcast(String message) {
    final stale = <WebSocket>[];
    for (final socket in _desktopSockets) {
      try {
        socket.add(message);
      } catch (_) {
        stale.add(socket);
      }
    }
    _desktopSockets.removeAll(stale);
  }

  bool _localWifiLive() {
    if (!mounted) return false;
    return context.read<PrefService>().isLocalWifiModeEnabled();
  }

  Map<String, dynamic> _wifiEnvelope(String type, List<Map<String, String>> items) {
    final clientCode = mounted
        ? (context.read<PrefService>().getEmployee()?.clientCode ?? '')
        : '';
    return {
      'type': type,
      'ClientCode': clientCode,
      'DeviceId': _shortDeviceId,
      'Items': items,
    };
  }

  List<Map<String, String>> _tagPayload(Iterable<DesktopTag> tags) {
    final items = <Map<String, String>>[];
    for (final tag in tags) {
      final epc = tag.epc
          .trim()
          .toUpperCase()
          .replaceAll(' ', '')
          .replaceAll('\n', '')
          .replaceAll('\r', '');
      final rfid = tag.rfidCode.trim();
      if (epc.isEmpty || rfid.toLowerCase() == 'scan here') continue;
      items.add({'EPC': epc, 'RFIDCode': rfid});
    }
    return items;
  }

  String _syncMessage() {
    final envelope = _wifiEnvelope('sync', _tagPayload(_desktopScans));
    _localWifiJson = json.encode({
      'ClientCode': envelope['ClientCode'],
      'DeviceId': envelope['DeviceId'],
      'Items': envelope['Items'],
    });
    return json.encode(envelope);
  }

  void _pushLiveTags(List<DesktopTag> tags) {
    if (!_localWifiLive() || tags.isEmpty) return;
    final items = _tagPayload(tags);
    if (items.isEmpty) return;
    _syncMessage();
    _broadcast(json.encode(_wifiEnvelope('tags', items)));
  }

  void _pushLiveSync() {
    if (!_localWifiLive()) return;
    _broadcast(_syncMessage());
  }

  Future<void> _stopWebServer() async {
    _serverRetry?.cancel();
    _serverRetry = null;
    for (final socket in _desktopSockets.toList()) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _desktopSockets.clear();
    await _server?.close(force: true);
    _server = null;
  }

  String hexToAscii(String hex) {
    final cleanHex = hex.replaceAll(' ', '').toUpperCase();
    if (cleanHex.length % 2 != 0) return '';
    try {
      final buffer = StringBuffer();
      for (int i = 0; i < cleanHex.length; i += 2) {
        final str = cleanHex.substring(i, i + 2);
        final code = int.parse(str, radix: 16);
        buffer.write(String.fromCharCode(code));
      }
      return buffer.toString().replaceAll('\u0000', '').trim();
    } catch (_) {
      return '';
    }
  }

  void _processTagBatch(List<String> tags) {
    if (tags.isEmpty || !mounted) return;

    if (_isSingleScan && _tagScannedInSession) return;

    final db = context.read<DbService>();
    final toAdd = <DesktopTag>[];

    for (final raw in tags) {
      final epc = raw.trim().toUpperCase();
      if (epc.isEmpty || !_seenEpcs.add(epc)) continue;

      String mappedRfid = '';
      if (epc.startsWith('E')) {
        mappedRfid = db.findBulkItemByScanKeySync(epc)?.rfid ?? '';
      } else {
        mappedRfid = hexToAscii(epc);
      }

      toAdd.add(DesktopTag(epc: epc, rfidCode: mappedRfid));
      if (_isSingleScan) break;
    }

    if (toAdd.isEmpty) {
      if (_isSingleScan) unawaited(_stopScanning());
      return;
    }

    if (_isSingleScan) _tagScannedInSession = true;

    _pendingTags.addAll(toAdd);
    _flushPendingTagsNow();

    if (_isSingleScan) {
      unawaited(_stopScanning());
    }

    unawaited(_fillRfidCodes(toAdd));
  }

  Future<void> _fillRfidCodes(List<DesktopTag> tags) async {
    if (!mounted) return;
    final db = context.read<DbService>();
    var changed = false;
    for (final tag in tags) {
      if (tag.rfidCode.trim().isNotEmpty) continue;
      if (!tag.epc.startsWith('E')) continue;
      try {
        final rfid = await db.lookupRfidForTid(tag.epc);
        if (rfid.isNotEmpty && tag.rfidCode.trim().isEmpty) {
          tag.rfidCode = rfid;
          changed = true;
        }
      } catch (e) {
        debugPrint('Error querying tag mapping from local DB: $e');
      }
    }
    if (changed && mounted) {
      setState(() {});
      _pushLiveTags(tags);
    }
  }

  void _flushPendingTagsNow() {
    _uiFlushTimer?.cancel();
    _uiFlushTimer = null;
    if (!mounted || _pendingTags.isEmpty) return;
    final added = List<DesktopTag>.from(_pendingTags);
    setState(() {
      _desktopScans.addAll(_pendingTags);
      _pendingTags.clear();
    });
    _pushLiveTags(added);
  }

  Future<void> _startSingleScan() async {
    if (_scanBusy) return;

    if (_isScanning && _isSingleScan) {
      await _stopScanning();
      return;
    }

    _scanBusy = true;
    _singleScanTimer?.cancel();
    final gen = ++_scanGeneration;
    if (mounted) {
      setState(() {
        _isScanning = true;
        _isSingleScan = true;
        _tagScannedInSession = false;
      });
    }

    try {
      // Same UART start as Inventory. startScanning waits on a Bluetooth
      // tray probe (about 30s) and then uses the slower search radio.
      final started = await _rfidService.startInventoryScanning(
        power: _selectedPower,
        skipBleProbe: true,
      );
      if (gen != _scanGeneration) {
        if (started) {
          await _rfidService.stopScanning();
          await _rfidService.stopInventorySound();
          await _rfidService.haltScan();
        }
        return;
      }

      if (!started && mounted) {
        setState(() {
          _isScanning = false;
          _isSingleScan = false;
        });
        return;
      }

      _singleScanTimer = Timer(const Duration(seconds: 2), () {
        if (_isSingleScan && _isScanning) {
          unawaited(_stopScanning());
        }
      });
    } finally {
      _scanBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startGScan() async {
    if (_scanBusy) return;

    if (_isScanning && !_isSingleScan) {
      await _stopScanning();
      return;
    }

    _scanBusy = true;
    _singleScanTimer?.cancel();
    final gen = ++_scanGeneration;
    if (mounted) {
      setState(() {
        _isScanning = true;
        _isSingleScan = false;
      });
    }

    try {
      final started = await _rfidService.startInventoryScanning(
        power: _selectedPower,
        skipBleProbe: true,
      );
      if (gen != _scanGeneration) {
        if (started) {
          await _rfidService.stopScanning();
          await _rfidService.stopInventorySound();
          await _rfidService.haltScan();
        }
        return;
      }

      if (!started && mounted) {
        setState(() => _isScanning = false);
      }
    } finally {
      _scanBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopScanning() async {
    _scanGeneration++;
    _singleScanTimer?.cancel();
    _tagBatcher.flushNow();
    _flushPendingTagsNow();
    if (!_isScanning && !_rfidService.isScanning) {
      await _rfidService.stopInventorySound();
      await _rfidService.haltScan();
      return;
    }
    if (mounted) {
      setState(() {
        _isScanning = false;
        _isSingleScan = false;
      });
    }
    await _rfidService.stopScanning();
    await _rfidService.stopInventorySound();
    await _rfidService.haltScan();
    _tagBatcher.flushNow();
    _flushPendingTagsNow();
  }

  void _handleHardwareTrigger() {
    if (_isScanning) {
      unawaited(_stopScanning());
    } else {
      unawaited(_startGScan());
    }
  }

  bool _usableIp(String? ip) {
    if (ip == null) return false;
    final value = ip.trim();
    return value.isNotEmpty && value != '0.0.0.0' && !value.startsWith('127.');
  }

  Future<String> _deviceWifiIp() async {
    try {
      final wifiIp = await NetworkInfo().getWifiIP();
      if (_usableIp(wifiIp)) return wifiIp!.trim();
    } catch (_) {}
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (!name.contains('wlan') && !name.contains('ap')) continue;
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && _usableIp(addr.address)) {
            return addr.address;
          }
        }
      }
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && _usableIp(addr.address)) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '';
  }

  List<Map<String, String>> _localWifiItems() {
    final items = <Map<String, String>>[];
    for (final tag in _desktopScans) {
      final epc = tag.epc.trim().toUpperCase().replaceAll(' ', '').replaceAll('\n', '').replaceAll('\r', '');
      final rfid = tag.rfidCode.trim();
      if (epc.isEmpty || rfid.isEmpty || rfid.toLowerCase() == 'scan here') continue;
      items.add({'EPC': epc, 'RFIDCode': rfid});
    }
    return items;
  }

  // Local WiFi Mode: the gun hosts the scan. Desktop opens http://DEVICE_IP:8080/rfid-data.
  Future<void> _saveScansToLocalWifi(PrefService pref) async {
    final employee = pref.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    if (clientCode.isEmpty || _shortDeviceId.isEmpty) {
      _showToast(context.sRead.deviceConfigNotFound);
      return;
    }

    final items = _localWifiItems();
    if (items.isEmpty) {
      _showToast(context.sRead.pleaseScanValidRfid);
      return;
    }

    if (_server == null) {
      await _startWebServer();
    }
    _localWifiJson = json.encode({
      'ClientCode': clientCode,
      'DeviceId': _shortDeviceId,
      'Items': items,
    });
    _broadcast(json.encode({
      'type': 'sync',
      'ClientCode': clientCode,
      'DeviceId': _shortDeviceId,
      'Items': items,
    }));

    final ip = await _deviceWifiIp();
    if (!mounted) return;
    if (ip.isEmpty) {
      _showToast(context.sRead.deviceIpNotFoundSameWifi);
      return;
    }

    final desktopUrl = 'http://$ip:8080/rfid-data';
    debugPrint('LOCAL_SERVER Open this URL on desktop: $desktopUrl');
    _showToast(
      context.sRead.localModeOpenOnDesktop(desktopUrl),
      duration: const Duration(seconds: 6),
    );
  }

  Future<void> _saveScansToServer() async {
    final pref = context.read<PrefService>();
    if (pref.isLocalWifiModeEnabled()) {
      await _saveScansToLocalWifi(pref);
      return;
    }
    final employee = pref.getEmployee();
    final clientCode = employee?.clientCode ?? '';

    if (clientCode.isEmpty || _shortDeviceId.isEmpty) {
      _showToast(context.sRead.deviceConfigNotFound);
      return;
    }

    final nowStr = formatCurrentDateTime();
    final List<Map<String, dynamic>> payload = [];

    for (var tag in _desktopScans) {
      final epc = tag.epc.trim();
      final rfid = tag.rfidCode.trim();
      if (epc.isNotEmpty && rfid.isNotEmpty && rfid.toLowerCase() != 'scan here') {
        payload.add({
          'Id': 0,
          'CreatedOn': nowStr,
          'LastUpdated': nowStr,
          'StatusType': true,
          'ClientCode': clientCode,
          'DeviceId': _shortDeviceId,
          'TIDValue': epc,
          'RFIDCode': rfid,
        });
      }
    }

    if (payload.isEmpty) {
      _showToast(context.sRead.pleaseScanValidRfid);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final api = ApiService(pref);
      final success = await api.addRFIDScannedData(payload);
      if (success) {
        _showToast(context.sRead.itemsSavedSuccessfully);
        _uiFlushTimer?.cancel();
        _uiFlushTimer = null;
        _pendingTags.clear();
        if (mounted) {
          setState(() {
            _desktopScans.clear();
            _seenEpcs.clear();
          });
        }
      } else {
        _showToast(context.sRead.failedToSaveItemsToServer);
      }
    } catch (e) {
      _showToast(UserFacingError.isNetwork(e)
          ? context.sRead.noInternetConnection
          : context.sRead.errorSavingData(UserFacingError.of(e)));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showClearConfirmationDialog() {
    showAppDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.s.confirm,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          context.s.tr('clearServerStockConfirm'),
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.s.cancel, style: GoogleFonts.poppins(color: Colors.grey[600])),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearScansFromServer();
            },
            child: Text(context.s.ok, style: GoogleFonts.poppins(color: const Color(0xFF5231A7), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearScansFromServer() async {
    final pref = context.read<PrefService>();
    final employee = pref.getEmployee();
    final clientCode = employee?.clientCode ?? '';

    if (clientCode.isEmpty || _shortDeviceId.isEmpty) {
      _showToast(context.sRead.deviceConfigNotFound);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final api = ApiService(pref);
      final response = await api.clearStockData(clientCode, _shortDeviceId);
      if (response != null && response['success'] == true) {
        final deletedRecords = response['deletedRecords'] ?? 0;
        _showToast(context.sRead.recordsDeletedSuccess(deletedRecords));
        setState(() {
          _desktopScans.clear();
          _seenEpcs.clear();
        });
        _pushLiveSync();
      } else {
        _showToast(context.sRead.failedToClearServerStock);
      }
    } catch (e) {
      _showToast(UserFacingError.isNetwork(e)
          ? context.sRead.noInternetConnection
          : context.sRead.errorClearingData(UserFacingError.of(e)));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  Future<void> _resetScanning() async {
    if (_scanBusy) return;
    _scanBusy = true;
    if (mounted) setState(() {});
    try {
      await _stopScanning();
      _tagBatcher.flushNow();
      _pendingTags.clear();
      _uiFlushTimer?.cancel();
      _uiFlushTimer = null;
      if (mounted) {
        setState(() {
          _desktopScans.clear();
          _seenEpcs.clear();
        });
        _pushLiveSync();
        _showToast(context.sRead.scanResetSuccessful);
      }
    } finally {
      _scanBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _showManualRfidDialog(int index) async {
    final tag = _desktopScans[index];
    final s = context.sRead;
    final initialRfid = tag.rfidCode == s.scanHere ? '' : tag.rfidCode;

    await _stopScanning();
    _assignRfidDialogOpen = true;
    await showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AssignRfidCodeDialog(
        epc: tag.epc,
        initialRfid: initialRfid,
        onAssign: (rfid) {
          setState(() {
            tag.rfidCode = rfid.trim();
          });
          _pushLiveTags([tag]);
        },
      ),
    );
    _assignRfidDialogOpen = false;
  }

  void _showToast(String message, {Duration duration = const Duration(seconds: 2)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        duration: duration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

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
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              s.scanToDesktop,
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            actions: [
              Center(
                child: PopupMenuButton<int>(
                  offset: const Offset(0, 45),
                  constraints: const BoxConstraints(maxHeight: kDropdownMenuMaxHeight, minWidth: 60),
                  onSelected: (int val) {
                    setState(() => _selectedPower = val);
                    _rfidService.setPower(val);
                    context.read<PrefService>().savePower(PrefService.keyProductCount, val);
                  },
                  itemBuilder: (context) {
                    return List.generate(30, (index) => index + 1).map((val) {
                      return PopupMenuItem<int>(
                        value: val,
                        child: Text(
                          '$val',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                        ),
                      );
                    }).toList();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$_selectedPower',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFD32940),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Table Header
              Container(
                color: const Color(0xFF3B363E),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        s.headerSr,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 8,
                      child: Text(
                        s.colEpc,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        s.colRfid,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // Tag List
              Expanded(
                child: _desktopScans.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.desktop_windows, size: 50, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              s.noTagsScannedYet,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final rowStyle = GoogleFonts.poppins(fontSize: 11);
                          final blankStyle = GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w600,
                          );
                          final filledStyle = GoogleFonts.poppins(fontSize: 11, color: Colors.black87);
                          return ListView.builder(
                            itemCount: _desktopScans.length,
                            addAutomaticKeepAlives: false,
                            itemBuilder: (context, index) {
                              final tag = _desktopScans[index];
                              final isBlank = tag.rfidCode.trim().isEmpty;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text('${index + 1}', style: rowStyle),
                                    ),
                                    Expanded(
                                      flex: 8,
                                      child: Text(tag.epc, style: rowStyle),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: GestureDetector(
                                        onTap: () => _showManualRfidDialog(index),
                                        child: Text(
                                          isBlank ? s.scanHere : tag.rfidCode,
                                          style: isBlank ? blankStyle : filledStyle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),

              // Total count row
              Container(
                color: Colors.grey[100],
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                alignment: Alignment.centerLeft,
                child: Text(
                  s.totalScannedCount(_desktopScans.length),
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                ),
              ),

              // Bottom Bar
              ScanBottomBarDesktop(
                onSave: _saveScansToServer,
                onClear: _showClearConfirmationDialog,
                onScan: () => unawaited(_startSingleScan()),
                onGscan: () => unawaited(_startGScan()),
                onReset: () => unawaited(_resetScanning()),
                isScanning: _isScanning && _isSingleScan,
                isBulkScanning: _isScanning && !_isSingleScan,
              ),
            ],
          ),
          if (_isLoading)
            const Positioned.fill(
              child: ModalBarrier(
                color: Colors.black26,
                dismissible: false,
              ),
            ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF5231A7),
              ),
            ),
        ],
      ),
    );
  }
}

class _AssignRfidCodeDialog extends StatefulWidget {
  final String epc;
  final String initialRfid;
  final ValueChanged<String> onAssign;

  const _AssignRfidCodeDialog({
    required this.epc,
    required this.initialRfid,
    required this.onAssign,
  });

  @override
  State<_AssignRfidCodeDialog> createState() => _AssignRfidCodeDialogState();
}

class _AssignRfidCodeDialogState extends State<_AssignRfidCodeDialog> with BarcodeScanMixin {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<void>? _barcodeTriggerSub;
  StreamSubscription<void>? _uhfTriggerSub;
  bool _barcodeScanActive = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialRfid);
    bindBarcodeScanner();
    _barcodeTriggerSub = barcodeRfid.barcodeTriggerStream.listen((_) {
      if (!mounted) return;
      setState(() => _barcodeScanActive = true);
    });
    _uhfTriggerSub = barcodeRfid.triggerStream.listen((_) {
      if (!mounted) return;
      unawaited(_startBarcodeScan(fromHardwareKey: true));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      unawaited(_startBarcodeScan());
    });
  }

  Future<void> _startBarcodeScan({bool fromHardwareKey = false}) async {
    if (!mounted) return;
    setState(() => _barcodeScanActive = true);
    _focusNode.requestFocus();
    if (!fromHardwareKey) {
      await barcodeRfid.startBarcodeScan();
    }
  }

  @override
  void onBarcodeScanned(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _controller.text = trimmed.toUpperCase();
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      _barcodeScanActive = false;
    });
    unawaited(barcodeRfid.stopBarcodeScan());
  }

  @override
  void dispose() {
    _barcodeTriggerSub?.cancel();
    _uhfTriggerSub?.cancel();
    unbindBarcodeScanner();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        s.assignRfidCode,
        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EPC: ${widget.epc}',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              labelText: s.fieldRfidCode,
              border: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _barcodeScanActive ? const Color(0xFF5231A7) : Colors.grey,
                  width: _barcodeScanActive ? 1.5 : 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _barcodeScanActive ? const Color(0xFF5231A7) : Colors.grey,
                  width: _barcodeScanActive ? 1.5 : 1,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5231A7), width: 1.5),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  Icons.qr_code_scanner,
                  color: _barcodeScanActive ? const Color(0xFF5231A7) : Colors.grey,
                ),
                onPressed: () => unawaited(_startBarcodeScan()),
              ),
            ),
            style: GoogleFonts.poppins(fontSize: 14),
            textCapitalization: TextCapitalization.characters,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel, style: GoogleFonts.poppins(color: Colors.grey[600])),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onAssign(_controller.text.trim().toUpperCase());
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5231A7)),
          child: Text(s.assign, style: GoogleFonts.poppins(color: Colors.white)),
        ),
      ],
    );
  }
}
