import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'db_service.dart';
import 'order_offline_service.dart';
import 'pref_service.dart';

class OrderSyncRunner {
  static Future<int> runOnce() async {
    final prefService = await PrefService.init();
    if (!prefService.isLoggedIn()) return 0;

    final api = ApiService(prefService);
    final db = DbService();
    final offline = OrderOfflineService(
      dbService: db,
      apiService: api,
      prefService: prefService,
    );

    final count = await offline.syncAll();
    if (count > 0) {
      debugPrint('OrderSyncRunner: synced $count pending item(s)');
    }
    return count;
  }
}
