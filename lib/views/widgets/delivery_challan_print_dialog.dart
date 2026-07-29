import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';
import '../../models/delivery_challan.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../services/pref_service.dart';
import '../../utils/bluetooth_permission_util.dart';
import 'delivery_challan_pdf.dart';

/// Same print options as Sparkle Delivery Challan list: View PDF | Bluetooth Printer.
Future<void> showDeliveryChallanPrintOptions({
  required BuildContext context,
  required DeliveryChallanModel challan,
}) async {
  final prefs = await PrefService.init();
  final orgName = prefs.getOrganisationName() ?? '';
  final clientCode = prefs.getEmployee()?.clientCode ?? challan.clientCode;
  String companyName = orgName;
  if (clientCode.isNotEmpty && clientCode.toLowerCase() != 'ls000053') {
    try {
      final api = ApiService(prefs);
      final apiName = await api.getCompanyName(clientCode);
      if (apiName != null && apiName.isNotEmpty) companyName = apiName;
    } catch (_) {}
  }
  if (!context.mounted) return;

  await showAppDialog<void>(
    context: context,
    builder: (ctx) => _DeliveryChallanPrintDialog(
      challan: challan,
      orgName: orgName,
      companyName: companyName,
    ),
  );
}

class _DeliveryChallanPrintDialog extends StatefulWidget {
  final DeliveryChallanModel challan;
  final String orgName;
  final String companyName;

  const _DeliveryChallanPrintDialog({
    required this.challan,
    required this.orgName,
    required this.companyName,
  });

  @override
  State<_DeliveryChallanPrintDialog> createState() => _DeliveryChallanPrintDialogState();
}

class _DeliveryChallanPrintDialogState extends State<_DeliveryChallanPrintDialog> {
  final _printer = BluetoothPrinterService();
  bool _showBluetooth = false;
  bool _loadingDevices = false;
  bool _connecting = false;
  bool _printing = false;
  bool _printerConnected = false;
  String _status = 'Not connected';
  List<Map<String, String>> _devices = [];

  Future<void> _onConnectBluetoothTap() async {
    final s = context.sRead;
    setState(() {
      _loadingDevices = true;
      _status = s.connectingBluetooth;
      _devices = [];
      _printerConnected = false;
    });

    try {
      final granted = await requestBluetoothPermissions();
      if (!mounted) return;
      if (!granted) {
        setState(() {
          _loadingDevices = false;
          _status = s.pleaseGrantBluetoothPermissions;
        });
        return;
      }

      final result = await _printer.listBondedPrintersDetailed()
          .timeout(const Duration(seconds: 8), onTimeout: () {
        return (
          devices: <Map<String, String>>[],
          bluetoothEnabled: true,
          hasPermission: true,
          message: 'Timed out listing Bluetooth devices',
        );
      });

      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _devices = result.devices;
        if (!result.hasPermission) {
          _status = s.pleaseGrantBluetoothPermissions;
        } else if (!result.bluetoothEnabled) {
          _status = s.pleaseTurnOnBluetooth;
        } else if (result.devices.isEmpty) {
          _status = s.noPairedBluetoothDevices;
        } else {
          _status = s.selectPrinterDevice;
        }
        if (result.message.isNotEmpty && result.devices.isEmpty) {
          _status = result.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _status = e.toString();
      });
    }
  }

  Future<void> _connectDevice(String name, String address) async {
    final s = context.sRead;
    setState(() {
      _connecting = true;
      _printerConnected = false;
      _status = '${s.connectingBluetooth} ${name.isNotEmpty ? name : address}';
      _devices = []; // hide list while connecting (same as Kotlin)
    });

    try {
      final connect = await _printer.connect(address).timeout(
        const Duration(seconds: 20),
        onTimeout: () => (ok: false, message: 'Bluetooth connection timed out'),
      );
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _printerConnected = connect.ok;
        _status = connect.message.isNotEmpty
            ? connect.message
            : (connect.ok ? s.bluetoothPrinterConnected : s.bluetoothConnectFailed);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _printerConnected = false;
        _status = '$e';
      });
    }
  }

  Future<void> _printChallan() async {
    final s = context.sRead;
    if (!_printerConnected) {
      setState(() => _status = s.connectPrinterFirst);
      return;
    }
    setState(() {
      _printing = true;
      _status = s.printingPleaseWait;
    });
    try {
      final printRes = await _printer.printDeliveryChallan(
        challan: widget.challan,
        companyName: widget.companyName.isNotEmpty ? widget.companyName : widget.orgName,
      ).timeout(
        const Duration(seconds: 45),
        onTimeout: () => (ok: false, message: 'Print timed out'),
      );
      if (!mounted) return;
      setState(() {
        _printing = false;
        _status = printRes.ok
            ? s.printedSuccessfully
            : (printRes.message.isNotEmpty ? printRes.message : s.printFailed);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _printing = false;
        _status = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final busy = _loadingDevices || _connecting || _printing;

    return AlertDialog(
      title: Text(s.printOptions, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _optionButton(
              label: s.viewPdf,
              onTap: busy
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await printDeliveryChallanPdf(
                        context: context,
                        challan: widget.challan,
                        orgName: widget.orgName,
                      );
                    },
            ),
            const SizedBox(height: 10),
            _optionButton(
              label: s.bluetoothPrinter,
              onTap: busy
                  ? null
                  : () {
                      setState(() {
                        _showBluetooth = true;
                        _status = 'Not connected';
                      });
                    },
            ),
            if (_showBluetooth) ...[
              const SizedBox(height: 12),
              _optionButton(
                label: s.connectBluetoothPrinter,
                onTap: busy ? null : _onConnectBluetoothTap,
              ),
              const SizedBox(height: 8),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              if (!_loadingDevices && !_connecting && _devices.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _devices.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final d = _devices[index];
                        final name = d['name'] ?? 'Bluetooth Device';
                        final address = d['address'] ?? '';
                        return ListTile(
                          dense: true,
                          title: Text(name, style: GoogleFonts.poppins(fontSize: 13)),
                          subtitle: Text(address, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
                          onTap: address.isEmpty ? null : () => _connectDevice(name, address),
                        );
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              _optionButton(
                label: s.printChallan,
                onTap: (!_printerConnected || busy) ? null : _printChallan,
                enabled: _printerConnected && !busy,
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[800]),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel, style: GoogleFonts.poppins()),
        ),
      ],
    );
  }

  Widget _optionButton({
    required String label,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final active = enabled && onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: active ? null : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: active ? Colors.white : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
