import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Home-screen menu icons. Gold line icons on the cream home grid.
class GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const GradientIcon({
    super.key,
    required this.icon,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: AppColors.gold,
    );
  }
}
