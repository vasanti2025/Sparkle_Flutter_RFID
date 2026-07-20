import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

bool isCameraPermissionError(Object error) {
  if (error is CameraException) {
    return error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt';
  }
  final message = error.toString().toLowerCase();
  return message.contains('camera access') || message.contains('permission');
}

Future<bool> ensureCameraPermission() async {
  var status = await Permission.camera.status;
  if (status.isGranted) return true;
  if (status.isPermanentlyDenied || status.isRestricted) return false;
  status = await Permission.camera.request();
  return status.isGranted;
}

Future<bool> isCameraPermissionBlocked() async {
  final status = await Permission.camera.status;
  return status.isPermanentlyDenied || status.isRestricted;
}

Future<bool> openCameraPermissionSettings() => openAppSettings();

Future<bool> shouldOpenSettingsForCamera(Object error) async {
  if (error is CameraException && error.code == 'CameraAccessDeniedWithoutPrompt') {
    return true;
  }
  final status = await Permission.camera.status;
  return status.isPermanentlyDenied || status.isRestricted;
}
