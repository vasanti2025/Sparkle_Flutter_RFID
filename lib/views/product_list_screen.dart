import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../l10n/l10n_extension.dart';
import '../models/bulk_item.dart';
import '../viewmodels/product_view_model.dart';
import '../theme/list_text_styles.dart';
import 'widgets/scan_bottom_bar.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late ScrollController _leftScrollController;
  late ScrollController _middleScrollController;
  late ScrollController _rightScrollController;
  ScrollController? _activeScrollController;
  final TextEditingController _searchController = TextEditingController();
  
  bool _isGridView = false;
  bool _isExportingPdf = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _leftScrollController = ScrollController();
    _middleScrollController = ScrollController();
    _rightScrollController = ScrollController();

    _leftScrollController.addListener(() {
      if (_activeScrollController == _leftScrollController) {
        if (_middleScrollController.hasClients) _middleScrollController.jumpTo(_leftScrollController.offset);
        if (_rightScrollController.hasClients) _rightScrollController.jumpTo(_leftScrollController.offset);
      }
    });

    _middleScrollController.addListener(() {
      if (_activeScrollController == _middleScrollController) {
        if (_leftScrollController.hasClients) _leftScrollController.jumpTo(_middleScrollController.offset);
        if (_rightScrollController.hasClients) _rightScrollController.jumpTo(_middleScrollController.offset);
      }
      
      // Handle pagination
      if (_middleScrollController.position.pixels >= _middleScrollController.position.maxScrollExtent - 200) {
        Provider.of<ProductViewModel>(context, listen: false).loadNextPage();
      }
    });

    _rightScrollController.addListener(() {
      if (_activeScrollController == _rightScrollController) {
        if (_leftScrollController.hasClients) _leftScrollController.jumpTo(_rightScrollController.offset);
        if (_middleScrollController.hasClients) _middleScrollController.jumpTo(_rightScrollController.offset);
      }
    });

    _leftScrollController.addListener(() {
      if (_leftScrollController.position.pixels >= _leftScrollController.position.maxScrollExtent - 200) {
        Provider.of<ProductViewModel>(context, listen: false).loadNextPage();
      }
    });

    _rightScrollController.addListener(() {
      if (_rightScrollController.position.pixels >= _rightScrollController.position.maxScrollExtent - 200) {
        Provider.of<ProductViewModel>(context, listen: false).loadNextPage();
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = Provider.of<ProductViewModel>(context, listen: false);
      if (viewModel.products.isEmpty) {
        viewModel.loadNextPage();
      }
      _searchController.text = viewModel.searchQuery;
    });
  }

  @override
  void dispose() {
    _leftScrollController.dispose();
    _middleScrollController.dispose();
    _rightScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _editProduct(BulkItem item) async {
    final result = await Navigator.pushNamed(
      context,
      '/edit_product',
      arguments: item,
    );
    if (result == true) {
      if (!mounted) return;
      Provider.of<ProductViewModel>(context, listen: false).refreshList();
    }
  }

  void _confirmDeleteProduct(BulkItem item) {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            s.deleteProduct, 
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Text(
            s.confirmDeleteProduct(item.productName ?? '', item.itemCode ?? ''),
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel, style: GoogleFonts.poppins(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                final viewModel = Provider.of<ProductViewModel>(context, listen: false);
                final success = await viewModel.deleteProductItem(item.bulkItemId);
                if (success) {
                   messenger.showSnackBar(
                    SnackBar(content: Text('✅ ${s.productDeletedSuccessfully}')),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(content: Text('❌ ${s.errorWithMessage(viewModel.errorMessage ?? '')}')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(s.delete, style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showFilterDialog(ProductViewModel viewModel) async {
    final s = context.sRead;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    await viewModel.loadFilterOptions();
    if (mounted) Navigator.pop(context);

    String tempSku = viewModel.selectedSku;
    String tempCategory = viewModel.selectedCategory;
    String tempProduct = viewModel.selectedProduct;
    String tempDesign = viewModel.selectedDesign;
    String tempPurity = viewModel.selectedPurity;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.filter_alt, color: Color(0xFF5231A7)),
                  const SizedBox(width: 8),
                  Text(s.filters, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDropdownField(s.fieldCategory, viewModel.categoryOptions, tempCategory, s, (val) {
                      setState(() => tempCategory = val ?? '');
                    }),
                    _buildDropdownField(s.fieldProduct, viewModel.productOptions, tempProduct, s, (val) {
                      setState(() => tempProduct = val ?? '');
                    }),
                    _buildDropdownField(s.fieldDesign, viewModel.designOptions, tempDesign, s, (val) {
                      setState(() => tempDesign = val ?? '');
                    }),
                    _buildDropdownField(s.fieldPurity, viewModel.purityOptions, tempPurity, s, (val) {
                      setState(() => tempPurity = val ?? '');
                    }),
                    _buildDropdownField(s.fieldSku, viewModel.skuOptions, tempSku, s, (val) {
                      setState(() => tempSku = val ?? '');
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    viewModel.resetFilters();
                    Navigator.pop(context);
                  },
                  child: Text(s.reset, style: GoogleFonts.poppins(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () {
                    viewModel.updateFilters(
                      sku: tempSku,
                      category: tempCategory,
                      product: tempProduct,
                      design: tempDesign,
                      purity: tempPurity,
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5231A7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(s.apply, style: GoogleFonts.poppins(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDropdownField(String label, List<String> options, String selectedValue, dynamic s, ValueChanged<String?> onChanged) {
    final list = [s.all, ...options];
    final currentVal = list.contains(selectedValue) && selectedValue.isNotEmpty ? selectedValue : s.all;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: currentVal,
            onChanged: (val) => onChanged(val == s.all ? '' : val),
            items: list.map((opt) {
              return DropdownMenuItem<String>(
                value: opt,
                child: Text(opt, style: GoogleFonts.poppins(fontSize: 13), overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              fillColor: Colors.grey[50],
              filled: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToPdf(ProductViewModel viewModel) async {
    final s = context.sRead;
    setState(() {
      _isExportingPdf = true;
    });

    try {
      final list = await viewModel.getFilteredProductsForExport();

      if (list.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.noProductsToExport)),
          );
        }
        return;
      }

      final doc = pw.Document();
      final pageFormat = PdfPageFormat.a4.landscape;

      final headers = [
        s.headerSr, s.fieldProduct, s.itemCode, s.colRfid, s.colGrossWt, s.colStoneWt,
        s.colDiamondWt, s.colNetWt, s.fieldCategory, s.fieldDesign, s.fieldPurity, s.colSku, s.colEpc, s.colVendor
      ];

      final chunks = <List<BulkItem>>[];
      for (var i = 0; i < list.length; i += 40) {
        chunks.add(list.sublist(i, i + 40 > list.length ? list.length : i + 40));
      }

      for (var pageIndex = 0; pageIndex < chunks.length; pageIndex++) {
        final chunk = chunks[pageIndex];

        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(15),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(
                      s.labelledStockReport,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(s.totalItems(list.length), style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(s.pageOf(pageIndex + 1, chunks.length), style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.TableHelper.fromTextArray(
                    headers: headers,
                    data: List.generate(chunk.length, (index) {
                      final item = chunk[index];
                      final srNo = pageIndex * 40 + index + 1;
                      return [
                        '$srNo',
                        item.productName,
                        item.itemCode,
                        item.rfid,
                        item.grossWeight,
                        item.stoneWeight,
                        item.diamondWeight,
                        item.netWeight,
                        item.category,
                        item.design,
                        item.purity,
                        item.sku,
                        item.epc,
                        item.vendor,
                      ];
                    }),
                    headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
                    cellStyle: const pw.TextStyle(fontSize: 6),
                    cellAlignment: pw.Alignment.center,
                    cellPadding: const pw.EdgeInsets.all(3),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(25), 
                      1: const pw.FixedColumnWidth(70), 
                      2: const pw.FixedColumnWidth(55), 
                      3: const pw.FixedColumnWidth(55), 
                      4: const pw.FixedColumnWidth(40), 
                      5: const pw.FixedColumnWidth(40), 
                      6: const pw.FixedColumnWidth(40), 
                      7: const pw.FixedColumnWidth(40), 
                      8: const pw.FixedColumnWidth(50), 
                      9: const pw.FixedColumnWidth(50), 
                      10: const pw.FixedColumnWidth(40), 
                      11: const pw.FixedColumnWidth(45), 
                      12: const pw.FixedColumnWidth(85), 
                      13: const pw.FixedColumnWidth(55), 
                    },
                  ),
                ],
              );
            },
          ),
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'LabelledStock_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.errorGeneratingPdf(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final viewModel = context.watch<ProductViewModel>();
    final products = viewModel.products;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      // Keep the scan bottom bar pinned; the keyboard overlays the body
      // instead of pushing the bar up.
      resizeToAvoidBottomInset: false,
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
              s.productListCount(products.length),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => viewModel.refreshList(),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search, View Toggle, Filter & Export PDF Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: s.searchSkuCodeName,
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      viewModel.updateSearchQuery('');
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (val) {
                            setState(() {}); // Toggle suffix icon
                            viewModel.updateSearchQuery(val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildGradientButton(
                        text: _isGridView ? s.listView : s.gridView,
                        iconWidget: Icon(
                          _isGridView ? Icons.view_headline : Icons.grid_view,
                          size: 16,
                          color: Colors.black,
                        ),
                        onTap: () {
                          setState(() {
                            _isGridView = !_isGridView;
                          });
                        },
                      ),
                      const SizedBox(width: 10),
                      _buildGradientButton(
                        text: '${s.filters}${viewModel.selectedCategory.isNotEmpty || viewModel.selectedProduct.isNotEmpty || viewModel.selectedPurity.isNotEmpty ? "(*)" : ""}',
                        iconWidget: const Icon(
                          Icons.filter_alt,
                          size: 16,
                          color: Colors.black,
                        ),
                        onTap: () => _showFilterDialog(viewModel),
                      ),
                      const SizedBox(width: 10),
                      _buildGradientButton(
                        text: _isExportingPdf ? s.exporting : s.exportPdf,
                        iconWidget: _isExportingPdf
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 1.5,
                                ),
                              )
                            : const Icon(
                                Icons.picture_as_pdf,
                                size: 16,
                                color: Colors.black,
                              ),
                        onTap: _isExportingPdf ? () {} : () => _exportToPdf(viewModel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),

            // Main Product Grid/List
            Expanded(
              child: products.isEmpty && !viewModel.isListLoading
                  ? _buildEmptyState()
                  : _isGridView
                      ? _buildGridView(products, viewModel)
                      : _buildSpreadsheetView(products, viewModel),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ScanBottomBar(
        onSave: () {},
        onList: () {},
        onScan: () {
          setState(() {
            _isScanning = !_isScanning;
          });
        },
        onGscan: () {
          setState(() {
            _isScanning = !_isScanning;
          });
        },
        onReset: () {
          setState(() {
            _searchController.clear();
            viewModel.updateSearchQuery('');
            viewModel.resetFilters();
          });
        },
        isScanning: _isScanning,
      ),
    );
  }

  Widget _buildEmptyState() {
    final s = context.s;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            s.noProductsMatchingFilters,
            style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            s.tryResettingFilters,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(List<BulkItem> products, ProductViewModel viewModel) {
    final width = MediaQuery.of(context).size.width;
    int columns = width > 900 ? 3 : 2;

    return GridView.builder(
      controller: _middleScrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemCount: products.length + (viewModel.hasReachedEnd ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == products.length) {
          return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
        }
        return _buildGridCard(products[index]);
      },
    );
  }

  Widget _buildGridCard(BulkItem item) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetailsDialog(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 72,
                  height: 72,
                  color: Colors.grey[100],
                  child: _buildItemImage(item),
                ),
              ),
              const SizedBox(height: 12),
              // Row 1: RFID & Code
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'RFID: ${item.rfid.isNotEmpty ? item.rfid : "-"}',
                      style: GoogleFonts.poppins(fontSize: 9, color: Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Code: ${item.itemCode.isNotEmpty ? item.itemCode : "-"}',
                      style: GoogleFonts.poppins(fontSize: 9, color: Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Row 2: Gross Wt & Net Wt
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'G. Wt: ${item.grossWeight.isNotEmpty ? item.grossWeight : "-"}',
                      style: GoogleFonts.poppins(fontSize: 9, color: Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'N. Wt: ${item.netWeight.isNotEmpty ? item.netWeight : "-"}',
                      style: GoogleFonts.poppins(fontSize: 9, color: Colors.black87),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Gradient Outline button
  Widget _buildGradientButton({
    required String text,
    required Widget iconWidget,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD32940), Color(0xFF5231A7)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Container(
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6.5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconWidget,
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Details dialog on card click
  void _showDetailsDialog(BulkItem item) {
    final s = context.sRead;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                s.itemDetails,
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 150,
                    height: 150,
                    color: Colors.grey[100],
                    child: _buildItemImage(item),
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow(s.productName, item.productName),
                _buildInfoRow(s.itemCode, item.itemCode),
                _buildInfoRow(s.lblRfid, item.rfid),
                _buildInfoRow(s.lblGrossWt, item.grossWeight),
                _buildInfoRow(s.lblStoneWt, item.stoneWeight),
                _buildInfoRow(s.lblDiamondWt, item.diamondWeight),
                _buildInfoRow(s.lblNetWt, item.netWeight),
                _buildInfoRow(s.fieldCategory, item.category),
                _buildInfoRow(s.fieldDesign, item.design),
                _buildInfoRow(s.fieldPurity, item.purity),
                _buildInfoRow(s.makingPerGram, item.makingPerGram),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value.isNotEmpty ? value : '-',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpreadsheetView(List<BulkItem> products, ProductViewModel viewModel) {
    final s = context.s;
    const double colSr = 40;
    const double colActions = 75;

    const double colProduct = 120;
    const double colCode = 70;
    const double colRfid = 60;
    const double colGwt = 60;
    const double colSwt = 60;
    const double colDwt = 60;
    const double colNwt = 60;
    const double colCat = 70;
    const double colDesign = 60;
    const double colPur = 60;
    const double colMakingGram = 80;
    const double colMakingPercent = 80;
    const double colFixMaking = 80;
    const double colFixWastage = 80;
    const double colStoneAmt = 60;
    const double colDiamondAmt = 60;
    const double colSku = 70;
    const double colEpc = 160;
    const double colVendor = 80;

    const double scrollableWidth = colProduct + colCode + colRfid + colGwt + colSwt + colDwt + colNwt + colCat + colDesign + colPur + colMakingGram + colMakingPercent + colFixMaking + colFixWastage + colStoneAmt + colDiamondAmt + colSku + colEpc + colVendor;

    return Row(
      children: [
        // Left Side: Pinned/Fixed Sr Column
        SizedBox(
          width: colSr,
          child: Column(
            children: [
              // Header
              Container(
                height: 40,
                color: Colors.grey[300],
                child: _buildHeaderCell(s.headerSr, colSr),
              ),
              // Pinned rows
              Expanded(
                child: Listener(
                  onPointerDown: (_) => _activeScrollController = _leftScrollController,
                  child: ListView.builder(
                    controller: _leftScrollController,
                    itemCount: products.length + (viewModel.hasReachedEnd ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == products.length) {
                        return const SizedBox(height: 52); // Keep space matching loading indicator on right
                      }
                      final isOdd = index % 2 == 1;
                      return Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: isOdd ? Colors.grey[50] : Colors.white,
                          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                        ),
                        child: Row(
                          children: [
                            _buildDataCell('${index + 1}', colSr),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Middle Side: Scrollable Columns
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: scrollableWidth,
              child: Column(
                children: [
                  // Header
                  Container(
                    height: 40,
                    color: Colors.grey[300],
                    child: Row(
                      children: [
                        _buildHeaderCell(s.fieldProduct, colProduct),
                        _buildHeaderCell(s.itemCode, colCode),
                        _buildHeaderCell(s.lblRfid, colRfid),
                        _buildHeaderCell(s.colGrossWt, colGwt),
                        _buildHeaderCell(s.colStoneWt, colSwt),
                        _buildHeaderCell(s.colDiamondWt, colDwt),
                        _buildHeaderCell(s.colNetWt, colNwt),
                        _buildHeaderCell(s.fieldCategory, colCat),
                        _buildHeaderCell(s.fieldDesign, colDesign),
                        _buildHeaderCell(s.fieldPurity, colPur),
                        _buildHeaderCell(s.makingPerGram, colMakingGram),
                        _buildHeaderCell(s.fieldMakingPercent, colMakingPercent),
                        _buildHeaderCell(s.fieldFixMaking, colFixMaking),
                        _buildHeaderCell(s.fieldFixWastage, colFixWastage),
                        _buildHeaderCell(s.colStoneAmt, colStoneAmt),
                        _buildHeaderCell(s.colDiamondAmt, colDiamondAmt),
                        _buildHeaderCell(s.colSku, colSku),
                        _buildHeaderCell(s.colEpc, colEpc),
                        _buildHeaderCell(s.colVendor, colVendor),
                      ],
                    ),
                  ),
                  // Scrollable rows
                  Expanded(
                    child: Listener(
                      onPointerDown: (_) => _activeScrollController = _middleScrollController,
                      child: ListView.builder(
                        controller: _middleScrollController,
                        itemCount: products.length + (viewModel.hasReachedEnd ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (index == products.length) {
                            return const SizedBox(
                              height: 52,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final item = products[index];
                          final isOdd = index % 2 == 1;

                          return Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: isOdd ? Colors.grey[50] : Colors.white,
                              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                            ),
                            child: Row(
                              children: [
                                _buildDataCell(item.productName, colProduct),
                                _buildDataCell(item.itemCode, colCode),
                                _buildDataCell(item.rfid, colRfid),
                                _buildDataCell(item.grossWeight, colGwt),
                                _buildDataCell(item.stoneWeight, colSwt),
                                _buildDataCell(item.diamondWeight, colDwt),
                                _buildDataCell(item.netWeight, colNwt),
                                _buildDataCell(item.category, colCat),
                                _buildDataCell(item.design, colDesign),
                                _buildDataCell(item.purity, colPur),
                                _buildDataCell(item.makingPerGram, colMakingGram),
                                _buildDataCell(item.makingPercent, colMakingPercent),
                                _buildDataCell(item.fixMaking, colFixMaking),
                                _buildDataCell(item.fixWastage, colFixWastage),
                                _buildDataCell(item.stoneAmount, colStoneAmt),
                                _buildDataCell(item.diamondAmount, colDiamondAmt),
                                _buildDataCell(item.sku, colSku),
                                _buildDataCell(item.epc, colEpc),
                                _buildDataCell(item.vendor, colVendor),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Right Side: Pinned/Fixed Actions Column
        SizedBox(
          width: colActions,
          child: Column(
            children: [
              // Header
              Container(
                height: 40,
                color: Colors.grey[300],
                child: _buildHeaderCell(s.actions, colActions),
              ),
              // Pinned rows
              Expanded(
                child: Listener(
                  onPointerDown: (_) => _activeScrollController = _rightScrollController,
                  child: ListView.builder(
                    controller: _rightScrollController,
                    itemCount: products.length + (viewModel.hasReachedEnd ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == products.length) {
                        return const SizedBox(height: 52); // Keep space matching loading indicator on left
                      }
                      final isOdd = index % 2 == 1;
                      final item = products[index];

                      return Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: isOdd ? Colors.grey[50] : Colors.white,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                        child: Container(
                          width: colActions,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () => _editProduct(item),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withAlpha(26),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.edit, color: Colors.blue, size: 16),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _confirmDeleteProduct(item),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withAlpha(26),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.delete, color: Colors.red, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCell(String label, double width) {
    return Container(
      width: width,
      height: double.infinity,
      alignment: Alignment.center,
      child: Text(
        label,
        style: ListTextStyles.header(context),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDataCell(String value, double width) {
    return Container(
      width: width,
      height: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        value.isNotEmpty ? value : '-',
        style: ListTextStyles.cell(context),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildItemImage(BulkItem item) {
    if (item.imageUrl.isNotEmpty) {
      final baseUrl = 'https://rrgold.loyalstring.co.in/';
      var storedUrl = item.imageUrl.trim();
      if (storedUrl.endsWith(',')) {
        storedUrl = storedUrl.substring(0, storedUrl.length - 1).trim();
      }
      String finalUrl;
      
      if (storedUrl.startsWith('http://') || storedUrl.startsWith('https://')) {
        finalUrl = storedUrl;
      } else {
        final imgList = storedUrl.split(',');
        final lastImg = imgList.isNotEmpty ? imgList.last.trim() : '';
        finalUrl = '$baseUrl$lastImg';
      }

      return Image.network(
        finalUrl,
        fit: BoxFit.cover,
        cacheWidth: 144,
        cacheHeight: 144,
        errorBuilder: (context, error, stackTrace) {
          return Icon(Icons.image, color: Colors.grey[400], size: 36);
        },
      );
    }
    
    return Icon(Icons.image, color: Colors.grey[400], size: 36);
  }
}
