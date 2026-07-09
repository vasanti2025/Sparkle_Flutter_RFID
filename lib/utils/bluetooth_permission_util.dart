import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

Future<bool> requestBluetoothPermissions() async {
  if (!Platform.isAndroid) return true;

  final modern = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
  final connectGranted = modern[Permission.bluetoothConnect]?.isGranted ?? false;
  final scanGranted = modern[Permission.bluetoothScan]?.isGranted ?? false;
  if (connectGranted && scanGranted) return true;

  final legacy = await [Permission.bluetooth, Permission.locationWhenInUse].request();
  final bluetoothGranted = legacy[Permission.bluetooth]?.isGranted ?? false;
  final locationGranted = legacy[Permission.locationWhenInUse]?.isGranted ?? false;
  return bluetoothGranted && locationGranted;
}

Future<bool> hasBluetoothPermissions() async {
  if (!Platform.isAndroid) return true;

  final connect = await Permission.bluetoothConnect.status;
  final scan = await Permission.bluetoothScan.status;
  if (connect.isGranted && scan.isGranted) return true;

  final bluetooth = await Permission.bluetooth.status;
  final location = await Permission.locationWhenInUse.status;
  return bluetooth.isGranted && location.isGranted;
}
