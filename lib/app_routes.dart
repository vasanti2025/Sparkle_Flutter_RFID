import 'package:flutter/material.dart';

import 'models/stock_transfer_models.dart';
import 'utils/deferred_screen.dart';
import 'utils/fast_page_route.dart';
import 'views/dashboard_screen.dart';
import 'views/login_screen.dart';

import 'views/add_product_screen.dart';
import 'views/bulk_product_screen.dart';
import 'views/inventory_menu_screen.dart';
import 'views/product_list_screen.dart';
import 'views/product_management_screen.dart';
import 'views/scan_display_screen.dart';

import 'views/add_face_screen.dart' deferred as add_face;
import 'views/delivery_challan_list_screen.dart' deferred as delivery_challan_list;
import 'views/delivery_challan_screen.dart' deferred as delivery_challan;
import 'views/edit_product_screen.dart' deferred as edit_product;
import 'views/face_login_screen.dart' deferred as face_login;
import 'views/location_list_screen.dart' deferred as location_list;
import 'views/order_list_screen.dart' deferred as order_list;
import 'views/order_screen.dart' deferred as order;
import 'views/privacy_policy_screen.dart' deferred as privacy_policy;
import 'views/quotation_list_screen.dart' deferred as quotation_list;
import 'views/quotation_screen.dart' deferred as quotation;
import 'views/sample_in_list_screen.dart' deferred as sample_in_list;
import 'views/sample_in_screen.dart' deferred as sample_in;
import 'views/sample_out_list_screen.dart' deferred as sample_out_list;
import 'views/sample_out_screen.dart' deferred as sample_out;
import 'views/scan_to_desktop_screen.dart' deferred as scan_desktop;
import 'views/search_screen.dart' deferred as search;
import 'views/settings_screen.dart' deferred as settings_screen;
import 'views/stock_transfer_detail_screen.dart' deferred as stock_transfer_detail;
import 'views/stock_transfer_in_out_screen.dart' deferred as stock_transfer_in_out;
import 'views/stock_transfer_preview_screen.dart' deferred as stock_transfer_preview;
import 'views/stock_transfer_screen.dart' deferred as stock_transfer;
import 'views/stock_verification_batch_details_screen.dart' deferred as stock_verification_batch_details;
import 'views/stock_verification_detail_screen.dart' deferred as stock_verification_detail;
import 'views/stock_verification_report_screen.dart' deferred as stock_verification_report;
import 'views/todays_rate_screen.dart' deferred as todays_rate;

export 'app_navigator.dart';

Route<dynamic>? generateAppRoute(RouteSettings settings) {
  final page = _buildRoutePage(settings);
  if (page == null) return null;
  return FastPageRoute(settings: settings, child: page);
}

Widget _defer(Future<void> Function() load, Widget Function() builder) {
  return DeferredScreen(loadLibrary: load, builder: builder);
}

