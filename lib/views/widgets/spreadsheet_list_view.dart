import 'package:flutter/material.dart';

/// Column definition for the scrollable middle section of a spreadsheet list.
class SpreadsheetColumnDef {
  final String header;
  final double width;
  final bool alignLeft;
  final int maxLines;
  final String Function(int index) valueBuilder;

  const SpreadsheetColumnDef({
    required this.header,
    required this.width,
    required this.valueBuilder,
    this.alignLeft = false,
    this.maxLines = 1,
  });
}

/// Reusable pinned-column spreadsheet: fixed header row, scrollable data rows below.
class SpreadsheetListView extends StatefulWidget {
  final int rowCount;
  final List<SpreadsheetColumnDef> columns;
  final String actionHeader;
  final double actionWidth;
  final Widget Function(BuildContext context, int index) actionBuilder;
  final double rowHeight;
  final double headerHeight;
  final double serialWidth;

  const SpreadsheetListView({
    super.key,
    required this.rowCount,
    required this.columns,
    required this.actionBuilder,
    this.actionHeader = 'Actions',
    this.actionWidth = 85,
    this.rowHeight = 48,
    this.headerHeight = 40,
    this.serialWidth = 45,
  });

  @override
  State<SpreadsheetListView> createState() => _SpreadsheetListViewState();
}

class _SpreadsheetListViewState extends State<SpreadsheetListView> {
  static const Color _headerColor = Color(0xFF2E2E2E);
  static const TextStyle _headerStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  static const TextStyle _cellStyle = TextStyle(fontSize: 11, color: Colors.black87);

  final ScrollController _vLeft = ScrollController();
  final ScrollController _vMiddle = ScrollController();
  final ScrollController _vRight = ScrollController();
  final ScrollController _headerHScroll = ScrollController();
  final ScrollController _bodyHScroll = ScrollController();
  ScrollController? _activeV;
  bool _syncingH = false;

  double get _scrollableWidth =>
      widget.columns.fold(0.0, (sum, col) => sum + col.width);

  @override
  void initState() {
    super.initState();
    _vLeft.addListener(_syncFromLeft);
    _vMiddle.addListener(_syncFromMiddle);
    _vRight.addListener(_syncFromRight);
    _headerHScroll.addListener(_syncHeaderToBody);
    _bodyHScroll.addListener(_syncBodyToHeader);
  }

  void _syncFromLeft() {
    if (_activeV != _vLeft) return;
    if (_vMiddle.hasClients) _vMiddle.jumpTo(_vLeft.offset);
    if (_vRight.hasClients) _vRight.jumpTo(_vLeft.offset);
  }

  void _syncFromMiddle() {
    if (_activeV != _vMiddle) return;
    if (_vLeft.hasClients) _vLeft.jumpTo(_vMiddle.offset);
    if (_vRight.hasClients) _vRight.jumpTo(_vMiddle.offset);
  }

  void _syncFromRight() {
    if (_activeV != _vRight) return;
    if (_vLeft.hasClients) _vLeft.jumpTo(_vRight.offset);
    if (_vMiddle.hasClients) _vMiddle.jumpTo(_vRight.offset);
  }

  void _syncHeaderToBody() {
    if (_syncingH) return;
    if (!_bodyHScroll.hasClients) return;
    _syncingH = true;
    _bodyHScroll.jumpTo(_headerHScroll.offset);
    _syncingH = false;
  }

  void _syncBodyToHeader() {
    if (_syncingH) return;
    if (!_headerHScroll.hasClients) return;
    _syncingH = true;
    _headerHScroll.jumpTo(_bodyHScroll.offset);
    _syncingH = false;
  }

  @override
  void dispose() {
    _vLeft.dispose();
    _vMiddle.dispose();
    _vRight.dispose();
    _headerHScroll.dispose();
    _bodyHScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeaderRow(),
        Expanded(child: _buildBodyRow()),
      ],
    );
  }

  Widget _buildHeaderRow() {
    return SizedBox(
      height: widget.headerHeight,
      child: Row(
        children: [
          _headerCell('S.No', widget.serialWidth),
          Expanded(
            child: SingleChildScrollView(
              controller: _headerHScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _scrollableWidth,
                height: widget.headerHeight,
                child: Row(
                  children: widget.columns
                      .map((c) => _headerCell(c.header, c.width, alignLeft: c.alignLeft))
                      .toList(),
                ),
              ),
            ),
          ),
          _headerCell(widget.actionHeader, widget.actionWidth),
        ],
      ),
    );
  }

  Widget _buildBodyRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: widget.serialWidth,
          child: Listener(
            onPointerDown: (_) => _activeV = _vLeft,
            child: ListView.builder(
              controller: _vLeft,
              padding: EdgeInsets.zero,
              cacheExtent: 320,
              itemExtent: widget.rowHeight,
              itemCount: widget.rowCount,
              itemBuilder: (context, index) {
                return RepaintBoundary(
                  child: _dataCell(
                    '${index + 1}',
                    widget.serialWidth,
                    index,
                    alignLeft: false,
                    center: true,
                  ),
                );
              },
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _bodyHScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _scrollableWidth,
                  height: constraints.maxHeight,
                  child: Listener(
                    onPointerDown: (_) => _activeV = _vMiddle,
                    child: ListView.builder(
                      controller: _vMiddle,
                      padding: EdgeInsets.zero,
                      cacheExtent: 320,
                      itemExtent: widget.rowHeight,
                      itemCount: widget.rowCount,
                      itemBuilder: (context, index) {
                        return RepaintBoundary(
                          key: ValueKey('row-$index'),
                          child: SizedBox(
                            height: widget.rowHeight,
                            child: Row(
                              children: widget.columns.map((col) {
                                return _dataCell(
                                  col.valueBuilder(index),
                                  col.width,
                                  index,
                                  alignLeft: col.alignLeft,
                                  maxLines: col.maxLines,
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: widget.actionWidth,
          child: Listener(
            onPointerDown: (_) => _activeV = _vRight,
            child: ListView.builder(
              controller: _vRight,
              padding: EdgeInsets.zero,
              cacheExtent: 320,
              itemExtent: widget.rowHeight,
              itemCount: widget.rowCount,
              itemBuilder: (context, index) {
                return RepaintBoundary(
                  child: Container(
                    height: widget.rowHeight,
                    decoration: _rowDecoration(index),
                    alignment: Alignment.center,
                    child: widget.actionBuilder(context, index),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _rowDecoration(int index) {
    return BoxDecoration(
      color: index.isOdd ? const Color(0xFFF4F4F4) : Colors.white,
      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
    );
  }

  Widget _headerCell(String label, double width, {bool alignLeft = false}) {
    return Container(
      width: width,
      height: widget.headerHeight,
      color: _headerColor,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(
        label,
        style: _headerStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignLeft ? TextAlign.left : TextAlign.center,
      ),
    );
  }

  Widget _dataCell(
    String text,
    double width,
    int index, {
    bool alignLeft = false,
    bool center = false,
    int maxLines = 1,
  }) {
    return Container(
      width: width,
      height: widget.rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: center
          ? Alignment.center
          : (alignLeft ? Alignment.centerLeft : Alignment.center),
      decoration: _rowDecoration(index),
      child: Text(
        text,
        style: _cellStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: alignLeft ? TextAlign.left : TextAlign.center,
      ),
    );
  }
}
