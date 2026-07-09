import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/stock_verification_report.dart';
import '../../l10n/l10n_extension.dart';

typedef DetailNavCallback = void Function({
  required int branchId,
  int? categoryId,
  int? productId,
  int? designId,
  required String type,
});

class ConsolidatedReportTree extends StatelessWidget {
  final List<ReportBranch> branches;
  final String selectedDate;
  final DetailNavCallback onBadgeTap;

  const ConsolidatedReportTree({
    super.key,
    required this.branches,
    required this.selectedDate,
    required this.onBadgeTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: branches.length,
      itemExtent: null,
      cacheExtent: 400,
      itemBuilder: (context, index) => _BranchRow(
        branch: branches[index],
        onBadgeTap: onBadgeTap,
      ),
    );
  }
}

class _BranchRow extends StatefulWidget {
  final ReportBranch branch;
  final DetailNavCallback onBadgeTap;

  const _BranchRow({required this.branch, required this.onBadgeTap});

  @override
  State<_BranchRow> createState() => _BranchRowState();
}

class _BranchRowState extends State<_BranchRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.branch;
    return Column(
      children: [
        _HierarchyCard(
          bg: const Color(0xFFF5F5F5),
          indent: 0,
          name: b.branchName ?? '-',
          total: b.totalInventoryItems ?? 0,
          matched: b.totalScannedItems ?? 0,
          unmatched: b.notScannedItems ?? 0,
          onTap: () => setState(() => _expanded = !_expanded),
          onTotal: () => widget.onBadgeTap(branchId: b.branchId ?? 0, type: 'TOTAL'),
          onMatched: () => widget.onBadgeTap(branchId: b.branchId ?? 0, type: 'MATCHED'),
          onUnmatched: () => widget.onBadgeTap(branchId: b.branchId ?? 0, type: 'UNMATCHED'),
        ),
        if (_expanded)
          ...b.categories.map(
            (c) => _CategoryRow(
              branchId: b.branchId ?? 0,
              category: c,
              onBadgeTap: widget.onBadgeTap,
            ),
          ),
      ],
    );
  }
}

class _CategoryRow extends StatefulWidget {
  final int branchId;
  final ReportCategory category;
  final DetailNavCallback onBadgeTap;

  const _CategoryRow({
    required this.branchId,
    required this.category,
    required this.onBadgeTap,
  });

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return Column(
      children: [
        _HierarchyCard(
          bg: const Color(0xFFF2F2F2),
          indent: 12,
          name: c.categoryName ?? '-',
          total: c.totalInventoryItems ?? 0,
          matched: c.totalScannedItems ?? 0,
          unmatched: c.notScannedItems ?? 0,
          onTap: () => setState(() => _expanded = !_expanded),
          onTotal: () => widget.onBadgeTap(
            branchId: widget.branchId,
            categoryId: c.categoryId,
            type: 'TOTAL',
          ),
          onMatched: () => widget.onBadgeTap(
            branchId: widget.branchId,
            categoryId: c.categoryId,
            type: 'MATCHED',
          ),
          onUnmatched: () => widget.onBadgeTap(
            branchId: widget.branchId,
            categoryId: c.categoryId,
            type: 'UNMATCHED',
          ),
        ),
        if (_expanded)
          ...c.products.map(
            (p) => _ProductRow(
              branchId: widget.branchId,
              categoryId: c.categoryId,
              product: p,
              onBadgeTap: widget.onBadgeTap,
            ),
          ),
      ],
    );
  }
}

class _ProductRow extends StatefulWidget {
  final int branchId;
  final int? categoryId;
  final ReportProduct product;
  final DetailNavCallback onBadgeTap;

  const _ProductRow({
    required this.branchId,
    required this.categoryId,
    required this.product,
    required this.onBadgeTap,
  });

  @override
  State<_ProductRow> createState() => _ProductRowState();
}

class _ProductRowState extends State<_ProductRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Column(
      children: [
        _HierarchyCard(
          bg: const Color(0xFFFAFAFA),
          indent: 24,
          name: p.productName ?? '-',
          total: p.totalInventoryItems ?? 0,
          matched: p.totalScannedItems ?? 0,
          unmatched: p.notScannedItems ?? 0,
          onTap: () => setState(() => _expanded = !_expanded),
          onTotal: () => widget.onBadgeTap(
            branchId: widget.branchId,
            categoryId: widget.categoryId,
            productId: p.productId,
            type: 'TOTAL',
          ),
          onMatched: () => widget.onBadgeTap(
            branchId: widget.branchId,
            categoryId: widget.categoryId,
            productId: p.productId,
            type: 'MATCHED',
          ),
          onUnmatched: () => widget.onBadgeTap(
            branchId: widget.branchId,
            categoryId: widget.categoryId,
            productId: p.productId,
            type: 'UNMATCHED',
          ),
        ),
        if (_expanded)
          ...p.designs.map(
            (d) => _DesignRow(
              branchId: widget.branchId,
              categoryId: widget.categoryId,
              productId: p.productId,
              design: d,
              onBadgeTap: widget.onBadgeTap,
            ),
          ),
      ],
    );
  }
}

