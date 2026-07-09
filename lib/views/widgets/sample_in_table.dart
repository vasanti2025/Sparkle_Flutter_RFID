import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';
import '../../models/sample_in.dart';

class SampleInTable extends StatelessWidget {
  final List<Map<String, dynamic>> issueItems;
  final Set<String> scannedCodes;
  final bool isReturnMode;
  final Set<String> selectedReturnCodes;
  final bool Function(Map<String, dynamic>) isMatched;
  final void Function(Map<String, dynamic>) onRowTap;
  final void Function(Map<String, dynamic>, int index)? onRowLongPress;
  final void Function(String itemCode) onReturnToggle;
  final void Function(bool isReturn) onReturnModeChange;

  const SampleInTable({
    super.key,
    required this.issueItems,
    required this.scannedCodes,
    required this.isReturnMode,
    required this.selectedReturnCodes,
    required this.isMatched,
    required this.onRowTap,
    this.onRowLongPress,
    required this.onReturnToggle,
    required this.onReturnModeChange,
  });

  @override
  Widget build(BuildContext context) {
    const colProduct = 100.0;
    const colItemcode = 90.0;
    const colTWt = 60.0;
    const colGwt = 60.0;
    const colSwt = 60.0;
    const colDwt = 60.0;
    const colNwt = 60.0;
    const colFwWt = 70.0;
    const colQty = 50.0;
    const colPcs = 50.0;
    const colStatus = 45.0;
    const scrollWidth = colItemcode + colTWt + colGwt + colSwt + colDwt + colNwt + colFwWt + colQty + colPcs;

    final matchCount = issueItems.where(isMatched).length;
    final notMatchCount = issueItems.length - matchCount;

    double sum(String Function(Map<String, dynamic>) sel) =>
        issueItems.fold(0.0, (s, it) => s + (double.tryParse(sel(it)) ?? 0.0));

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              _header('Product Name', colProduct, alignLeft: true),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: scrollWidth,
                    child: Row(
                      children: [
                        _header('Itemcode', colItemcode),
                        _header('T Wt', colTWt),
                        _header('G.Wt', colGwt),
                        _header('S.Wt', colSwt),
                        _header('D Wt', colDwt),
                        _header('N.Wt', colNwt),
                        _header('F+W Wt', colFwWt),
                        _header('Qty', colQty),
                        _header('Pcs', colPcs),
                      ],
                    ),
                  ),
                ),
              ),
              _header('Status', colStatus),
            ],
          ),
        ),
        Expanded(
          child: issueItems.isEmpty
              ? Center(child: Text(context.s.selectSampleOutNoToLoadItems, style: GoogleFonts.poppins(color: Colors.grey, fontSize: 13)))
              : ListView.builder(
                  itemCount: issueItems.length,
                  itemBuilder: (context, index) {
                    final issue = issueItems[index];
                    final matched = isMatched(issue);
                    final itemCode = issue['ItemCode']?.toString() ?? '';
                    final codeNorm = normSampleCode(itemCode);

                    return InkWell(
                      onTap: isReturnMode ? null : () => onRowTap(issue),
                      onLongPress: onRowLongPress != null ? () => onRowLongPress!(issue, index) : null,
                      child: Container(
                        height: 42,
                        color: index.isEven ? const Color(0xFFF4F4F4) : Colors.white,
                        child: Row(
                          children: [
                            _cell(issue['ProductName']?.toString() ?? '-', colProduct, alignLeft: true),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: scrollWidth,
                                  child: Row(
                                    children: [
                                      _cell(itemCode, colItemcode),
                                      _cell(issue['TotalWt']?.toString() ?? '', colTWt),
                                      _cell(issue['GrossWt']?.toString() ?? '', colGwt),
                                      _cell(issue['StoneWeight']?.toString() ?? '', colSwt),
                                      _cell(issue['DiamondWeight']?.toString() ?? '', colDwt),
                                      _cell(issue['NetWt']?.toString() ?? '', colNwt),
                                      _cell(issue['FineWastageWt']?.toString() ?? '', colFwWt),
                                      _cell('${issue['Quantity'] ?? 1}', colQty),
                                      _cell(issue['Pieces']?.toString() ?? '1', colPcs),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: colStatus,
                              child: Center(
                                child: isReturnMode
                                    ? (matched
                                        ? Checkbox(
                                            value: selectedReturnCodes.any((c) => normSampleCode(c) == codeNorm),
                                            onChanged: (_) => onReturnToggle(itemCode),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          )
                                        : const Icon(Icons.cancel, color: Color(0xFFD32F2F), size: 18))
                                    : Icon(
                                        matched ? Icons.check_circle : Icons.cancel,
                                        color: matched ? const Color(0xFF1B8F3A) : const Color(0xFFD32F2F),
                                        size: 18,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          height: 34,
          color: const Color(0xFF2E2E2E),
          child: Row(
            children: [
              _footerCell('Total', colProduct, alignLeft: true),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: scrollWidth,
                    child: Row(
                      children: [
                        _footerCell('${issueItems.length}', colItemcode),
                        _footerCell(sum((i) => i['TotalWt']?.toString() ?? '0').toStringAsFixed(3), colTWt),
                        _footerCell(sum((i) => i['GrossWt']?.toString() ?? '0').toStringAsFixed(3), colGwt),
                        _footerCell(sum((i) => i['StoneWeight']?.toString() ?? '0').toStringAsFixed(3), colSwt),
                        _footerCell(sum((i) => i['DiamondWeight']?.toString() ?? '0').toStringAsFixed(3), colDwt),
                        _footerCell(sum((i) => i['NetWt']?.toString() ?? '0').toStringAsFixed(3), colNwt),
                        _footerCell(sum((i) => i['FineWastageWt']?.toString() ?? '0').toStringAsFixed(3), colFwWt),
                        _footerCell('${issueItems.fold<int>(0, (s, i) => s + (int.tryParse(i['Quantity']?.toString() ?? '1') ?? 1))}', colQty),
                        _footerCell('${issueItems.fold<double>(0, (s, i) => s + (double.tryParse(i['Pieces']?.toString() ?? '0') ?? 0)).toStringAsFixed(0)}', colPcs),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: colStatus),
            ],
          ),
        ),
        if (scannedCodes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: _countChip(
                    title: 'Return',
                    count: matchCount,
                    enabled: matchCount > 0,
                    onTap: () => onReturnModeChange(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _countChip(
                    title: 'Non Return',
                    count: notMatchCount,
                    enabled: notMatchCount > 0,
                    onTap: () => onReturnModeChange(false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _header(String text, double width, {bool alignLeft = false}) {
    return Container(
      width: width,
      height: 40,
      color: const Color(0xFF2E2E2E),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _cell(String text, double width, {bool alignLeft = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(text, style: GoogleFonts.poppins(fontSize: 11, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _footerCell(String text, double width, {bool alignLeft = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(text, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _countChip({
    required String title,
    required int count,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF2F2F2),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: GoogleFonts.poppins(fontSize: 12, color: enabled ? Colors.black : Colors.grey)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF7B1FA2), borderRadius: BorderRadius.circular(6)),
                child: Text('$count', style: GoogleFonts.poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
