import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/pref_service.dart';
import 'services/db_service.dart';
import 'services/locale_service.dart';
import 'services/location_sync_service.dart';
import 'services/face_recognition_service.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'viewmodels/login_view_model.dart';
import 'viewmodels/product_view_model.dart';
import 'viewmodels/order_view_model.dart';
import 'viewmodels/delivery_challan_view_model.dart';
import 'viewmodels/daily_rate_view_model.dart';
import 'viewmodels/quotation_view_model.dart';
import 'viewmodels/sample_in_view_model.dart';
import 'viewmodels/sample_out_view_model.dart';
import 'viewmodels/stock_verification_view_model.dart';
import 'viewmodels/single_product_view_model.dart';
import 'viewmodels/bulk_product_view_model.dart';
import 'viewmodels/import_excel_view_model.dart';
import 'viewmodels/settings_view_model.dart';
import 'viewmodels/stock_transfer_view_model.dart';
import 'services/auto_sync_service.dart';
import 'services/order_sync_service.dart';
import 'services/rfid_service.dart';
import 'app_routes.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize shared preferences wrapper
  final prefService = await PrefService.init();
  final apiService = ApiService(prefService);
  final dbService = DbService();
  
  // Face model loads lazily when face login / add-face is opened.
  final faceRecognitionService = FaceRecognitionService();

  // Pre-create screen view-models so first navigation does not block on lazy init.
  final localeService = LocaleService(prefService);
  final dashboardViewModel = DashboardViewModel(prefService: prefService);
  final productViewModel = ProductViewModel(
    prefService: prefService,
    dbService: dbService,
    apiService: apiService,
  );
  final orderViewModel = OrderViewModel(
    prefService: prefService,
    dbService: dbService,
    apiService: apiService,
  );
  final deliveryChallanViewModel = DeliveryChallanViewModel(
    prefService: prefService,
    dbService: dbService,
    apiService: apiService,
  );
  final dailyRateViewModel = DailyRateViewModel(
    prefService: prefService,
    apiService: apiService,
  );
  final quotationViewModel = QuotationViewModel(
    prefService: prefService,
    dbService: dbService,
    apiService: apiService,
  );
  final sampleInViewModel = SampleInViewModel(
    prefService: prefService,
    dbService: dbService,
    apiService: apiService,
  );
  final sampleOutViewModel = SampleOutViewModel(
    prefService: prefService,
    dbService: dbService,
    apiService: apiService,
  );
  final stockVerificationViewModel = StockVerificationViewModel(
    prefService: prefService,
    apiService: apiService,
  );
  final settingsViewModel = SettingsViewModel(
    prefService: prefService,
    dbService: dbService,
    apiService: apiService,
  );
  final stockTransferViewModel = StockTransferViewModel(
    apiService: apiService,
    dbService: dbService,
    prefService: prefService,
  );

  // Warm font glyph cache before any screen builds.
  try {
    GoogleFonts.poppins();
  } catch (_) {}

  runApp(
    MultiProvider(
      providers: [
        Provider<PrefService>.value(value: prefService),
        Provider<ApiService>.value(value: apiService),
        Provider<DbService>.value(value: dbService),
        Provider<FaceRecognitionService>.value(value: faceRecognitionService),
        ChangeNotifierProvider<LocaleService>.value(value: localeService),
        ChangeNotifierProvider<LoginViewModel>(
          lazy: true,
          create: (_) => LoginViewModel(
            apiService: apiService,
            prefService: prefService,
          ),
        ),
        ChangeNotifierProvider<DashboardViewModel>.value(value: dashboardViewModel),
        ChangeNotifierProvider<ProductViewModel>.value(value: productViewModel),
        ChangeNotifierProvider<OrderViewModel>.value(value: orderViewModel),
        ChangeNotifierProvider<DeliveryChallanViewModel>.value(value: deliveryChallanViewModel),
        ChangeNotifierProvider<DailyRateViewModel>.value(value: dailyRateViewModel),
        ChangeNotifierProvider<QuotationViewModel>.value(value: quotationViewModel),
        ChangeNotifierProvider<SampleInViewModel>.value(value: sampleInViewModel),
        ChangeNotifierProvider<SampleOutViewModel>.value(value: sampleOutViewModel),
        ChangeNotifierProvider<StockVerificationViewModel>.value(value: stockVerificationViewModel),
        ChangeNotifierProvider<SingleProductViewModel>(
          lazy: true,
          create: (ctx) => SingleProductViewModel(
            prefService: prefService,
            apiService: apiService,
          ),
        ),
        ChangeNotifierProvider<BulkProductViewModel>(
          lazy: true,
          create: (ctx) => BulkProductViewModel(dbService: dbService),
        ),
        ChangeNotifierProvider<ImportExcelViewModel>(
          lazy: true,
          create: (ctx) => ImportExcelViewModel(
            dbService: dbService,
            apiService: apiService,
            prefService: prefService,
          ),
        ),
        ChangeNotifierProvider<SettingsViewModel>.value(value: settingsViewModel),
        ChangeNotifierProvider<StockTransferViewModel>.value(value: stockTransferViewModel),

      ],
      child: MyApp(prefService: prefService),
    ),
  );

  Future<void>(() async {
    try {
      await dbService.database;
      GoogleFonts.poppins();
    } catch (e, st) {
      debugPrint('DB init deferred error: $e\n$st');
    }
    try {
      await AutoSyncService.initialize();
    } catch (e, st) {
      debugPrint('AutoSync init skipped: $e\n$st');
    }
    try {
      await LocationSyncService.initializeIfEnabled();
    } catch (e, st) {
      debugPrint('LocationSync init skipped: $e\n$st');
    }
    try {
      await OrderSyncService.initializeIfEnabled();
      await OrderSyncService.syncNow();
    } catch (e, st) {
      debugPrint('OrderSync init skipped: $e\n$st');
    }
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
      debugPrint('Tray mode init skipped: $e\n$st');
    }
  });
}

class MyApp extends StatelessWidget {
  final PrefService prefService;

  const MyApp({super.key, required this.prefService});

  @override
  Widget build(BuildContext context) {
    final localeService = context.watch<LocaleService>();
    final bool loggedIn = prefService.isLoggedIn();

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
        textTheme: GoogleFonts.poppinsTextTheme(),
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
