import 'package:flutter/material.dart';
import 'package:rfid_flutter/utils/app_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n_extension.dart';
import '../viewmodels/product_view_model.dart';

/// Joins multi-selected inventory filter names for scan display / DB IN clause.
const String kInventoryFilterSeparator = '\u001F';

class InventoryMenuScreen extends StatefulWidget {
  const InventoryMenuScreen({super.key});

  @override
  State<InventoryMenuScreen> createState() => _InventoryMenuScreenState();
}

class _InventoryMenuScreenState extends State<InventoryMenuScreen> {
  bool _isLoading = false;

  void _showMultiSelectionDialog({
    required String title,
    required List<String> items,
    required void Function(List<String> selected) onConfirm,
  }) {
    showAppDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return InventoryMultiSelectionDialog(
          title: title,
          items: items,
          onConfirm: onConfirm,
        );
      },
    );
  }

  void _handleMenuClick(String key, ProductViewModel viewModel, dynamic s) async {
    if (key == 'Scan Display') {
      _navigateToScanDisplay('Scan Display', const ['Scan Display']);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (key == 'Scan Counter') {
        final list = await viewModel.getCounters();
        if (!mounted) return;
        if (list.isEmpty) {
          _showToast(s.noCountersFound);
        } else {
          _showMultiSelectionDialog(
            title: s.counter,
            items: list,
            onConfirm: (vals) => _navigateToScanDisplay('Counter', vals),
          );
        }
      } else if (key == 'Scan Box') {
        final list = await viewModel.getBoxes();
        if (!mounted) return;
        if (list.isEmpty) {
          _showToast(s.noBoxesFound);
        } else {
          _showMultiSelectionDialog(
            title: s.box,
            items: list,
            onConfirm: (vals) => _navigateToScanDisplay('Box', vals),
          );
        }
      } else if (key == 'Scan Branch') {
        final list = await viewModel.getBranches();
        if (!mounted) return;
        if (list.isEmpty) {
          _showToast(s.noBranchesFound);
        } else {
          _showMultiSelectionDialog(
            title: s.branch,
            items: list,
            onConfirm: (vals) => _navigateToScanDisplay('Branch', vals),
          );
        }
      } else if (key == 'Exhibition') {
        final list = await viewModel.getExhibitions();
        if (!mounted) return;
        if (list.isEmpty) {
          _showToast(s.noExhibitionsFound);
        } else {
          _showMultiSelectionDialog(
            title: s.exhibition,
            items: list,
            onConfirm: (vals) => _navigateToScanDisplay('Exhibition', vals),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToScanDisplay(String filterType, List<String> filterValues) {
    Navigator.pushNamed(
      context,
      '/scan_display',
      arguments: {
        'filterType': filterType,
        'filterValue': filterValues.join(kInventoryFilterSeparator),
      },
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppFonts.poppins()),
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
              style: AppFonts.poppins(
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
                  style: AppFonts.poppins(
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

class InventoryMultiSelectionDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  final void Function(List<String> selected) onConfirm;

  const InventoryMultiSelectionDialog({
    super.key,
    required this.title,
    required this.items,
    required this.onConfirm,
  });

  @override
  State<InventoryMultiSelectionDialog> createState() => _InventoryMultiSelectionDialogState();
}

class _InventoryMultiSelectionDialogState extends State<InventoryMultiSelectionDialog> {
  bool _expanded = true;
  final Set<String> _selected = {};

  bool get _allSelected =>
      widget.items.isNotEmpty && _selected.length == widget.items.length;

  void _toggleSelectAll(bool? checked) {
    setState(() {
      if (checked == true) {
        _selected
          ..clear()
          ..addAll(widget.items);
      } else {
        _selected.clear();
      }
    });
  }

  void _toggleItem(String item, bool? checked) {
    setState(() {
      if (checked == true) {
        _selected.add(item);
      } else {
        _selected.remove(item);
      }
    });
  }

  void _onOk() {
    final s = context.sRead;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.pleaseSelectAtLeastOne, style: AppFonts.poppins()),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final selected = widget.items.where(_selected.contains).toList();
    Navigator.pop(context);
    widget.onConfirm(selected);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Material(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3F3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            s.selectLabel(widget.title),
                            style: AppFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: const Color(0xFF3B363E),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _expanded = !_expanded),
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
                  AnimatedSize(
                    duration: Duration.zero,
                    clipBehavior: Clip.hardEdge,
                    child: _expanded
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3F3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                constraints: const BoxConstraints(maxHeight: 280),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CheckboxListTile(
                                      dense: true,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      activeColor: const Color(0xFF5231A7),
                                      title: Text(
                                        s.selectAll,
                                        style: AppFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF3B363E),
                                        ),
                                      ),
                                      value: _allSelected,
                                      onChanged: _toggleSelectAll,
                                    ),
                                    const Divider(height: 1),
                                    Flexible(
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        padding: EdgeInsets.zero,
                                        itemCount: widget.items.length,
                                        itemBuilder: (context, index) {
                                          final item = widget.items[index];
                                          final checked = _selected.contains(item);
                                          return CheckboxListTile(
                                            dense: true,
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            activeColor: const Color(0xFF5231A7),
                                            title: Text(
                                              item,
                                              style: AppFonts.poppins(
                                                fontSize: 14,
                                                color: const Color(0xFF3B363E),
                                              ),
                                            ),
                                            value: checked,
                                            onChanged: (v) => _toggleItem(item, v),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                                    ),
                                  ),
                                  child: TextButton(
                                    onPressed: _onOk,
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    child: Text(
                                      s.ok,
                                      style: AppFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
