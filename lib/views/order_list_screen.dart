import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rfid_flutter/utils/app_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../utils/nav_perf.dart';
import '../viewmodels/order_view_model.dart';
import 'widgets/list_action_icon.dart';
import 'widgets/order_pdf.dart';
import 'widgets/spreadsheet_list_view.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Wait for page transition so dashboard → list feels instant.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      runAfterRouteSettled(context, () {
        if (!mounted) return;
        final vm = context.read<OrderViewModel>();
        // Skip long pending sync on open — cloud button / background worker handle that.
        unawaited(vm.fetchOrdersHistory(syncPendingFirst: false));
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _editOrder(Map<String, dynamic> order) {
    context.read<OrderViewModel>().setOrderForEditing(order);
    Navigator.pushNamed(context, '/order').then((_) {
      if (!mounted) return;
      context.read<OrderViewModel>().fetchOrdersHistory();
    });
  }

  void _confirmDelete(Map<String, dynamic> order) {
    final orderId = order['CustomOrderId'] as int? ?? 0;
    final localOrderId = order['LocalOrderId']?.toString();
    var displayId = _resolveOrderNo(order);
    if (displayId == '-') {
      displayId = orderId.toString();
    }
    final s = context.sRead;
    showAppDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(s.deleteOrder, style: AppFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text(s.deleteOrderConfirm.replaceAll('{id}', displayId), style: AppFonts.poppins(fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel, style: AppFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                final success = await context.read<OrderViewModel>().deleteOrderFromHistory(
                  orderId,
                  localOrderId: localOrderId,
                );
                if (!mounted) return;
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.orderDeletedSuccessfully)),
                  );
                } else {
                  final err = context.read<OrderViewModel>().errorMessage ?? s.failedWithMessage('');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${s.error}: $err')),
                  );
                }
              },
              child: Text(s.delete, style: AppFonts.poppins(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _syncOrders() async {
    // Use sRead (listen: false) — context.s watches LocaleService and crashes in onPressed.
    final s = context.sRead;
    final vm = context.read<OrderViewModel>();
    if (vm.isSyncing) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.syncOrdersNow),
        duration: const Duration(seconds: 2),
      ),
    );

    final before = vm.pendingSyncCount;
    final count = await vm.syncPendingOrdersNow();
    if (!mounted) return;

    final remaining = vm.pendingSyncCount;
    final err = vm.errorMessage;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (count > 0 && remaining == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.dataSyncSuccessfully)),
      );
      return;
    }

    if (count == 0 && before == 0 && remaining == 0 && (err == null || err.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to sync')),
      );
      return;
    }

    // Always show the real server/local error in a dialog (snackbars truncate).
    final message = (err != null && err.isNotEmpty)
        ? err
        : (remaining > 0
            ? 'Synced $count; $remaining still pending'
            : 'Sync failed — check internet / customer');

    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          count > 0 ? 'Partial sync' : s.error,
          style: AppFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            message,
            style: AppFonts.poppins(fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final deleted = await vm.clearFailedPendingCreates();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Cleared $deleted stuck pending order(s). Create the order again, then sync.',
                  ),
                ),
              );
            },
            child: Text('Clear stuck', style: AppFonts.poppins(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: AppFonts.poppins()),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      return DateFormat('dd-MM-yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  String _resolveOrderDate(Map<String, dynamic> order) {
    var raw = order['OrderDate'];
    if (raw == null || raw.toString().trim().isEmpty) {
      final items = order['CustomOrderItem'] as List?;
      if (items != null && items.isNotEmpty) {
        final first = items.first;
        if (first is Map) {
          raw = first['OrderDate'];
        }
      }
    }
    if (raw == null || raw.toString().trim().isEmpty) {
      raw = order['CreatedOn'] ?? order['LastUpdated'];
    }
    return _formatDate(raw);
  }

  String _resolveOrderNo(Map<String, dynamic> order) {
    final no = order['OrderNo']?.toString().trim();
    if (no != null && no.isNotEmpty && no != '0') return no;
    return '-';
  }

  Map<String, double> _orderWeights(Map<String, dynamic> order) {
    final items = order['CustomOrderItem'] as List? ?? [];
    double gWt = 0, sWt = 0, dWt = 0, nWt = 0, fWt = 0;
    for (final it in items) {
      final map = it as Map;
      gWt += double.tryParse(map['GrossWt']?.toString() ?? '') ?? 0.0;
      sWt += double.tryParse(map['StoneWt']?.toString() ?? '') ?? 0.0;
      dWt += double.tryParse(map['DiamondWt']?.toString() ?? '') ?? 0.0;
      nWt += double.tryParse(map['NetWt']?.toString() ?? '') ?? 0.0;
      fWt += double.tryParse(map['FixedWt']?.toString() ?? '') ?? 0.0;
    }
    return {'g': gWt, 's': sWt, 'd': dWt, 'n': nWt, 'f': fWt};
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isHistoryLoading = context.select<OrderViewModel, bool>((vm) => vm.isHistoryLoading);
    final ordersHistory = context.select<OrderViewModel, List<dynamic>>((vm) => vm.ordersHistory);
    final isOfflineMode = context.select<OrderViewModel, bool>((vm) => vm.isOfflineMode);
    final pendingSyncCount = context.select<OrderViewModel, int>((vm) => vm.pendingSyncCount);
    final isSyncing = context.select<OrderViewModel, bool>((vm) => vm.isSyncing);
    final query = _searchController.text.trim().toLowerCase();

    final filtered = ordersHistory.where((o) {
      final orderNo = o['OrderNo']?.toString().toLowerCase() ?? '';
      final custMap = o['Customer'] as Map<String, dynamic>? ?? {};
      final custName = '${custMap['FirstName'] ?? ''} ${custMap['LastName'] ?? ''}'.trim().toLowerCase();
      return orderNo.contains(query) || custName.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF5231A7), Color(0xFFD32940)]),
          ),
        ),
        title: Text(
          s.customerOrdersList,
          style: AppFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Always show sync — previously hidden when pendingSyncCount == 0,
          // so taps appeared to do nothing when the badge was missing.
          IconButton(
            tooltip: s.syncOrdersNow,
            onPressed: isSyncing ? null : _syncOrders,
            icon: isSyncing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Badge(
                    isLabelVisible: pendingSyncCount > 0,
                    label: Text('$pendingSyncCount', style: const TextStyle(fontSize: 10)),
                    child: const Icon(Icons.cloud_upload, color: Colors.white),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              context.read<OrderViewModel>().clearEditMode();
              Navigator.pushNamed(context, '/order').then((_) {
                if (!mounted) return;
                context.read<OrderViewModel>().fetchOrdersHistory();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (isOfflineMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 18, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.offlineOrderMode,
                      style: AppFonts.poppins(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() {}),
                    style: AppFonts.poppins(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: s.searchOrderHint,
                      hintStyle: AppFonts.poppins(fontSize: 13, color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                  ),
                ),
                if (_searchController.text.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _searchController.clear()),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                if (isHistoryLoading && filtered.isNotEmpty)
                  const LinearProgressIndicator(minHeight: 2, color: Color(0xFF5231A7)),
                Expanded(
                  child: isHistoryLoading && filtered.isEmpty
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF5231A7)))
                      : filtered.isEmpty
                          ? _buildEmptyState()
                          : _buildSpreadsheetView(filtered, context.read<OrderViewModel>()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final s = context.s;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            s.noOrdersFound,
            style: AppFonts.poppins(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSpreadsheetView(List<dynamic> list, OrderViewModel vm) {
    final s = context.s;
    return SpreadsheetListView(
      rowCount: list.length,
      actionWidth: 120,
      columns: [
        SpreadsheetColumnDef(
          header: s.headerOrderNo,
          width: 90,
          valueBuilder: (i) {
            final order = list[i] as Map<String, dynamic>;
            final no = _resolveOrderNo(order);
            final pending = order['IsPendingSync'] == true ||
                order['IsPendingSync']?.toString().toLowerCase() == 'true' ||
                (order['LocalOrderId']?.toString().isNotEmpty == true &&
                    (order['CustomOrderId'] == null ||
                        order['CustomOrderId'] == 0 ||
                        order['CustomOrderId']?.toString() == '0')) ||
                (order['OrderNo']?.toString().startsWith('LOCAL-') == true) ||
                (order['OrderStatus']?.toString().toUpperCase().contains('PENDING') == true);
            return pending && no != '-' ? '$no *' : no;
          },
        ),
        SpreadsheetColumnDef(
          header: s.date,
          width: 90,
          valueBuilder: (i) => _resolveOrderDate(list[i] as Map<String, dynamic>),
        ),
        SpreadsheetColumnDef(
          header: s.headerCustomer,
          width: 150,
          alignLeft: true,
          maxLines: 2,
          valueBuilder: (i) {
            final custMap = list[i]['Customer'] as Map<String, dynamic>? ?? {};
            final name = '${custMap['FirstName'] ?? ''} ${custMap['LastName'] ?? ''}'.trim();
            return name.isEmpty ? s.walkInCustomer : name;
          },
        ),
        SpreadsheetColumnDef(
          header: s.qty,
          width: 55,
          valueBuilder: (i) => list[i]['Qty']?.toString() ?? '0',
        ),
        SpreadsheetColumnDef(
          header: s.headerGrossWt,
          width: 70,
          valueBuilder: (i) => _orderWeights(list[i])['g']!.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerStoneWt,
          width: 70,
          valueBuilder: (i) => _orderWeights(list[i])['s']!.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerDiamondWt,
          width: 75,
          valueBuilder: (i) => _orderWeights(list[i])['d']!.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerNetWt,
          width: 70,
          valueBuilder: (i) => _orderWeights(list[i])['n']!.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerFineWt,
          width: 70,
          valueBuilder: (i) => _orderWeights(list[i])['f']!.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerTaxAmt,
          width: 85,
          valueBuilder: (i) => list[i]['TotalGSTAmount']?.toString() ?? '0.00',
        ),
        SpreadsheetColumnDef(
          header: s.headerTotalAmt,
          width: 95,
          valueBuilder: (i) => '₹${list[i]['TotalAmount'] ?? "0.00"}',
        ),
      ],
      actionBuilder: (context, index) {
        final order = list[index];
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            listActionIcon(icon: Icons.edit, onTap: () => _editOrder(order)),
            listActionIcon(
              icon: Icons.print,
              onTap: () async {
                await printCustomOrderPdf(
                  context: context,
                  orderRes: order,
                  baseUrl: vm.baseUrl,
                );
              },
            ),
            listActionIcon(icon: Icons.delete, onTap: () => _confirmDelete(order)),
          ],
        );
      },
    );
  }
}
