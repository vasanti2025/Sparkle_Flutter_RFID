import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_navigator.dart';
import '../l10n/l10n_extension.dart';
import '../services/app_warmup_service.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/login_view_model.dart';
import '../viewmodels/product_view_model.dart';
import '../viewmodels/stock_transfer_view_model.dart';
import 'widgets/gradient_icon.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _navigating = false;

  static const _menuDefs = [
    {'key': 'product', 'icon': Icons.shopping_bag, 'route': '/product_management'},
    {'key': 'inventory', 'icon': Icons.layers, 'route': '/inventory'},
    {'key': 'order', 'icon': Icons.receipt_long, 'route': '/order_list'},
    {'key': 'search', 'icon': Icons.search, 'route': '/search'},
    {'key': 'stockTransfer', 'icon': Icons.swap_horiz, 'route': '/stock_transfer'},
    {'key': 'report', 'icon': Icons.assessment, 'route': '/stock_verification_report'},
    {'key': 'quotations', 'icon': Icons.description, 'route': '/quotation_list'},
    {'key': 'deliveryChallan', 'icon': Icons.local_shipping, 'route': '/delivery_challan_list'},
    {'key': 'labelTodayRate', 'icon': Icons.trending_up, 'route': '/todays_rate'},
    {'key': 'sampleIn', 'icon': Icons.login, 'route': '/sample_in_list'},
    {'key': 'sampleOut', 'icon': Icons.logout, 'route': '/sample_out_list'},
    {'key': 'settings', 'icon': Icons.settings, 'route': '/settings'},
  ];

  static const _drawerExtra = [
    {'key': 'home', 'icon': Icons.home, 'isHome': true},
    {'key': 'logout', 'icon': Icons.exit_to_app, 'isLogout': true},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DashboardViewModel>().loadUser();
      AppWarmupService.instance.start(appNavigatorKey);
    });
    // Do NOT prefetch all list APIs here — it competes with navigation and
    // freezes/hangs the handheld. Each list screen loads when opened.
  }

  String _titleForKey(String key, dynamic s) {
    switch (key) {
      case 'product':
        return s.product;
      case 'inventory':
        return s.inventory;
      case 'order':
        return s.order;
      case 'search':
        return s.search;
      case 'stockTransfer':
        return s.stockTransfer;
      case 'report':
        return s.report;
      case 'quotations':
        return s.quotations;
      case 'deliveryChallan':
        return s.deliveryChallan;
      case 'labelTodayRate':
        return s.labelTodayRate;
      case 'sampleIn':
        return s.sampleIn;
      case 'sampleOut':
        return s.sampleOut;
      case 'settings':
        return s.settings;
      case 'home':
        return s.home;
      case 'logout':
        return s.logout;
      default:
        return key;
    }
  }

  Future<void> _pushNamed(BuildContext context, String route, [Object? arguments]) async {
    if (_navigating || !mounted) return;
    _navigating = true;
    try {
      await Navigator.pushNamed(context, route, arguments: arguments);
    } finally {
      if (mounted) _navigating = false;
    }
  }

  void _navigateByKey(BuildContext context, String key, dynamic s) {
    switch (key) {
      case 'product':
        unawaited(_pushNamed(context, '/product_management'));
      case 'inventory':
        unawaited(_pushNamed(context, '/inventory'));
      case 'order':
        unawaited(_pushNamed(context, '/order_list'));
      case 'search':
        unawaited(_pushNamed(context, '/search', {
          'listKey': 'normal',
          'items': const [],
        }));
      case 'deliveryChallan':
        unawaited(_pushNamed(context, '/delivery_challan_list'));
      case 'quotations':
        unawaited(_pushNamed(context, '/quotation_list'));
      case 'sampleIn':
        unawaited(_pushNamed(context, '/sample_in_list'));
      case 'sampleOut':
        unawaited(_pushNamed(context, '/sample_out_list'));
      case 'report':
        unawaited(_pushNamed(context, '/stock_verification_report'));
      case 'labelTodayRate':
        unawaited(_pushNamed(context, '/todays_rate'));
      case 'settings':
        unawaited(_pushNamed(context, '/settings'));
      case 'stockTransfer':
        unawaited(_pushNamed(context, '/stock_transfer'));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final employeeName = context.select<DashboardViewModel, String?>(
      (vm) => vm.employee?.username,
    );

    final menuItems = _menuDefs
        .map((item) => {
              ...item,
              'title': _titleForKey(item['key'] as String, s),
            })
        .toList();

    final drawerItems = [
      ..._drawerExtra.take(1).map((item) => {...item, 'title': _titleForKey(item['key'] as String, s)}),
      ...menuItems,
      ..._drawerExtra.skip(1).map((item) => {...item, 'title': _titleForKey(item['key'] as String, s)}),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              s.home,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
        ),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              height: 140,
              padding: const EdgeInsets.only(left: 16, bottom: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF315BA3), Color(0xFFA7192E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.white24,
                      radius: 20,
                      child: Icon(Icons.person, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      employeeName ?? s.user,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Scrollable Drawer Items
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: drawerItems.length,
                itemBuilder: (context, index) {
                  final item = drawerItems[index];
                  return ListTile(
                    leading: Icon(
                      item['icon'] as IconData,
                      color: Colors.grey[700],
                    ),
                    title: Text(
                      item['title'] as String,
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () async {
                      if (item['isLogout'] == true) {
                        final dashVm = context.read<DashboardViewModel>();
                        final loginVm = context.read<LoginViewModel>();
                        ProductViewModel? productVm;
                        StockTransferViewModel? stockVm;
                        try {
                          productVm = context.read<ProductViewModel>();
                        } catch (_) {}
                        try {
                          stockVm = context.read<StockTransferViewModel>();
                        } catch (_) {}
                        final nav = Navigator.of(context, rootNavigator: true);
                        Navigator.pop(context);
                        try {
                          await productVm?.resetForLogout();
                        } catch (_) {}
                        try {
                          stockVm?.resetSession();
                        } catch (_) {}
                        await dashVm.logout();
                        loginVm.reloadRememberMe();
                        nav.pushNamedAndRemoveUntil('/login', (_) => false);
                      } else if (item['isHome'] == true) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pop(context);
                        _navigateByKey(context, item['key'] as String, s);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // Determine column count based on screen width
                    int crossAxisCount = 3;
                    if (width < 328) {
                      crossAxisCount = 2;
                    } else if (width > 900) {
                      crossAxisCount = 6;
                    } else if (width > 600) {
                      crossAxisCount = 5;
                    } else if (width > 400) {
                      crossAxisCount = 4;
                    }

                    return GridView.builder(
                      itemCount: menuItems.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.0,
                      ),
                      itemBuilder: (context, index) {
                        final item = menuItems[index];
                        return Card(
                          color: Colors.white,
                          elevation: 4,
                          shadowColor: Colors.black26,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: () {
                              final route = item['route'] as String?;
                              if (route == null || route == '/coming_soon') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${item['title']} - ${s.comingSoon}'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                                return;
                              }
                              if (route == '/search') {
                                unawaited(_pushNamed(context, '/search', {
                                  'listKey': 'normal',
                                  'items': const [],
                                }));
                              } else {
                                unawaited(_pushNamed(context, route));
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GradientIcon(
                                    icon: item['icon'] as IconData,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item['title'] as String,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Bottom Brand Logo Text
              const SizedBox(height: 12),
              Text(
                s.sparkleRfid,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
