import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/db_service.dart';
import '../services/rfid_service.dart';

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
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    try {
      final db = ctx.read<DbService>();
      await db.database;
      unawaited(RfidService().preWarmReader());
    } catch (_) {}
  }
}
