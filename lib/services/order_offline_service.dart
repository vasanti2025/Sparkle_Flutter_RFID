import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import 'api_service.dart';
import 'db_service.dart';
import 'order_payload_builder.dart';
import 'pref_service.dart';

/// Offline storage + sync queue for the Order module.
class OrderOfflineService {
  final DbService _dbService;
  final ApiService _apiService;
  final PrefService _prefService;

  OrderOfflineService({
    required DbService dbService,
    required ApiService apiService,
    required PrefService prefService,
  })  : _dbService = dbService,
        _apiService = apiService,
        _prefService = prefService;

  /// Parses last order number from API (handles String/int and key variants).
  static int parseLastOrderNoResponse(Map<String, dynamic>? res) {
    if (res == null) return 0;
    for (final key in ['LastOrderNo', 'lastOrderNo', 'OrderNo', 'orderNo']) {
      final v = res[key];
      if (v == null) continue;
      final n = int.tryParse(v.toString().trim());
      if (n != null && n >= 0) return n;
    }
    return 0;
  }

  /// Next assignable order number after the last one used on server.
  static int nextOrderNoFromLastUsed(int lastUsed) {
    return lastUsed > 0 ? lastUsed + 1 : 1;
  }

  /// Resolves the next order number from cache, pending queue, and API.
  Future<int> resolveNextOrderNo(String clientCode) async {
    var candidate = 1;

    final cache = await loadMasterCache(clientCode);
    if (cache != null && cache.lastOrderNo > 0) {
      candidate = cache.lastOrderNo;
    }

    final pendingRows = await _dbService.getPendingOrders(clientCode);
    for (final row in pendingRows) {
      final fromRow = int.tryParse(row['order_no']?.toString() ?? '') ?? 0;
      if (fromRow >= candidate) candidate = fromRow + 1;

      try {
        final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
        final fromPayload = int.tryParse(payload['OrderNo']?.toString() ?? '') ?? 0;
        if (fromPayload >= candidate) candidate = fromPayload + 1;
      } catch (_) {}
    }

    if (await isOnline()) {
      try {
        final res = await _apiService.getLastOrderNo(clientCode);
        final apiNext = nextOrderNoFromLastUsed(parseLastOrderNoResponse(res));
        if (apiNext > candidate) candidate = apiNext;
      } catch (_) {}
    }

    return candidate;
  }

  void _ensureOrderMeta(Map<String, dynamic> order, {String? fallbackOrderNo}) {
    final orderNo = order['OrderNo']?.toString().trim();
    if ((orderNo == null || orderNo.isEmpty || orderNo == '0') && fallbackOrderNo != null) {
      order['OrderNo'] = fallbackOrderNo;
    }

    var orderDate = order['OrderDate']?.toString().trim() ?? '';
    if (orderDate.isEmpty) {
      final items = order['CustomOrderItem'] as List?;
      if (items != null && items.isNotEmpty) {
        final first = items.first;
        if (first is Map) {
          orderDate = first['OrderDate']?.toString().trim() ?? '';
        }
      }
    }
    if (orderDate.isEmpty) {
      orderDate = DateTime.now().toIso8601String().split('T').first;
    }
    order['OrderDate'] ??= orderDate;
    order['CreatedOn'] = order['CreatedOn']?.toString().trim().isNotEmpty == true
        ? order['CreatedOn']
        : orderDate;
    order['DeliverDate'] ??= order['DeliverDate'] ?? orderDate;

    final assignedNo = order['OrderNo']?.toString() ?? '';
    final items = order['CustomOrderItem'] as List?;
    if (items != null && assignedNo.isNotEmpty) {
      for (final it in items) {
        if (it is Map<String, dynamic>) {
          it['OrderNo'] = assignedNo;
          it['OrderDate'] ??= orderDate;
        }
      }
    }
  }

  void _applyOrderNoToPayload(Map<String, dynamic> payload, int orderNo) {
    final noStr = orderNo.toString();
    payload['OrderNo'] = noStr;
    final items = payload['CustomOrderItem'] as List?;
    if (items != null) {
      for (final it in items) {
        if (it is Map<String, dynamic>) {
          it['OrderNo'] = noStr;
        }
      }
    }
  }

