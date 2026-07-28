import 'package:flutter/material.dart';

/// Short fade so the tap feels instant while the next screen prepares.
/// Zero-duration routes made heavy first frames feel like freezes/hangs.
class FastPageRoute<T> extends PageRouteBuilder<T> {
  FastPageRoute({
    required RouteSettings settings,
    required Widget child,
  }) : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: const Duration(milliseconds: 100),
          reverseTransitionDuration: const Duration(milliseconds: 80),
          opaque: true,
          barrierDismissible: false,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
              child: child,
            );
          },
        );
}
