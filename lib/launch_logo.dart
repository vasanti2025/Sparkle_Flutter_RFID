import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'l10n/l10n_extension.dart';
import 'utils/app_fonts.dart';
import 'views/login_screen.dart';

/// Splash matching the brand screen: larger centered logo and taglines,
/// company lines centered at the bottom.
class LaunchLogo extends StatelessWidget {
  const LaunchLogo({super.key});

  static const Color background = Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return ColoredBox(
      color: background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final logoW = math.min(w * 0.52, math.min(200.0, h * 0.36));
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: (h - logoW) / 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image(
                        image: const AssetImage(
                          'assets/branding/splash_logo_white.png',
                        ),
                        width: logoW,
                        height: logoW,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.splashTagline,
                        textAlign: TextAlign.center,
                        style: AppFonts.poppins(
                          color: const Color(0xFFD9D6CE),
                          fontSize: 16,
                          height: 1.4,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        s.splashTaglineStrong,
                        textAlign: TextAlign.center,
                        style: AppFonts.poppins(
                          color: const Color(0xFFE6C477),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.splashFooter1,
                        textAlign: TextAlign.center,
                        style: AppFonts.poppins(
                          color: const Color(0xFF96938C),
                          fontSize: 12,
                          height: 1.45,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        s.splashFooter2,
                        textAlign: TextAlign.center,
                        style: AppFonts.poppins(
                          color: const Color(0xFF96938C),
                          fontSize: 12,
                          height: 1.45,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

}

/// Shows the brand splash, then the real sign-in screen.
class LoginSplashGate extends StatefulWidget {
  const LoginSplashGate({super.key});

  @override
  State<LoginSplashGate> createState() => _LoginSplashGateState();
}

class _LoginSplashGateState extends State<LoginSplashGate> {
  bool _showLogin = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _showLogin = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showLogin) return const LaunchLogo();
    return const LoginScreen();
  }
}
