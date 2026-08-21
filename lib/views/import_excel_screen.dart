import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../utils/app_dialogs.dart';
import '../viewmodels/import_excel_view_model.dart';

/// Progress + result screen only. File picker and mapping run on Product screen.
class ImportExcelScreen extends StatefulWidget {
  final Map<String, String> initialMapping;
  /// When set, import from Google Sheet CSV (Sparkle sync sheet path).
  final String? googleSheetCsvUrl;

  const ImportExcelScreen({
    super.key,
    required this.initialMapping,
    this.googleSheetCsvUrl,
  });

  @override
  State<ImportExcelScreen> createState() => _ImportExcelScreenState();
}

class _ImportExcelScreenState extends State<ImportExcelScreen> {
  bool _resultShown = false;
  bool _importStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startImport());
  }

  Future<void> _startImport() async {
    if (_importStarted || !mounted) return;
    _importStarted = true;
    final vm = context.read<ImportExcelViewModel>();
    final sheetUrl = widget.googleSheetCsvUrl;
    if (sheetUrl != null && sheetUrl.isNotEmpty) {
      await vm.importMappedDataFromSheet(sheetUrl, widget.initialMapping);
    } else {
      await vm.importMappedData(widget.initialMapping);
    }
  }

  void _goBackToProductManagement() {
    if (mounted) {
      Navigator.popUntil(context, ModalRoute.withName('/product_management'));
    }
  }

  void _showResultDialog(ImportExcelViewModel vm) {
    if (_resultShown) return;
    _resultShown = true;
    final s = context.sRead;

    final failed = vm.progress.failedFields;
    final isError = failed.isNotEmpty || vm.progress.importedFields == 0;
    final message = !isError
        ? '✅ ${s.importSuccessfulCount(vm.progress.importedFields)}'
        : '⚠️ ${s.importWithErrorsList(failed.join(', '))}';

    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 360, maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isError ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      size: 100,
                      color: isError ? Colors.orange : Colors.green,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isError ? Colors.red : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 25),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(colors: [Color(0xFF3053F0), Color(0xFFE82E5A)]),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            vm.resetImportState();
                            Navigator.pop(ctx);
                            _goBackToProductManagement();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(s.done, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: () {
                    vm.resetImportState();
                    Navigator.pop(ctx);
                    _goBackToProductManagement();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ImportExcelViewModel>();
    final s = context.s;

    if (vm.importDone && !_resultShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showResultDialog(vm);
      });
    }

    final total = vm.progress.totalFields;
    final done = vm.progress.importedFields;
    final progressValue = total > 0 ? (done / total).clamp(0.0, 1.0) : null;

    // Light full-screen progress (avoid black overlay flash during long imports).
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF5231A7),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      s.importingExcelData,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                      backgroundColor: const Color(0xFFE5E7EB),
                      color: const Color(0xFF5231A7),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s.fieldsImportedProgress(done, total),
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    if (vm.progress.failedFields.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        s.failedFieldsLabel(vm.progress.failedFields.join(', ')),
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.red),
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
