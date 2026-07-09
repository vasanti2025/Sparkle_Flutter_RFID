import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../services/db_service.dart';
import '../services/excel_product_service.dart';
import '../viewmodels/product_view_model.dart';
import 'import_excel_flow.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() => _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  bool _dialogShown = false;
  bool _exporting = false;

  Future<void> _exportExcel(BuildContext context) async {
    final s = context.sRead;
    setState(() => _exporting = true);
    try {
      final db = context.read<DbService>();
      final items = await db.getAllBulkItems();
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.noLocalDataToExportSyncFirst)),
          );
        }
        return;
      }
      final file = await ExcelProductService.exportBulkItemsToExcel(items);
      await ExcelProductService.shareExportedFile(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.exportFailed(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final viewModel = context.watch<ProductViewModel>();

    // Expiry/Success Dialog trigger
    if (viewModel.syncCompleted && !_dialogShown) {
      _dialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSuccessDialog(context, viewModel);
      });
    }

    // Error message trigger
    if (viewModel.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(viewModel.errorMessage!),
            backgroundColor: Colors.red,
          ),
        );
        viewModel.clearErrorMessage();
      });
    }

    // Define Grid Items matching original Kotlin project
    final List<Map<String, dynamic>> productItems = [
      {
        'label': s.addSingleProduct,
        'icon': Icons.add_circle_outline,
        'isGradient': true,
        'action': 'add_single'
      },
      {
        'label': s.addBulkProducts,
        'icon': Icons.grid_on_outlined,
        'isGradient': true,
        'action': 'add_bulk'
      },
      {
        'label': s.importExcel,
        'icon': Icons.file_open_outlined,
        'isGradient': false,
        'action': 'import_excel'
      },
      {
        'label': s.exportExcel,
        'icon': Icons.ios_share_outlined,
        'isGradient': false,
        'action': 'export_excel'
      },
      {
        'label': s.syncData,
        'icon': Icons.sync,
        'isGradient': false,
        'action': 'sync'
      },
      {
        'label': s.scanToDesktop,
        'icon': Icons.monitor_outlined,
        'isGradient': false,
        'action': 'scan_desktop'
      },
      {
        'label': s.syncSheetData,
        'icon': Icons.table_chart_outlined,
        'isGradient': false,
        'action': 'sync_sheet'
      },
      {
        'label': s.uploadDataToServer,
        'icon': Icons.cloud_upload_outlined,
        'isGradient': false,
        'action': 'upload_server'
      },
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              s.product,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final height = constraints.maxHeight;
                        
                        int crossAxisCount = width > 600 ? 4 : 2;
                        int rowCount = (productItems.length / crossAxisCount).ceil();
                        
                        double spacing = width > 600 ? 16 : 12;
                        
                        double cardWidth = (width - (crossAxisCount - 1) * spacing) / crossAxisCount;
                        double cardHeight = (height - (rowCount - 1) * spacing) / rowCount;
                        
                        double childAspectRatio = 1.15;
                        if (cardHeight > 0 && cardWidth > 0) {
                          childAspectRatio = cardWidth / cardHeight;
                        }

                        return GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: productItems.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childAspectRatio: childAspectRatio,
                          ),
                          itemBuilder: (context, index) {
                            final item = productItems[index];
                            final bool isGradient = item['isGradient'] as bool;
                            
                            final decoration = isGradient
                                ? const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  )
                                : const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF2B2B2B), Color(0xFF444444)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  );

                            return Card(
                              elevation: 4,
                              shadowColor: Colors.black26,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                  onTap: () {
                                    final action = item['action'] as String;
                                    if (action == 'sync') {
                                      viewModel.syncProducts();
                                    } else if (action == 'scan_desktop') {
                                      Navigator.pushNamed(context, '/scan_desktop');
                                    } else if (action == 'add_single') {
                                      Navigator.pushNamed(context, '/add_product');
                                    } else if (action == 'add_bulk') {
                                      Navigator.pushNamed(context, '/bulk_product');
                                    } else if (action == 'import_excel') {
                                      ImportExcelFlow.start(context);
                                    } else if (action == 'export_excel') {
                                      _exportExcel(context);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${item['label'].replaceAll('\n', ' ')} - ${s.comingSoon}'),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                child: Container(
                                  decoration: decoration,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        item['icon'] as IconData,
                                        size: width > 600 ? 32 : 28,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        item['label'] as String,
                                        style: GoogleFonts.poppins(
                                          fontSize: width > 600 ? 13 : 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Open Product List bottom button
                  const SizedBox(height: 16),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3053F0), Color(0xFFE82E5A)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            viewModel.refreshList();
                            Navigator.pushNamed(context, '/product_list');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            s.openProductList,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // Non-blocking loader with Circular and Linear progress indicators
          if (viewModel.isLoading || _exporting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withAlpha(153),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Card(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3053F0)),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _exporting ? s.exportingExcel : viewModel.syncStatusText,
                              style: GoogleFonts.poppins(
                                color: Colors.black87,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (!_exporting) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: viewModel.syncProgress,
                                minHeight: 8,
                                backgroundColor: Colors.grey[200],
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE82E5A)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              s.percentCompleted((viewModel.syncProgress * 100).toInt()),
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, ProductViewModel viewModel) {
    bool isExpanded = false;
    final s = context.sRead;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final skipped = viewModel.skippedItemCodes;
        final showList = skipped.take(10).toList();
        final int more = (skipped.length - showList.length).clamp(0, 9999999);

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 20),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () {
                        viewModel.clearSyncCompleted();
                        _dialogShown = false;
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                    size: 80,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.dataSyncSuccessfully,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.syncedItemsCount(viewModel.syncSyncedCount, viewModel.syncTotalCount),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  // Skipped items section
                  if (skipped.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      s.notSyncedCount(skipped.length),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFE82E5A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 140,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: isExpanded ? skipped.length : showList.length,
                        itemBuilder: (context, i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            child: Text(
                              '• ${skipped[i]}',
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87),
                            ),
                          );
                        },
                      ),
                    ),
                    if (skipped.length > 10) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            isExpanded = !isExpanded;
                          });
                        },
                        child: Text(
                          isExpanded ? s.showLess : s.showMoreCount(more),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFF3053F0),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ]
                  ],
                  
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3053F0), Color(0xFFE82E5A)],
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        viewModel.clearSyncCompleted();
                        _dialogShown = false;
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        s.done,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
