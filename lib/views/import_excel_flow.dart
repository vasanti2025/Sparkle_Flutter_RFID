import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../viewmodels/import_excel_view_model.dart';
import 'import_excel_screen.dart';
import '../utils/app_dialogs.dart';
import '../utils/fast_page_route.dart';
import 'widgets/excel_file_picker_dialog.dart';
import 'widgets/excel_field_mapping_dialog.dart';

/// Opens Import Excel instantly from Product screen — no empty route or preload wait.
class ImportExcelFlow {
  ImportExcelFlow._();

  static Future<void> start(BuildContext context) async {
    final vm = context.read<ImportExcelViewModel>();
    vm.resetImportState();

    final pickConfirmed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExcelFilePickerDialog(
        onDismiss: () => Navigator.pop(ctx, false),
        onFileSelected: () => Navigator.pop(ctx, true),
      ),
    );
    if (pickConfirmed != true || !context.mounted) return;

    // Prefer path over in-memory bytes to reduce peak RAM on large files.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: false,
    );
    if (!context.mounted) return;

    if (result == null || result.files.isEmpty) {
      return start(context);
    }

    final path = result.files.first.path;
    final fallbackBytes = result.files.first.bytes;
    if ((path == null || path.isEmpty) && fallbackBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.sRead.couldNotReadFile)));
      return start(context);
    }

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
                  context.sRead.importingExcelData,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);
    try {
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        await vm.setFileFromPathAsync(path);
      } else if (fallbackBytes != null) {
        await vm.setFileBytesAsync(fallbackBytes);
      } else {
        throw Exception('Could not read Excel file');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.sRead.couldNotReadFile)),
        );
      }
      return;
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;

    final columns = vm.excelColumns;
    if (columns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.sRead.noHeadersInExcel)));
      return start(context);
    }

    vm.prefetchRfidMap();

    final mapping = await showAppDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExcelFieldMappingDialog(
        excelColumns: columns,
        onDismiss: () => Navigator.pop(ctx),
        onImport: (m) => Navigator.pop(ctx, m),
      ),
    );
    if (mapping == null || !context.mounted) return;

    await Navigator.push<void>(
      context,
      FastPageRoute<void>(
        settings: const RouteSettings(name: '/import_excel'),
        child: ImportExcelScreen(initialMapping: mapping),
      ),
    );
  }
}
