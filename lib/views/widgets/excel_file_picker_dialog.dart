import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';

/// Matches Kotlin [FilePickerDialog] — dashed gradient upload area + Cancel/OK buttons.
class ExcelFilePickerDialog extends StatelessWidget {
  final VoidCallback onDismiss;
  final VoidCallback onFileSelected;

  const ExcelFilePickerDialog({
    super.key,
    required this.onDismiss,
    required this.onFileSelected,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              GestureDetector(
                onTap: onFileSelected,
                child: CustomPaint(
                  painter: _GradientDashedBorderPainter(radius: 16),
                  child: Container(
                    width: double.infinity,
                    height: 140,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.file_upload_outlined, size: 46, color: Colors.grey[700]),
                        const SizedBox(height: 8),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.black87),
                            children: [
                              TextSpan(text: s.tapTo),
                              TextSpan(
                                text: s.chooseFile,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                  color: const Color(0xFF3053F0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.formatsLabel,
                      style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.maxFileSize,
                    style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _gradientBtn(s.cancel, Icons.cancel_outlined, onDismiss)),
                  const SizedBox(width: 12),
                  Expanded(child: _gradientBtn(s.confirm, Icons.check_circle_outline, onFileSelected)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradientBtn(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(colors: [Color(0xFF3053F0), Color(0xFFE82E5A)]),
        ),
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white, size: 16),
          label: Text(label, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ),
    );
  }
}

class _GradientDashedBorderPainter extends CustomPainter {
  final double radius;

  _GradientDashedBorderPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF5231A7), Color(0xFFD32940)],
      ).createShader(rect)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}