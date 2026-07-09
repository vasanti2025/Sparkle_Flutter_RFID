import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Size;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class CameraCaptureInfo {
  final int sensorOrientation;
  final CameraLensDirection lensDirection;

  const CameraCaptureInfo({
    required this.sensorOrientation,
    required this.lensDirection,
  });
}

class FaceRecognitionService {
  late FaceDetector _faceDetector;
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  String? _initError;

  FaceRecognitionService() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: false,
        enableClassification: false,
        minFaceSize: 0.08,
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

  /// Preferred entry for camera [takePicture] output.
  Future<List<double>?> getEmbeddingFromCameraFile(
    String filePath, {
    required CameraCaptureInfo captureInfo,
  }) async {
    await ensureInitialized();
    if (!_isModelLoaded || _interpreter == null) {
      debugPrint('TFLITE: Model not loaded (${_initError ?? 'unknown'})');
      return null;
    }

    try {
      final bytes = await File(filePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint('TFLITE: Failed to decode camera JPEG');
        return null;
      }

      final candidates = _buildOrientedCandidates(decoded, captureInfo);
      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        final embedding = await _detectAndEmbed(candidate);
        if (embedding != null) {
          debugPrint('TFLITE: Face found using orientation candidate #$i');
          return embedding;
        }
      }

      debugPrint('TFLITE: No face detected after ${candidates.length} orientation attempts');
      return null;
    } catch (e, st) {
      debugPrint('TFLITE Error during camera inference: $e\n$st');
      return null;
    }
  }

  Future<List<double>?> getEmbeddingFromImageFile(String filePath) async {
    return getEmbeddingFromCameraFile(
      filePath,
      captureInfo: const CameraCaptureInfo(
        sensorOrientation: 0,
        lensDirection: CameraLensDirection.front,
      ),
    );
  }

  List<img.Image> _buildOrientedCandidates(img.Image source, CameraCaptureInfo info) {
    final out = <img.Image>[];

    void add(img.Image image) {
      if (image.width >= 48 && image.height >= 48) {
        out.add(image);
      }
    }

    img.Image rotate(img.Image image, int angle) {
      if (angle == 0) return image;
      return img.copyRotate(image, angle: angle);
    }

    img.Image mirror(img.Image image) {
      return img.flipHorizontal(image);
    }

    final rotations = <int>{
      0,
      info.sensorOrientation,
      (360 - info.sensorOrientation) % 360,
      90,
      180,
      270,
    };

    for (final angle in rotations) {
      final rotated = rotate(source, angle);
      add(rotated);
      add(_centerSquare(rotated));
      if (info.lensDirection == CameraLensDirection.front) {
        add(mirror(rotated));
        add(_centerSquare(mirror(rotated)));
      }
    }

    return out;
  }

  img.Image _centerSquare(img.Image image, {double fraction = 0.82}) {
    final side = (min(image.width, image.height) * fraction).round();
    if (side <= 0) return image;
    final x = ((image.width - side) / 2).round();
    final y = ((image.height - side) / 2).round();
    return img.copyCrop(image, x: x, y: y, width: side, height: side);
  }

  Future<List<double>?> _detectAndEmbed(img.Image image) async {
    final inputImage = _inputImageFromBitmap(image);
    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) return null;

    faces.sort((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaB.compareTo(areaA);
    });

    return _embeddingFromFace(image, faces.first);
  }

  InputImage _inputImageFromBitmap(img.Image image) {
    final bytes = _toBgraBytes(image);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.width * 4,
      ),
    );
  }

  Uint8List _toBgraBytes(img.Image image) {
    final bytes = Uint8List(image.width * image.height * 4);
    var offset = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        bytes[offset++] = pixel.b.toInt();
        bytes[offset++] = pixel.g.toInt();
        bytes[offset++] = pixel.r.toInt();
        bytes[offset++] = 255;
      }
    }
    return bytes;
  }

  List<double>? _embeddingFromFace(img.Image originalImage, Face face) {
    final rect = face.boundingBox;
    final padX = rect.width * 0.12;
    final padY = rect.height * 0.12;
    final x = max(0, (rect.left - padX).toInt());
    final y = max(0, (rect.top - padY).toInt());
    final right = min(originalImage.width.toDouble(), rect.right + padX);
    final bottom = min(originalImage.height.toDouble(), rect.bottom + padY);
    final w = (right - x).toInt();
    final h = (bottom - y).toInt();
    if (w <= 0 || h <= 0) return null;

    final croppedFace = img.copyCrop(originalImage, x: x, y: y, width: w, height: h);
    final resizedFace = img.copyResize(croppedFace, width: 112, height: 112);
    return _runInference(resizedFace);
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

    final embedding = List<double>.from(output[0]);
    debugPrint('TFLITE: Generated embedding of size ${embedding.length}');
    return embedding;
  }

  void dispose() {
    _faceDetector.close();
    _interpreter?.close();
  }
}
