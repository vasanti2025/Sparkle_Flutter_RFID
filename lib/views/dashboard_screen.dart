import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_navigator.dart';
import '../l10n/l10n_extension.dart';
import '../models/stock_verification_report.dart';
import '../services/app_warmup_service.dart' deferred as warmup;
import '../services/bootstrap_channel.dart';
import '../services/db_service.dart';
import '../services/location_sync_service.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../services/session_lifecycle.dart';
import '../utils/app_fonts.dart';
import '../utils/background_location_consent.dart';
import '../session_vm_hooks.dart' deferred as vm_hooks;
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/login_view_model.dart';
import '../viewmodels/stock_verification_view_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool _navigating = false;
  String _appVersion = '';
  int? _labelCount;
  List<({String name, int count})> _stockBars = const [];
  int? _matchQty;
  int? _unmatchQty;

  static const _menuDefs = [
    {'key': 'product', 'icon': Icons.diamond_outlined, 'route': '/product_management'},
    {'key': 'inventory', 'icon': Icons.qr_code_scanner_outlined, 'route': '/inventory'},
    {'key': 'order', 'icon': Icons.receipt_long_outlined, 'route': '/order_list'},
    {'key': 'search', 'icon': Icons.search, 'route': '/search'},
    {'key': 'stockTransfer', 'icon': Icons.swap_horiz, 'route': '/stock_transfer'},
    {'key': 'report', 'icon': Icons.bar_chart_outlined, 'route': '/stock_verification_report'},
    {'key': 'quotations', 'icon': Icons.description_outlined, 'route': '/quotation_list'},
    {'key': 'deliveryChallan', 'icon': Icons.local_shipping_outlined, 'route': '/delivery_challan_list'},
    {'key': 'labelTodayRate', 'icon': Icons.trending_up, 'route': '/todays_rate'},
    {'key': 'sampleIn', 'icon': Icons.login, 'route': '/sample_in_list'},
    {'key': 'sampleOut', 'icon': Icons.logout, 'route': '/sample_out_list'},
    {'key': 'settings', 'icon': Icons.settings_outlined, 'route': '/settings'},
  ];

  static const _drawerExtra = [
    {'key': 'home', 'icon': Icons.home_outlined, 'isHome': true},
    {'key': 'logout', 'icon': Icons.logout, 'isLogout': true},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DashboardViewModel>().loadUser();
      unawaited(SessionLifecycle.instance.startMonitoring());
      RfidService().checkBluetoothAfterLogin();
      unawaited(_startWarmup());
      unawaited(_loadAppVersion());
      unawaited(_loadHomeStats());
      unawaited(Future<void>.delayed(const Duration(seconds: 6), () async {
        if (!mounted) return;
        await _offerBackgroundLocationConsent();
      }));
    });
    // Do NOT prefetch all list APIs here — it competes with navigation and
    // freezes/hangs the handheld. Each list screen loads when opened.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  Future<void> _loadAppVersion() async {
    final version = await BootstrapChannel.getAppVersion();
    if (!mounted || version.isEmpty) return;
    setState(() => _appVersion = version);
  }

  Future<void> _loadHomeStats() async {
    try {
      final db = await context.read<DbService>().database;
      final totalRows = await db.rawQuery('SELECT COUNT(*) AS c FROM bulk_items');
      final total = (totalRows.first['c'] as int?) ??
          int.tryParse('${totalRows.first['c']}') ??
          0;
      final rows = await db.rawQuery(
        "SELECT IFNULL(NULLIF(TRIM(category), ''), '—') AS name, COUNT(*) AS c "
        'FROM bulk_items GROUP BY name ORDER BY c DESC LIMIT 5',
      );
      if (!mounted) return;
      setState(() {
        _labelCount = total;
        _stockBars = [
          for (final row in rows)
            (
              name: '${row['name']}',
              count: (row['c'] as int?) ?? int.tryParse('${row['c']}') ?? 0,
            ),
        ];
      });
    } catch (_) {}

    await Future<void>.delayed(const Duration(seconds: 6));
    if (!mounted) return;
    try {
      final vm = context.read<StockVerificationViewModel>();
      await vm.fetchSessions();
      if (!mounted) return;
      final sessions = vm.sessionList?.sessions ?? const <ReportSessionItem>[];
      if (sessions.isEmpty) return;
      final latest = _latestSession(sessions);
      setState(() {
        _matchQty = latest.matchQty;
        _unmatchQty = latest.unmatchQty;
      });
    } catch (_) {}
  }

  ReportSessionItem _latestSession(List<ReportSessionItem> sessions) {
    ReportSessionItem best = sessions.first;
    DateTime? bestAt = _sessionTime(best);
    for (final session in sessions.skip(1)) {
      final at = _sessionTime(session);
      if (at != null && (bestAt == null || at.isAfter(bestAt))) {
        best = session;
        bestAt = at;
      }
    }
    return best;
  }

  DateTime? _sessionTime(ReportSessionItem session) {
    final ended = DateTime.tryParse(session.endedOn.trim());
    if (ended != null) return ended;
    return DateTime.tryParse(session.startedOn.trim());
  }

  Future<void> _offerBackgroundLocationConsent() async {
    if (!mounted) return;
    final pref = context.read<PrefService>();
    if (!pref.isLoggedIn() || !pref.isLocationSyncEnabled()) return;
    if (pref.isBackgroundLocationConsentGranted()) return;
    final allowed = await BackgroundLocationConsent.request(context);
    if (!mounted) return;
    if (!allowed) {
      await pref.setLocationSyncEnabled(false);
      await LocationSyncService.applySettings(false);
      return;
    }
    await LocationSyncService.initializeIfEnabled();
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
    final gridItems = _gridItems(menuItems);
    final bottomItems = _bottomItems(menuItems);

    final drawerItems = [
      ..._drawerExtra.take(1).map((item) => {...item, 'title': _titleForKey(item['key'] as String, s)}),
      ...menuItems,
      ..._drawerExtra.skip(1).map((item) => {...item, 'title': _titleForKey(item['key'] as String, s)}),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F5F2),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/branding/splash_logo_white.png',
                width: 42,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.sparkleRfid.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: const Color(0xFF20201F),
                    ),
                  ),
                  Text(
                    s.home,
                    style: AppFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                      color: const Color(0xFF20201F),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (barContext) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: const Color(0xFFF3F1EC),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Scaffold.of(barContext).openDrawer(),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.person_outline, color: Color(0xFF20201F)),
                  ),
                ),
              ),
            ),
          ),
        ],
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
                  colors: [Color(0xFF1A1A1A), Color(0xFF3A3228)],
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
                      child: const Icon(Icons.person_outline, color: Color(0xFFC4A35A), size: 24),
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
                      color: const Color(0xFFC4A35A),
                    ),
                    title: Text(
                      item['title'] as String,
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: item['isLogout'] == true && _appVersion.isNotEmpty
                        ? Text(
                            '($_appVersion)',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          )
                        : null,
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: [
              _homeStatRow(context, s),
              const SizedBox(height: 14),
              Expanded(child: _homeGrid(context, s, gridItems)),
              const SizedBox(height: 12),
              _homeBottomRow(context, bottomItems),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, Object>> _gridItems(List<Map<String, Object>> menuItems) {
    const bottom = {'sampleIn', 'sampleOut', 'settings'};
    return [
      for (final item in menuItems)
        if (!bottom.contains(item['key'])) item,
    ];
  }

  List<Map<String, Object>> _bottomItems(List<Map<String, Object>> menuItems) {
    const order = ['sampleIn', 'sampleOut', 'settings'];
    return [
      for (final key in order)
        for (final item in menuItems)
          if (item['key'] == key) item,
    ];
  }

  void _openMenuItem(BuildContext context, Map<String, Object> item, dynamic s) {
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
      return;
    }
    unawaited(_pushNamed(context, route));
  }

  Widget _homeStatRow(BuildContext context, dynamic s) {
    final maxBar = _stockBars.fold<int>(0, (max, bar) {
      return bar.count > max ? bar.count : max;
    });
    return SizedBox(
      height: 148,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF20201E),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.totalLabelStock,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.poppins(
                      color: const Color(0xFFD9D6CE),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _labelCount == null ? '—' : '$_labelCount',
                    style: AppFonts.poppins(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 46,
                    child: _stockBars.isEmpty
                        ? Align(
                            alignment: Alignment.bottomLeft,
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6C477),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < _stockBars.length; i++) ...[
                                if (i > 0) const SizedBox(width: 6),
                                Expanded(
                                  child: Tooltip(
                                    message: _stockBars[i].name,
                                    child: Container(
                                      height: maxBar <= 0
                                          ? 8
                                          : 10 + (36 * _stockBars[i].count / maxBar),
                                      decoration: BoxDecoration(
                                        color: i == 0
                                            ? const Color(0xFFE6C477)
                                            : const Color(0x66E6C477),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: const Color(0xFFF3EFE4),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => unawaited(_pushNamed(context, '/stock_verification_report')),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.lastVerification,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.poppins(
                          color: const Color(0xFF20201F),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const Spacer(),
                      _countLine(s.matched, _matchQty, const Color(0xFF2E7D32)),
                      const SizedBox(height: 4),
                      _countLine(s.unmatched, _unmatchQty, const Color(0xFF8C3A2F)),
                      const SizedBox(height: 8),
                      _matchBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countLine(String label, int? value, Color color) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.poppins(fontSize: 11, color: const Color(0xFF6D6B66)),
          ),
        ),
        Text(
          value == null ? '—' : '$value',
          style: AppFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF20201F),
          ),
        ),
      ],
    );
  }

  Widget _matchBar() {
    final matched = _matchQty ?? 0;
    final unmatched = _unmatchQty ?? 0;
    final total = matched + unmatched;
    final matchFlex = total == 0 ? 1 : matched;
    final unmatchFlex = total == 0 ? 1 : unmatched;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            Expanded(flex: matchFlex == 0 ? 1 : matchFlex, child: const ColoredBox(color: Color(0xFF2E7D32))),
            Expanded(flex: unmatchFlex == 0 ? 1 : unmatchFlex, child: const ColoredBox(color: Color(0xFFC4A35A))),
          ],
        ),
      ),
    );
  }

  Widget _homeGrid(BuildContext context, dynamic s, List<Map<String, Object>> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var crossAxisCount = 3;
        if (width < 280) crossAxisCount = 2;
        if (width > 700) crossAxisCount = 4;
        return GridView.builder(
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.05,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openMenuItem(context, item, s),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8E5DF)),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item['icon'] as IconData,
                        size: 26,
                        color: const Color(0xFF866526),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item['title'] as String,
                        style: AppFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF20201F),
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
    );
  }

  Widget _homeBottomRow(BuildContext context, List<Map<String, Object>> items) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: const Color(0xFFF3F1EC),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openMenuItem(context, items[i], context.s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  child: Text(
                    items[i]['title'] as String,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF20201F),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
