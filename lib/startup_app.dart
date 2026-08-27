import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_bootstrap_extended.dart' deferred as extended;
import 'app_navigator.dart';
import 'app_warmup.dart';
import 'services/db_service.dart';
import 'services/pref_service.dart';
import 'startup_bootstrap.dart';
import 'utils/app_dialogs.dart';
import 'utils/fast_page_route.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'viewmodels/login_view_model.dart';
import 'views/dashboard_screen.dart';
import 'views/login_screen.dart';

/// Real Login/Dashboard tree — loaded after Instant first frame so splash can dismiss.
Widget buildReadyApp({
  required PrefService prefService,
  required bool loggedIn,
  required void Function(DbService db) onDbReady,
  required void Function(bool loggedIn) onSessionResolved,
}) {
  return buildStartupProviders(
    prefService: prefService,
    onDbReady: onDbReady,
    child: _ExtendedProvidersLoader(
      loggedIn: loggedIn,
      prefService: prefService,
      onSessionResolved: onSessionResolved,
    ),
  );
}

/// Loads heavy ViewModels + routes after Login/Dashboard first frame.
class _ExtendedProvidersLoader extends StatefulWidget {
  final bool loggedIn;
  final PrefService prefService;
  final void Function(bool loggedIn) onSessionResolved;

  const _ExtendedProvidersLoader({
    required this.loggedIn,
    required this.prefService,
    required this.onSessionResolved,
  });

  @override
  State<_ExtendedProvidersLoader> createState() =>
      _ExtendedProvidersLoaderState();
}

class _ExtendedProvidersLoaderState extends State<_ExtendedProvidersLoader> {
  bool _extendedReady = false;
  bool _warmScheduled = false;
  Route<dynamic>? Function(RouteSettings settings)? _routeGenerator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadExtended());
      unawaited(_hydrateInBackground());
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

  Future<void> _hydrateInBackground() async {
    try {
      await PrefService.init();
      var resolvedLoggedIn = widget.prefService.hasValidSession();

      // Employee JSON is enough to restore the session even if `logged_in` was
      // missing or native bootstrap read the wrong type.
      if (!resolvedLoggedIn && widget.prefService.getEmployee() != null) {
        await widget.prefService.setLoggedIn(true);
        resolvedLoggedIn = true;
      }

      widget.onSessionResolved(resolvedLoggedIn);
      _refreshViewModelsAfterHydrate();

      if (!resolvedLoggedIn &&
          widget.prefService.isRememberMe() &&
          widget.prefService.getSavedUsername().isNotEmpty &&
          widget.prefService.getSavedPassword().isNotEmpty) {
        for (var i = 0; i < 20 && appNavigatorKey.currentContext == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          try {
            final ok = await ctx.read<LoginViewModel>().login(
              ctx,
              username: widget.prefService.getSavedUsername(),
              password: widget.prefService.getSavedPassword(),
            );
            if (ok) {
              resolvedLoggedIn = widget.prefService.hasValidSession();
            }
          } catch (e) {
            debugPrint('Silent autologin failed: $e');
          }
        }
        if (mounted && resolvedLoggedIn) {
          widget.onSessionResolved(true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
              '/dashboard',
              (route) => false,
            );
          });
        }
      }

      if (!_warmScheduled) {
        _warmScheduled = true;
        if (!mounted) return;
        DbService? db;
        try {
          db = context.read<DbService>();
        } catch (_) {}
        Future<void>.delayed(const Duration(seconds: 2), () {
          unawaited(warmAfterFirstFrame(widget.prefService, db));
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
        final generator = routeGenerator;
        if (generator != null) return generator(settings);
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
            return null;
        }
      },
    );
  }
}