Widget? _buildRoutePage(RouteSettings settings) {
  switch (settings.name) {
    case '/login':
      return const LoginScreen();
    case '/dashboard':
      return const DashboardScreen();
    case '/face_login':
      return _defer(face_login.loadLibrary, () => face_login.FaceLoginScreen());
    case '/add_face':
      return _defer(add_face.loadLibrary, () => add_face.AddFaceScreen());
    case '/privacy_policy':
      return _defer(privacy_policy.loadLibrary, () => privacy_policy.PrivacyPolicyScreen());
    case '/product_management':
      return const ProductManagementScreen();
    case '/add_product':
      return const AddProductScreen();
    case '/bulk_product':
      return const BulkProductScreen();
    case '/settings':
      return _defer(settings_screen.loadLibrary, () => settings_screen.SettingsScreen());
    case '/location_list':
      return _defer(location_list.loadLibrary, () => location_list.LocationListScreen());
    case '/product_list':
      return const ProductListScreen();
    case '/edit_product':
      return _defer(edit_product.loadLibrary, () => edit_product.EditProductScreen());
    case '/inventory':
      return const InventoryMenuScreen();
    case '/scan_display':
      return const ScanDisplayScreen();
    case '/scan_desktop':
      return _defer(scan_desktop.loadLibrary, () => scan_desktop.ScanToDesktopScreen());
    case '/search':
      return _defer(search.loadLibrary, () => search.SearchScreen());
    case '/order':
      return _defer(order.loadLibrary, () => order.OrderScreen());
    case '/order_list':
      return _defer(order_list.loadLibrary, () => order_list.OrderListScreen());
    case '/delivery_challan_list':
      return _defer(delivery_challan_list.loadLibrary, () => delivery_challan_list.DeliveryChallanListScreen());
    case '/delivery_challan':
      return _defer(delivery_challan.loadLibrary, () => delivery_challan.DeliveryChallanScreen());
    case '/todays_rate':
      return _defer(todays_rate.loadLibrary, () => todays_rate.TodaysRateScreen());
    case '/quotation':
      return _defer(quotation.loadLibrary, () => quotation.QuotationScreen());
    case '/quotation_list':
      return _defer(quotation_list.loadLibrary, () => quotation_list.QuotationListScreen());
    case '/sample_out_list':
      return _defer(sample_out_list.loadLibrary, () => sample_out_list.SampleOutListScreen());
    case '/sample_out':
      return _defer(sample_out.loadLibrary, () => sample_out.SampleOutScreen());
    case '/sample_in_list':
      return _defer(sample_in_list.loadLibrary, () => sample_in_list.SampleInListScreen());
    case '/sample_in':
      return _defer(sample_in.loadLibrary, () => sample_in.SampleInScreen());
    case '/stock_transfer':
      return _defer(stock_transfer.loadLibrary, () => stock_transfer.StockTransferScreen());
    case '/stock_transfer_preview':
      return _defer(stock_transfer_preview.loadLibrary, () => stock_transfer_preview.StockTransferPreviewScreen());
    case '/stock_transfer_in_out':
      final args = settings.arguments as Map<String, dynamic>?;
      return _defer(
        stock_transfer_in_out.loadLibrary,
        () => stock_transfer_in_out.StockTransferInOutScreen(
          requestType: args?['requestType']?.toString() ?? 'In Request',
        ),
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
      return _defer(
        stock_transfer_detail.loadLibrary,
        () => stock_transfer_detail.StockTransferDetailScreen(
          requestType: args?['requestType']?.toString() ?? 'In Request',
          transferId: args?['transferId'] as int? ?? 0,
          transferTypeName: args?['transferTypeName']?.toString() ?? '',
          items: items,
          isSelfApproval: args?['isSelfApproval'] == true,
        ),
      );
    case '/stock_verification_report':
      return _defer(
        stock_verification_report.loadLibrary,
        () => stock_verification_report.StockVerificationReportScreen(),
      );
    case '/report_batch_details':
      final args = settings.arguments as Map<String, dynamic>?;
      return _defer(
        stock_verification_batch_details.loadLibrary,
        () => stock_verification_batch_details.StockVerificationBatchDetailsScreen(
          scanBatchId: args?['scanBatchId']?.toString() ?? '',
        ),
      );
    case '/report_detail':
      final args = settings.arguments as Map<String, dynamic>?;
      return _defer(
        stock_verification_detail.loadLibrary,
        () => stock_verification_detail.StockVerificationDetailScreen(
          branchId: args?['branchId'] as int? ?? 0,
          categoryId: args?['categoryId'] as int? ?? 0,
          productId: args?['productId'] as int? ?? 0,
          designId: args?['designId'] as int? ?? 0,
          type: args?['type']?.toString() ?? 'TOTAL',
          date: args?['date']?.toString() ?? '',
        ),
      );
    default:
      return null;
  }
}
