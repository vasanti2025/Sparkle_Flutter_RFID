import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_bootstrap.dart';
import 'app_routes.dart';
import 'services/db_service.dart';
import 'services/pref_service.dart';
import 'utils/app_dropdown.dart';
import 'views/dashboard_screen.dart';
import 'views/login_screen.dart';

/// Opens like a normal app / Sparkle:
/// native splash → first frame Login or Home (no blank bridge, no RFID at start).
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final prefService = await PrefService.init();
  final loggedIn = prefService.isLoggedIn();
  DbService? dbService;

  runApp(
    buildAppProviders(
      prefService: prefService,
      onDbReady: (db) => dbService = db,
      child: MyApp(loggedIn: loggedIn),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(warmAfterFirstFrame(prefService, dbService));
  });
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
      home: loggedIn ? const DashboardScreen() : const LoginScreen(),
      onGenerateRoute: generateAppRoute,
    );
  }
}
