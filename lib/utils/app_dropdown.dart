import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Max height for dropdown / popup menus so long lists become scrollable.
const double kDropdownMenuMaxHeight = 320;

/// Shared constraints for [PopupMenuButton] menus with many items.
const BoxConstraints kPopupMenuConstraints = BoxConstraints(
  maxHeight: kDropdownMenuMaxHeight,
  minWidth: 160,
  maxWidth: 320,
);

/// Scrollable bottom-sheet picker for long option lists.
Future<T?> showScrollableOptionSheet<T>({
  required BuildContext context,
  required List<T> options,
  required String Function(T option) labelOf,
  String? title,
}) {
  if (options.isEmpty) return Future.value(null);

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.55;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null && title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final option = options[i];
                    return ListTile(
                      title: Text(labelOf(option), style: GoogleFonts.poppins(fontSize: 14)),
                      onTap: () => Navigator.pop(ctx, option),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
