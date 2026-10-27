import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';

/// Keeps DB + scan index hot after dashboard is shown.
class AppWarmupService {
  AppWarmupService._();
  static final AppWarmupService instance = AppWarmupService._();

  bool _started = false;

  void start(GlobalKey<NavigatorState> navigatorKey) {
    if (_started) return;
    _started = true;
    unawaited(_warmDatabase(navigatorKey));
  }

  Future<void> _warmDatabase(GlobalKey<NavigatorState> navigatorKey) async {
    // Avoid competing with first dashboard paint. Opening the database at
    // 2 seconds overlapped that paint and closed the app on some runs.
    await Future<void>.delayed(const Duration(seconds: 8));
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    try {
      final db = ctx.read<DbService>();
      await db.database;
    } catch (_) {}
  }
}
