import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../launch_logo.dart';
import '../../services/app_version_service.dart';
import '../force_update_screen.dart';

/// Blocks splash / auto-login / any route until the installed version is allowed.
class AppVersionGate extends StatefulWidget {
  const AppVersionGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppVersionGate> createState() => _AppVersionGateState();
}

class _AppVersionGateState extends State<AppVersionGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<AppVersionService>().check());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final service = context.read<AppVersionService>();
    if (service.needsUpdate) {
      unawaited(service.check(forceRefresh: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppVersionService>();
    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(
          absorbing: !service.isAllowed,
          child: widget.child,
        ),
        if (service.needsUpdate)
          const ForceUpdateScreen()
        else if (service.isChecking)
          const LaunchLogo(),
      ],
    );
  }
}
