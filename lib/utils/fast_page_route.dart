import 'package:flutter/material.dart';

/// Instant route — no zoom/fade that feels like a scale animation on Android.
class FastPageRoute<T> extends PageRouteBuilder<T> {
  FastPageRoute({
    required RouteSettings settings,
    required Widget child,
  }) : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          opaque: true,
          barrierDismissible: false,
          transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
        );
}

/// Same as [FastPageRoute] for push calls that build the page inline.
PageRoute<T> instantRoute<T>({
  required RouteSettings settings,
  required Widget child,
}) {
  return FastPageRoute<T>(settings: settings, child: child);
}
