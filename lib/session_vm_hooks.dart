import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'viewmodels/product_view_model.dart';
import 'viewmodels/stock_transfer_view_model.dart';

/// Product / stock-transfer VM hooks — loaded only after Login, not at splash.
void resetStockTransferSession(BuildContext context) {
  _retry(() {
    context.read<StockTransferViewModel>().resetSession();
  }, context);
}

void startProductSyncAfterLogin(BuildContext context) {
  _retry(() {
    final productVm = context.read<ProductViewModel>();
    Future<void>.delayed(const Duration(seconds: 1), () {
      unawaited(productVm.syncProducts(force: true));
    });
  }, context);
}

Future<void> resetProductAndStockForLogout(BuildContext context) async {
  try {
    await context.read<ProductViewModel>().resetForLogout();
  } catch (_) {}
  if (!context.mounted) return;
  try {
    context.read<StockTransferViewModel>().resetSession();
  } catch (_) {}
}

void _retry(void Function() action, BuildContext context, [int attempt = 0]) {
  try {
    action();
  } catch (_) {
    if (attempt >= 8 || !context.mounted) return;
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (context.mounted) _retry(action, context, attempt + 1);
    });
  }
}
