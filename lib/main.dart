import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'login_app.dart';
import 'services/bootstrap_channel.dart';
import 'services/pref_service.dart';

@pragma('vm:entry-point')
void main(List<String> args) {
  final initialLoggedIn = args.isNotEmpty && args.first == 'dashboard';
  final savedUsername = args.length > 1 ? _decodeBootstrapArg(args[1]) : '';
  final savedPassword = args.length > 2 ? _decodeBootstrapArg(args[2]) : '';

  WidgetsFlutterBinding.ensureInitialized();
  // Never block first Login paint on a Google Fonts CDN fetch (handhelds, no net).
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(
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
      unawaited(_applySnapshot());
    });
  }

  Future<void> _applySnapshot() async {
    try {
      final snapshot = await BootstrapChannel.getSnapshot();
      if (snapshot != null && snapshot.isNotEmpty) {
        _prefService.applyNativeSnapshot(snapshot);
      }
      var resolvedLoggedIn = _prefService.hasValidSession();
      if (!mounted) return;
      setState(() => _sessionLoggedIn = resolvedLoggedIn);
    } catch (e) {
      debugPrint('STARTUP snapshot failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return buildLoginApp(
      prefService: _prefService,
      loggedIn: _sessionLoggedIn,
      onSessionResolved: (loggedIn) {
        if (!mounted || _sessionLoggedIn == loggedIn) return;
        setState(() => _sessionLoggedIn = loggedIn);
      },
    );
  }
}
