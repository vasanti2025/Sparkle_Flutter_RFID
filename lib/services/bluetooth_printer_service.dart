import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/delivery_challan.dart';
import '../services/pref_service.dart';

/// Dart bridge to Xprinter POSConnect (same SDK as Sparkle Delivery Challan Bluetooth print).
class BluetoothPrinterService {
  static final BluetoothPrinterService _instance = BluetoothPrinterService._();
  factory BluetoothPrinterService() => _instance;
  BluetoothPrinterService._();

  static const _channel = MethodChannel('com.loyalstring.rfid/printer');

  Future<List<Map<String, String>>> listBondedPrinters() async {
    final detailed = await listBondedPrintersDetailed();
    return detailed.devices;
  }

  Future<
      ({
        List<Map<String, String>> devices,
        bool bluetoothEnabled,
        bool hasPermission,
        String message,
      })> listBondedPrintersDetailed() async {
    try {
      final res = await _channel.invokeMethod<dynamic>('listBondedPrinters');
      if (res is Map) {
        final raw = res['devices'];
        final devices = <Map<String, String>>[];
        if (raw is List) {
          for (final e in raw) {
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e);
            final address = m['address']?.toString() ?? '';
            if (address.isEmpty) continue;
            devices.add({
              'name': m['name']?.toString() ?? 'Bluetooth Device',
              'address': address,
            });
          }
        }
        return (
          devices: devices,
          bluetoothEnabled: res['bluetoothEnabled'] != false,
          hasPermission: res['hasPermission'] != false,
          message: res['message']?.toString() ?? '',
        );
      }
      // Backward compatible: plain list
      if (res is List) {
        final devices = res.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return {
            'name': m['name']?.toString() ?? 'Bluetooth Device',
            'address': m['address']?.toString() ?? '',
          };
        }).where((e) => e['address']!.isNotEmpty).toList();
        return (
          devices: devices,
          bluetoothEnabled: true,
          hasPermission: true,
          message: '',
        );
      }
      return (devices: <Map<String, String>>[], bluetoothEnabled: true, hasPermission: true, message: '');
    } catch (e) {
      debugPrint('listBondedPrinters: $e');
      return (
        devices: <Map<String, String>>[],
        bluetoothEnabled: true,
        hasPermission: false,
        message: '$e',
      );
    }
  }

  Future<({bool ok, String message})> connect(String address) async {
    try {
      final res = await _channel.invokeMethod<Map>('connectPrinter', {'address': address});
      return (ok: res?['ok'] == true, message: res?['message']?.toString() ?? '');
    } catch (e) {
      return (ok: false, message: '$e');
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnectPrinter');
    } catch (_) {}
  }

  Future<bool> isConnected() async {
    try {
      return await _channel.invokeMethod<bool>('isPrinterConnected') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<({bool ok, String message})> printDeliveryChallan({
    required DeliveryChallanModel challan,
    required String companyName,
  }) async {
    final prefs = await PrefService.init();
    final clientCode = prefs.getEmployee()?.clientCode ?? challan.clientCode;
    final org = prefs.getOrganisationName() ?? companyName;

    final items = challan.challanDetails.map((d) {
      return {
        'itemName': d.productName.isNotEmpty ? d.productName : d.designName,
        'purity': d.purity,
        'pcs': d.pcs > 0 ? d.pcs : (int.tryParse(d.pieces) ?? 1),
        'grossWt': d.grossWt,
        'stoneWt': d.totalStoneWeight.isNotEmpty ? d.totalStoneWeight : (challan.totalStoneWeight ?? '0'),
        'netWt': d.netWt,
        'stoneAmt': d.stoneAmt.isNotEmpty ? d.stoneAmt : d.totalStoneAmount,
        'ratePerGram': d.ratePerGram.isNotEmpty ? d.ratePerGram : d.metalRate,
        'wastage': d.makingPercentage.isNotEmpty ? d.makingPercentage : d.makingFixedWastage,
        'itemAmount': d.itemAmount.isNotEmpty ? d.itemAmount : d.totalItemAmount,
      };
    }).toList();

    try {
      final res = await _channel.invokeMethod<Map>('printDeliveryChallan', {
        'customerName': challan.customerName ?? '',
        'phone': '',
        'createdDateTime': challan.createdOn ?? '',
        'totalNetAmount': challan.totalNetAmount ?? challan.totalAmount ?? '0',
        'totalAmount': challan.totalAmount ?? '0',
        'companyName': companyName.isNotEmpty ? companyName : org,
        'organizationName': org,
        'clientCode': clientCode,
        'items': items,
      });
      return (ok: res?['ok'] == true, message: res?['message']?.toString() ?? '');
    } catch (e) {
      return (ok: false, message: '$e');
    }
  }
}
