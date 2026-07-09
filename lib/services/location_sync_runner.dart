import '../models/location_item.dart';
import 'api_service.dart';
import 'db_service.dart';
import 'location_service.dart';
import 'pref_service.dart';

class LocationSyncRunner {
  static Future<void> runOnce() async {
    final prefService = await PrefService.init();
    if (!prefService.isLoggedIn() || !prefService.isLocationSyncEnabled()) return;

    final employee = prefService.getEmployee();
    if (employee == null) return;

    final reading = await LocationService.getCurrentLocation();
    if (reading == null) return;

    final api = ApiService(prefService);
    final added = await api.addClientLocation(
      clientCode: employee.clientCode ?? '',
      userId: employee.id,
      branchId: employee.defaultBranchId,
      latitude: reading.latitude,
      longitude: reading.longitude,
      address: reading.address,
    );
    if (!added) return;

    final locations = await api.getClientLocations(
      clientCode: employee.clientCode ?? '',
      userId: employee.id,
      branchId: employee.defaultBranchId,
    );

    final db = DbService();
    await db.replaceAllLocations(locations);
  }
}
