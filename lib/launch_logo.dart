import 'package:flutter/material.dart';
import 'package:rfid_flutter/services/bootstrap_channel.dart';

/// Matches the native windowBackground so the gap before Login/Home is the
/// brand logo, not a blank white frame. The version is the installed
/// versionName, the same value the drawer reads from the app bundle.
class LaunchLogo extends StatefulWidget {
  const LaunchLogo({super.key});

  static const Color background = Color(0xFFFFFFFF);

  @override
  State<LaunchLogo> createState() => _LaunchLogoState();
}

class _LaunchLogoState extends State<LaunchLogo> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    BootstrapChannel.getAppVersion().then((version) {
      if (!mounted || version.isEmpty) return;
      setState(() => _version = version);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LaunchLogo.background,
      child: Stack(
        children: [
          const Center(
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
              padding: const EdgeInsets.only(bottom: 28),
              child: Text(
                _version.isEmpty ? '' : 'Version $_version',
                style: const TextStyle(
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
