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

enum _OrderReportView { allOrders, skuWise, customerWise }

class _SkuSummaryRow {
  final String sku;
  final double qty;
  final double grossWt;
  final double stoneWt;
  final double netWt;
  final double totalAmt;

  const _SkuSummaryRow({
    required this.sku,
    required this.qty,
    required this.grossWt,
    required this.stoneWt,
    required this.netWt,
    required this.totalAmt,
  });
}

class _CustomerSummaryRow {
  final String customerName;
  final int orderCount;
  final double qty;
  final double grossWt;
  final double netWt;
  final double totalAmt;

  const _CustomerSummaryRow({
    required this.customerName,
    required this.orderCount,
    required this.qty,
    required this.grossWt,
    required this.netWt,
    required this.totalAmt,
  });
}

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  static const _filterBlue = Color(0xFF2563EB);

  static const List<MapEntry<String, String>> _dateFieldOptions = [
    MapEntry('OrderDate', 'Order Date'),
    MapEntry('DeliverDate', 'Delivery Date'),
  ];

  static const List<String> _orderStatusOptions = [
    'Order Received',
    'Allocation Pending',
    'Order Completed',
    'Order In Process',
    'Partial Order In Process',
  ];

  final TextEditingController _searchController = TextEditingController();
  _OrderReportView _reportView = _OrderReportView.allOrders;
  String _filterDateField = 'OrderDate';
  DateTime? _filterFromDate;
  DateTime? _filterToDate;
  String _filterStatus = '';

  bool get _hasActiveFilters =>
      _reportView != _OrderReportView.allOrders ||
      _filterFromDate != null ||
      _filterToDate != null ||
      _filterStatus.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Wait for page transition so dashboard → list feels instant.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      runAfterRouteSettled(context, () {
        if (!mounted) return;
        final vm = context.read<OrderViewModel>();
        unawaited(vm.loadMasterData());
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

  Map<String, dynamic> _asOrderMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  DateTime? _parseDateValue(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;

    final isoPart = text.split('T').first.trim();
    var parsed = DateTime.tryParse(isoPart);
    if (parsed != null) return parsed;

    final slashParts = isoPart.split('/');
    if (slashParts.length == 3) {
      final day = int.tryParse(slashParts[0]);
      final month = int.tryParse(slashParts[1]);
      final year = int.tryParse(slashParts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final dashParts = isoPart.split('-');
    if (dashParts.length == 3) {
      final year = int.tryParse(dashParts[0]);
      final month = int.tryParse(dashParts[1]);
      final day = int.tryParse(dashParts[2]);
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  List<String> _statusFilterOptions(List<dynamic> ordersHistory) {
    final options = <String>[..._orderStatusOptions];
    for (final raw in ordersHistory) {
      if (raw is! Map) continue;
      final status = _resolveOrderStatus(_asOrderMap(raw));
      if (status.isNotEmpty && !options.contains(status)) {
        options.add(status);
      }
    }
    return options;
  }

  String _resolveCustomerName(Map<String, dynamic> order) {
    final custMap = _asOrderMap(order['Customer']);
    final name = '${custMap['FirstName'] ?? ''} ${custMap['LastName'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    return order['CustomerName']?.toString().trim() ?? '';
  }

  DateTime? _resolveOrderDateTime(Map<String, dynamic> order) {
    var raw = order['OrderDate'];
    if (raw == null || raw.toString().trim().isEmpty) {
      final items = order['CustomOrderItem'] as List?;
      if (items != null && items.isNotEmpty) {
        final first = items.first;
        if (first is Map) raw = first['OrderDate'];
      }
    }
    raw ??= order['CreatedOn'] ?? order['LastUpdated'];
    return _parseDateValue(raw);
  }

  DateTime? _resolveDeliverDateTime(Map<String, dynamic> order) {
    var parsed = _parseDateValue(order['DeliverDate']);
    if (parsed != null) return parsed;

    final items = order['CustomOrderItem'] as List?;
    if (items == null) return null;

    DateTime? best;
    for (final raw in items) {
      if (raw is! Map) continue;
      final itemDate = _parseDateValue(raw['DeliverDate']);
      if (itemDate == null) continue;
      if (best == null || itemDate.isAfter(best)) best = itemDate;
    }
    return best;
  }

  DateTime? _resolveFilterDateTime(Map<String, dynamic> order) {
    if (_filterDateField == 'DeliverDate') {
      return _resolveDeliverDateTime(order) ?? _resolveOrderDateTime(order);
    }
    return _resolveOrderDateTime(order);
  }

  String _resolveOrderStatus(Map<String, dynamic> order) {
    final status = order['OrderStatus']?.toString().trim() ?? '';
    if (status.isNotEmpty) return status;
    if (order['IsPendingSync'] == true ||
        order['IsPendingSync']?.toString().toLowerCase() == 'true') {
      return 'Pending Sync';
    }
    return 'Order Received';
  }

  bool _matchesStatusFilter(Map<String, dynamic> order) {
    if (_filterStatus.isEmpty) return true;
    final status = _resolveOrderStatus(order).toLowerCase();
    return status == _filterStatus.toLowerCase();
  }

  bool _isWithinFilterDateRange(DateTime day) {
    var from = _filterFromDate == null
        ? null
        : DateTime(_filterFromDate!.year, _filterFromDate!.month, _filterFromDate!.day);
    var to = _filterToDate == null
        ? null
        : DateTime(_filterToDate!.year, _filterToDate!.month, _filterToDate!.day);

    if (from != null && to != null && from.isAfter(to)) {
      final swap = from;
      from = to;
      to = swap;
    }

    if (from != null && day.isBefore(from)) return false;
    if (to != null && day.isAfter(to)) return false;
    return true;
  }

  int _compareFilteredOrders(Map<String, dynamic> a, Map<String, dynamic> b) {
    final dateA = _resolveFilterDateTime(a);
    final dateB = _resolveFilterDateTime(b);
    if (dateA != null && dateB != null) {
      final byDate = dateB.compareTo(dateA);
      if (byDate != 0) return byDate;
    } else if (dateA != null) {
      return -1;
    } else if (dateB != null) {
      return 1;
    }

    final noA = int.tryParse(_resolveOrderNo(a)) ?? 0;
    final noB = int.tryParse(_resolveOrderNo(b)) ?? 0;
    if (noA != noB) return noB.compareTo(noA);

    final idA = a['CustomOrderId'] as int? ?? int.tryParse(a['CustomOrderId']?.toString() ?? '') ?? 0;
    final idB = b['CustomOrderId'] as int? ?? int.tryParse(b['CustomOrderId']?.toString() ?? '') ?? 0;
    return idB.compareTo(idA);
  }

  Future<void> _pickFilterDate({
    required BuildContext dialogContext,
    required DateTime? initial,
    required ValueChanged<DateTime?> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: dialogContext,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _showFilterDialog() async {
    final ordersHistory = context.read<OrderViewModel>().ordersHistory;
    final statusOptions = _statusFilterOptions(ordersHistory);

    var tempReportView = _reportView;
    var tempDateField = _filterDateField;
    var tempFrom = _filterFromDate;
    var tempTo = _filterToDate;
    var tempStatus = _filterStatus;
    if (!_dateFieldOptions.any((e) => e.key == tempDateField)) {
      tempDateField = 'OrderDate';
    }
    if (tempStatus.isNotEmpty && !statusOptions.contains(tempStatus)) {
      tempStatus = '';
    }

    await showAppDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget sectionLabel(String text) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  text,
                  style: AppFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                    letterSpacing: 0.6,
                  ),
                ),
              );
            }

            Widget reportOption(String label, _OrderReportView value) {
              final selected = tempReportView == value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setDialogState(() => tempReportView = value),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? _filterBlue : Colors.grey.shade300,
                        width: selected ? 1.5 : 1,
                      ),
                      color: selected ? _filterBlue.withValues(alpha: 0.05) : Colors.white,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: selected ? _filterBlue : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: AppFonts.poppins(
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              color: selected ? _filterBlue : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            Widget dateField({
              required DateTime? value,
              required VoidCallback onTap,
            }) {
              return Expanded(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      hintText: 'dd-mm-yyyy',
                      hintStyle: AppFonts.poppins(fontSize: 13, color: Colors.grey[400]),
                      suffixIcon: Icon(Icons.calendar_today, size: 18, color: Colors.grey[500]),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Text(
                      value == null ? 'dd-mm-yyyy' : DateFormat('dd-MM-yyyy').format(value),
                      style: AppFonts.poppins(
                        fontSize: 13,
                        color: value == null ? Colors.grey[400] : Colors.black87,
                      ),
                    ),
                  ),
                ),
              );
            }

            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, color: Colors.grey[700], size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Report & Filters',
                              style: AppFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            sectionLabel('SELECT REPORT VIEW'),
                            reportOption('All Orders List', _OrderReportView.allOrders),
                            reportOption('SKU Wise Order Summary', _OrderReportView.skuWise),
                            reportOption('Customer Wise Order Summary', _OrderReportView.customerWise),
                            const SizedBox(height: 18),
                            sectionLabel('DATE RANGE FILTER'),
                            DropdownButtonFormField<String>(
                              value: tempDateField,
                              isExpanded: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: _dateFieldOptions
                                  .map(
                                    (entry) => DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(entry.value, style: AppFonts.poppins()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setDialogState(() => tempDateField = val);
                              },
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                dateField(
                                  value: tempFrom,
                                  onTap: () async {
                                    await _pickFilterDate(
                                      dialogContext: dialogContext,
                                      initial: tempFrom,
                                      onPicked: (date) => setDialogState(() => tempFrom = date),
                                    );
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('to', style: AppFonts.poppins(color: Colors.grey[600])),
                                ),
                                dateField(
                                  value: tempTo,
                                  onTap: () async {
                                    await _pickFilterDate(
                                      dialogContext: dialogContext,
                                      initial: tempTo ?? tempFrom,
                                      onPicked: (date) => setDialogState(() => tempTo = date),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            sectionLabel('ORDER STATUS'),
                            DropdownButtonFormField<String>(
                              value: tempStatus.isEmpty ? '' : tempStatus,
                              isExpanded: true,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: '',
                                  child: Text('All Statuses', style: AppFonts.poppins()),
                                ),
                                ...statusOptions.map(
                                  (status) => DropdownMenuItem(
                                    value: status,
                                    child: Text(status, style: AppFonts.poppins()),
                                  ),
                                ),
                              ],
                              onChanged: (val) => setDialogState(() => tempStatus = val ?? ''),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _reportView = _OrderReportView.allOrders;
                                  _filterDateField = 'OrderDate';
                                  _filterFromDate = null;
                                  _filterToDate = null;
                                  _filterStatus = '';
                                });
                                Navigator.pop(ctx);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(
                                'Reset All',
                                style: AppFonts.poppins(fontWeight: FontWeight.w600, color: Colors.grey[700]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _reportView = tempReportView;
                                  _filterDateField = tempDateField;
                                  _filterFromDate = tempFrom;
                                  _filterToDate = tempTo;
                                  _filterStatus = tempStatus;
                                });
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _filterBlue,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(
                                'Apply & Close',
                                style: AppFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<_SkuSummaryRow> _buildSkuSummary(List<dynamic> orders) {
    final map = <String, _SkuSummaryRow>{};

    void add(String sku, double qty, double g, double s, double n, double amt) {
      final key = sku.isEmpty ? '—' : sku;
      final existing = map[key];
      if (existing == null) {
        map[key] = _SkuSummaryRow(sku: key, qty: qty, grossWt: g, stoneWt: s, netWt: n, totalAmt: amt);
      } else {
        map[key] = _SkuSummaryRow(
          sku: key,
          qty: existing.qty + qty,
          grossWt: existing.grossWt + g,
          stoneWt: existing.stoneWt + s,
          netWt: existing.netWt + n,
          totalAmt: existing.totalAmt + amt,
        );
      }
    }

    for (final raw in orders) {
      if (raw is! Map) continue;
      final order = Map<String, dynamic>.from(raw);
      final items = order['CustomOrderItem'] as List? ?? [];
      if (items.isEmpty) {
        add('', double.tryParse(order['Qty']?.toString() ?? '') ?? 0, 0, 0, 0,
            double.tryParse(order['TotalAmount']?.toString() ?? '') ?? 0);
        continue;
      }
      for (final it in items) {
        if (it is! Map) continue;
        final m = Map<String, dynamic>.from(it);
        add(
          m['SKU']?.toString() ?? m['Sku']?.toString() ?? '',
          double.tryParse(m['Quantity']?.toString() ?? m['Qty']?.toString() ?? '') ?? 1,
          double.tryParse(m['GrossWt']?.toString() ?? '') ?? 0,
          double.tryParse(m['StoneWt']?.toString() ?? '') ?? 0,
          double.tryParse(m['NetWt']?.toString() ?? '') ?? 0,
          double.tryParse(m['Amount']?.toString() ?? m['ItemAmt']?.toString() ?? '') ?? 0,
        );
      }
    }

    final rows = map.values.toList()
      ..sort((a, b) => a.sku.toLowerCase().compareTo(b.sku.toLowerCase()));
    return rows;
  }

  List<_CustomerSummaryRow> _buildCustomerSummary(List<dynamic> orders) {
    final map = <String, _CustomerSummaryRow>{};

    for (final raw in orders) {
      if (raw is! Map) continue;
      final order = Map<String, dynamic>.from(raw);
      final name = _resolveCustomerName(order);
      final key = name.isEmpty ? 'Walk-in Customer' : name;
      final weights = _orderWeights(order);
      final qty = double.tryParse(order['Qty']?.toString() ?? '') ?? 0;
      final amt = double.tryParse(order['TotalAmount']?.toString() ?? '') ?? 0;
      final existing = map[key];
      if (existing == null) {
        map[key] = _CustomerSummaryRow(
          customerName: key,
          orderCount: 1,
          qty: qty,
          grossWt: weights['g'] ?? 0,
          netWt: weights['n'] ?? 0,
          totalAmt: amt,
        );
      } else {
        map[key] = _CustomerSummaryRow(
          customerName: key,
          orderCount: existing.orderCount + 1,
          qty: existing.qty + qty,
          grossWt: existing.grossWt + (weights['g'] ?? 0),
          netWt: existing.netWt + (weights['n'] ?? 0),
          totalAmt: existing.totalAmt + amt,
        );
      }
    }

    final rows = map.values.toList()
      ..sort((a, b) => a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase()));
    return rows;
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

  List<dynamic> _applyOrderFilters(List<dynamic> ordersHistory, String query) {
    final filtered = ordersHistory.where((raw) {
      if (raw is! Map) return false;
      final order = _asOrderMap(raw);
      final orderNo = order['OrderNo']?.toString().toLowerCase() ?? '';
      final custName = _resolveCustomerName(order).toLowerCase();
      final matchesSearch = orderNo.contains(query) || custName.contains(query);
      if (!matchesSearch) return false;
      if (!_matchesStatusFilter(order)) return false;

      if (_filterFromDate != null || _filterToDate != null) {
        final orderDate = _resolveFilterDateTime(order);
        if (orderDate == null) return false;
        final day = DateTime(orderDate.year, orderDate.month, orderDate.day);
        if (!_isWithinFilterDateRange(day)) return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      if (a is! Map || b is! Map) return 0;
      return _compareFilteredOrders(_asOrderMap(a), _asOrderMap(b));
    });
    return filtered;
  }

  String _downloadFileName() {
    if (_filterFromDate != null || _filterToDate != null) {
      final from = _filterFromDate != null
          ? DateFormat('yyyyMMdd').format(_filterFromDate!)
          : 'start';
      final to = _filterToDate != null
          ? DateFormat('yyyyMMdd').format(_filterToDate!)
          : 'end';
      return 'Customer_Orders_${from}_to_$to';
    }
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return 'Customer_Orders_$stamp';
  }

  Future<void> _downloadOrders(List<dynamic> ordersHistory) async {
    final s = context.sRead;
    final vm = context.read<OrderViewModel>();
    final filtered = _applyOrderFilters(
      ordersHistory,
      _searchController.text.trim().toLowerCase(),
    );

    if (filtered.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.noOrdersFound)),
      );
      return;
    }

    final enrichedOrders = <Map<String, dynamic>>[];
    for (final raw in filtered) {
      if (raw is! Map) continue;
      enrichedOrders.add(await vm.orderForPdf(_asOrderMap(raw)));
    }

    if (enrichedOrders.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.noOrdersFound)),
      );
      return;
    }

    if (!mounted) return;
    await openOrdersPdf(
      context: context,
      orders: enrichedOrders,
      baseUrl: vm.baseUrl,
      fileName: _downloadFileName(),
    );
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

    final filtered = _applyOrderFilters(ordersHistory, query);

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
          PopupMenuButton<String>(
            icon: Badge(
              isLabelVisible: pendingSyncCount > 0 || _hasActiveFilters,
              smallSize: 8,
              child: const Icon(Icons.more_vert, color: Colors.white),
            ),
            color: Colors.white,
            onSelected: (value) {
              switch (value) {
                case 'sync':
                  if (!isSyncing) _syncOrders();
                  break;
                case 'filter':
                  _showFilterDialog();
                  break;
                case 'download':
                  _downloadOrders(ordersHistory);
                  break;
                case 'add':
                  context.read<OrderViewModel>().clearEditMode();
                  Navigator.pushNamed(context, '/order').then((_) {
                    if (!mounted) return;
                    context.read<OrderViewModel>().fetchOrdersHistory();
                  });
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'sync',
                enabled: !isSyncing,
                child: Row(
                  children: [
                    if (isSyncing)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.cloud_upload, size: 18, color: kListActionIconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s.syncOrdersNow, style: AppFonts.poppins(fontSize: 13)),
                    ),
                    if (pendingSyncCount > 0)
                      Text(
                        '$pendingSyncCount',
                        style: AppFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'filter',
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_list,
                      size: 18,
                      color: _hasActiveFilters ? const Color(0xFF2563EB) : kListActionIconColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.filter,
                        style: AppFonts.poppins(
                          fontSize: 13,
                          fontWeight: _hasActiveFilters ? FontWeight.w600 : FontWeight.normal,
                          color: _hasActiveFilters ? const Color(0xFF2563EB) : null,
                        ),
                      ),
                    ),
                    if (_hasActiveFilters)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2563EB),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'download',
                child: Row(
                  children: [
                    const Icon(Icons.file_download, size: 18, color: kListActionIconColor),
                    const SizedBox(width: 10),
                    Text('Download', style: AppFonts.poppins(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'add',
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 18, color: kListActionIconColor),
                    const SizedBox(width: 10),
                    Text('Add Order', style: AppFonts.poppins(fontSize: 13)),
                  ],
                ),
              ),
            ],
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
                          : _buildReportView(filtered, context.read<OrderViewModel>()),
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

  Widget _buildReportView(List<dynamic> list, OrderViewModel vm) {
    switch (_reportView) {
      case _OrderReportView.skuWise:
        return _buildSkuSummaryView(_buildSkuSummary(list));
      case _OrderReportView.customerWise:
        return _buildCustomerSummaryView(_buildCustomerSummary(list));
      case _OrderReportView.allOrders:
        return _buildSpreadsheetView(list, vm);
    }
  }

  Widget _buildSkuSummaryView(List<_SkuSummaryRow> rows) {
    final s = context.s;
    return SpreadsheetListView(
      rowCount: rows.length,
      actionWidth: 0,
      columns: [
        SpreadsheetColumnDef(
          header: 'SKU',
          width: 120,
          alignLeft: true,
          valueBuilder: (i) => rows[i].sku,
        ),
        SpreadsheetColumnDef(
          header: s.qty,
          width: 70,
          valueBuilder: (i) => rows[i].qty.toStringAsFixed(0),
        ),
        SpreadsheetColumnDef(
          header: s.headerGrossWt,
          width: 90,
          valueBuilder: (i) => rows[i].grossWt.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerStoneWt,
          width: 90,
          valueBuilder: (i) => rows[i].stoneWt.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerNetWt,
          width: 90,
          valueBuilder: (i) => rows[i].netWt.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerTotalAmt,
          width: 110,
          valueBuilder: (i) => '₹${rows[i].totalAmt.toStringAsFixed(2)}',
        ),
      ],
      actionBuilder: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildCustomerSummaryView(List<_CustomerSummaryRow> rows) {
    final s = context.s;
    return SpreadsheetListView(
      rowCount: rows.length,
      actionWidth: 0,
      columns: [
        SpreadsheetColumnDef(
          header: s.headerCustomer,
          width: 170,
          alignLeft: true,
          maxLines: 2,
          valueBuilder: (i) => rows[i].customerName,
        ),
        SpreadsheetColumnDef(
          header: 'Orders',
          width: 70,
          valueBuilder: (i) => rows[i].orderCount.toString(),
        ),
        SpreadsheetColumnDef(
          header: s.qty,
          width: 70,
          valueBuilder: (i) => rows[i].qty.toStringAsFixed(0),
        ),
        SpreadsheetColumnDef(
          header: s.headerGrossWt,
          width: 90,
          valueBuilder: (i) => rows[i].grossWt.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerNetWt,
          width: 90,
          valueBuilder: (i) => rows[i].netWt.toStringAsFixed(3),
        ),
        SpreadsheetColumnDef(
          header: s.headerTotalAmt,
          width: 110,
          valueBuilder: (i) => '₹${rows[i].totalAmt.toStringAsFixed(2)}',
        ),
      ],
      actionBuilder: (_, __) => const SizedBox.shrink(),
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
            final order = list[i] as Map<String, dynamic>;
            final name = _resolveCustomerName(order);
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
                final vm = context.read<OrderViewModel>();
                final enriched = await vm.orderForPdf(order);
                if (!context.mounted) return;
                await printCustomOrderPdf(
                  context: context,
                  orderRes: enriched,
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