  Future<bool> isOnline() async {
    try {
      final code = _prefService.getEmployee()?.clientCode ?? '';
      if (code.isEmpty) return false;
      await _apiService.getLastOrderNo(code).timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      // Fallback: if order list API responds, treat as online.
      try {
        final code = _prefService.getEmployee()?.clientCode ?? '';
        await _apiService.searchOrdersByRfid(code, '').timeout(const Duration(seconds: 5));
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> cacheMasterData({
    required String clientCode,
    required List<CustomerModel> customers,
    required List<dynamic> dailyRates,
    required List<dynamic> branches,
    required int lastOrderNo,
  }) async {
    await _dbService.saveOrderMasterCache(
      clientCode: clientCode,
      customersJson: jsonEncode(customers.map((c) => c.toJson()).toList()),
      dailyRatesJson: jsonEncode(dailyRates),
      branchesJson: jsonEncode(branches),
      lastOrderNo: lastOrderNo,
    );
  }

  Future<OrderMasterCache?> loadMasterCache(String clientCode) async {
    final row = await _dbService.loadOrderMasterCache(clientCode);
    if (row == null) return null;
    return OrderMasterCache.fromRow(row);
  }

  Future<void> cacheOrdersHistory(String clientCode, List<dynamic> orders) async {
    // Do not wipe existing cache with an empty list (bad/empty API response).
    if (orders.isEmpty) {
      final existing = await _dbService.loadOrdersHistoryCache(clientCode);
      if (existing.isNotEmpty) return;
    }
    await _dbService.replaceOrdersHistoryCache(clientCode, orders);
  }

  Future<List<dynamic>> loadCachedHistory(String clientCode) async {
    return _dbService.loadOrdersHistoryCache(clientCode);
  }

  bool _sContainsOffline(dynamic status) {
    final s = status?.toString().toUpperCase() ?? '';
    return s.contains('PENDING') || s.contains('OFFLINE');
  }

  /// Saves order locally when API is unavailable. Returns a response-shaped map for PDF/UI.
  ///
  /// - New create → new `local_*` row, operation `create`
  /// - Re-edit pending create → upsert same [localOrderId], keep `create`
  /// - Edit synced server order → `SRV-{customOrderId}`, operation `update`
  Future<Map<String, dynamic>> saveOrderOffline({
    required Map<String, dynamic> payload,
    required String operation,
    required int customOrderId,
    required String orderNo,
    String? localOrderId,
  }) async {
    final clientCode = _prefService.getEmployee()?.clientCode ?? '';

    String resolvedLocalId;
    String resolvedOp = operation;

    if (localOrderId != null && localOrderId.isNotEmpty) {
      // Re-edit of an offline-created (unsynced) order — keep CREATE.
      resolvedLocalId = localOrderId;
      if (customOrderId <= 0) {
        resolvedOp = 'create';
      }
    } else if (customOrderId > 0 && resolvedOp == 'update') {
      // Sparkle: localId = "SRV-$serverOrderId"
      resolvedLocalId = 'SRV_$customOrderId';
    } else if (resolvedOp == 'delete' && customOrderId > 0) {
      resolvedLocalId = 'SRV_$customOrderId';
    } else {
      resolvedLocalId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      resolvedOp = 'create';
    }

    final enriched = Map<String, dynamic>.from(payload);
    enriched['syncStatus'] = false;
    enriched['IsPendingSync'] = true;
    enriched['LocalOrderId'] = resolvedLocalId;
    // Keep API OrderStatus as "Order Received" (Sparkle does NOT store PENDING in payload).
    // UI uses IsPendingSync / * marker instead.
    if (_sContainsOffline(enriched['OrderStatus'])) {
      enriched['OrderStatus'] = 'Order Received';
    } else {
      enriched['OrderStatus'] =
          enriched['OrderStatus']?.toString().isNotEmpty == true
              ? enriched['OrderStatus']
              : 'Order Received';
    }
    enriched['operation'] = resolvedOp;
    _ensureOrderMeta(enriched, fallbackOrderNo: orderNo);

    if (customOrderId > 0) {
      enriched['CustomOrderId'] = customOrderId;
    } else {
      enriched['CustomOrderId'] = 0;
      // Always use LOCAL-* for unsynced creates (Sparkle); real OrderNo assigned on sync.
      if (resolvedOp == 'create') {
        final localNo = 'LOCAL-$resolvedLocalId';
        enriched['OrderNo'] = localNo;
        final items = enriched['CustomOrderItem'] as List?;
        if (items != null) {
          for (final it in items) {
            if (it is Map<String, dynamic>) {
              it['OrderNo'] = localNo;
            }
          }
        }
      }
    }

    await _dbService.insertPendingOrder(
      localId: resolvedLocalId,
      clientCode: clientCode,
      customOrderId: customOrderId,
      orderNo: enriched['OrderNo']?.toString() ?? orderNo,
      operation: resolvedOp,
      payloadJson: jsonEncode(enriched),
    );

    // Only bump cached last order no for numeric local numbers.
    final numericNo = int.tryParse(enriched['OrderNo']?.toString() ?? '') ?? 0;
    if (numericNo > 0) {
      await _dbService.updateCachedLastOrderNo(clientCode, numericNo + 1);
    }

    return enriched;
  }

  Future<List<Map<String, dynamic>>> getPendingOrders(String clientCode) async {
    final rows = await _dbService.getPendingOrders(clientCode);
    return rows.map((r) {
      final payload = jsonDecode(r['payload_json'] as String) as Map<String, dynamic>;
      payload['LocalOrderId'] = r['local_id'];
      payload['IsPendingSync'] = true;
      payload['SyncStatus'] = r['sync_status'];
      payload['operation'] = r['operation'];
      payload['PendingOperation'] = r['operation'];
      payload['CustomOrderId'] = r['custom_order_id'] ?? payload['CustomOrderId'] ?? 0;
      if (payload['OrderStatus'] == null ||
          payload['OrderStatus'].toString().isEmpty) {
        payload['OrderStatus'] = 'PENDING (OFFLINE)';
      }
      _ensureOrderMeta(payload, fallbackOrderNo: r['order_no']?.toString());
      return payload;
    }).toList();
  }

  Future<int> pendingCount(String clientCode) async {
    final orders = await _dbService.countPendingOrders(clientCode);
    final customers = await _dbService.countPendingCustomers(clientCode);
    return orders + customers;
  }

  /// Latest pending order/customer error for UI feedback.
  Future<String?> lastPendingError(String clientCode) async {
    final orderRows = await _dbService.getPendingOrders(clientCode);
    for (final r in orderRows.reversed) {
      final err = r['last_error']?.toString();
      if (err != null && err.trim().isNotEmpty) return err;
    }
    final custRows = await _dbService.getPendingCustomers(clientCode);
    for (final r in custRows.reversed) {
      final err = r['last_error']?.toString();
      if (err != null && err.trim().isNotEmpty) return err;
    }
    return null;
  }

  /// Removes pending CREATE rows whose OrderNo already exists on the server.
  Future<int> dropPendingCreatesAlreadyOnServer(
    String clientCode,
    List<dynamic> serverOrders,
  ) async {
    final serverNos = <String>{};
    for (final o in serverOrders) {
      if (o is Map) {
        final no = o['OrderNo']?.toString().trim() ?? '';
        if (no.isNotEmpty && no != '0' && !no.startsWith('LOCAL-')) {
          serverNos.add(no);
        }
      }
    }
    if (serverNos.isEmpty) return 0;

    final rows = await _dbService.getPendingOrders(clientCode);
    var removed = 0;
    for (final row in rows) {
      final op = (row['operation'] as String? ?? '').toLowerCase();
      if (op != 'create' && op.isNotEmpty) continue;
      final orderNo = row['order_no']?.toString().trim() ?? '';
      String payloadNo = '';
      try {
        final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
        payloadNo = payload['OrderNo']?.toString().trim() ?? '';
      } catch (_) {}
      final candidates = {orderNo, payloadNo}.where((n) => n.isNotEmpty);
      if (candidates.any(serverNos.contains)) {
        await _dbService.deletePendingOrder(row['local_id'] as String);
        removed++;
      }
    }
    return removed;
  }

  /// Saves customer locally when API is unavailable.
  Future<CustomerModel> saveCustomerOffline(Map<String, dynamic> req) async {
    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    final localId = 'cust_local_${DateTime.now().millisecondsSinceEpoch}';
    final tempId = -DateTime.now().millisecondsSinceEpoch;

    final payload = Map<String, dynamic>.from(req);
    payload['Id'] = tempId;
    payload['ClientCode'] = clientCode;
    payload['IsPendingSync'] = true;
    payload['LocalCustomerId'] = localId;

    await _dbService.insertPendingCustomer(
      localId: localId,
      clientCode: clientCode,
      tempCustomerId: tempId,
      payloadJson: jsonEncode(payload),
    );

    return CustomerModel.fromJson(payload);
  }

  Future<List<CustomerModel>> getPendingCustomerModels(String clientCode) async {
    final rows = await _dbService.getPendingCustomers(clientCode);
    return rows.map((r) {
      final payload = jsonDecode(r['payload_json'] as String) as Map<String, dynamic>;
      payload['Id'] = r['temp_customer_id'];
      payload['IsPendingSync'] = true;
      payload['LocalCustomerId'] = r['local_id'];
      return CustomerModel.fromJson(payload);
    }).toList();
  }

  Future<void> updateCustomersInCache(String clientCode, List<CustomerModel> customers) async {
    await _dbService.replaceCustomersInMasterCache(
      clientCode,
      jsonEncode(customers.map((c) => c.toJson()).toList()),
    );
  }

  Future<bool> deletePendingOrder(String localId) async {
    return _dbService.deletePendingOrder(localId);
  }

  /// Clears all pending CREATE rows (stuck offline orders with bad payloads).
  Future<int> clearPendingCreates(String clientCode) async {
    final rows = await _dbService.getPendingOrders(clientCode);
    var n = 0;
    for (final row in rows) {
      final op = (row['operation'] as String? ?? 'create').toLowerCase();
      if (op == 'create' || op.isEmpty) {
        await _dbService.deletePendingOrder(row['local_id'] as String);
        n++;
      }
    }
    // Also clear any leftover from other client_code mismatches.
    if (n == 0) {
      final all = await _dbService.getAllPendingOrders();
      for (final row in all) {
        final op = (row['operation'] as String? ?? 'create').toLowerCase();
        if (op == 'create' || op.isEmpty) {
          await _dbService.deletePendingOrder(row['local_id'] as String);
          n++;
        }
      }
    }
    return n;
  }

  Future<bool> deletePendingByCustomOrderId(int customOrderId) async {
    return _dbService.deletePendingByCustomOrderId(customOrderId);
  }

  /// Sync pending customers first, then orders. Returns total synced count.
  Future<int> syncAll() async {
    final customers = await syncPendingCustomers();
    // Remap any leftover temp customer ids from earlier synced customers.
    await _remapFromSyncedCustomersTable(
      _prefService.getEmployee()?.clientCode ?? '',
    );
    final orders = await syncPendingOrders();
    return customers + orders;
  }

  Future<void> _remapFromSyncedCustomersTable(String clientCode) async {
    if (clientCode.isEmpty) return;
    try {
      final db = await _dbService.database;
      final rows = await db.query(
        'pending_customers',
        where: 'client_code = ? AND server_customer_id > 0',
        whereArgs: [clientCode],
      );
      if (rows.isEmpty) return;
      final idMap = <int, int>{};
      for (final r in rows) {
        final tempId = r['temp_customer_id'] as int? ?? 0;
        final serverId = r['server_customer_id'] as int? ?? 0;
        if (tempId != 0 && serverId > 0) idMap[tempId] = serverId;
      }
      if (idMap.isNotEmpty) {
        await _remapPendingOrdersCustomerIds(clientCode, idMap);
      }
    } catch (e) {
      debugPrint('_remapFromSyncedCustomersTable: $e');
    }
  }

  Future<int> syncPendingCustomers() async {
    var clientCode = _prefService.getEmployee()?.clientCode?.trim() ?? '';

    var rows = clientCode.isNotEmpty
        ? await _dbService.getPendingCustomers(clientCode)
        : await _dbService.getAllPendingCustomers();
    if (rows.isEmpty) {
      rows = await _dbService.getAllPendingCustomers();
    }
    if (rows.isEmpty) return 0;

    if (clientCode.isEmpty) {
      clientCode = rows.first['client_code']?.toString().trim() ?? '';
      if (clientCode.isEmpty) {
        try {
          final payload =
              jsonDecode(rows.first['payload_json'] as String) as Map<String, dynamic>;
          clientCode = payload['ClientCode']?.toString().trim() ?? '';
        } catch (_) {}
      }
    }
    if (clientCode.isEmpty) return 0;

    final idMap = <int, int>{};
    var synced = 0;

    for (final row in rows) {
      final localId = row['local_id'] as String;
      final tempId = row['temp_customer_id'] as int? ?? 0;
      final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      payload.remove('IsPendingSync');
      payload.remove('LocalCustomerId');
      payload['Id'] = 0;

      try {
        final result = await _apiService.addCustomer(payload);
        var serverId = _parsePositiveId(result?['Id']);
        if (serverId <= 0) {
          serverId = await _resolveCustomerIdByMobile(clientCode, payload['Mobile']?.toString() ?? '');
        }
        if (serverId <= 0) {
          await _dbService.markPendingCustomerFailed(localId, 'Server did not return customer Id');
          continue;
        }

        await _dbService.markPendingCustomerSynced(localId, serverId);
        if (tempId != 0) idMap[tempId] = serverId;
        synced++;
      } catch (e, st) {
        debugPrint('Customer sync failed for $localId: $e\n$st');
        await _dbService.markPendingCustomerFailed(localId, e.toString());
      }
    }

    if (idMap.isNotEmpty) {
      await _remapPendingOrdersCustomerIds(clientCode, idMap);
      try {
        final rawCustomers = await _apiService.getAllCustomers(clientCode);
        final customers = rawCustomers
            .map((c) => CustomerModel.fromJson(c as Map<String, dynamic>))
            .toList();
        final cache = await loadMasterCache(clientCode);
        if (cache != null) {
          await cacheMasterData(
            clientCode: clientCode,
            customers: customers,
            dailyRates: cache.dailyRates,
            branches: cache.branches,
            lastOrderNo: cache.lastOrderNo,
          );
        }
      } catch (_) {}
    }

    return synced;
  }

  int _parsePositiveId(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v > 0 ? v : 0;
    if (v is num) return v.toInt() > 0 ? v.toInt() : 0;
    final n = int.tryParse(v.toString().trim()) ?? 0;
    return n > 0 ? n : 0;
  }

  Future<int> _resolveCustomerIdByMobile(String clientCode, String mobile) async {
    final m = mobile.trim();
    if (m.isEmpty) return 0;
    try {
      final raw = await _apiService.getAllCustomers(clientCode);
      for (final c in raw) {
        if (c is Map && c['Mobile']?.toString().trim() == m) {
          final id = _parsePositiveId(c['Id']);
          if (id > 0) return id;
        }
      }
    } catch (_) {}
    // Fallback: master cache (works offline / if customers API flaky).
    try {
      final cache = await loadMasterCache(clientCode);
      for (final c in cache?.customers ?? const <CustomerModel>[]) {
        if ((c.mobile ?? '').trim() == m) {
          final id = c.id ?? 0;
          if (id > 0) return id;
        }
      }
    } catch (_) {}
    return 0;
  }

  Future<void> _remapPendingOrdersCustomerIds(String clientCode, Map<int, int> idMap) async {
    final rows = await _dbService.getPendingOrders(clientCode);
    for (final row in rows) {
      final localId = row['local_id'] as String;
      final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      var changed = false;

      final topCid = int.tryParse(payload['CustomerId']?.toString() ?? '') ?? 0;
      if (idMap.containsKey(topCid)) {
        payload['CustomerId'] = idMap[topCid].toString();
        changed = true;
      }

      final cust = payload['Customer'];
      if (cust is Map<String, dynamic>) {
        final cid = cust['Id'] as int? ?? int.tryParse(cust['Id']?.toString() ?? '') ?? 0;
        if (idMap.containsKey(cid)) {
          cust['Id'] = idMap[cid];
          changed = true;
        }
      }

      final items = payload['CustomOrderItem'] as List?;
      if (items != null) {
        for (final it in items) {
          if (it is Map<String, dynamic>) {
            final cid = it['CustomerId'] as int? ?? int.tryParse(it['CustomerId']?.toString() ?? '') ?? 0;
            if (idMap.containsKey(cid)) {
              it['CustomerId'] = idMap[cid];
              changed = true;
            }
          }
        }
      }

      if (changed) {
        await _dbService.updatePendingOrderPayload(localId, jsonEncode(payload));
      }
    }
  }

  /// Upload pending orders when internet is available. Returns number synced.
  /// Order matches Sparkle: DELETE → UPDATE → CREATE.
  Future<int> syncPendingOrders() async {
    var clientCode = _prefService.getEmployee()?.clientCode?.trim() ?? '';

    // Drop stale "synced" creates that never got a server id — they often already
    // exist on the server and re-uploading them creates duplicate OrderNo rows.
    if (clientCode.isNotEmpty) {
      await _dbService.purgeUnconfirmedSyncedCreates(clientCode);
    }

    var rows = clientCode.isNotEmpty
        ? await _dbService.getPendingOrders(clientCode)
        : await _dbService.getAllPendingOrders();
    if (rows.isEmpty) {
      rows = await _dbService.getAllPendingOrders();
    }
    if (rows.isEmpty) return 0;

    // Recover client code from row / payload if prefs are empty.
    if (clientCode.isEmpty) {
      clientCode = rows.first['client_code']?.toString().trim() ?? '';
      if (clientCode.isEmpty) {
        try {
          final payload =
              jsonDecode(rows.first['payload_json'] as String) as Map<String, dynamic>;
          clientCode = payload['ClientCode']?.toString().trim() ?? '';
        } catch (_) {}
      }
    }
    if (clientCode.isEmpty) {
      debugPrint('OrderSync: no ClientCode available — cannot sync');
      return 0;
    }

    // Soft online check — still attempt sync if probe is flaky.
    final online = await isOnline();
    if (!online) {
      debugPrint('OrderSync: online probe failed — still attempting upload');
    }

    final deletes = rows.where((r) => (r['operation'] as String?)?.toLowerCase() == 'delete').toList();
    final updates = rows.where((r) => (r['operation'] as String?)?.toLowerCase() == 'update').toList();
    final creates = rows.where((r) {
      final op = (r['operation'] as String?)?.toLowerCase() ?? '';
      return op == 'create' || op.isEmpty;
    }).toList();
    final ordered = [...deletes, ...updates, ...creates];

    var synced = 0;

    // Fresh server last-order-no once for this CREATE batch (Sparkle style).
    var runningNo = 0;
    if (creates.isNotEmpty) {
      try {
        final res = await _apiService.getLastOrderNo(clientCode);
        runningNo = parseLastOrderNoResponse(res);
      } catch (_) {
        runningNo = (await resolveNextOrderNo(clientCode)) - 1;
        if (runningNo < 0) runningNo = 0;
      }
    }

    // Known server OrderNos — used to skip already-uploaded creates.
    Set<String> serverOrderNos = {};
    try {
      final existing = await _apiService.getAllOrders(clientCode);
      for (final o in existing) {
        if (o is Map) {
          final no = o['OrderNo']?.toString().trim() ?? '';
          if (no.isNotEmpty) serverOrderNos.add(no);
        }
      }
    } catch (_) {}

    for (final row in ordered) {
      final localId = row['local_id'] as String;
      final operation = (row['operation'] as String? ?? 'create').toLowerCase();
      var payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;

      try {
        if (operation == 'delete') {
          final id = row['custom_order_id'] as int? ??
              int.tryParse(payload['CustomOrderId']?.toString() ?? '') ??
              0;
          if (id > 0) {
            final ok = await _apiService.deleteCustomOrder(clientCode, id);
            if (!ok) throw Exception('DeleteCustomOrder failed for $id');
          }
          await _dbService.deletePendingOrder(localId);
          synced++;
          continue;
        }

        _ensureOrderMeta(payload, fallbackOrderNo: row['order_no']?.toString());

        if (operation == 'update') {
          final serverId = row['custom_order_id'] as int? ??
              int.tryParse(payload['CustomOrderId']?.toString() ?? '') ??
              0;
          if (serverId <= 0) {
            throw Exception('Update missing CustomOrderId');
          }

          var customerId = _parsePositiveId(payload['CustomerId']);
          if (customerId <= 0) {
            customerId = await _ensureCustomerIdOnPayload(clientCode, payload, localId);
          }
          if (customerId <= 0) {
            throw Exception(
              'CustomerId missing — select a customer with a server Id (or sync offline customers first)',
            );
          }

          // Sparkle-shaped body (same as Kotlin CustomOrderRequest).
          payload = OrderPayloadBuilder.toSparkleApiPayload(
            payload,
            clientCode: clientCode,
            employee: _prefService.getEmployee(),
            customOrderId: serverId,
            customerId: customerId,
            orderNo: payload['OrderNo']?.toString(),
            forceCreateDefaults: false,
          );

          debugPrint(
            'OrderSync UPDATE localId=$localId CustomOrderId=$serverId CustomerId=$customerId',
          );

          final result = await _apiService.updateCustomOrder(payload);
          if (result == null) {
            throw Exception('UpdateCustomOrder returned empty response');
          }
          await _dbService.deletePendingOrder(localId);
          synced++;
          continue;
        }

        // -------- CREATE --------
        var customerId = _parsePositiveId(payload['CustomerId']);
        if (customerId <= 0) {
          customerId = await _ensureCustomerIdOnPayload(clientCode, payload, localId);
        }
        if (customerId <= 0) {
          throw Exception(
            'CustomerId missing — select a customer with a server Id (or sync offline customers first)',
          );
        }

        // Always assign a fresh sequential OrderNo (never reuse a previous attempt).
        runningNo += 1;
        _applyOrderNoToPayload(payload, runningNo);
        payload['OrderStatus'] = 'Order Received';
        payload['CustomerId'] = customerId.toString();
        await _dbService.updatePendingOrderPayload(
          localId,
          jsonEncode(payload),
          orderNo: runningNo.toString(),
        );

        // If this OrderNo already exists on server, skip upload (already synced earlier).
        if (serverOrderNos.contains(runningNo.toString())) {
          debugPrint('Order sync skip duplicate OrderNo=$runningNo for $localId');
          await _dbService.deletePendingOrder(localId);
          synced++;
          continue;
        }

        // Sparkle worker: Gson CustomOrderRequest + new OrderNo only.
        // forceCreateDefaults → GST="0"/GSTApplied="false" like Kotlin create.
        payload = OrderPayloadBuilder.toSparkleApiPayload(
          payload,
          clientCode: clientCode,
          employee: _prefService.getEmployee(),
          customOrderId: 0,
          customerId: customerId,
          orderNo: runningNo.toString(),
          forceCreateDefaults: true,
        );

        if (customerId <= 0) {
          throw Exception('CustomerId is 0 — cannot AddCustomOrder. Re-select a server customer.');
        }

        debugPrint(
          'OrderSync CREATE localId=$localId OrderNo=$runningNo CustomerId=$customerId '
          'GST=${payload['GST']} GSTApplied=${payload['GSTApplied']} '
          'OrderDate=${payload['OrderDate']} items=${(payload['CustomOrderItem'] as List?)?.length}',
        );

        final result = await _apiService.addCustomOrder(payload);
        if (result == null) {
          throw Exception('AddCustomOrder returned empty response');
        }

        var serverOrderId = _extractCustomOrderId(result);
        if (serverOrderId <= 0) {
          // API sometimes returns success without Id — resolve by OrderNo.
          serverOrderId = await _resolveOrderIdByOrderNo(clientCode, runningNo.toString());
        }

        debugPrint(
          'Order synced: OrderNo=$runningNo localId=$localId serverId=$serverOrderId result=$result',
        );

        // Hard-delete pending row after successful create (prevents re-upload duplicates).
        await _dbService.deletePendingOrder(localId);
        serverOrderNos.add(runningNo.toString());
        synced++;
      } catch (e, st) {
        debugPrint('Order sync failed for $localId: $e\n$st');
        await _dbService.markPendingOrderFailed(localId, e.toString());
      }
    }

    if (synced > 0) {
      try {
        final raw = await _apiService.getAllOrders(clientCode);
        await cacheOrdersHistory(clientCode, raw);
        final lastUsed = parseLastOrderNoResponse(
          await _apiService.getLastOrderNo(clientCode),
        );
        final next = nextOrderNoFromLastUsed(lastUsed);
        await _dbService.updateCachedLastOrderNo(clientCode, next > runningNo ? next : runningNo + 1);
      } catch (_) {
        if (runningNo > 0) {
          await _dbService.updateCachedLastOrderNo(clientCode, runningNo + 1);
        }
      }
    }

    return synced;
  }

  int _extractCustomOrderId(Map<String, dynamic> result) {
    for (final key in ['CustomOrderId', 'customOrderId', 'Id', 'id', 'OrderId']) {
      final v = result[key];
      if (v == null) continue;
      final n = int.tryParse(v.toString());
      if (n != null && n > 0) return n;
    }
    return 0;
  }

  Future<int> _resolveOrderIdByOrderNo(String clientCode, String orderNo) async {
    try {
      final raw = await _apiService.getAllOrders(clientCode);
      for (final o in raw) {
        if (o is Map && o['OrderNo']?.toString() == orderNo) {
          return _parsePositiveId(o['CustomOrderId']);
        }
      }
    } catch (_) {}
    return 0;
  }

  Future<int> _ensureCustomerIdOnPayload(
    String clientCode,
    Map<String, dynamic> payload,
    String localId,
  ) async {
    final custRaw = payload['Customer'];
    final cust = custRaw is Map
        ? Map<String, dynamic>.from(custRaw)
        : <String, dynamic>{};

    // Keep temp (negative) id for pending_customers remap before clearing.
    final tempFromRoot = int.tryParse(payload['CustomerId']?.toString() ?? '') ?? 0;
    final tempFromCust = int.tryParse(cust['Id']?.toString() ?? '') ?? 0;
    final tempId = tempFromRoot < 0
        ? tempFromRoot
        : (tempFromCust < 0 ? tempFromCust : 0);

    var customerId = _parsePositiveId(payload['CustomerId']);
    if (customerId <= 0) {
      customerId = _parsePositiveId(cust['Id']);
    }
    // Negative = offline temp id — never send to API.
    if (customerId < 0) customerId = 0;

    if (customerId <= 0) {
      customerId = await _resolveCustomerIdByMobile(
        clientCode,
        cust['Mobile']?.toString() ?? '',
      );
    }
    // Also try remapping from previously synced pending customers.
    if (customerId <= 0) {
      customerId = await _lookupSyncedCustomerId(
        clientCode,
        tempId: tempId,
        mobile: cust['Mobile']?.toString() ?? '',
      );
    }
    if (customerId <= 0) return 0;

    payload['CustomerId'] = customerId.toString();
    cust['Id'] = customerId;
    payload['Customer'] = cust;
    final items = payload['CustomOrderItem'] as List?;
    if (items != null) {
      for (final it in items) {
        if (it is Map) {
          it['CustomerId'] = customerId;
        }
      }
    }
    await _dbService.updatePendingOrderPayload(localId, jsonEncode(payload));
    return customerId;
  }

  /// Finds server customer id from earlier synced pending_customers rows.
  Future<int> _lookupSyncedCustomerId(
    String clientCode, {
    required int tempId,
    required String mobile,
  }) async {
    try {
      final db = await _dbService.database;
      if (tempId != 0) {
        final byTemp = await db.query(
          'pending_customers',
          where: 'client_code = ? AND temp_customer_id = ? AND server_customer_id > 0',
          whereArgs: [clientCode, tempId],
          limit: 1,
        );
        if (byTemp.isNotEmpty) {
          return byTemp.first['server_customer_id'] as int? ?? 0;
        }
      }
      if (mobile.isNotEmpty) {
        final rows = await db.query(
          'pending_customers',
          where: "client_code = ? AND server_customer_id > 0",
          whereArgs: [clientCode],
        );
        for (final r in rows) {
          try {
            final p = jsonDecode(r['payload_json'] as String) as Map<String, dynamic>;
            if (p['Mobile']?.toString() == mobile) {
              return r['server_customer_id'] as int? ?? 0;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return 0;
  }

  List<dynamic> mergeHistoryWithPending({
    required List<dynamic> serverOrCached,
    required List<Map<String, dynamic>> pending,
  }) {
    final merged = <dynamic>[];
    final pendingUpdateIds = <int>{};
    final pendingDeleteIds = <int>{};
    final seenOrderNos = <String>{};
    final seenIds = <int>{};
    final seenLocalIds = <String>{};

    for (final p in pending) {
      final op = (p['operation']?.toString() ?? p['PendingOperation']?.toString() ?? '')
          .toLowerCase();
      final id = p['CustomOrderId'] as int? ??
          int.tryParse(p['CustomOrderId']?.toString() ?? '') ??
          0;
      if (op == 'delete' && id > 0) {
        pendingDeleteIds.add(id);
      } else if (op == 'update' && id > 0) {
        pendingUpdateIds.add(id);
      }
    }

    // Server / cache rows first (deduped).
    for (final o in serverOrCached) {
      if (o is! Map) {
        merged.add(o);
        continue;
      }
      final id = o['CustomOrderId'] as int? ??
          int.tryParse(o['CustomOrderId']?.toString() ?? '') ??
          0;
      final orderNo = o['OrderNo']?.toString().trim() ?? '';

      if (id > 0 && pendingDeleteIds.contains(id)) continue;
      if (id > 0 && pendingUpdateIds.contains(id)) continue; // pending update replaces

      if (id > 0 && seenIds.contains(id)) continue;
      if (orderNo.isNotEmpty &&
          orderNo != '0' &&
          !orderNo.startsWith('LOCAL-') &&
          seenOrderNos.contains(orderNo)) {
        continue;
      }

      if (id > 0) seenIds.add(id);
      if (orderNo.isNotEmpty) seenOrderNos.add(orderNo);
      merged.add(o);
    }

    // Pending updates / creates (skip if already represented by server OrderNo/Id).
    for (final p in pending.reversed) {
      final op = (p['operation']?.toString() ?? p['PendingOperation']?.toString() ?? '')
          .toLowerCase();
      if (op == 'delete') continue;

      final id = p['CustomOrderId'] as int? ??
          int.tryParse(p['CustomOrderId']?.toString() ?? '') ??
          0;
      final localId = p['LocalOrderId']?.toString() ?? '';
      final orderNo = p['OrderNo']?.toString().trim() ?? '';

      if (localId.isNotEmpty && seenLocalIds.contains(localId)) continue;
      if (id > 0 && seenIds.contains(id)) continue;

      // Hide pending create/update that already exists on server with same OrderNo.
      if (orderNo.isNotEmpty &&
          !orderNo.startsWith('LOCAL-') &&
          !orderNo.startsWith('local_') &&
          seenOrderNos.contains(orderNo)) {
        continue;
      }

      if (localId.isNotEmpty) seenLocalIds.add(localId);
      if (id > 0) seenIds.add(id);
      if (orderNo.isNotEmpty) seenOrderNos.add(orderNo);
      merged.insert(0, p);
    }

    return merged;
  }
}

class OrderMasterCache {
  final List<CustomerModel> customers;
  final List<dynamic> dailyRates;
  final List<dynamic> branches;
  final int lastOrderNo;
  final DateTime? cachedAt;

  OrderMasterCache({
    required this.customers,
    required this.dailyRates,
    required this.branches,
    required this.lastOrderNo,
    this.cachedAt,
  });

  factory OrderMasterCache.fromRow(Map<String, dynamic> row) {
    final customersRaw = jsonDecode(row['customers_json'] as String? ?? '[]') as List;
    return OrderMasterCache(
      customers: customersRaw
          .map((c) => CustomerModel.fromJson(c as Map<String, dynamic>))
          .toList(),
      dailyRates: jsonDecode(row['daily_rates_json'] as String? ?? '[]') as List,
      branches: jsonDecode(row['branches_json'] as String? ?? '[]') as List,
      lastOrderNo: row['last_order_no'] as int? ?? 0,
      cachedAt: DateTime.tryParse(row['cached_at'] as String? ?? ''),
    );
  }
}
