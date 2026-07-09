import 'package:flutter/material.dart';

class CurvedHeaderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF0077D4),
          Color(0xFFD60000),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, height * 0.3)
      ..quadraticBezierTo(
        width * -0.3,
        height * 1.3,
        width,
        height * 0.75,
      )
      ..lineTo(width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
