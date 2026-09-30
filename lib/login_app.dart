import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_bootstrap_extended.dart' deferred as extended;
import 'app_navigator.dart';
import 'app_warmup.dart' deferred as warmup;
import 'services/bootstrap_channel.dart';
import 'services/db_service.dart';
import 'services/pref_service.dart';
import 'startup_bootstrap.dart';
import 'utils/app_dialogs.dart';
import 'utils/fast_page_route.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'viewmodels/login_view_model.dart';
import 'views/dashboard_screen.dart';
import 'views/login_screen.dart';

/// Replaces the first-frame logo with Login or Dashboard.
void runBootApp({
  required bool initialLoggedIn,
  required String savedUsername,
  required String savedPassword,
}) {
  runApp(
    _BootstrapApp(
      initialLoggedIn: initialLoggedIn,
      savedUsername: savedUsername,
      savedPassword: savedPassword,
    ),
  );
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
    unawaited(_applySnapshot());
    unawaited(PrefService.init());
  }

  Future<void> _applySnapshot() async {
    try {
      final snapshot = await BootstrapChannel.getSnapshot();
      if (snapshot != null && snapshot.isNotEmpty) {
        _prefService.applyNativeSnapshot(snapshot);
        if (!mounted) return;
        setState(() => _sessionLoggedIn = _prefService.hasValidSession());
      }
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

/// Login or Dashboard after the native/logo first frame.
Widget buildLoginApp({
  required PrefService prefService,
  required bool loggedIn,
  required void Function(bool loggedIn) onSessionResolved,
}) {
  return buildStartupProviders(
    prefService: prefService,
    onDbReady: (_) {},
    child: _LoginAppRoot(
      loggedIn: loggedIn,
      prefService: prefService,
      onSessionResolved: onSessionResolved,
    ),
  );
}

class _LoginAppRoot extends StatefulWidget {
  final bool loggedIn;
  final PrefService prefService;
  final void Function(bool loggedIn) onSessionResolved;

  const _LoginAppRoot({
    required this.loggedIn,
    required this.prefService,
    required this.onSessionResolved,
  });

  @override
  State<_LoginAppRoot> createState() => _LoginAppRootState();
}

class _LoginAppRootState extends State<_LoginAppRoot> {
  bool _extendedReady = false;
  bool _extendedLoading = false;
  bool _warmScheduled = false;
  Route<dynamic>? Function(RouteSettings settings)? _routeGenerator;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateInBackground());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted) unawaited(_loadExtended());
      }));
    });
  }

  Future<void> _loadExtended() async {
    if (_extendedReady || _extendedLoading) return;
    _extendedLoading = true;
    try {
      await extended.loadLibrary();
      if (!mounted) return;
      setState(() {
        _extendedReady = true;
        _routeGenerator = extended.routeGenerator;
      });
    } catch (e, st) {
      _extendedLoading = false;
      debugPrint('Extended load failed: $e\n$st');
    }
  }

  Future<void> _hydrateInBackground() async {
    try {
      if (widget.prefService.hasValidSession() || widget.loggedIn) {
        widget.onSessionResolved(widget.prefService.hasValidSession() || widget.loggedIn);
        if (mounted) setState(() {});
      }

      await PrefService.init();
      if (!mounted) return;
      final resolvedLoggedIn = widget.prefService.hasValidSession();
      widget.onSessionResolved(resolvedLoggedIn);
      if (mounted) setState(() {});
      _refreshViewModelsAfterHydrate();

      if (!_warmScheduled) {
        _warmScheduled = true;
        DbService? db;
        try {
          if (mounted) db = context.read<DbService>();
        } catch (_) {}
        Future<void>.delayed(const Duration(seconds: 2), () async {
          try {
            await warmup.loadLibrary();
            await warmup.warmAfterFirstFrame(widget.prefService, db);
          } catch (e, st) {
            debugPrint('Warmup skipped: $e\n$st');
          }
        });
      }
    } catch (e, st) {
      debugPrint('STARTUP hydrate failed: $e\n$st');
      if (mounted) setState(() {});
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
    final localeService = context.watchLocale();
    final sessionOk = widget.prefService.hasValidSession();
    final showDashboard = sessionOk || widget.loggedIn;

    final app = MaterialApp(
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
      home: showDashboard
          ? const DashboardScreen()
          : const LoginScreen(),
      onGenerateRoute: (settings) {
        final generator = _routeGenerator;
        if (generator != null) {
          final route = generator(settings);
          if (route != null) return route;
        }
        switch (settings.name) {
          case '/login':
            return FastPageRoute(
              settings: settings,
              child: const LoginScreen(),
            );
          case '/dashboard':
            return FastPageRoute(
              settings: settings,
              child: const DashboardScreen(),
            );
          default:
            return FastPageRoute(
              settings: settings,
              child: _PendingExtendedRoute(
                ensureLoaded: _loadExtended,
                resolve: () => _routeGenerator?.call(settings),
              ),
            );
        }
      },
    );

    if (!_extendedReady) return app;
    return extended.ExtendedProvidersScope(child: app);
  }
}

class _PendingExtendedRoute extends StatefulWidget {
  final Future<void> Function() ensureLoaded;
  final Route<dynamic>? Function() resolve;

  const _PendingExtendedRoute({
    required this.ensureLoaded,
    required this.resolve,
  });

  @override
  State<_PendingExtendedRoute> createState() => _PendingExtendedRouteState();
}

class _PendingExtendedRouteState extends State<_PendingExtendedRoute> {
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    await widget.ensureLoaded();
    if (!mounted) return;
    final route = widget.resolve();
    if (route == null || !mounted) return;
    Navigator.of(context).pushReplacement(route);
  }

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: CircularProgressIndicator(color: Color(0xFF5231A7)),
      ),
    );
  }
}
