import 'package:flutter/material.dart';

/// App page route: polished fade-through + soft lift (no heavy Material zoom).
class FastPageRoute<T> extends PageRouteBuilder<T> {
  FastPageRoute({
    required RouteSettings settings,
    required Widget child,
  }) : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: const Duration(milliseconds: 340),
          reverseTransitionDuration: const Duration(milliseconds: 280),
          opaque: true,
          barrierDismissible: false,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return buildAppPageTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              child: child,
            );
          },
        );
}

/// Shared enter/exit transition used by [FastPageRoute] and theme builders.
Widget buildAppPageTransition({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
}) {
  final enter = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  final cover = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  // This route entering (or popping back in).
  final slideIn = Tween<Offset>(
    begin: const Offset(0, 0.05),
    end: Offset.zero,
  ).animate(enter);
  final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
    CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    ),
  );
  final scaleIn = Tween<double>(begin: 0.965, end: 1.0).animate(enter);

  // This route covered by another page on top.
  final slideCover = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(0, -0.025),
  ).animate(cover);
  final fadeCover = Tween<double>(begin: 1.0, end: 0.85).animate(cover);
  final scaleCover = Tween<double>(begin: 1.0, end: 0.98).animate(cover);

  // Brand veil only while entering forward.
  final veilOpacity = Tween<double>(begin: 0.16, end: 0.0).animate(
    CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    ),
  );

  return SlideTransition(
    position: slideCover,
    child: FadeTransition(
      opacity: fadeCover,
      child: ScaleTransition(
        scale: scaleCover,
        child: SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: fadeIn,
            child: ScaleTransition(
              scale: scaleIn,
              alignment: Alignment.bottomCenter,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  child,
                  IgnorePointer(
                    child: FadeTransition(
                      opacity: veilOpacity,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF5231A7),
                              Color(0xFFD32940),
                            ],
                          ),
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Same as [FastPageRoute] for push calls that build the page inline.
PageRoute<T> instantRoute<T>({
  required RouteSettings settings,
  required Widget child,
}) {
  return FastPageRoute<T>(settings: settings, child: child);
}
