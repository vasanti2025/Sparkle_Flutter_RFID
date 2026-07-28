import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'app_bootstrap.dart';
import 'app_routes.dart';
import 'services/bootstrap_channel.dart';
import 'services/db_service.dart';
import 'services/pref_service.dart';
import 'utils/app_dropdown.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'viewmodels/login_view_model.dart';

/// Native MainActivity passes `login` or `dashboard` from Android SharedPreferences
/// synchronously — first frame can be Login/Home without waiting for Dart prefs.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  final initialLoggedIn = args.isNotEmpty && args.first == 'dashboard';
  final savedUsername = args.length > 1 ? args[1] : '';
  final savedPassword = args.length > 2 ? args[2] : '';
  runApp(_BootstrapApp(
    initialLoggedIn: initialLoggedIn,
    savedUsername: savedUsername,
    savedPassword: savedPassword,
  ));
}

/// One [runApp] for the process — avoids Geolocator/other plugins attaching twice.
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
  late final Widget _root;
  DbService? _dbService;
  bool _warmScheduled = false;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    _prefService = PrefService.bootstrapQuick(
      loggedIn: widget.initialLoggedIn,
      username: widget.savedUsername,
      password: widget.savedPassword,
    );
    _root = buildAppProviders(
      prefService: _prefService,
      onDbReady: (db) => _dbService = db,
      child: MyApp(loggedIn: widget.initialLoggedIn),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hydrateInBackground());
    });
  }

  Future<void> _hydrateInBackground() async {
    try {
      final snapshot = await BootstrapChannel.getSnapshot();
      if (snapshot != null && snapshot.isNotEmpty) {
        _prefService.applyNativeSnapshot(snapshot);
        _refreshViewModelsAfterHydrate();
        if (mounted) setState(() {});
      }

      await PrefService.init();
      _refreshViewModelsAfterHydrate();

      if (!_warmScheduled) {
        _warmScheduled = true;
        Future<void>.delayed(const Duration(seconds: 2), () {
          unawaited(warmAfterFirstFrame(_prefService, _dbService));
        });
      }
    } catch (e, st) {
      debugPrint('STARTUP hydrate failed: $e\n$st');
      if (!mounted) return;
      setState(() => _bootError = e.toString());
    }
  }

  void _refreshViewModelsAfterHydrate() {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ctx.read<LoginViewModel>().reloadRememberMe();
    } catch (_) {}
    try {
      ctx.read<DashboardViewModel>().loadUser();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_bootError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
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
                ],
              ),
            ),
          ),
        ),
      );
    }
    return _root;
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
