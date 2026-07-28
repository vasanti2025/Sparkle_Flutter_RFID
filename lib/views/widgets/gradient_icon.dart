import 'package:flutter/material.dart';

/// Lightweight menu icon (no ShaderMask — that janks low-RAM handhelds).
class GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const GradientIcon({
    super.key,
    required this.icon,
    this.size = 24.0,
  });

  static const Color _color = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: _color,
    );
  }
}
