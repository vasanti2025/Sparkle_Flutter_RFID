import 'package:flutter/material.dart';

/// Matches the native windowBackground so the gap before Login/Home is the
/// brand logo, not a blank white frame.
class LaunchLogo extends StatelessWidget {
  const LaunchLogo({super.key});

  static const Color background = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: background,
      child: Stack(
        children: [
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.55,
              child: Image(
                image: AssetImage('assets/branding/splash_logo.png'),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 28),
              child: Text(
                'Version 1.0.8',
                style: TextStyle(
                  color: Color(0xFF46464A),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
