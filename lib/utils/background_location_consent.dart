import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../services/location_sync_service.dart';
import '../services/pref_service.dart';

/// Play-required disclosure before foreground, then background, location.
class BackgroundLocationConsent {
  static bool _promptOpen = false;

  /// Shows the disclosure when needed, then requests while-in-use and
  /// background location. Background GPS sync starts only when both are granted.
  static Future<bool> request(BuildContext context) async {
    if (_promptOpen) return false;
    final pref = context.read<PrefService>();
    if (pref.isBackgroundLocationConsentGranted() && await _hasBackgroundPermission()) {
      return true;
    }

    _promptOpen = true;
    try {
      final agreed = await _showDisclosure(context);
      if (!context.mounted) return false;
      await pref.setBackgroundLocationConsent(agreed);
      if (!agreed) return false;

      final granted = await _requestForegroundThenBackground();
      if (!granted) return false;
      await LocationSyncService.applySettings(true);
      return true;
    } finally {
      _promptOpen = false;
    }
  }

  static Future<bool> _showDisclosure(BuildContext context) async {
    final strings = context.sRead;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              strings.backgroundLocationTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Text(
                strings.backgroundLocationBody,
                style: const TextStyle(fontSize: 15, height: 1.4, color: Color(0xFF222222)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(strings.backgroundLocationNotNow),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5231A7)),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(strings.backgroundLocationContinue),
              ),
            ],
          ),
        );
      },
    );
    return result == true;
  }

  static Future<bool> _hasBackgroundPermission() async {
    return (await Permission.locationAlways.status).isGranted;
  }

  /// While-in-use first, then background. Android 11+ opens system settings
  /// for "Allow all the time"; wait until the user returns.
  static Future<bool> _requestForegroundThenBackground() async {
    var foreground = await Permission.locationWhenInUse.status;
    if (!foreground.isGranted) {
      foreground = await Permission.locationWhenInUse.request();
    }
    if (!foreground.isGranted) return false;

    var background = await Permission.locationAlways.status;
    if (background.isGranted) return true;

    final askedAt = DateTime.now();
    background = await Permission.locationAlways.request();
    if (background.isGranted) return true;

    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      background = await Permission.locationAlways.status;
      if (background.isGranted) return true;
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == AppLifecycleState.resumed &&
          DateTime.now().difference(askedAt) > const Duration(seconds: 2)) {
        return (await Permission.locationAlways.status).isGranted;
      }
    }
    return false;
  }
}
