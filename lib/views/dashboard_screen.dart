import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:showcaseview/showcaseview.dart';
import '../app_navigator.dart';
import '../l10n/app_strings.dart';
import '../l10n/l10n_extension.dart';
import '../services/app_warmup_service.dart' deferred as warmup;
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../services/session_lifecycle.dart';
import '../session_vm_hooks.dart' deferred as vm_hooks;
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/login_view_model.dart';
import 'widgets/gradient_icon.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const _showcaseScope = 'home_dashboard';

  bool _navigating = false;
  bool _homeShowcaseStarted = false;
  ShowcaseView? _showcaseView;
  String _appVersion = '';

  final GlobalKey _howToUseKey = GlobalKey();
  final GlobalKey _productKey = GlobalKey();
  final GlobalKey _inventoryKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();

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
    WidgetsBinding.instance.addObserver(this);
    _registerHomeShowcase();
    unawaited(_loadAppVersion());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DashboardViewModel>().loadUser();
      unawaited(SessionLifecycle.instance.startMonitoring());
      RfidService().checkBluetoothAfterLogin();
      unawaited(_startWarmup());
      _startHomeShowcaseIfNeeded();
    });
    // Do NOT prefetch all list APIs here — it competes with navigation and
    // freezes/hangs the handheld. Each list screen loads when opened.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _showcaseView?.unregister();
    super.dispose();
  }

  void _registerHomeShowcase() {
    final lang = PrefService.instanceOrNull?.getAppLanguage() ?? 'en';
    final s = AppStrings.of(lang);
    _showcaseView = ShowcaseView.register(
      scope: _showcaseScope,
      enableAutoScroll: true,
      disableMovingAnimation: true,
      blurValue: 1,
      globalTooltipActionConfig: const TooltipActionConfig(
        position: TooltipActionPosition.inside,
        alignment: MainAxisAlignment.spaceBetween,
        actionGap: 12,
      ),
      globalTooltipActions: [
        TooltipActionButton(
          type: TooltipDefaultActionType.skip,
          name: s.skip,
          textStyle: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        TooltipActionButton(
          type: TooltipDefaultActionType.next,
          textStyle: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ],
    );
  }

  void _startHomeShowcaseIfNeeded() {
    if (!mounted || _homeShowcaseStarted) return;
    PrefService? pref = PrefService.instanceOrNull;
    if (pref == null && context.mounted) {
      try {
        pref = context.read<PrefService>();
      } catch (_) {
        return;
      }
    }
    if (pref == null || pref.hasSeenHomeShowcase()) return;

    _homeShowcaseStarted = true;
    unawaited(pref.setHomeShowcaseSeen(true));
    _showcaseView?.startShowCase(
      [
        _howToUseKey,
        _productKey,
        _inventoryKey,
        _searchKey,
        _settingsKey,
      ],
      delay: const Duration(milliseconds: 400),
    );
  }

  String _showcaseDesc(String key, dynamic s) {
    switch (key) {
      case 'product':
        return s.showcaseProductDesc as String;
      case 'inventory':
        return s.showcaseInventoryDesc as String;
      case 'search':
        return s.showcaseSearchDesc as String;
      case 'settings':
        return s.showcaseSettingsDesc as String;
      default:
        return '';
    }
  }

  GlobalKey? _showcaseKeyFor(String key) {
    switch (key) {
      case 'product':
        return _productKey;
      case 'inventory':
        return _inventoryKey;
      case 'search':
        return _searchKey;
      case 'settings':
        return _settingsKey;
      default:
        return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(SessionLifecycle.instance.checkAndEnforce());
      try {
        context.read<DashboardViewModel>().loadUser();
      } catch (_) {}
    }
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
    final isStockTransfer = route == '/stock_transfer';
    if (isStockTransfer) {
      _resetStockTransferForm(context);
    }
    _navigating = true;
    try {
      await Navigator.pushNamed(context, route, arguments: arguments);
    } finally {
      if (isStockTransfer) {
        _resetStockTransferForm(context);
      }
      if (mounted) _navigating = false;
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final version = info.version.trim();
      if (version.isEmpty) return;
      setState(() => _appVersion = 'v$version');
    } catch (_) {}
  }

  Future<void> _startWarmup() async {
    try {
      await warmup.loadLibrary();
      if (!mounted) return;
      warmup.AppWarmupService.instance.start(appNavigatorKey);
    } catch (_) {}
  }

  void _resetStockTransferForm(BuildContext context) {
    unawaited(() async {
      try {
        await vm_hooks.loadLibrary();
        if (!context.mounted) return;
        vm_hooks.resetStockTransferForm(context);
      } catch (_) {}
    }());
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
      (vm) {
        final e = vm.employee;
        if (e == null) return null;
        final name = (e.username ?? e.userName ?? '').trim();
        return name.isEmpty ? null : name;
      },
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              Showcase(
                key: _howToUseKey,
                scope: _showcaseScope,
                title: s.howToUse,
                description: s.showcaseHowToUseDesc,
                tooltipBackgroundColor: Colors.white,
                targetBorderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: () => unawaited(_pushNamed(context, '/how_to_use')),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.ondemand_video, size: 18),
                    label: Text(
                      s.howToUse,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
                        final nav = Navigator.of(context, rootNavigator: true);
                        Navigator.pop(context);
                        SessionLifecycle.instance.stopMonitoring();
                        try {
                          await vm_hooks.loadLibrary();
                          if (context.mounted) {
                            await vm_hooks.resetProductAndStockForLogout(context);
                          }
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
                        final menuKey = item['key'] as String;
                        final card = Card(
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
                                    style: const TextStyle(
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
                        final showcaseKey = _showcaseKeyFor(menuKey);
                        if (showcaseKey == null) return card;
                        return Showcase(
                          key: showcaseKey,
                          scope: _showcaseScope,
                          title: item['title'] as String,
                          description: _showcaseDesc(menuKey, s),
                          tooltipBackgroundColor: Colors.white,
                          targetBorderRadius: BorderRadius.circular(12),
                          child: card,
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
              if (_appVersion.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _appVersion,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
