import 'package:flutter/material.dart';

/// Home-screen menu icons only (dashboard). Brand red→purple gradient.
/// Do not reuse for other screens unless gradient icons are intentional there.
class GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const GradientIcon({
    super.key,
    required this.icon,
    this.size = 24.0,
  });

  static const List<Color> _gradientColors = [
    Color(0xFFD32940),
    Color(0xFF5231A7),
  ];

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: _gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Icon(
        icon,
        size: size,
        color: Colors.white,
      ),
    );
  }
}
