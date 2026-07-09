import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../viewmodels/product_view_model.dart';

class InventoryMenuScreen extends StatefulWidget {
  const InventoryMenuScreen({super.key});

  @override
  State<InventoryMenuScreen> createState() => _InventoryMenuScreenState();
}

class _InventoryMenuScreenState extends State<InventoryMenuScreen> {
  bool _isLoading = false;

  void _showSelectionDialog({
    required String title,
    required List<String> items,
    required Function(String) onSelect,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return _SelectionDialog(
          title: title,
          items: items,
          onSelect: onSelect,
        );
      },
    );
  }

  void _handleMenuClick(String key, ProductViewModel viewModel, dynamic s) async {
    if (key == 'Scan Display') {
      _navigateToScanDisplay('Scan Display', 'Scan Display');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (key == 'Scan Counter') {
        final list = await viewModel.getCounters();
        if (list.isEmpty) {
          _showToast(s.noCountersFound);
        } else {
          _showSelectionDialog(
            title: s.counter,
            items: list,
            onSelect: (val) => _navigateToScanDisplay('Counter', val),
          );
        }
      } else if (key == 'Scan Box') {
        final list = await viewModel.getBoxes();
        if (list.isEmpty) {
          _showToast(s.noBoxesFound);
        } else {
          _showSelectionDialog(
            title: s.box,
            items: list,
            onSelect: (val) => _navigateToScanDisplay('Box', val),
          );
        }
      } else if (key == 'Scan Branch') {
        final list = await viewModel.getBranches();
        if (list.isEmpty) {
          _showToast(s.noBranchesFound);
        } else {
          _showSelectionDialog(
            title: s.branch,
            items: list,
            onSelect: (val) => _navigateToScanDisplay('Branch', val),
          );
        }
      } else if (key == 'Exhibition') {
        final list = await viewModel.getExhibitions();
        if (list.isEmpty) {
          _showToast(s.noExhibitionsFound);
        } else {
          _showSelectionDialog(
            title: s.exhibition,
            items: list,
            onSelect: (val) => _navigateToScanDisplay('Exhibition', val),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToScanDisplay(String filterType, String filterValue) {
    Navigator.pushNamed(
      context,
      '/scan_display',
      arguments: {
        'filterType': filterType,
        'filterValue': filterValue,
      },
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final viewModel = Provider.of<ProductViewModel>(context, listen: false);

    final List<Map<String, dynamic>> menuItems = [
      {'key': 'Scan Display', 'title': s.scanDisplay, 'icon': Icons.qr_code_scanner},
      {'key': 'Scan Counter', 'title': s.scanCounter, 'icon': Icons.dns},
      {'key': 'Scan Box', 'title': s.scanBox, 'icon': Icons.all_inbox},
      {'key': 'Scan Branch', 'title': s.scanBranch, 'icon': Icons.store},
      {'key': 'Exhibition', 'title': s.exhibition, 'icon': Icons.star},
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
              s.inventory,
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView.separated(
              itemCount: menuItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final item = menuItems[index];
                return _buildMenuButton(
                  title: item['title'] as String,
                  icon: item['icon'] as IconData,
                  onTap: () => _handleMenuClick(item['key'] as String, viewModel, s),
                );
              },
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF3B363E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 24),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  final Function(String) onSelect;

  const _SelectionDialog({
    required this.title,
    required this.items,
    required this.onSelect,
  });

  @override
  State<_SelectionDialog> createState() => _SelectionDialogState();
}

class _SelectionDialogState extends State<_SelectionDialog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Close Button Row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Header Row (Select + plus)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3F3),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.selectLabel(widget.title),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: const Color(0xFF3B363E),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _expanded = !_expanded;
                      });
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _expanded ? Icons.remove : Icons.add,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Expandable items list
            if (_expanded) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSelect(item);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        child: Text(
                          item,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFF3B363E),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
