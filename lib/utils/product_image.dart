import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bulk_item.dart';
import '../services/pref_service.dart';

/// Product thumbnail from a [BulkItem] image URL or local path.
class ProductImage extends StatelessWidget {
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

  factory ProductImage.fromBulkItem(
    BulkItem item, {
    required double iconSize,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return ProductImage._(
      imageUrl: item.imageUrl,
      iconSize: iconSize,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  String _resolveUrl(BuildContext context) {
    var path = imageUrl.trim();
    if (path.isEmpty) return '';
    if (path.endsWith(',')) {
      path = path.substring(0, path.length - 1).trim();
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('file://')) {
      return path;
    }
    if (File(path).existsSync()) {
      return path;
    }

    final baseUrl = context.read<PrefService>().getEffectiveApiBaseUrl();
    final imgList = path.split(',');
    final lastImg = imgList.isNotEmpty ? imgList.last.trim() : '';
    if (lastImg.isEmpty) return '';
    return '$baseUrl$lastImg';
  }

  Widget _placeholder() {
    return Center(
      child: Icon(Icons.image_outlined, size: iconSize, color: Colors.grey[400]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveUrl(context);
    if (resolved.isEmpty) {
      return _placeholder();
    }

    if (resolved.startsWith('file://')) {
      final file = File(Uri.parse(resolved).toFilePath());
      if (!file.existsSync()) return _placeholder();
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    if (!resolved.startsWith('http')) {
      final file = File(resolved);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          cacheHeight: cacheHeight,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      }
    }

    return Image.network(
      resolved,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      errorBuilder: (_, __, ___) => _placeholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: SizedBox(
            width: iconSize * 0.45,
            height: iconSize * 0.45,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}
