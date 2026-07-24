// Generates iOS AppIcon + LaunchImage from Sparkle branding assets.
// Run: dart run tool/generate_branding_icons.dart

import 'dart:io';

import 'package:image/image.dart' as img;

Future<void> main() async {
  final root = Directory.current.path;
  final branding = Directory('$root/assets/branding');
  branding.createSync(recursive: true);

  // Prefer foreground adaptive icon; fall back to webp / png logo.
  final candidates = [
    File('${branding.path}/app_icon_fg.webp'),
    File('${branding.path}/app_icon.webp'),
    File('${branding.path}/sparkle_logo.png'),
  ];

  img.Image? source;
  for (final f in candidates) {
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    source = img.decodeImage(bytes);
    if (source != null) {
      stdout.writeln('Using ${f.path} (${source.width}x${source.height})');
      break;
    }
  }
  if (source == null) {
    stderr.writeln('No usable branding image found');
    exit(1);
  }

  // Square canvas with Sparkle-like light background.
  img.Image squareIcon(int size) {
    final canvas = img.Image(width: size, height: size);
    img.fill(canvas, color: img.ColorRgba8(250, 250, 250, 255));
    final fitted = img.copyResize(
      source!,
      width: (size * 0.78).round(),
      height: (size * 0.78).round(),
      interpolation: img.Interpolation.cubic,
    );
    final ox = ((size - fitted.width) / 2).round();
    final oy = ((size - fitted.height) / 2).round();
    img.compositeImage(canvas, fitted, dstX: ox, dstY: oy);
    return canvas;
  }

  final iosIconDir = Directory('$root/ios/Runner/Assets.xcassets/AppIcon.appiconset');
  iosIconDir.createSync(recursive: true);

  final iosSizes = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };

  for (final e in iosSizes.entries) {
    final out = File('${iosIconDir.path}/${e.key}');
    out.writeAsBytesSync(img.encodePng(squareIcon(e.value)));
    stdout.writeln('Wrote ${e.key}');
  }

  // Launch images (centered logo on white).
  final launchDir = Directory('$root/ios/Runner/Assets.xcassets/LaunchImage.imageset');
  launchDir.createSync(recursive: true);
  final logoPng = File('${branding.path}/sparkle_logo.png');
  img.Image launchSrc;
  if (logoPng.existsSync()) {
    launchSrc = img.decodeImage(logoPng.readAsBytesSync()) ?? source;
  } else {
    launchSrc = source;
  }

  img.Image launchImage(int w, int h) {
    final canvas = img.Image(width: w, height: h);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
    final targetW = (w * 0.45).round().clamp(64, w);
    final resized = img.copyResize(
      launchSrc,
      width: targetW,
      interpolation: img.Interpolation.cubic,
    );
    final ox = ((w - resized.width) / 2).round();
    final oy = ((h - resized.height) / 2).round();
    img.compositeImage(canvas, resized, dstX: ox, dstY: oy);
    return canvas;
  }

  File('${launchDir.path}/LaunchImage.png').writeAsBytesSync(img.encodePng(launchImage(168, 185)));
  File('${launchDir.path}/LaunchImage@2x.png').writeAsBytesSync(img.encodePng(launchImage(336, 370)));
  File('${launchDir.path}/LaunchImage@3x.png').writeAsBytesSync(img.encodePng(launchImage(504, 555)));
  stdout.writeln('Wrote iOS LaunchImages');

  // Master 1024 icon for tools / store.
  File('${branding.path}/app_icon_1024.png').writeAsBytesSync(img.encodePng(squareIcon(1024)));
  stdout.writeln('Done');
}
