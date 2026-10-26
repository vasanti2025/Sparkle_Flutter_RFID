import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_navigator.dart';
import '../l10n/l10n_extension.dart';
import '../services/app_warmup_service.dart' deferred as warmup;
import '../services/location_sync_service.dart';
import '../services/pref_service.dart';
import '../services/rfid_service.dart';
import '../services/session_lifecycle.dart';
import '../utils/app_fonts.dart';
import '../utils/background_location_consent.dart';
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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _navigating = false;
  late final AnimationController _enter;
  late final AnimationController _ambient;

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
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DashboardViewModel>().loadUser();
      unawaited(SessionLifecycle.instance.startMonitoring());
      RfidService().checkBluetoothAfterLogin();
      unawaited(_startWarmup());
      unawaited(_offerBackgroundLocationConsent());
    });
    // Do NOT prefetch all list APIs here — it competes with navigation and
    // freezes/hangs the handheld. Each list screen loads when opened.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _enter.dispose();
    _ambient.dispose();
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

    final drawerItems = [
      ..._drawerExtra.take(1).map((item) => {...item, 'title': _titleForKey(item['key'] as String, s)}),
      ...menuItems,
      ..._drawerExtra.skip(1).map((item) => {...item, 'title': _titleForKey(item['key'] as String, s)}),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedBuilder(
          animation: _ambient,
          builder: (context, child) {
            final t = _ambient.value;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(
                      const Color(0xFF5231A7),
                      const Color(0xFF6B45C4),
                      t,
                    )!,
                    Color.lerp(
                      const Color(0xFFD32940),
                      const Color(0xFFE0455A),
                      1 - t,
                    )!,
                  ],
                  begin: Alignment(-1 + t * 0.3, -1),
                  end: Alignment(1 - t * 0.3, 1),
                ),
              ),
              child: child,
            );
          },
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              s.home,
              style: AppFonts.poppins(
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
                      style: AppFonts.poppins(
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
                      style: AppFonts.poppins(
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
      body: Stack(
        children: [
          // Soft ambient brand blobs (very light — handheld-safe).
          AnimatedBuilder(
            animation: _ambient,
            builder: (context, _) {
              final t = _ambient.value;
              return IgnorePointer(
                child: Stack(
                  children: [
                    Positioned(
                      top: -40 + (18 * t),
                      right: -30 + (12 * (1 - t)),
                      child: _AmbientBlob(
                        size: 160,
                        color: const Color(0xFF5231A7).withValues(alpha: 0.07),
                      ),
                    ),
                    Positioned(
                      bottom: 40 + (10 * (1 - t)),
                      left: -50 + (16 * t),
                      child: _AmbientBlob(
                        size: 190,
                        color: const Color(0xFFD32940).withValues(alpha: 0.06),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _enter,
                    builder: (context, _) {
                      final v = CurvedAnimation(
                        parent: _enter,
                        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
                      ).value;
                      return Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(0, 12 * (1 - v)),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF5231A7).withValues(alpha: 0.28),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                AnimatedBuilder(
                                  animation: _ambient,
                                  builder: (context, child) {
                                    final pulse = 0.92 + (_ambient.value * 0.08);
                                    return Transform.scale(scale: pulse, child: child);
                                  },
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.waving_hand_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        employeeName == null
                                            ? s.home
                                            : '${s.home}, $employeeName',
                                        style: AppFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        s.sparkleRfid,
                                        style: AppFonts.poppins(
                                          color: Colors.white.withValues(alpha: 0.85),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w400,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
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
                            final start = (index * 0.055).clamp(0.0, 0.65);
                            final end = (start + 0.35).clamp(0.0, 1.0);
                            final curved = CurvedAnimation(
                              parent: _enter,
                              curve: Interval(start, end, curve: Curves.easeOutCubic),
                            );
                            return AnimatedBuilder(
                              animation: curved,
                              builder: (context, child) {
                                final v = curved.value;
                                return Opacity(
                                  opacity: v,
                                  child: Transform.translate(
                                    offset: Offset(0, 18 * (1 - v)),
                                    child: Transform.scale(
                                      scale: 0.92 + (0.08 * v),
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              child: _HomeMenuTile(
                                title: item['title'] as String,
                                icon: item['icon'] as IconData,
                                index: index,
                                featured: _isFeaturedCell(item['key'] as String),
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
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: Listenable.merge([_enter, _ambient]),
                    builder: (context, _) {
                      final enter = CurvedAnimation(
                        parent: _enter,
                        curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
                      ).value;
                      final pulse = 0.55 + (0.45 * _ambient.value);
                      return Opacity(
                        opacity: enter,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - enter)),
                          child: ShaderMask(
                            blendMode: BlendMode.srcIn,
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                Color.lerp(
                                  Colors.grey.shade500,
                                  const Color(0xFF5231A7),
                                  pulse * 0.55,
                                )!,
                                Color.lerp(
                                  Colors.grey.shade500,
                                  const Color(0xFFD32940),
                                  pulse * 0.55,
                                )!,
                              ],
                            ).createShader(bounds),
                            child: Text(
                              s.sparkleRfid,
                              style: AppFonts.poppins(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isFeaturedCell(String key) {
    return key == 'product' ||
        key == 'inventory' ||
        key == 'search' ||
        key == 'order' ||
        key == 'stockTransfer';
  }
}

class _AmbientBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _HomeMenuTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final int index;
  final bool featured;
  final VoidCallback onTap;

  const _HomeMenuTile({
    required this.title,
    required this.icon,
    required this.index,
    required this.featured,
    required this.onTap,
  });

  @override
  State<_HomeMenuTile> createState() => _HomeMenuTileState();
}

class _HomeMenuTileState extends State<_HomeMenuTile>
    with TickerProviderStateMixin {
  late final AnimationController _press;
  late final AnimationController _shine;
  late final AnimationController _orbit;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 180),
    );
    // Diagonal light sweep — different timing per cell.
    _shine = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.featured ? 2400 : 3200),
    );
    _orbit = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.featured ? 3600 : 4800),
    );
    final phase = (widget.index % 6) / 6.0;
    _shine.value = phase;
    _orbit.value = (phase + 0.3) % 1.0;
    _shine.repeat();
    if (widget.featured) {
      _orbit.repeat();
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _shine.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_press, _shine, _orbit]),
      builder: (context, _) {
        final press = Curves.easeOut.transform(_press.value);
        // Ease in-out bump so the shine pauses briefly between passes.
        final raw = _shine.value;
        final shineT = Curves.easeInOut.transform(
          raw < 0.7 ? (raw / 0.7) : 0.0,
        );

        return Transform.scale(
          scale: 1.0 - (0.05 * press),
          child: Material(
            color: Colors.white,
            elevation: 3,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onTapDown: (_) => _press.forward(),
              onTapUp: (_) => _press.reverse(),
              onTapCancel: () => _press.reverse(),
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (widget.featured) ...[
                                // Orbiting accent dots around the icon.
                                Transform.rotate(
                                  angle: _orbit.value * 6.283185307179586,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Transform.translate(
                                        offset: const Offset(18, 0),
                                        child: _MiniDot(
                                          color: const Color(0xFF5231A7)
                                              .withValues(alpha: 0.75),
                                        ),
                                      ),
                                      Transform.translate(
                                        offset: const Offset(-14, 10),
                                        child: _MiniDot(
                                          color: const Color(0xFFD32940)
                                              .withValues(alpha: 0.7),
                                          size: 4,
                                        ),
                                      ),
                                      Transform.translate(
                                        offset: const Offset(-8, -14),
                                        child: _MiniDot(
                                          color: const Color(0xFF5231A7)
                                              .withValues(alpha: 0.55),
                                          size: 3.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Soft expanding ring.
                                Transform.scale(
                                  scale: 0.75 + (_orbit.value * 0.45),
                                  child: Opacity(
                                    opacity: (1 - _orbit.value) * 0.45,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFFD32940),
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              GradientIcon(
                                icon: widget.icon,
                                size: 32,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.title,
                          style: AppFonts.poppins(
                            fontSize: 12,
                            fontWeight: widget.featured
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Diagonal shimmer sweep across the cell.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Transform.translate(
                        offset: Offset(-90 + (180 * shineT), -20 + (40 * shineT)),
                        child: Transform.rotate(
                          angle: -0.7,
                          child: Container(
                            width: 28,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(
                                    alpha: widget.featured ? 0.55 : 0.32,
                                  ),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniDot extends StatelessWidget {
  final Color color;
  final double size;

  const _MiniDot({required this.color, this.size = 5});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
