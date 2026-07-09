import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';

import '../viewmodels/import_excel_view_model.dart';



/// Progress + result screen only. File picker and mapping run on Product screen.

class ImportExcelScreen extends StatefulWidget {

  final Map<String, String> initialMapping;



  const ImportExcelScreen({

    super.key,

    required this.initialMapping,

  });



  @override

  State<ImportExcelScreen> createState() => _ImportExcelScreenState();

}



class _ImportExcelScreenState extends State<ImportExcelScreen> {

  bool _showOverlay = true;

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

    await context.read<ImportExcelViewModel>().importMappedData(widget.initialMapping);

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



    showDialog<void>(

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

        setState(() => _showOverlay = false);

        _showResultDialog(vm);

      });

    }



    return Scaffold(

      backgroundColor: Colors.white,

      body: Stack(

        children: [

          if (_showOverlay)

            Container(

              color: Colors.black.withValues(alpha: 0.5),

              alignment: Alignment.center,

              padding: const EdgeInsets.all(32),

              child: ConstrainedBox(

                constraints: BoxConstraints(maxWidth: 360),

                child: Card(

                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

                  child: Padding(

                    padding: const EdgeInsets.all(24),

                    child: Column(

                      mainAxisSize: MainAxisSize.min,

                      children: [

                        Text(s.importingExcelData, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),

                        const SizedBox(height: 12),

                        LinearProgressIndicator(

                          value: vm.progress.totalFields > 0

                              ? vm.progress.importedFields / vm.progress.totalFields

                              : null,

                        ),

                        const SizedBox(height: 8),

                        Text(

                          s.fieldsImportedProgress(vm.progress.importedFields, vm.progress.totalFields),

                          style: GoogleFonts.poppins(fontSize: 13),

                          textAlign: TextAlign.center,

                        ),

                        if (vm.progress.failedFields.isNotEmpty) ...[

                          const SizedBox(height: 6),

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

        ],

      ),

    );

  }

}


