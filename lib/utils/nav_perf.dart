import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Runs [action] after the current route transition finishes so list screens
/// can defer heavy sync/API work until the push animation completes.
void runAfterRouteSettled(BuildContext context, VoidCallback action) {
  final animation = ModalRoute.of(context)?.animation;
  if (animation == null || animation.status == AnimationStatus.completed) {
    SchedulerBinding.instance.scheduleFrameCallback((_) => action());
    return;
  }

  void onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      animation.removeStatusListener(onStatus);
      SchedulerBinding.instance.scheduleFrameCallback((_) => action());
    }
  }

  animation.addStatusListener(onStatus);
}
