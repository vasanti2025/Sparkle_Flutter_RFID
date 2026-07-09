import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/stock_transfer_models.dart';
import 'services/app_warmup_service.dart';
import 'utils/fast_page_route.dart';
import 'viewmodels/dashboard_view_model.dart';
import 'views/add_face_screen.dart';
import 'views/add_product_screen.dart';
import 'views/bulk_product_screen.dart';
import 'views/dashboard_screen.dart';
import 'views/delivery_challan_list_screen.dart';
import 'views/delivery_challan_screen.dart';
import 'views/edit_product_screen.dart';
import 'views/face_login_screen.dart';
import 'views/inventory_menu_screen.dart';
import 'views/location_list_screen.dart';
import 'views/login_screen.dart';
import 'views/order_list_screen.dart';
import 'views/order_screen.dart';
import 'views/privacy_policy_screen.dart';
import 'views/product_list_screen.dart';
import 'views/product_management_screen.dart';
import 'views/quotation_list_screen.dart';
import 'views/quotation_screen.dart';
import 'views/sample_in_list_screen.dart';
import 'views/sample_in_screen.dart';
import 'views/sample_out_list_screen.dart';
import 'views/sample_out_screen.dart';
import 'views/scan_display_screen.dart';
import 'views/scan_to_desktop_screen.dart';
import 'views/search_screen.dart';
import 'views/settings_screen.dart';
import 'views/stock_transfer_detail_screen.dart';
import 'views/stock_transfer_in_out_screen.dart';
import 'views/stock_transfer_preview_screen.dart';
import 'views/stock_transfer_screen.dart';
import 'views/stock_verification_batch_details_screen.dart';
import 'views/stock_verification_detail_screen.dart';
import 'views/stock_verification_report_screen.dart';
import 'views/todays_rate_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Route<dynamic>? generateAppRoute(RouteSettings settings) {
  final page = _buildRoutePage(settings);
  if (page == null) return null;
  return FastPageRoute(settings: settings, child: page);
}

Widget? _buildRoutePage(RouteSettings settings) {
  switch (settings.name) {
    case '/login':
      return const LoginScreen();
    case '/dashboard':
      return const _DashboardRoute();
    case '/face_login':
      return const FaceLoginScreen();
    case '/add_face':
      return const AddFaceScreen();
    case '/privacy_policy':
      return const PrivacyPolicyScreen();
    case '/product_management':
      return const ProductManagementScreen();
    case '/add_product':
      return const AddProductScreen();
    case '/bulk_product':
      return const BulkProductScreen();
    case '/settings':
      return const SettingsScreen();
    case '/location_list':
      return const LocationListScreen();
    case '/product_list':
      return const ProductListScreen();
    case '/edit_product':
      return const EditProductScreen();
    case '/inventory':
      return const InventoryMenuScreen();
    case '/scan_display':
      return const ScanDisplayScreen();
    case '/scan_desktop':
      return const ScanToDesktopScreen();
    case '/search':
      return const SearchScreen();
    case '/order':
      return const OrderScreen();
    case '/order_list':
      return const OrderListScreen();
    case '/delivery_challan_list':
      return const DeliveryChallanListScreen();
    case '/delivery_challan':
      return const DeliveryChallanScreen();
    case '/todays_rate':
      return const TodaysRateScreen();
    case '/quotation':
      return const QuotationScreen();
    case '/quotation_list':
      return const QuotationListScreen();
    case '/sample_out_list':
      return const SampleOutListScreen();
    case '/sample_out':
      return const SampleOutScreen();
    case '/sample_in_list':
      return const SampleInListScreen();
    case '/sample_in':
      return const SampleInScreen();
    case '/stock_transfer':
      return const StockTransferScreen();
    case '/stock_transfer_preview':
      return const StockTransferPreviewScreen();
    case '/stock_transfer_in_out':
      final args = settings.arguments as Map<String, dynamic>?;
      return StockTransferInOutScreen(
        requestType: args?['requestType']?.toString() ?? 'In Request',
      );
    case '/stock_transfer_detail':
      final args = settings.arguments as Map<String, dynamic>?;
      final rawItems = args?['items'];
      final items = <LabelledStockItem>[];
      if (rawItems is List) {
        for (final e in rawItems) {
          if (e is LabelledStockItem) {
            items.add(e);
          } else if (e is Map<String, dynamic>) {
            items.add(LabelledStockItem.fromJson(e));
          }
        }
      }
      return StockTransferDetailScreen(
        requestType: args?['requestType']?.toString() ?? 'In Request',
        transferId: args?['transferId'] as int? ?? 0,
        transferTypeName: args?['transferTypeName']?.toString() ?? '',
        items: items,
      );
    case '/stock_verification_report':
      return const StockVerificationReportScreen();
    case '/report_batch_details':
      final args = settings.arguments as Map<String, dynamic>?;
      return StockVerificationBatchDetailsScreen(
        scanBatchId: args?['scanBatchId']?.toString() ?? '',
      );
    case '/report_detail':
      final args = settings.arguments as Map<String, dynamic>?;
      return StockVerificationDetailScreen(
        branchId: args?['branchId'] as int? ?? 0,
        categoryId: args?['categoryId'] as int? ?? 0,
        productId: args?['productId'] as int? ?? 0,
        designId: args?['designId'] as int? ?? 0,
        type: args?['type']?.toString() ?? 'TOTAL',
        date: args?['date']?.toString() ?? '',
      );
    default:
      return null;
  }
}

class _DashboardRoute extends StatefulWidget {
  const _DashboardRoute();

  @override
  State<_DashboardRoute> createState() => _DashboardRouteState();
}

class _DashboardRouteState extends State<_DashboardRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<DashboardViewModel>(context, listen: false).loadUser();
      AppWarmupService.instance.start(appNavigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) => const DashboardScreen();
}
