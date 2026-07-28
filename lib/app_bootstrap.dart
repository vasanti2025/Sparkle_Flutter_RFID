import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_service.dart';
import 'services/auto_sync_service.dart';
import 'services/db_service.dart';
import 'services/face_recognition_service.dart';
import 'services/locale_service.dart';
import 'services/location_sync_service.dart';
import 'services/order_sync_service.dart';
import 'services/pref_service.dart';
import 'services/rfid_service.dart';
import 'viewmodels/bulk_product_view_model.dart';
import 'viewmodels/daily_rate_view_model.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'viewmodels/delivery_challan_view_model.dart';
import 'viewmodels/import_excel_view_model.dart';
import 'viewmodels/login_view_model.dart';
import 'viewmodels/order_view_model.dart';
import 'viewmodels/product_view_model.dart';
import 'viewmodels/quotation_view_model.dart';
import 'viewmodels/sample_in_view_model.dart';
import 'viewmodels/sample_out_view_model.dart';
import 'viewmodels/settings_view_model.dart';
import 'viewmodels/single_product_view_model.dart';
import 'viewmodels/stock_transfer_view_model.dart';
import 'viewmodels/stock_verification_view_model.dart';

extension AppBootstrapContext on BuildContext {
  LocaleService watchLocale() => watch<LocaleService>();
}

Widget buildAppProviders({
  required PrefService prefService,
  required void Function(DbService db) onDbReady,
  required Widget child,
}) {
  final apiService = ApiService(prefService);
  final dbService = DbService();
  onDbReady(dbService);
  final localeService = LocaleService(prefService);

  return MultiProvider(
    providers: [
      Provider<PrefService>.value(value: prefService),
      Provider<ApiService>.value(value: apiService),
      Provider<DbService>.value(value: dbService),
      Provider<FaceRecognitionService>(
        lazy: true,
        create: (_) => FaceRecognitionService(),
      ),
      ChangeNotifierProvider<LocaleService>.value(value: localeService),
      ChangeNotifierProvider<LoginViewModel>(
        lazy: true,
        create: (_) => LoginViewModel(
          apiService: apiService,
          prefService: prefService,
        ),
      ),
      ChangeNotifierProvider<DashboardViewModel>(
        lazy: true,
        create: (_) => DashboardViewModel(
          prefService: prefService,
          dbService: dbService,
        ),
      ),
      ChangeNotifierProvider<ProductViewModel>(
        lazy: true,
        create: (_) => ProductViewModel(
          prefService: prefService,
          dbService: dbService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<OrderViewModel>(
        lazy: true,
        create: (_) => OrderViewModel(
          prefService: prefService,
          dbService: dbService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<DeliveryChallanViewModel>(
        lazy: true,
        create: (_) => DeliveryChallanViewModel(
          prefService: prefService,
          dbService: dbService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<DailyRateViewModel>(
        lazy: true,
        create: (_) => DailyRateViewModel(
          prefService: prefService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<QuotationViewModel>(
        lazy: true,
        create: (_) => QuotationViewModel(
          prefService: prefService,
          dbService: dbService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<SampleInViewModel>(
        lazy: true,
        create: (_) => SampleInViewModel(
          prefService: prefService,
          dbService: dbService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<SampleOutViewModel>(
        lazy: true,
        create: (_) => SampleOutViewModel(
          prefService: prefService,
          dbService: dbService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<StockVerificationViewModel>(
        lazy: true,
        create: (_) => StockVerificationViewModel(
          prefService: prefService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<SingleProductViewModel>(
        lazy: true,
        create: (_) => SingleProductViewModel(
          prefService: prefService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<BulkProductViewModel>(
        lazy: true,
        create: (_) => BulkProductViewModel(dbService: dbService),
      ),
      ChangeNotifierProvider<ImportExcelViewModel>(
        lazy: true,
        create: (_) => ImportExcelViewModel(
          dbService: dbService,
          apiService: apiService,
          prefService: prefService,
        ),
      ),
      ChangeNotifierProvider<SettingsViewModel>(
        lazy: true,
        create: (_) => SettingsViewModel(
          prefService: prefService,
          dbService: dbService,
          apiService: apiService,
        ),
      ),
      ChangeNotifierProvider<StockTransferViewModel>(
        lazy: true,
        create: (_) => StockTransferViewModel(
          apiService: apiService,
          dbService: dbService,
          prefService: prefService,
        ),
      ),
    ],
    child: child,
  );
}

Future<void> warmAfterFirstFrame(
  PrefService prefService,
  DbService? dbService,
) async {
  if (dbService != null) {
    try {
      await dbService.database;
    } catch (e, st) {
      debugPrint('DB init deferred error: $e\n$st');
    }
  }

  Future<void>.delayed(const Duration(seconds: 3), () async {
    try {
      await AutoSyncService.initialize();
    } catch (e, st) {
      debugPrint('AutoSync init skipped: $e\n$st');
    }
  });

  Future<void>.delayed(const Duration(seconds: 8), () async {
    try {
      await LocationSyncService.initializeIfEnabled();
    } catch (e, st) {
      debugPrint('LocationSync init skipped: $e\n$st');
    }
  });

  Future<void>.delayed(const Duration(seconds: 12), () async {
    try {
      await OrderSyncService.initializeIfEnabled();
    } catch (e, st) {
      debugPrint('OrderSync init skipped: $e\n$st');
    }
  });

  Future<void>.delayed(const Duration(seconds: 20), () async {
    try {
      if (prefService.isTrayModeEnabled()) {
        await RfidService().restoreTrayModeFromPrefs(
          enabled: true,
          address: prefService.getTrayDeviceAddress(),
        );
      } else if (prefService.isR6ModeEnabled()) {
        await RfidService().restoreR6ModeFromPrefs(
          enabled: true,
          address: prefService.getR6DeviceAddress(),
        );
      }
    } catch (e, st) {
      debugPrint('Tray/R6 mode init skipped: $e\n$st');
    }
  });
}
