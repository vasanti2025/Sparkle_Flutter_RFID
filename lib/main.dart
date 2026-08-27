import 'dart:async';
import 'dart:convert';

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
  DbService? _dbService;
  bool _fullReady = false;
  bool _warmScheduled = false;
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
      setState(() => _fullReady = true);
      unawaited(_hydrateInBackground());
    });
  }

  Future<void> _hydrateInBackground() async {
    try {
      final snapshot = await BootstrapChannel.getSnapshot();
      if (snapshot != null && snapshot.isNotEmpty) {
        _prefService.applyNativeSnapshot(snapshot);
      }

      await PrefService.init();

      // Absolute 1hr session — clear stale sessions before choosing home route.
      if (_prefService.isLoggedIn() && _prefService.isSessionTimedOut()) {
        await _prefService.logout();
      }

      var resolvedLoggedIn = _prefService.hasValidSession();

      if (!resolvedLoggedIn &&
          _prefService.isRememberMe() &&
          _prefService.getSavedUsername().isNotEmpty &&
          _prefService.getSavedPassword().isNotEmpty) {
        for (var i = 0; i < 20 && appNavigatorKey.currentContext == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          try {
            final ok = await ctx.read<LoginViewModel>().login(
              ctx,
              username: _prefService.getSavedUsername(),
              password: _prefService.getSavedPassword(),
            );
            if (ok) {
              resolvedLoggedIn = _prefService.hasValidSession();
            }
          } catch (e) {
            debugPrint('Silent autologin failed: $e');
          }
        }
      }

      // Still marked logged-in but session data missing → force login screen.
      if (!resolvedLoggedIn && _prefService.isLoggedIn()) {
        await _prefService.logout();
      }

      if (mounted && resolvedLoggedIn != _sessionLoggedIn) {
        setState(() => _sessionLoggedIn = resolvedLoggedIn);
      }
      _refreshViewModelsAfterHydrate();

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
        loggedIn: _sessionLoggedIn,
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
