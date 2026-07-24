import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationReading {
  final String latitude;
  final String longitude;
  final String address;

  LocationReading({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

class LocationService {
  static Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  static Future<String> _addressFor(double lat, double lng) async {
    var address = 'Unknown location';
    try {
      final places = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 3), onTimeout: () => <Placemark>[]);
      if (places.isNotEmpty) {
        final p = places.first;
        address = [p.street, p.subLocality, p.locality, p.administrativeArea, p.postalCode]
            .where((e) => e != null && e.trim().isNotEmpty)
            .join(', ');
        if (address.isEmpty) address = p.name ?? address;
      }
    } catch (_) {}
    return address;
  }

  /// Prefer last-known (instant) then a short fresh fix — never block UI for 20s.
  static Future<LocationReading?> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    final granted = await ensurePermission();
    if (!granted) return null;

    Position? position = await Geolocator.getLastKnownPosition();
    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      position = fresh;
    } catch (_) {
      // Keep last-known if a fresh fix times out.
    }
    if (position == null) return null;

    final address = await _addressFor(position.latitude, position.longitude);
    return LocationReading(
      latitude: position.latitude.toString(),
      longitude: position.longitude.toString(),
      address: address,
    );
  }
}
