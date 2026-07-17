import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Face pipeline aligned with Sparkle_Optimised:
/// live camera frame → upright bitmap → ML Kit detect → crop → MobileFaceNet.
class FaceRecognitionService {
  late FaceDetector _faceDetector;
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  String? _initError;
  bool _busy = false;
  Directory? _tempDir;
  int _debugFrame = 0;

  /// Portrait UI → 0. Update if you unlock device rotation.
  int deviceOrientationDegrees = 0;

  FaceRecognitionService() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableClassification: true,
        minFaceSize: 0.05,
      ),
    );
  }

  Future<void> ensureInitialized() async {
    if (_isModelLoaded) return;
    await init();
  }

  Future<void> init() async {
    if (_isModelLoaded) return;
    try {
      _interpreter?.close();
      _interpreter = await Interpreter.fromAsset('assets/mobile_face_net.tflite');
      _isModelLoaded = true;
      _initError = null;
      _tempDir = await getTemporaryDirectory();
      debugPrint('TFLITE: Model loaded successfully');
    } catch (e) {
      _isModelLoaded = false;
      _initError = e.toString();
      debugPrint('TFLITE Error: Failed to load model: $e');
    }
  }

  bool get isModelLoaded => _isModelLoaded;
  String? get initError => _initError;

  static const double matchThreshold = 1.0;

  static double euclideanDistance(List<double> a, List<double> b) {
    if (a.isEmpty || b.length != a.length) return double.maxFinite;
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  static List<double> parseEmbedding(String raw) {
    if (raw.trim().isEmpty) return const [];
    return raw.split(',').map((e) => double.tryParse(e.trim()) ?? 0.0).toList();
  }

  /// Live CameraImage path (Add Face / Face Login stream).
  Future<List<double>?> processCameraImage({
    required CameraImage image,
    required CameraDescription camera,
  }) async {
    await ensureInitialized();
    if (!_isModelLoaded || _interpreter == null) return null;
    if (_busy) return null;
    _busy = true;
    _debugFrame++;
    try {
      final frame = _cameraImageToBitmap(image);
      if (frame == null) {
        if (_debugFrame % 30 == 1) {
          debugPrint(
            'FACE: bitmap convert failed format=${image.format.group} '
            'planes=${image.planes.length} ${image.width}x${image.height}',
          );
        }
        return null;
      }

      final sensor = camera.sensorOrientation;
      // Try sensor-correct upright image first, then common fallbacks.
      final angles = <int>{
        _androidUprightAngle(camera),
        sensor,
        (360 - sensor) % 360,
        0,
        90,
        270,
        180,
      };

      for (final angle in angles) {
        final oriented = angle == 0 ? frame : img.copyRotate(frame, angle: angle);
        final embedding = await _detectAndEmbedBitmap(oriented);
        if (embedding != null) {
          if (_debugFrame % 15 == 1) {
            debugPrint('FACE: detected with angle=$angle size=${oriented.width}x${oriented.height}');
          }
          return embedding;
        }
      }

      if (_debugFrame % 30 == 1) {
        debugPrint(
          'FACE: no face after ${angles.length} angles '
          'sensor=$sensor format=${image.format.raw} planes=${image.planes.length}',
        );
      }
      return null;
    } catch (e, st) {
      debugPrint('FACE Error: $e\n$st');
      return null;
    } finally {
      _busy = false;
    }
  }

  /// Still JPEG path (Save fallback when stream has not produced a face yet).
  Future<List<double>?> getEmbeddingFromJpegFile(String filePath) async {
    await ensureInitialized();
    if (!_isModelLoaded || _interpreter == null) return null;
    try {
      final bytes = await File(filePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final oriented = img.bakeOrientation(decoded);

      final angles = <int>{0, 90, 270, 180};
      for (final angle in angles) {
        final candidate = angle == 0 ? oriented : img.copyRotate(oriented, angle: angle);
        final embedding = await _detectAndEmbedBitmap(candidate);
        if (embedding != null) return embedding;
      }
      return null;
    } catch (e, st) {
      debugPrint('FACE JPEG Error: $e\n$st');
      return null;
    }
  }

  int _androidUprightAngle(CameraDescription camera) {
    final sensor = camera.sensorOrientation;
    if (Platform.isIOS) return sensor;
    final device = deviceOrientationDegrees;
    if (camera.lensDirection == CameraLensDirection.front) {
      return (sensor + device) % 360;
    }
    return (sensor - device + 360) % 360;
  }

  /// Detect via JPEG file (most reliable on Android ML Kit) then crop+embed.
  Future<List<double>?> _detectAndEmbedBitmap(img.Image bitmap) async {
    if (bitmap.width < 48 || bitmap.height < 48) return null;

    _tempDir ??= await getTemporaryDirectory();
    final path = '${_tempDir!.path}/face_frame.jpg';
    await File(path).writeAsBytes(img.encodeJpg(bitmap, quality: 92), flush: true);

    final faces = await _faceDetector.processImage(InputImage.fromFilePath(path));
    if (faces.isEmpty) return null;

    faces.sort((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaB.compareTo(areaA);
    });

    final faceBmp = _cropFace(bitmap, faces.first.boundingBox);
    if (faceBmp == null) return null;
    final resized = img.copyResize(faceBmp, width: 112, height: 112);
    return _runInference(resized);
  }

  img.Image? _cameraImageToBitmap(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.bgra8888 ||
          (Platform.isIOS && image.planes.length == 1 && image.planes.first.bytesPerPixel == 4)) {
        return _bgraToImage(image);
      }
      return _yuvToImage(image);
    } catch (e) {
      debugPrint('FACE: bitmap convert failed: $e');
      return null;
    }
  }

  img.Image _bgraToImage(CameraImage image) {
    final plane = image.planes.first;
    final out = img.Image(width: image.width, height: image.height);
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = y * stride + x * 4;
        if (i + 2 >= bytes.length) continue;
        out.setPixelRgba(x, y, bytes[i + 2], bytes[i + 1], bytes[i], 255);
      }
    }
    return out;
  }

  img.Image _yuvToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final out = img.Image(width: width, height: height);

    // NV21 single plane
    if (image.planes.length == 1) {
      final bytes = image.planes[0].bytes;
      final rowStride = image.planes[0].bytesPerRow;
      final frameSize = width * height;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final yp = bytes[y * rowStride + x];
          final uvIndex = frameSize + (y >> 1) * width + (x & ~1);
          final vp = bytes[uvIndex.clamp(0, bytes.length - 1)];
          final up = bytes[(uvIndex + 1).clamp(0, bytes.length - 1)];
          out.setPixelRgba(
            x,
            y,
            (yp + 1.370705 * (vp - 128)).round().clamp(0, 255),
            (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128)).round().clamp(0, 255),
            (yp + 1.732446 * (up - 128)).round().clamp(0, 255),
            255,
          );
        }
      }
      return out;
    }

    // YUV_420_888 (CameraX default)
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y >> 1) * uPlane.bytesPerRow;
      final vvRow = (y >> 1) * vPlane.bytesPerRow;
      for (var x = 0; x < width; x++) {
        final yp = yPlane.bytes[yRow + x];
        final uvCol = (x >> 1) * uvPixelStride;
        final up = uPlane.bytes[(uvRow + uvCol).clamp(0, uPlane.bytes.length - 1)];
        final vp = vPlane.bytes[
            (vvRow + (x >> 1) * (vPlane.bytesPerPixel ?? 1)).clamp(0, vPlane.bytes.length - 1)];
        out.setPixelRgba(
          x,
          y,
          (yp + 1.370705 * (vp - 128)).round().clamp(0, 255),
          (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128)).round().clamp(0, 255),
          (yp + 1.732446 * (up - 128)).round().clamp(0, 255),
          255,
        );
      }
    }
    return out;
  }

  img.Image? _cropFace(img.Image bitmap, Rect boundingBox) {
    // Slight pad helps MobileFaceNet (Sparkle used tight crop; pad is safer).
    final padX = boundingBox.width * 0.12;
    final padY = boundingBox.height * 0.12;
    final left = max(0, (boundingBox.left - padX).toInt());
    final top = max(0, (boundingBox.top - padY).toInt());
    final right = min(bitmap.width, (boundingBox.right + padX).toInt());
    final bottom = min(bitmap.height, (boundingBox.bottom + padY).toInt());
    final w = right - left;
    final h = bottom - top;
    if (w <= 8 || h <= 8) return null;
    return img.copyCrop(bitmap, x: left, y: top, width: w, height: h);
  }

  List<double>? _runInference(img.Image resizedFace) {
    if (_interpreter == null) return null;

    final buffer = Float32List(1 * 112 * 112 * 3);
    var index = 0;
    for (var y = 0; y < 112; y++) {
      for (var x = 0; x < 112; x++) {
        final pixel = resizedFace.getPixel(x, y);
        buffer[index++] = (pixel.r / 255.0 - 0.5) / 0.5;
        buffer[index++] = (pixel.g / 255.0 - 0.5) / 0.5;
        buffer[index++] = (pixel.b / 255.0 - 0.5) / 0.5;
      }
    }

    final input = buffer.reshape([1, 112, 112, 3]);
    final output = List.generate(1, (_) => List<double>.filled(192, 0));
    _interpreter!.run(input, output);
    return List<double>.from(output[0]);
  }

  /// CameraX often ignores nv21 and returns yuv420 — accept either.
  static ImageFormatGroup preferredImageFormat() {
    if (Platform.isAndroid) return ImageFormatGroup.yuv420;
    return ImageFormatGroup.bgra8888;
  }

  void dispose() {
    _faceDetector.close();
    _interpreter?.close();
  }
}
