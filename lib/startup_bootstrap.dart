import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_service.dart';
import 'services/db_service.dart';
import 'services/locale_service.dart';
import 'services/pref_service.dart';
import 'services/session_lifecycle.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'viewmodels/login_view_model.dart';

extension AppBootstrapContext on BuildContext {
  LocaleService watchLocale() => watch<LocaleService>();
}

/// Minimal providers for cold start — Login / Dashboard only (fast first frame).
Widget buildStartupProviders({
  required PrefService prefService,
  required void Function(DbService db) onDbReady,
  required Widget child,
}) {
  final apiService = ApiService(prefService);
  SessionLifecycle.instance.attach(prefs: prefService, api: apiService);
  final dbService = DbService();
  onDbReady(dbService);
  final localeService = LocaleService(prefService);

  return MultiProvider(
    providers: [
      Provider<PrefService>.value(value: prefService),
      Provider<ApiService>.value(value: apiService),
      Provider<DbService>.value(value: dbService),
      ChangeNotifierProvider<LocaleService>.value(value: localeService),
      ChangeNotifierProvider<LoginViewModel>(
        create: (_) => LoginViewModel(
          apiService: apiService,
          prefService: prefService,
        ),
      ),
      ChangeNotifierProvider<DashboardViewModel>(
        create: (_) => DashboardViewModel(
          prefService: prefService,
          dbService: dbService,
        ),
      ),
    ],
    child: child,
  );
}
