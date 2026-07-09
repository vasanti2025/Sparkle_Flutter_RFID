import 'package:flutter/material.dart';

/// No animation — screen appears on the same frame as the tap.
class FastPageRoute<T> extends PageRouteBuilder<T> {
  FastPageRoute({
    required RouteSettings settings,
    required Widget child,
  }) : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
        );
}