class _DesignRow extends StatelessWidget {
  final int branchId;
  final int? categoryId;
  final int? productId;
  final ReportDesign design;
  final DetailNavCallback onBadgeTap;

  const _DesignRow({
    required this.branchId,
    required this.categoryId,
    required this.productId,
    required this.design,
    required this.onBadgeTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = design;
    return _HierarchyCard(
      bg: Colors.white,
      indent: 36,
      name: d.designName ?? '-',
      total: d.totalInventoryItems ?? 0,
      matched: d.totalScannedItems ?? 0,
      unmatched: d.notScannedItems ?? 0,
      onTap: null,
      onTotal: () => onBadgeTap(
        branchId: branchId,
        categoryId: categoryId,
        productId: productId,
        designId: d.designId,
        type: 'TOTAL',
      ),
      onMatched: () => onBadgeTap(
        branchId: branchId,
        categoryId: categoryId,
        productId: productId,
        designId: d.designId,
        type: 'MATCHED',
      ),
      onUnmatched: () => onBadgeTap(
        branchId: branchId,
        categoryId: categoryId,
        productId: productId,
        designId: d.designId,
        type: 'UNMATCHED',
      ),
    );
  }
}

class _HierarchyCard extends StatelessWidget {
  final Color bg;
  final double indent;
  final String name;
  final int total;
  final int matched;
  final int unmatched;
  final VoidCallback? onTap;
  final VoidCallback onTotal;
  final VoidCallback onMatched;
  final VoidCallback onUnmatched;

  const _HierarchyCard({
    required this.bg,
    required this.indent,
    required this.name,
    required this.total,
    required this.matched,
    required this.unmatched,
    this.onTap,
    required this.onTotal,
    required this.onMatched,
    required this.onUnmatched,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, top: 4, bottom: 4, right: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 13,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _QtyBadge(value: total, color: const Color(0xFFBBDEFB), onTap: onTotal),
                _QtyBadge(value: matched, color: const Color(0xFFC8E6C9), onTap: onMatched),
                _QtyBadge(value: unmatched, color: const Color(0xFFFFCDD2), onTap: onUnmatched),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QtyBadge extends StatelessWidget {
  final int value;
  final Color color;
  final VoidCallback onTap;

  const _QtyBadge({required this.value, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 9,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '$value',
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class ConsolidatedHeaderRow extends StatelessWidget {
  const ConsolidatedHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 13, child: _hdr(s.branch)),
          Expanded(flex: 9, child: _hdr(s.totalInv)),
          Expanded(flex: 9, child: _hdr(s.matched)),
          Expanded(flex: 9, child: _hdr(s.unmatched)),
        ],
      ),
    );
  }

  Widget _hdr(String t) => Text(
        t,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
}

class BatchHeaderRow extends StatelessWidget {
  const BatchHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 14, child: _hdr(s.branch)),
          Expanded(flex: 14, child: _hdr(s.start)),
          Expanded(flex: 14, child: _hdr(s.end)),
          Expanded(flex: 10, child: _hdr(s.totalQty)),
          Expanded(flex: 10, child: _hdr(s.match)),
          Expanded(flex: 12, child: _hdr(s.unmatch)),
        ],
      ),
    );
  }

  Widget _hdr(String t) => Text(
        t,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
}

class BatchSessionRow extends StatelessWidget {
  final ReportSessionItem session;
  final VoidCallback onTap;

  const BatchSessionRow({super.key, required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(flex: 14, child: _cell(session.branchName ?? '_')),
            Expanded(flex: 14, child: _cell(formatReportDateTime(session.startedOn))),
            Expanded(flex: 14, child: _cell(formatReportDateTime(session.endedOn))),
            Expanded(flex: 10, child: _cell('${session.totalQty}')),
            Expanded(flex: 10, child: _cell('${session.matchQty}')),
            Expanded(flex: 12, child: _cell('${session.unmatchQty}')),
          ],
        ),
      ),
    );
  }

  Widget _cell(String t) => Text(
        t,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 11),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );

  String formatReportDateTime(String dateTime) {
    try {
      final parsed = DateTime.parse(dateTime);
      return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year} '
          '${parsed.hour > 12 ? parsed.hour - 12 : parsed.hour}:${parsed.minute.toString().padLeft(2, '0')} '
          '${parsed.hour >= 12 ? 'PM' : 'AM'}';
    } catch (_) {
      return dateTime;
    }
  }
}
