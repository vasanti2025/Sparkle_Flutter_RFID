import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../services/google_sheet_service.dart';
import '../services/pref_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/fast_page_route.dart';
import '../viewmodels/import_excel_view_model.dart';
import 'import_excel_screen.dart';
import 'widgets/excel_field_mapping_dialog.dart';

/// Sparkle ProductManagement "Sync Sheet Data" flow.
class SyncSheetFlow {
  SyncSheetFlow._();

  static Future<void> start(BuildContext context) async {
    final s = context.sRead;
    final pref = context.read<PrefService>();
    final vm = context.read<ImportExcelViewModel>();
    vm.resetImportState();

    final sheetId = GoogleSheetService.extractSheetId(pref.getSheetUrl());
    if (sheetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.pleaseAddValidSheetUrl)),
      );
      return;
    }

    final csvUrl = GoogleSheetService.csvExportUrl(sheetId);

    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF5231A7)),
                const SizedBox(height: 16),
                Text(
                  s.fetchingSheetHeaders,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    List<String> headers = const [];
    try {
      headers = await vm.fetchGoogleSheetHeaders(csvUrl);
    } catch (_) {
      headers = const [];
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;

    if (headers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.failedToFetchSheetHeaders)),
      );
      return;
    }

    vm.prefetchRfidMap();
    vm.prepareSheetImport(csvUrl);

    final mapping = await showAppDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExcelFieldMappingDialog(
        excelColumns: headers,
        onDismiss: () => Navigator.pop(ctx),
        onImport: (m) => Navigator.pop(ctx, m),
      ),
    );
    if (mapping == null || !context.mounted) return;

    await Navigator.push<void>(
      context,
      FastPageRoute<void>(
        settings: const RouteSettings(name: '/import_excel'),
        child: ImportExcelScreen(
          initialMapping: mapping,
          googleSheetCsvUrl: csvUrl,
        ),
      ),
    );
  }
}
