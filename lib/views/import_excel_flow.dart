import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../viewmodels/import_excel_view_model.dart';

import 'import_excel_screen.dart';

import 'widgets/excel_field_mapping_dialog.dart';

import 'widgets/excel_file_picker_dialog.dart';



/// Opens Import Excel instantly from Product screen — no empty route or preload wait.

class ImportExcelFlow {

  ImportExcelFlow._();



  static Future<void> start(BuildContext context) async {

    final vm = context.read<ImportExcelViewModel>();

    vm.resetImportState();



    final pickConfirmed = await showDialog<bool>(

      context: context,

      barrierDismissible: false,

      builder: (ctx) => ExcelFilePickerDialog(

        onDismiss: () => Navigator.pop(ctx, false),

        onFileSelected: () => Navigator.pop(ctx, true),

      ),

    );

    if (pickConfirmed != true || !context.mounted) return;



    final result = await FilePicker.platform.pickFiles(

      type: FileType.custom,

      allowedExtensions: ['xlsx', 'xls'],

      withData: true,

    );

    if (!context.mounted) return;



    if (result == null || result.files.isEmpty) {

      return start(context);

    }



    final bytes = result.files.first.bytes;

    if (bytes == null) {

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.s.couldNotReadFile)));

      return start(context);

    }



    vm.setFileBytes(bytes);

    final columns = vm.excelColumns;

    if (columns.isEmpty) {

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.s.noHeadersInExcel)));

      return start(context);

    }



    // Prefetch GetAllRFID mapping while user maps columns (Kotlin syncRFIDDataIfNeeded).

    vm.prefetchRfidMap();



    final mapping = await showDialog<Map<String, String>>(

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

      PageRouteBuilder<void>(

        pageBuilder: (_, __, ___) => ImportExcelScreen(initialMapping: mapping),

        transitionDuration: Duration.zero,

        reverseTransitionDuration: const Duration(milliseconds: 200),

      ),

    );

  }

}


