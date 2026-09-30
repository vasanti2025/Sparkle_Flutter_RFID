import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'login_app.dart';

@pragma('vm:entry-point')
void main(List<String> args) {
  final initialLoggedIn = args.isNotEmpty && args.first == 'dashboard';
  final savedUsername = args.length > 1 ? _decodeBootstrapArg(args[1]) : '';
  final savedPassword = args.length > 2 ? _decodeBootstrapArg(args[2]) : '';

  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runBootApp(
    initialLoggedIn: initialLoggedIn,
    savedUsername: savedUsername,
    savedPassword: savedPassword,
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
