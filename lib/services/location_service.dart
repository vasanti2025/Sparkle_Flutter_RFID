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

  static Future<LocationReading?> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    final granted = await ensurePermission();
    if (!granted) return null;

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    var address = 'Unknown location';
    try {
      final places = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (places.isNotEmpty) {
        final p = places.first;
        address = [p.street, p.subLocality, p.locality, p.administrativeArea, p.postalCode]
            .where((e) => e != null && e.trim().isNotEmpty)
            .join(', ');
        if (address.isEmpty) address = p.name ?? address;
      }
    } catch (_) {}

    return LocationReading(
      latitude: position.latitude.toString(),
      longitude: position.longitude.toString(),
      address: address,
    );
  }
}
