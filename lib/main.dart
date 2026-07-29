import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_bootstrap_extended.dart' deferred as extended;
import 'app_routes.dart';
import 'app_warmup.dart';
import 'instant/instant_dashboard_shell.dart';
import 'instant/instant_login_shell.dart';
import 'services/bootstrap_channel.dart';
import 'services/db_service.dart';
import 'services/pref_service.dart';
import 'startup_bootstrap.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'viewmodels/login_view_model.dart';
import 'views/dashboard_screen.dart';
import 'views/login_screen.dart';
import 'utils/app_dialogs.dart';

@pragma('vm:entry-point')
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final initialLoggedIn = args.isNotEmpty && args.first == 'dashboard';
  final savedUsername = args.length > 1 ? args[1] : '';
  final savedPassword = args.length > 2 ? args[2] : '';
  runApp(_BootstrapApp(
    initialLoggedIn: initialLoggedIn,
    savedUsername: savedUsername,
    savedPassword: savedPassword,
  ));
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
  DbService? _dbService;
  bool _fullReady = false;
  bool _warmScheduled = false;

  @override
  void initState() {
    super.initState();
    _prefService = PrefService.bootstrapQuick(
      loggedIn: widget.initialLoggedIn,
      username: widget.savedUsername,
      password: widget.savedPassword,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _fullReady = true);
      unawaited(_hydrateInBackground());
    });
  }

  Future<void> _hydrateInBackground() async {
    try {
      final snapshot = await BootstrapChannel.getSnapshot();
      if (snapshot != null && snapshot.isNotEmpty) {
        _prefService.applyNativeSnapshot(snapshot);
        _refreshViewModelsAfterHydrate();
      }

      unawaited(PrefService.init().then((_) => _refreshViewModelsAfterHydrate()));

      if (!_warmScheduled) {
        _warmScheduled = true;
        Future<void>.delayed(const Duration(seconds: 2), () {
          unawaited(warmAfterFirstFrame(_prefService, _dbService));
        });
      }
    } catch (e, st) {
      debugPrint('STARTUP hydrate failed: $e\n$st');
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
    if (!_fullReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: widget.initialLoggedIn
            ? const InstantDashboardShell()
            : InstantLoginShell(
                username: widget.savedUsername,
                password: widget.savedPassword,
              ),
      );
    }

    return buildStartupProviders(
      prefService: _prefService,
      onDbReady: (db) => _dbService = db,
      child: _ExtendedProvidersLoader(
        loggedIn: widget.initialLoggedIn,
      ),
    );
  }
}

/// Loads heavy ViewModels + routes after Login/Dashboard first frame.
class _ExtendedProvidersLoader extends StatefulWidget {
  final bool loggedIn;

  const _ExtendedProvidersLoader({required this.loggedIn});

  @override
  State<_ExtendedProvidersLoader> createState() => _ExtendedProvidersLoaderState();
}

class _ExtendedProvidersLoaderState extends State<_ExtendedProvidersLoader> {
  bool _extendedReady = false;
  Route<dynamic>? Function(RouteSettings settings)? _routeGenerator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadExtended());
    });
  }

  Future<void> _loadExtended() async {
    try {
      await extended.loadLibrary();
      if (!mounted) return;
      setState(() {
        _extendedReady = true;
        _routeGenerator = extended.routeGenerator;
      });
    } catch (e, st) {
      debugPrint('Extended load failed: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _StartupApp(
      loggedIn: widget.loggedIn,
      routeGenerator: _routeGenerator,
    );
    if (!_extendedReady) return app;
    return extended.ExtendedProvidersScope(child: app);
  }
}

class _StartupApp extends StatelessWidget {
  final bool loggedIn;
  final Route<dynamic>? Function(RouteSettings settings)? routeGenerator;

  const _StartupApp({
    required this.loggedIn,
    this.routeGenerator,
  });

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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: NoZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: NoZoomPageTransitionsBuilder(),
            TargetPlatform.linux: NoZoomPageTransitionsBuilder(),
            TargetPlatform.macOS: NoZoomPageTransitionsBuilder(),
            TargetPlatform.windows: NoZoomPageTransitionsBuilder(),
            TargetPlatform.fuchsia: NoZoomPageTransitionsBuilder(),
          },
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: localeService.textDirection,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: loggedIn ? const DashboardScreen() : const LoginScreen(),
      onGenerateRoute: (settings) {
        final generator = routeGenerator ?? generateAppRoute;
        return generator(settings);
      },
    );
  }
}
