import 'dart:async';

import 'package:flutter/material.dart';

import '../services/rfid_service.dart';

/// Shared barcode wiring for Order / Quotation / Delivery Challan / Sample Out / Add Product.
///
/// - Scan icon → [RfidService.startBarcodeScan]
/// - Device key 139 → [RfidService.barcodeTriggerStream] (native also starts scan)
/// - Decoded value → [RfidService.barcodeStream]
mixin BarcodeScanMixin<T extends StatefulWidget> on State<T> {
  final RfidService barcodeRfid = RfidService();
  StreamSubscription<String>? _barcodeSub;
  StreamSubscription<void>? _barcodeTriggerSub;

  /// Called when a barcode is decoded (field fill + product lookup).
  void onBarcodeScanned(String code);

  /// Wire listeners. Call from initState after other setup.
  void bindBarcodeScanner({bool openDecoder = true}) {
    if (openDecoder) {
      unawaited(barcodeRfid.openBarcode());
    }
    _barcodeSub = barcodeRfid.barcodeStream.listen((code) {
      if (!mounted) return;
      final trimmed = code.trim();
      if (trimmed.isEmpty) return;
      onBarcodeScanned(trimmed);
    });
    _barcodeTriggerSub = barcodeRfid.barcodeTriggerStream.listen((_) {
      // Native already starts decode on key 139; keep Flutter path for icon parity.
      if (!mounted) return;
      unawaited(barcodeRfid.startBarcodeScan());
    });
  }

  Future<void> startBarcodeFromIcon() => barcodeRfid.startBarcodeScan();

  void unbindBarcodeScanner() {
    _barcodeSub?.cancel();
    _barcodeSub = null;
    _barcodeTriggerSub?.cancel();
    _barcodeTriggerSub = null;
    unawaited(barcodeRfid.stopBarcodeScan());
  }
}
