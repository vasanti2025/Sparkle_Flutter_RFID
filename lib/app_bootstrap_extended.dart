import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'app_routes.dart';
import 'services/api_service.dart';
import 'services/db_service.dart';
import 'services/pref_service.dart';
import 'viewmodels/bulk_product_view_model.dart';
import 'viewmodels/daily_rate_view_model.dart';
import 'viewmodels/delivery_challan_view_model.dart';
import 'viewmodels/import_excel_view_model.dart';
import 'viewmodels/order_view_model.dart';
import 'viewmodels/product_view_model.dart';
import 'viewmodels/quotation_view_model.dart';
import 'viewmodels/sample_in_view_model.dart';
import 'viewmodels/sample_out_view_model.dart';
import 'viewmodels/settings_view_model.dart';
import 'viewmodels/single_product_view_model.dart';
import 'viewmodels/stock_transfer_view_model.dart';
import 'viewmodels/stock_verification_view_model.dart';

/// Remaining ViewModels — loaded after Login/Dashboard first frame.
List<SingleChildWidget> buildExtendedProviders({
  required PrefService prefService,
  required ApiService apiService,
  required DbService dbService,
}) {
  return [
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
  ];
}

/// Wraps [child] with extended providers using startup services from context.
class ExtendedProvidersScope extends StatelessWidget {
  final Widget child;

  const ExtendedProvidersScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: buildExtendedProviders(
        prefService: context.read<PrefService>(),
        apiService: context.read<ApiService>(),
        dbService: context.read<DbService>(),
      ),
      child: child,
    );
  }
}

Route<dynamic>? Function(RouteSettings settings) get routeGenerator => generateAppRoute;
