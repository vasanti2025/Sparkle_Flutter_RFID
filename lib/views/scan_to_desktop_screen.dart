import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../services/rfid_service.dart';
import '../services/db_service.dart';
import '../services/pref_service.dart';
import '../services/api_service.dart';
import '../utils/tag_scan_batcher.dart';
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
  HttpServer? _server;

  String _shortDeviceId = '';
  bool _isLoading = false;
  bool _isSingleScan = false;
  bool _tagScannedInSession = false;
  Timer? _singleScanTimer;
  late final TagScanBatcher _tagBatcher;
  final List<DesktopTag> _pendingTags = [];
  Timer? _uiFlushTimer;

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
      flushInterval: const Duration(milliseconds: 150),
      onFlush: (tags) => _processTagBatch(tags),
    );
    _initDeviceAndServer();
    
    // Subscribe to RFID scanned tag events
    _tagsSubscription = _rfidService.tagsStream.listen((tag) {
      if (!_rfidService.isScanning && !_isScanning) return;
      _tagBatcher.add(tag);
      if (_isSingleScan) {
        _tagBatcher.flushNow();
      }
    });
    
    // Subscribe to gun key triggers
    _triggerSubscription = _rfidService.triggerStream.listen((_) {
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
    _rfidService.stopScanning();
    _stopWebServer();
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

    // Call addDeviceId update user API to associate this deviceId to user
    final employee = pref.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    if (clientCode.isNotEmpty) {
      await ApiService(pref).addDeviceId(clientCode, _shortDeviceId);
    }

    await _initIpAndServer();
    await _loadScannedDataFromServer();
  }

  Future<void> _loadScannedDataFromServer() async {
    final pref = context.read<PrefService>();
    final employee = pref.getEmployee();
    final clientCode = employee?.clientCode ?? '';
    if (clientCode.isEmpty || _shortDeviceId.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final api = ApiService(pref);
      final response = await api.getAllScantoDesktop(clientCode);
      if (response != null && response['success'] == true) {
        final rawList = response['data'] as List?;
        if (rawList != null) {
          final List<DesktopTag> loadedTags = [];
          for (var rawItem in rawList) {
            if (rawItem is Map<String, dynamic>) {
              final devId = rawItem['DeviceId']?.toString().trim() ?? '';
              if (devId.toLowerCase() == _shortDeviceId.toLowerCase()) {
                final epc = rawItem['TIDValue']?.toString() ?? '';
                final rfidCode = rawItem['RFIDCode']?.toString() ?? '';
                loadedTags.add(DesktopTag(epc: epc, rfidCode: rfidCode));
              }
            }
          }
          setState(() {
            _desktopScans.clear();
            _desktopScans.addAll(loadedTags);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading scanned data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _initIpAndServer() async {
    await _startWebServer();
  }

  Future<void> _startWebServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _server!.listen((HttpRequest request) {
        if (request.uri.path == '/rfid-data') {
          final employee = context.read<PrefService>().getEmployee();
          final clientCode = employee?.clientCode ?? '';

          final items = _desktopScans.map((tag) => {
            'EPC': tag.epc,
            'RFIDCode': tag.rfidCode,
          }).toList();
          
          final payload = {
            'ClientCode': clientCode,
            'DeviceId': _shortDeviceId,
            'Items': items,
          };
          
          request.response
            ..headers.contentType = ContentType.json
            ..headers.add('Access-Control-Allow-Origin', '*')
            ..write(json.encode(payload));
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write('<html><body><h2>RFID Local Server Running</h2><p>Endpoint: <b>/rfid-data</b></p></body></html>');
        }
        request.response.close();
      });
      debugPrint('Local HTTP server started on port 8080');
    } catch (e) {
      debugPrint('Failed to start HTTP server: $e');
    }
  }

  Future<void> _stopWebServer() async {
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

  Future<void> _processTagBatch(List<String> tags) async {
    if (tags.isEmpty || !mounted) return;

    if (_isSingleScan) {
      if (_tagScannedInSession) return;
      _tagScannedInSession = true;
    }

    final db = context.read<DbService>();
    final existing = _desktopScans.map((t) => t.epc).toSet();
    final toAdd = <DesktopTag>[];

    for (final raw in tags) {
      final epc = raw.trim().toUpperCase();
      if (epc.isEmpty || existing.contains(epc)) continue;

      String mappedRfid = '';
      if (epc.startsWith('E')) {
        try {
          mappedRfid = await db.lookupRfidForTid(epc);
        } catch (e) {
          debugPrint('Error querying tag mapping from local DB: $e');
        }
      } else {
        mappedRfid = hexToAscii(epc);
      }

      toAdd.add(DesktopTag(epc: epc, rfidCode: mappedRfid));
      existing.add(epc);
    }

    if (toAdd.isEmpty) {
      if (_isSingleScan) _stopScanning();
      return;
    }

    _pendingTags.addAll(toAdd);
    _scheduleUiFlush();

    if (_isSingleScan) {
      _stopScanning();
    }
  }

  void _scheduleUiFlush() {
    _uiFlushTimer ??= Timer(const Duration(milliseconds: 100), () {
      _uiFlushTimer = null;
      if (!mounted || _pendingTags.isEmpty) return;
      setState(() {
        _desktopScans.addAll(_pendingTags);
        _pendingTags.clear();
      });
    });
  }

  void _startSingleScan() async {
    _singleScanTimer?.cancel();
    if (_isScanning) {
      await _rfidService.stopScanning();
    }
    setState(() {
      _isScanning = true;
      _isSingleScan = true;
      _tagScannedInSession = false;
    });
    
    // Start scanning with power 20 (standard single scan power)
    await _rfidService.startScanning(power: 20);

    // Timeout single scan after 2 seconds
    _singleScanTimer = Timer(const Duration(seconds: 2), () {
      if (_isSingleScan && _isScanning) {
        _stopScanning();
      }
    });
  }

  void _startGScan() async {
    _singleScanTimer?.cancel();
    if (_isScanning) {
      await _rfidService.stopScanning();
    }
    setState(() {
      _isScanning = true;
      _isSingleScan = false;
    });
    await _rfidService.startScanning(power: _selectedPower);
  }

  void _stopScanning() async {
    _singleScanTimer?.cancel();
    if (!_isScanning) return;
    await _rfidService.stopScanning();
    setState(() {
      _isScanning = false;
      _isSingleScan = false;
    });
  }

  void _handleHardwareTrigger() {
    if (_isScanning) {
      _stopScanning();
    } else {
      _startGScan();
    }
  }

  Future<void> _saveScansToServer() async {
    final pref = context.read<PrefService>();
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
        await _loadScannedDataFromServer();
      } else {
        _showToast(context.sRead.failedToSaveItemsToServer);
      }
    } catch (e) {
      _showToast(context.sRead.errorSavingData('$e'));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showClearConfirmationDialog() {
    showDialog(
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
        });
      } else {
        _showToast(context.sRead.failedToClearServerStock);
      }
    } catch (e) {
      _showToast(context.sRead.errorClearingData('$e'));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  void _resetScanning() {
    _stopScanning();
    setState(() {
      _desktopScans.clear();
    });
    _showToast(context.sRead.scanResetSuccessful);
  }

  void _showManualRfidDialog(int index) {
    final tag = _desktopScans[index];
    final s = context.sRead;
    final controller = TextEditingController(text: tag.rfidCode == s.scanHere ? '' : tag.rfidCode);
    
    showDialog(
      context: context,
      builder: (context) {
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
                'EPC: ${tag.epc}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: s.fieldRfidCode,
                  border: const OutlineInputBorder(),
                ),
                style: GoogleFonts.poppins(fontSize: 14),
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
                setState(() {
                  tag.rfidCode = controller.text.trim();
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5231A7)),
              child: Text(s.assign, style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        duration: const Duration(seconds: 2),
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
                    : ListView.builder(
                        itemCount: _desktopScans.length,
                        itemBuilder: (context, index) {
                          final tag = _desktopScans[index];
                          final isBlank = tag.rfidCode.trim().isEmpty;
                          final displayText = isBlank ? s.scanHere : tag.rfidCode;
                          
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${index + 1}',
                                    style: GoogleFonts.poppins(fontSize: 11),
                                  ),
                                ),
                                Expanded(
                                  flex: 8,
                                  child: Text(
                                    tag.epc,
                                    style: GoogleFonts.poppins(fontSize: 11),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: GestureDetector(
                                    onTap: () => _showManualRfidDialog(index),
                                    child: Text(
                                      displayText,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: isBlank ? Colors.blue : Colors.black87,
                                        decoration: isBlank ? TextDecoration.underline : TextDecoration.none,
                                        fontWeight: isBlank ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                onScan: () {
                  if (_isScanning && _isSingleScan) {
                    _stopScanning();
                  } else {
                    _startSingleScan();
                  }
                },
                onGscan: () {
                  if (_isScanning && !_isSingleScan) {
                    _stopScanning();
                  } else {
                    _startGScan();
                  }
                },
                onReset: _resetScanning,
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
