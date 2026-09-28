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
  bool searchable = false,
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
          child: _OptionSheetBody<T>(
            options: options,
            labelOf: labelOf,
            title: title,
            searchable: searchable,
          ),
        ),
      );
    },
  );
}

class _OptionSheetBody<T> extends StatefulWidget {
  final List<T> options;
  final String Function(T option) labelOf;
  final String? title;
  final bool searchable;

  const _OptionSheetBody({
    required this.options,
    required this.labelOf,
    this.title,
    this.searchable = false,
  });

  @override
  State<_OptionSheetBody<T>> createState() => _OptionSheetBodyState<T>();
}

class _OptionSheetBodyState<T> extends State<_OptionSheetBody<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options
            .where((o) => widget.labelOf(o).toLowerCase().contains(q))
            .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null && widget.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              widget.title!,
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[500]),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        Flexible(
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No matches', style: GoogleFonts.poppins(color: Colors.grey[600])),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final option = filtered[i];
                    return ListTile(
                      title: Text(widget.labelOf(option), style: GoogleFonts.poppins(fontSize: 14)),
                      onTap: () => Navigator.pop(context, option),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
