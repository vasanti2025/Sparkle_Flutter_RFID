import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../services/pref_service.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

class TutorialSlide {
  const TutorialSlide({
    required this.asset,
    required this.titleKey,
    required this.descKey,
  });

  final String asset;
  final String titleKey;
  final String descKey;
}

class TutorialPagerScreen extends StatefulWidget {
  const TutorialPagerScreen({super.key, required this.continueToDashboard});

  final bool continueToDashboard;

  @override
  State<TutorialPagerScreen> createState() => _TutorialPagerScreenState();
}

class _TutorialPagerScreenState extends State<TutorialPagerScreen> {
  static const _slides = [
    TutorialSlide(
      asset: 'assets/tutorial/slide_1.webp',
      titleKey: 'tutorialScanTitle',
      descKey: 'tutorialScanDesc',
    ),
    TutorialSlide(
      asset: 'assets/tutorial/slide_2.webp',
      titleKey: 'tutorialSecurityTitle',
      descKey: 'tutorialSecurityDesc',
    ),
    TutorialSlide(
      asset: 'assets/tutorial/slide_3.jpg',
      titleKey: 'tutorialInventoryTitle',
      descKey: 'tutorialInventoryDesc',
    ),
    TutorialSlide(
      asset: 'assets/tutorial/slide_4.jpg',
      titleKey: 'tutorialVaultTitle',
      descKey: 'tutorialVaultDesc',
    ),
  ];

  final PageController _pageController = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _index >= _slides.length - 1;

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      await context.read<PrefService>().setOnboardingTutorialSeen(true);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => widget.continueToDashboard
            ? const DashboardScreen()
            : const LoginScreen(),
      ),
    );
  }

  void _next() {
    if (_isLast) {
      unawaited(_finish());
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final slide = _slides[i];
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    slide.asset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black26,
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black87,
                        ],
                        stops: [0, 0.22, 0.55, 1],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: TextButton(
                      onPressed: () => unawaited(_finish()),
                      child: Text(
                        s.skip,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    s.tr(_slides[_index].titleKey),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.tr(_slides[_index].descKey),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final selected = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: selected ? 22 : 8,
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFFD32940) : Colors.white38,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _next,
                          child: Center(
                            child: Text(
                              _isLast ? s.getStarted : s.next,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget launchHomeScreen({
  required PrefService pref,
  required bool loggedIn,
}) {
  if (!pref.hasSeenOnboardingTutorial()) {
    return TutorialPagerScreen(continueToDashboard: loggedIn);
  }
  return loggedIn ? const DashboardScreen() : const LoginScreen();
}
