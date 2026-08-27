import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'services/bootstrap_channel.dart';
import 'services/pref_service.dart';
import 'startup_app.dart' deferred as startup;
import 'utils/app_logger.dart';

@pragma('vm:entry-point')
void main(List<String> args) {
  final initialLoggedIn = args.isNotEmpty && args.first == 'dashboard';
  final savedUsername = args.length > 1 ? _decodeBootstrapArg(args[1]) : '';
  final savedPassword = args.length > 2 ? _decodeBootstrapArg(args[2]) : '';

  AppLogger.bootstrapAndRunApp(
    _BootstrapApp(
      initialLoggedIn: initialLoggedIn,
      savedUsername: savedUsername,
      savedPassword: savedPassword,
    ),
  );
}

String _decodeBootstrapArg(String raw) {
  if (raw.isEmpty) return raw;
  try {
    return utf8.decode(base64.decode(raw));
  } catch (_) {
    // Legacy installs passed plain text args.
    return raw;
  }
}

class _BootstrapApp extends StatefulWidget {
  final bool initialLoggedIn;
  final String savedUsername;
  final String savedPassword;

  const _BootstrapApp({
    required this.initialLoggedIn,
    this.savedUsername = '',
    this.savedPassword = '',
  });

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final PrefService _prefService;
  bool _libReady = false;
  late bool _sessionLoggedIn;

  @override
  void initState() {
    super.initState();
    _sessionLoggedIn = widget.initialLoggedIn;
    _prefService = PrefService.bootstrapQuick(
      loggedIn: widget.initialLoggedIn,
      username: widget.savedUsername,
      password: widget.savedPassword,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootAfterFirstFrame());
    });
  }

  Future<void> _bootAfterFirstFrame() async {
    try {
      final snapshotFuture = BootstrapChannel.getSnapshot();
      final libFuture = startup.loadLibrary();

      try {
        final snapshot = await snapshotFuture;
        if (snapshot != null && snapshot.isNotEmpty) {
          _prefService.applyNativeSnapshot(snapshot);
        }
      } catch (e) {
        debugPrint('STARTUP snapshot failed: $e');
      }

      var resolvedLoggedIn = _prefService.hasValidSession();
      if (!resolvedLoggedIn && _prefService.getEmployee() != null) {
        unawaited(_prefService.setLoggedIn(true));
        resolvedLoggedIn = true;
      }

      await libFuture;
      if (!mounted) return;
      setState(() {
        _sessionLoggedIn = resolvedLoggedIn;
        _libReady = true;
      });
    } catch (e, st) {
      debugPrint('STARTUP boot failed: $e\n$st');
      try {
        await startup.loadLibrary();
      } catch (_) {}
      if (mounted && !_libReady) {
        setState(() => _libReady = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_libReady) {
      // Keep the native splash look until real Login/Dashboard is ready.
      // Never paint the old placeholder dashboard grid.
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _LaunchSplash(),
      );
    }

    return startup.buildReadyApp(
      prefService: _prefService,
      loggedIn: _sessionLoggedIn,
      onDbReady: (_) {},
      onSessionResolved: (loggedIn) {
        if (!mounted || _sessionLoggedIn == loggedIn) return;
        setState(() => _sessionLoggedIn = loggedIn);
      },
    );
  }
}

/// Same as native LaunchTheme — white + logo — so the old icon-grid never flashes.
class _LaunchSplash extends StatelessWidget {
  const _LaunchSplash();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: Image(
          image: AssetImage('assets/branding/sparkle_logo.png'),
          width: 180,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
