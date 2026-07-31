/// Proportional column widths for horizontal table layouts.
///
/// Scales [baseWidths] up when their sum is less than [availableWidth]
/// so data columns fill the remaining screen width without changing ratios.
List<double> stretchColumnWidths(
  List<double> baseWidths,
  double availableWidth,
) {
  if (baseWidths.isEmpty || availableWidth <= 0) {
    return List<double>.from(baseWidths);
  }

  final total = baseWidths.fold<double>(0, (sum, width) => sum + width);
  if (total <= 0 || total >= availableWidth) {
    return List<double>.from(baseWidths);
  }

  final scale = availableWidth / total;
  return baseWidths.map((width) => width * scale).toList();
}
