import 'package:flutter/material.dart';

import '../../l10n/l10n_extension.dart';
import '../../utils/app_fonts.dart';

/// Same Matched / Unmatched / Unlabelled / Resume / Search Unmatched panel
/// used on Scan Display. Shared so Search Unmatched can show the identical popup.
class ScanDisplayListMenuOverlay extends StatelessWidget {
  final int matchedCount;
  final int unmatchedCount;
  final int unlabelledCount;
  final VoidCallback onDismiss;
  final VoidCallback onMatched;
  final VoidCallback onUnmatched;
  final VoidCallback onUnlabelled;
  final VoidCallback onResumeScan;
  final VoidCallback onSearchUnmatched;

  const ScanDisplayListMenuOverlay({
    super.key,
    required this.matchedCount,
    required this.unmatchedCount,
    required this.unlabelledCount,
    required this.onDismiss,
    required this.onMatched,
    required this.onUnmatched,
    required this.onUnlabelled,
    required this.onResumeScan,
    required this.onSearchUnmatched,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Positioned.fill(
      child: GestureDetector(
        onTap: onDismiss,
        child: Container(
          color: Colors.black54,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 60,
                bottom: 70,
                width: 180,
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    elevation: 8,
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 16.0,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _menuCard(
                              title: s.matchedItems,
                              icon: Icons.check_circle_outline,
                              count: matchedCount,
                              onTap: onMatched,
                            ),
                            const SizedBox(height: 8),
                            _menuCard(
                              title: s.unmatchedItems,
                              icon: Icons.error_outline,
                              count: unmatchedCount,
                              onTap: onUnmatched,
                            ),
                            const SizedBox(height: 8),
                            _menuCard(
                              title: s.unlabelledItems,
                              icon: Icons.label_off_outlined,
                              count: unlabelledCount,
                              onTap: onUnlabelled,
                            ),
                            const SizedBox(height: 8),
                            _menuCard(
                              title: s.resumeScan,
                              icon: Icons.play_arrow_outlined,
                              onTap: onResumeScan,
                            ),
                            const SizedBox(height: 8),
                            _menuCard(
                              title: s.searchUnmatched,
                              icon: Icons.search,
                              count: unmatchedCount,
                              onTap: onSearchUnmatched,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuCard({
    required String title,
    required IconData icon,
    int? count,
    required VoidCallback onTap,
  }) {
    final displayText = count != null ? '$title ($count)' : title;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3053F0), Color(0xFFE82E5A)],
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Container(
          margin: const EdgeInsets.all(1.0),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3.0),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: const Color(0xFF5231A7),
              ),
              const SizedBox(height: 4),
              Text(
                displayText,
                style: AppFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
                softWrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
