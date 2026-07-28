import 'dart:io';

import 'package:flutter/services.dart';

/// Fast native read of FlutterSharedPreferences — avoids slow Dart plugin cold start.
class BootstrapChannel {
  static const _channel = MethodChannel('com.loyalstring.rfid/bootstrap');

  static Future<Map<String, dynamic>?> getSnapshot() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getSnapshot');
      if (raw == null) return null;
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }
}
