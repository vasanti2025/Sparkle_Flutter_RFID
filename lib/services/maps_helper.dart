import 'package:url_launcher/url_launcher.dart';
import '../models/location_item.dart';

class MapsHelper {
  static Future<void> openSinglePoint({
    required String latitude,
    required String longitude,
    required String label,
  }) async {
    final lat = latitude.trim();
    final lng = longitude.trim();
    final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  static Future<void> openDayRoute(List<LocationItem> points) async {
    if (points.length < 2) return;

    final origin = '${points.first.latitude},${points.first.longitude}';
    final destination = '${points.last.latitude},${points.last.longitude}';
    final middle = points.length > 2 ? points.sublist(1, points.length - 1) : <LocationItem>[];
    final waypoints = middle.map((p) => '${p.latitude},${p.longitude}').join('|');

    final buffer = StringBuffer('https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination');
    if (waypoints.isNotEmpty) {
      buffer.write('&waypoints=$waypoints');
    }

    final uri = Uri.parse(buffer.toString());
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
