import 'package:permission_handler/permission_handler.dart';

Future<bool> ensureCameraPermission() async {
  var status = await Permission.camera.status;
  if (status.isGranted) return true;
  if (status.isPermanentlyDenied) return false;
  status = await Permission.camera.request();
  return status.isGranted;
}
