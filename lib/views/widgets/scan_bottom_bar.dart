import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/l10n_extension.dart';

const String _gscanSvgStr = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M8.4 0H3.6C2.645 0 1.729 0.379 1.055 1.055C0.379 1.729 0 2.645 0 3.6C0 4.876 0 6.559 0 8.4C0 9.062 0.538 9.6 1.2 9.6C1.862 9.6 2.4 9.062 2.4 8.4V3.6C2.4 3.282 2.526 2.976 2.752 2.752C2.976 2.526 3.282 2.4 3.6 2.4H8.4C9.062 2.4 9.6 1.862 9.6 1.2C9.6 0.538 9.062 0 8.4 0ZM0 14.4V20.4C0 21.355 0.379 22.271 1.055 22.945C1.729 23.621 2.645 24 3.6 24C4.592 24 5.832 24 7.2 24C7.862 24 8.4 23.462 8.4 22.8C8.4 22.138 7.862 21.6 7.2 21.6H3.6C3.282 21.6 2.976 21.474 2.752 21.248C2.526 21.024 2.4 20.718 2.4 20.4V14.4C2.4 13.738 1.862 13.2 1.2 13.2C0.538 13.2 0 13.738 0 14.4ZM15.6 24H20.4C21.355 24 22.271 23.621 22.945 22.945C23.621 22.271 24 21.355 24 20.4C24 19.124 24 17.441 24 15.6C24 14.938 23.462 14.4 22.8 14.4C22.138 14.4 21.6 14.938 21.6 15.6V20.4C21.6 20.718 21.474 21.024 21.248 21.248C21.024 21.474 20.718 21.6 20.4 21.6H15.6C14.938 21.6 14.4 22.138 14.4 22.8C14.4 23.462 14.938 24 15.6 24ZM24 8.4V3.6C24 2.645 23.621 1.729 22.945 1.055C22.271 0.379 21.355 0 20.4 0C19.124 0 17.441 0 15.6 0C14.938 0 14.4 1.2 14.4 1.2C14.4 1.862 14.938 2.4 15.6 2.4H20.4C20.718 2.4 21.024 2.526 21.248 2.752C21.474 2.976 21.6 3.282 21.6 3.6V8.4C21.6 9.062 22.138 9.6 22.8 9.6C23.462 9.6 24 9.062 24 8.4ZM6 13.2H18C18.662 13.2 19.2 12.662 19.2 12C19.2 11.338 18.662 10.8 18 10.8H6C5.338 10.8 4.8 11.338 4.8 12C4.8 12.662 5.338 13.2 6 13.2Z" fill="#495057" fill-rule="evenodd" clip-rule="evenodd"/>
</svg>
''';

/// Reusable utility widget to build individual text action buttons for the bottom bar.
Widget _buildBarButton({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  String stopLabel = 'Stop',
  bool isGscan = false,
  bool isScanning = false,
  bool isScreen = false,
}) {
  final iconColor = Colors.grey[700]!;
  final bool showStop = isGscan && isScanning && !isScreen;

  return TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(60, 60),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showStop)
          Icon(Icons.close, color: iconColor, size: 24)
        else if (isGscan)
          SvgPicture.string(
            _gscanSvgStr,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          )
        else
          Icon(icon, color: iconColor, size: 24),
        const SizedBox(height: 2),
        Text(
          showStop ? stopLabel : label,
          style: GoogleFonts.poppins(
            color: iconColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// Reusable overlapping circular scan button with linear gradient background.
Widget _buildOverlappingScanButton({
  required bool isScanning,
  required VoidCallback onTap,
  required dynamic s,
}) {
  final bool showStop = isScanning;
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 65,
      height: 65,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF5231A7), Color(0xFFD32940)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            showStop ? Icons.close : Icons.qr_code_scanner,
            color: Colors.white,
            size: 26,
          ),
          const SizedBox(height: 2),
          Text(
            showStop ? s.stop : s.scanBtn,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Overlapping background scaffold to hold the buttons.
Widget _buildBottomBarLayout({
  required Widget leftButton1,
  required Widget leftButton2,
  required Widget centerButton,
  required Widget rightButton1,
  required Widget rightButton2,
}) {
  return Container(
    height: 75,
    alignment: Alignment.bottomCenter,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // Background row of 4 buttons
        Container(
          height: 65,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 6,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              leftButton1,
              leftButton2,
              const SizedBox(width: 64), // Space for center overlapping button
              rightButton1,
              rightButton2,
            ],
          ),
        ),
        // Overlapping Center Button
        Positioned(
          top: -15,
          child: centerButton,
        ),
      ],
    ),
  );
}

class ScanBottomBar extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onList;
  final VoidCallback onScan;
  final VoidCallback onGscan;
  final VoidCallback onReset;
  final bool isScanning;
  final bool isEditMode;
  final bool isScreen;
  final bool isBulkScanning;

  const ScanBottomBar({
    super.key,
    required this.onSave,
    required this.onList,
    required this.onScan,
    required this.onGscan,
    required this.onReset,
    required this.isScanning,
    this.isEditMode = false,
    this.isScreen = false,
    this.isBulkScanning = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final String saveText = isScreen
        ? s.transfer
        : (isEditMode ? s.update : s.save);
    final IconData saveIcon = isScreen ? Icons.compare_arrows : Icons.save;

    // The center Scan button reflects a single-tag scan in progress, while the
    // Gscan button reflects a continuous (bulk) scan in progress. Each button
    // only turns into a "Stop" control for the scan mode it actually started.
    final bool showStopGscan = isBulkScanning;

    return _buildBottomBarLayout(
      leftButton1: _buildBarButton(
        icon: saveIcon,
        label: saveText,
        onTap: onSave,
      ),
      leftButton2: _buildBarButton(
        icon: Icons.list,
        label: s.listBtn,
        onTap: onList,
      ),
      centerButton: _buildOverlappingScanButton(
        isScanning: isScanning,
        onTap: onScan,
        s: s,
      ),
      rightButton1: _buildBarButton(
        icon: showStopGscan ? Icons.close : Icons.radio_button_checked,
        label: showStopGscan ? s.stop : s.gscan,
        onTap: onGscan,
        isGscan: !showStopGscan,
      ),
      rightButton2: _buildBarButton(
        icon: Icons.refresh,
        label: s.reset,
        onTap: onReset,
      ),
    );
  }
}

class ScanBottomBarInventory extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onList;
  final VoidCallback onScan;
  final VoidCallback onEmail;
  final VoidCallback onReset;
  final bool isScanning;

  const ScanBottomBarInventory({
    super.key,
    required this.onSave,
    required this.onList,
    required this.onScan,
    required this.onEmail,
    required this.onReset,
    required this.isScanning,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return _buildBottomBarLayout(
      leftButton1: _buildBarButton(
        icon: Icons.save,
        label: s.save,
        onTap: onSave,
      ),
      leftButton2: _buildBarButton(
        icon: Icons.list,
        label: s.listBtn,
        onTap: onList,
      ),
      centerButton: _buildOverlappingScanButton(
        isScanning: isScanning,
        onTap: onScan,
        s: s,
      ),
      rightButton1: _buildBarButton(
        icon: Icons.email,
        label: s.email,
        onTap: onEmail,
      ),
      rightButton2: _buildBarButton(
        icon: Icons.refresh,
        label: s.reset,
        onTap: onReset,
      ),
    );
  }
}

class ScanBottomBarDesktop extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onClear;
  final VoidCallback onScan;
  final VoidCallback onGscan;
  final VoidCallback onReset;
  final bool isScanning;
  final bool isBulkScanning;
  final bool isEditMode;

  const ScanBottomBarDesktop({
    super.key,
    required this.onSave,
    required this.onClear,
    required this.onScan,
    required this.onGscan,
    required this.onReset,
    required this.isScanning,
    this.isBulkScanning = false,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final String saveText = isEditMode ? s.update : s.save;
    final bool showStopGscan = isBulkScanning;
    return _buildBottomBarLayout(
      leftButton1: _buildBarButton(
        icon: Icons.save,
        label: saveText,
        onTap: onSave,
      ),
      leftButton2: _buildBarButton(
        icon: Icons.delete_outline,
        label: s.clearBtn,
        onTap: onClear,
      ),
      centerButton: _buildOverlappingScanButton(
        isScanning: isScanning,
        onTap: onScan,
        s: s,
      ),
      rightButton1: _buildBarButton(
        icon: showStopGscan ? Icons.close : Icons.center_focus_weak,
        label: showStopGscan ? s.stop : s.gscan,
        onTap: onGscan,
        isGscan: !showStopGscan,
      ),
      rightButton2: _buildBarButton(
        icon: Icons.refresh,
        label: s.reset,
        onTap: onReset,
      ),
    );
  }
}
