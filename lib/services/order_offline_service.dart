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
    order['CreatedOn'] ??= orderDate;
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
      await _apiService.getLastOrderNo(code).timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
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
    await _dbService.replaceOrdersHistoryCache(clientCode, orders);
  }

  Future<List<dynamic>> loadCachedHistory(String clientCode) async {
    return _dbService.loadOrdersHistoryCache(clientCode);
  }

  /// Saves order locally when API is unavailable. Returns a response-shaped map for PDF/UI.
  Future<Map<String, dynamic>> saveOrderOffline({
    required Map<String, dynamic> payload,
    required String operation,
    required int customOrderId,
    required String orderNo,
  }) async {
    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final enriched = Map<String, dynamic>.from(payload);
    enriched['syncStatus'] = true;
    enriched['IsPendingSync'] = true;
    enriched['LocalOrderId'] = localId;
    _ensureOrderMeta(enriched, fallbackOrderNo: orderNo);
    if (customOrderId > 0) {
      enriched['CustomOrderId'] = customOrderId;
    } else {
      enriched['CustomOrderId'] = 0;
    }

    await _dbService.insertPendingOrder(
      localId: localId,
      clientCode: clientCode,
      customOrderId: customOrderId,
      orderNo: orderNo,
      operation: operation,
      payloadJson: jsonEncode(enriched),
    );

    final nextNo = (int.tryParse(enriched['OrderNo']?.toString() ?? orderNo) ?? 0) + 1;
    if (nextNo > 1) {
      await _dbService.updateCachedLastOrderNo(clientCode, nextNo);
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
      _ensureOrderMeta(payload, fallbackOrderNo: r['order_no']?.toString());
      return payload;
    }).toList();
  }

  Future<int> pendingCount(String clientCode) async {
    final orders = await _dbService.countPendingOrders(clientCode);
    final customers = await _dbService.countPendingCustomers(clientCode);
    return orders + customers;
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

  Future<bool> deletePendingByCustomOrderId(int customOrderId) async {
    return _dbService.deletePendingByCustomOrderId(customOrderId);
  }

  /// Sync pending customers first, then orders. Returns total synced count.
  Future<int> syncAll() async {
    final customers = await syncPendingCustomers();
    final orders = await syncPendingOrders();
    return customers + orders;
  }
  Future<int> syncPendingCustomers() async {
    if (!await isOnline()) return 0;

    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    if (clientCode.isEmpty) return 0;

    final rows = await _dbService.getPendingCustomers(clientCode);
    if (rows.isEmpty) return 0;

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
        var serverId = result?['Id'] as int? ??
            int.tryParse(result?['Id']?.toString() ?? '') ??
            0;
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

  Future<int> _resolveCustomerIdByMobile(String clientCode, String mobile) async {
    if (mobile.isEmpty) return 0;
    try {
      final raw = await _apiService.getAllCustomers(clientCode);
      for (final c in raw) {
        if (c is Map && c['Mobile']?.toString() == mobile) {
          return c['Id'] as int? ?? 0;
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

      final cust = payload['Customer'];
      if (cust is Map<String, dynamic>) {
        final cid = cust['Id'] as int? ?? 0;
        if (idMap.containsKey(cid)) {
          cust['Id'] = idMap[cid];
          changed = true;
        }
      }

      final items = payload['CustomOrderItem'] as List?;
      if (items != null) {
        for (final it in items) {
          if (it is Map<String, dynamic>) {
            final cid = it['CustomerId'] as int? ?? 0;
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
  Future<int> syncPendingOrders() async {
    if (!await isOnline()) return 0;

    final clientCode = _prefService.getEmployee()?.clientCode ?? '';
    if (clientCode.isEmpty) return 0;

    final requeued = await _dbService.requeueUnconfirmedOrderUploads(clientCode);
    if (requeued > 0) {
      debugPrint('OrderSync: re-queued $requeued unconfirmed upload(s)');
    }

    final rows = await _dbService.getPendingOrders(clientCode);
    var synced = 0;
    var nextAssignable = await resolveNextOrderNo(clientCode);

    for (final row in rows) {
      final localId = row['local_id'] as String;
      final operation = row['operation'] as String;
      var payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;

      if (operation != 'delete') {
        _ensureOrderMeta(payload, fallbackOrderNo: row['order_no']?.toString());
        final currentNo = int.tryParse(payload['OrderNo']?.toString() ?? '') ?? 0;
        if (currentNo <= 0) {
          _applyOrderNoToPayload(payload, nextAssignable);
          nextAssignable++;
          await _dbService.updatePendingOrderPayload(localId, jsonEncode(payload));
        }
      }

      payload = OrderPayloadBuilder.enrichForApi(
        payload,
        clientCode: clientCode,
        employee: _prefService.getEmployee(),
      );

      try {
        if (operation == 'delete') {
          final id = row['custom_order_id'] as int? ?? 0;
          if (id > 0) {
            final ok = await _apiService.deleteCustomOrder(clientCode, id);
            if (!ok) continue;
          }
        } else if (operation == 'update') {
          final result = await _apiService.updateCustomOrder(payload);
          if (result == null) {
            throw Exception('UpdateCustomOrder returned empty response');
          }
        } else {
          var customerId = int.tryParse(payload['CustomerId']?.toString() ?? '') ?? 0;
          if (customerId <= 0) {
            final cust = payload['Customer'];
            if (cust is Map<String, dynamic>) {
              customerId = await _resolveCustomerIdByMobile(
                clientCode,
                cust['Mobile']?.toString() ?? '',
              );
              if (customerId > 0) {
                payload['CustomerId'] = customerId.toString();
                cust['Id'] = customerId;
                final items = payload['CustomOrderItem'] as List?;
                if (items != null) {
                  for (final it in items) {
                    if (it is Map<String, dynamic>) {
                      it['CustomerId'] = customerId;
                    }
                  }
                }
                await _dbService.updatePendingOrderPayload(localId, jsonEncode(payload));
              }
            }
          }
          if (customerId <= 0) {
            throw Exception('CustomerId missing — sync customers first');
          }
          final result = await _apiService.addCustomOrder(payload);
          if (result == null) {
            throw Exception('AddCustomOrder returned empty response');
          }
          final serverOrderId = result['CustomOrderId'] as int? ??
              int.tryParse(result['CustomOrderId']?.toString() ?? '') ??
              int.tryParse(result['Id']?.toString() ?? '') ??
              0;
          debugPrint('Order synced to server: OrderNo=${payload['OrderNo']} response=$result');
          await _dbService.markPendingOrderSynced(localId, customOrderId: serverOrderId);
          synced++;
          continue;
        }

        await _dbService.markPendingOrderSynced(localId);
        synced++;
      } catch (e, st) {
        debugPrint('Order sync failed for $localId: $e\n$st');
        await _dbService.markPendingOrderFailed(localId, e.toString());
      }
    }

    if (synced > 0) {
      try {
        final raw = await _apiService.searchOrdersByRfid(clientCode, '');
        await cacheOrdersHistory(clientCode, raw);
        final refreshedNext = await resolveNextOrderNo(clientCode);
        await _dbService.updateCachedLastOrderNo(clientCode, refreshedNext);
      } catch (_) {
        if (nextAssignable > 1) {
          await _dbService.updateCachedLastOrderNo(clientCode, nextAssignable);
        }
      }
    }

    return synced;
  }

  List<dynamic> mergeHistoryWithPending({
    required List<dynamic> serverOrCached,
    required List<Map<String, dynamic>> pending,
  }) {
    final merged = <dynamic>[...serverOrCached];
    final existingIds = <String>{};
    for (final o in merged) {
      if (o is Map) {
        final id = o['CustomOrderId']?.toString() ?? '';
        if (id.isNotEmpty) existingIds.add(id);
      }
    }
    for (final p in pending) {
      if (p['operation'] == 'delete') continue;
      final localId = p['LocalOrderId']?.toString() ?? '';
      if (!merged.any((o) => o is Map && o['LocalOrderId'] == localId)) {
        merged.insert(0, p);
      }
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
