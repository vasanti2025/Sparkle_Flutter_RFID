import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_bootstrap.dart';
import 'app_routes.dart';
import 'services/db_service.dart';
import 'services/pref_service.dart';
import 'utils/app_dropdown.dart';

/// Opens like a normal app / Sparkle:
/// native splash → instant white frame → Login or Home (single runApp, no plugin re-init).
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const _BootstrapApp());
}

/// One [runApp] for the process — avoids Geolocator/other plugins attaching twice.
class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  Widget? _root;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<PrefService> _loadPrefs() async {
    const timeout = Duration(seconds: 45);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await PrefService.init().timeout(timeout);
      } on TimeoutException catch (e) {
        debugPrint('STARTUP prefs attempt ${attempt + 1} timed out: $e');
        PrefService.resetInitForRetry();
        if (attempt == 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    throw StateError('unreachable');
  }

  Future<void> _boot() async {
    try {
      // Paint white bootstrap frame before SharedPreferences native I/O.
      await SchedulerBinding.instance.endOfFrame;

      final prefService = await _loadPrefs();
      if (!mounted) return;

      final loggedIn = prefService.isLoggedIn();
      DbService? dbService;

      setState(() {
        _bootError = null;
        _root = buildAppProviders(
          prefService: prefService,
          onDbReady: (db) => dbService = db,
          child: MyApp(loggedIn: loggedIn),
        );
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          unawaited(warmAfterFirstFrame(prefService, dbService));
        });
      });
    } catch (e, st) {
      debugPrint('STARTUP boot failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _bootError = e.toString();
        _root = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_root != null) return _root!;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: _bootError == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading…', style: TextStyle(color: Colors.black54)),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Startup failed.\n$_bootError',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black87),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() => _bootError = null);
                          unawaited(_boot());
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  final bool loggedIn;

  const MyApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    final localeService = context.watchLocale();

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Sparkle RFID',
      debugShowCheckedModeBanner: false,
      locale: localeService.locale,
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        textTheme: ThemeData.light().textTheme,
        dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
            maximumSize: WidgetStatePropertyAll(
              Size(double.infinity, kDropdownMenuMaxHeight),
            ),
          ),
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: localeService.textDirection,
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: loggedIn ? '/dashboard' : '/login',
      onGenerateRoute: generateAppRoute,
    );
  }
}
