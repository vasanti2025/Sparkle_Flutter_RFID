import 'package:flutter/material.dart';

/// Home "How to Use" videos. Replace [url] with any YouTube or direct video link.
class GuideVideo {
  const GuideVideo({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
    required this.url,
  });

  final String id;
  final String titleKey;
  final String descriptionKey;
  final IconData icon;
  final String url;

  bool get hasUrl => url.trim().isNotEmpty;

  bool get isYoutube {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  bool get isDirectVideo {
    final path = Uri.tryParse(url.trim())?.path.toLowerCase() ?? '';
    return path.endsWith('.mp4') ||
        path.endsWith('.m3u8') ||
        path.endsWith('.mov') ||
        path.endsWith('.webm') ||
        path.endsWith('.mkv');
  }

  /// Temporary sample clip so every cell opens a working player.
  /// Swap each [url] with the real guide video when ready.
  static const sampleUrl =
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

  static const List<GuideVideo> all = [
    GuideVideo(
      id: 'product',
      titleKey: 'product',
      descriptionKey: 'guideProductDesc',
      icon: Icons.shopping_bag,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'inventory',
      titleKey: 'inventory',
      descriptionKey: 'guideInventoryDesc',
      icon: Icons.layers,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'order',
      titleKey: 'order',
      descriptionKey: 'guideOrderDesc',
      icon: Icons.receipt_long,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'search',
      titleKey: 'search',
      descriptionKey: 'guideSearchDesc',
      icon: Icons.search,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'stockTransfer',
      titleKey: 'stockTransfer',
      descriptionKey: 'guideStockTransferDesc',
      icon: Icons.swap_horiz,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'report',
      titleKey: 'report',
      descriptionKey: 'guideReportDesc',
      icon: Icons.assessment,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'quotations',
      titleKey: 'quotations',
      descriptionKey: 'guideQuotationsDesc',
      icon: Icons.description,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'deliveryChallan',
      titleKey: 'deliveryChallan',
      descriptionKey: 'guideDeliveryChallanDesc',
      icon: Icons.local_shipping,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'labelTodayRate',
      titleKey: 'labelTodayRate',
      descriptionKey: 'guideTodayRateDesc',
      icon: Icons.trending_up,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'sampleIn',
      titleKey: 'sampleIn',
      descriptionKey: 'guideSampleInDesc',
      icon: Icons.login,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'sampleOut',
      titleKey: 'sampleOut',
      descriptionKey: 'guideSampleOutDesc',
      icon: Icons.logout,
      url: sampleUrl,
    ),
    GuideVideo(
      id: 'settings',
      titleKey: 'settings',
      descriptionKey: 'guideSettingsDesc',
      icon: Icons.settings,
      url: sampleUrl,
    ),
  ];
}
