import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_bootstrap_extended.dart' deferred as extended;
import 'app_navigator.dart';
import 'app_warmup.dart' deferred as warmup;
import 'services/db_service.dart';
import 'services/pref_service.dart';
import 'startup_app.dart' deferred as dash;
import 'startup_bootstrap.dart';
import 'utils/app_dialogs.dart';
import 'utils/fast_page_route.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'viewmodels/login_view_model.dart';
import 'views/login_screen.dart';

/// Login paints on the first Flutter frame — Dashboard/routes load after.
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
  bool _dashReady = false;
  bool _extendedReady = false;
  bool _warmScheduled = false;
  Route<dynamic>? Function(RouteSettings settings)? _routeGenerator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_hydrateInBackground());
      if (widget.prefService.hasValidSession()) {
        unawaited(_loadDashboardLib());
      }
    });
  }

  @override
  void didUpdateWidget(covariant _LoginAppRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loggedIn && !_dashReady && widget.prefService.hasValidSession()) {
      unawaited(_loadDashboardLib());
    }
  }

  Future<void> _loadDashboardLib() async {
    try {
      await dash.loadLibrary();
      if (mounted) setState(() => _dashReady = true);
    } catch (e, st) {
      debugPrint('Dashboard lib load failed: $e\n$st');
      if (mounted) setState(() {});
    }
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

  Future<void> _hydrateInBackground() async {
    try {
      await PrefService.init();
      if (!mounted) return;
      final resolvedLoggedIn = widget.prefService.hasValidSession();
      widget.onSessionResolved(resolvedLoggedIn);
      if (mounted) setState(() {});
      _refreshViewModelsAfterHydrate();

      if (resolvedLoggedIn && !_dashReady) {
        unawaited(_loadDashboardLib());
      }

      // Routes/VMs after Login or Dashboard has painted — loading them on
      // splash skipped 100+ frames and froze the first screen.
      unawaited(Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (mounted) unawaited(_loadExtended());
      }));

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
    final showDashboard = sessionOk && _dashReady;

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
          ? dash.buildDashboardPage()
          : sessionOk
              ? const _HoldSplash()
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
              child: _DeferredDashboard(ensureLoaded: _loadDashboardLib),
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

class _HoldSplash extends StatelessWidget {
  const _HoldSplash();

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

class _DeferredDashboard extends StatefulWidget {
  final Future<void> Function() ensureLoaded;

  const _DeferredDashboard({required this.ensureLoaded});

  @override
  State<_DeferredDashboard> createState() => _DeferredDashboardState();
}

class _DeferredDashboardState extends State<_DeferredDashboard> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    await widget.ensureLoaded();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF5231A7)),
        ),
      );
    }
    return dash.buildDashboardPage();
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
