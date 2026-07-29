import 'package:flutter/material.dart';

/// Ultra-light dashboard chrome — only Material widgets, paints on frame 1.
class InstantDashboardShell extends StatelessWidget {
  const InstantDashboardShell({super.key});

  static const _brand = Color(0xFF5231A7);

  static const _icons = [
    Icons.shopping_bag,
    Icons.layers,
    Icons.receipt_long,
    Icons.search,
    Icons.swap_horiz,
    Icons.assessment,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Sparkle RFID',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.92,
        ),
        itemCount: _icons.length,
        itemBuilder: (context, index) {
          return ColoredBox(
            color: Colors.white,
            child: Icon(_icons[index], color: _brand, size: 32),
          );
        },
      ),
    );
  }
}
