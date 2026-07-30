import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bulk_item.dart';
import '../services/pref_service.dart';

/// Fast product thumbnail. Uses CDN base first (same as Sparkle ProductList).
class ProductImage extends StatefulWidget {
  const ProductImage._({
    required this.imageUrl,
    required this.iconSize,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String imageUrl;
  final double iconSize;
  final int? cacheWidth;
  final int? cacheHeight;

  /// Default decode size for list/grid thumbs (must match [warmUrls]).
  static const int thumbCachePx = 144;

  factory ProductImage.fromBulkItem(
    BulkItem item, {
    required double iconSize,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return ProductImage._(
      imageUrl: item.imageUrl,
      iconSize: iconSize,
      cacheWidth: cacheWidth ?? thumbCachePx,
      cacheHeight: cacheHeight ?? thumbCachePx,
    );
  }

  /// Display-only product image from a raw DB / API path or URL.
  factory ProductImage.fromUrl(
    String imageUrl, {
    required double iconSize,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return ProductImage._(
      imageUrl: imageUrl,
      iconSize: iconSize,
      cacheWidth: cacheWidth ?? thumbCachePx,
      cacheHeight: cacheHeight ?? thumbCachePx,
    );
  }

  /// CDN host for relative product image paths (Sparkle default).
  static const String cdnBaseUrl = PrefService.defaultApiBaseUrl;

  static String resolveUrl(String imageUrl, {String? effectiveBaseUrl}) {
    var path = imageUrl.trim();
    if (path.isEmpty) return '';
    while (path.endsWith(',')) {
      path = path.substring(0, path.length - 1).trim();
    }
    if (path.isEmpty) return '';

    final parts = path
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final selected = parts.last;

    if (selected.startsWith('http://') || selected.startsWith('https://')) {
      return selected;
    }
    if (selected.startsWith('file://')) {
      return selected;
    }
    if (selected.startsWith('/') &&
        (selected.startsWith('/data/') ||
            selected.startsWith('/storage/') ||
            selected.startsWith('/sdcard/'))) {
      return selected;
    }

    final base = (effectiveBaseUrl != null && effectiveBaseUrl.isNotEmpty)
        ? (effectiveBaseUrl.endsWith('/')
            ? effectiveBaseUrl
            : '$effectiveBaseUrl/')
        : cdnBaseUrl;
    final relative =
        selected.startsWith('/') ? selected.substring(1) : selected;
    return '$base$relative';
  }

  static ImageProvider? networkProvider(
    String imageUrl, {
    int pixelSize = thumbCachePx,
  }) {
    final url = resolveUrl(imageUrl);
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return null;
    }
    return ResizeImage(
      NetworkImage(url),
      width: pixelSize,
      height: pixelSize,
    );
  }

  /// Start downloading/decoding as soon as item rows exist (before paint).
  /// Uses the same [ResizeImage] key as [Image.network] cacheWidth.
  static void warmUrls(
    Iterable<String> imageUrls, {
    int pixelSize = thumbCachePx,
  }) {
    for (final raw in imageUrls) {
      final provider = networkProvider(raw, pixelSize: pixelSize);
      if (provider == null) continue;
      provider.resolve(const ImageConfiguration()).addListener(
            ImageStreamListener(
              (ImageInfo _, bool __) {},
              onError: (Object _, StackTrace? __) {},
            ),
          );
    }
  }

  @override
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  int _urlIndex = 0;
  List<String>? _urls;

  List<String> _buildUrls(BuildContext context) {
    String? effective;
    try {
      effective = context.read<PrefService>().getEffectiveApiBaseUrl();
    } catch (_) {}

    final urls = <String>[];
    final seen = <String>{};

    void add(String u) {
      if (u.isEmpty) return;
      if (seen.add(u.toLowerCase())) urls.add(u);
    }

    add(ProductImage.resolveUrl(widget.imageUrl));
    if (effective != null &&
        effective.isNotEmpty &&
        effective.toLowerCase() != ProductImage.cdnBaseUrl.toLowerCase()) {
      add(ProductImage.resolveUrl(widget.imageUrl, effectiveBaseUrl: effective));
    }
    return urls;
  }

  @override
  void didUpdateWidget(covariant ProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _urls = null;
      _urlIndex = 0;
    }
  }

  Widget _placeholder() {
    return ColoredBox(
      color: Colors.grey.shade100,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: widget.iconSize,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  void _tryNext() {
    if (_urls == null) return;
    if (_urlIndex < _urls!.length - 1) {
      setState(() => _urlIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    _urls ??= _buildUrls(context);
    if (_urls!.isEmpty || _urlIndex >= _urls!.length) {
      return _placeholder();
    }

    final resolved = _urls![_urlIndex];
    final cacheW = widget.cacheWidth ?? ProductImage.thumbCachePx;
    final cacheH = widget.cacheHeight ?? ProductImage.thumbCachePx;

    if (resolved.startsWith('file://')) {
      final file = File(Uri.parse(resolved).toFilePath());
      if (!file.existsSync()) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext());
        return _placeholder();
      }
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: cacheW,
        cacheHeight: cacheH,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext());
          return _placeholder();
        },
      );
    }

    if (!resolved.startsWith('http://') && !resolved.startsWith('https://')) {
      final file = File(resolved);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cacheW,
          cacheHeight: cacheH,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext());
            return _placeholder();
          },
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext());
      return _placeholder();
    }

    return Image.network(
      resolved,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cacheW,
      cacheHeight: cacheH,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      // If already warmed/cached, paint immediately with the row text.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _placeholder();
      },
      errorBuilder: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext());
        return _placeholder();
      },
    );
  }
}
