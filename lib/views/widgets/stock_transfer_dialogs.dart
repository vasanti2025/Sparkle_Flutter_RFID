import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/l10n_extension.dart';

/// Sparkle-style Stock Requests dialog (In Request / Out Request).
/// Returns `'In Request'` or `'Out Request'`, or null if dismissed.
Future<String?> showStockRequestPopup(BuildContext context) {
  final s = context.sRead;
  return showAppDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFB71C1C), Color(0xFF3F51B5)],
                ),
              ),
              child: Text(
                s.tr('stockRequests'),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _dialogItem(
                    label: s.tr('inRequest'),
                    onTap: () => Navigator.of(ctx, rootNavigator: true).pop('In Request'),
                  ),
                  _dialogItem(
                    label: s.tr('outRequest'),
                    onTap: () => Navigator.of(ctx, rootNavigator: true).pop('Out Request'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

Widget _dialogItem({required String label, required VoidCallback onTap}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Material(
      color: const Color(0xFFEDEDED),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(label, style: GoogleFonts.poppins(fontSize: 14)),
          ),
        ),
      ),
    ),
  );
}

/// Sparkle StockInScreen Status Filter dialog.
Future<String?> showStockStatusFilterPopup(
  BuildContext context, {
  required String currentStatusKey,
}) {
  final s = context.sRead;
  final options = <({String key, String label, IconData icon})>[
    (key: 'pending', label: s.tr('pending'), icon: Icons.schedule),
    (key: 'approved', label: s.tr('approved'), icon: Icons.check_circle_outline),
    (key: 'rejected', label: s.tr('rejected'), icon: Icons.cancel_outlined),
    (key: 'lost', label: s.tr('lost'), icon: Icons.report_gmailerrorred_outlined),
  ];

  return showAppDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        backgroundColor: Colors.transparent,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                  ),
                ),
                child: Text(
                  s.tr('statusFilter'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              for (final opt in options) ...[
                const Divider(height: 1, thickness: 0.5, color: Color(0xFFE0E0E0)),
                Material(
                  color: currentStatusKey == opt.key
                      ? const Color(0xFFF3E9FF)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(ctx, rootNavigator: true).pop(opt.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(opt.icon, size: 22, color: const Color(0xFF9E9E9E)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              opt.label,
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx, rootNavigator: true).pop('all'),
                child: Text(s.all, style: GoogleFonts.poppins()),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      );
    },
  );
}
