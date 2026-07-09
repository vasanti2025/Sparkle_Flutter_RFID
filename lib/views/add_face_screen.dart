import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extension.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/pref_service.dart';
import '../services/face_recognition_service.dart';
import '../utils/camera_permission_util.dart';

class AddFaceScreen extends StatefulWidget {
  const AddFaceScreen({super.key});

  @override
  State<AddFaceScreen> createState() => _AddFaceScreenState();
}

class _AddFaceScreenState extends State<AddFaceScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInit = false;
  bool _hasError = false;
  String _errorText = '';
  bool _saving = false;
  int _selectedCameraIndex = 0;
  bool _modelReady = false;
  bool _faceDetected = false;
  bool _checkingFace = false;
  bool _captureLocked = false;

  late AnimationController _scanAnimController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanAnimController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final faceService = context.read<FaceRecognitionService>();
    await faceService.ensureInitialized();
    if (!mounted) return;

    if (!faceService.isModelLoaded) {
      setState(() {
        _hasError = true;
        _errorText = faceService.initError ?? 'Face model not loaded';
      });
      return;
    }

    setState(() => _modelReady = true);
    await _initCamera();
  }

  Future<void> _initCamera() async {
    final granted = await ensureCameraPermission();
    if (!granted) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorText = 'Camera permission is required to register face';
        });
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No cameras found');
      }

      final frontIndex = _cameras!.indexWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
      );
      _selectedCameraIndex = frontIndex != -1 ? frontIndex : 0;
      await _startCamera(_selectedCameraIndex);
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorText = e.toString();
        });
      }
    }
  }

  Future<void> _startCamera(int index) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      _cameras![index],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isInit = true;
          _hasError = false;
          _faceDetected = false;
        });
        _startFacePreviewCheck();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorText = e.toString();
        });
      }
    }
  }

  void _toggleCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    setState(() {
      _isInit = false;
      _faceDetected = false;
    });
    await _startCamera(_selectedCameraIndex);
  }

  CameraCaptureInfo? get _captureInfo {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return null;
    return CameraCaptureInfo(
      sensorOrientation: controller.description.sensorOrientation,
      lensDirection: controller.description.lensDirection,
    );
  }

  Future<void> _startFacePreviewCheck() async {
    if (!mounted || _checkingFace || _saving || _captureLocked) return;
    final controller = _cameraController;
    final captureInfo = _captureInfo;
    final faceService = context.read<FaceRecognitionService>();
    if (controller == null || captureInfo == null || !faceService.isModelLoaded) return;

    _checkingFace = true;
    try {
      final file = await controller.takePicture();
      final embedding = await faceService.getEmbeddingFromCameraFile(
        file.path,
        captureInfo: captureInfo,
      );
      if (!mounted) return;
      setState(() => _faceDetected = embedding != null);
    } catch (_) {
      if (mounted) setState(() => _faceDetected = false);
    } finally {
      _checkingFace = false;
      if (mounted && _isInit && !_saving) {
        Future.delayed(const Duration(milliseconds: 900), _startFacePreviewCheck);
      }
    }
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildFacePayload({
    required Employee employee,
    required String employeeJson,
    required String embeddingString,
  }) {
    final username = employee.userName ?? employee.username ?? '';
    return {
      'Name': username.isNotEmpty ? username : 'User',
      'UserId': employee.userId ?? employee.id,
      'EmployeeId': employee.employeeId ?? employee.id,
      'EmployeeJson': employeeJson,
      'Username': username,
      'ClientCode': employee.clientCode ?? '',
      'BranchId': employee.defaultBranchId,
      'UserType': employee.designation ?? 'User',
      'Width': 480,
      'Height': 640,
      'FaceWidth': 200,
      'FaceHeight': 200,
      'Top': 150,
      'Left': 140,
      'Right': 340,
      'Bottom': 350,
      'SmilingProbability': 0.8,
      'LeftEyeOpenProbability': 0.95,
      'RightEyeOpenProbability': 0.95,
      'FaceTimestamp': DateTime.now().toIso8601String(),
      'FaceTimeMs': DateTime.now().millisecondsSinceEpoch,
      'Embedding': embeddingString,
      'StatusType': true,
    };
  }

  Future<void> _onSaveFace() async {
    final pref = context.read<PrefService>();
    final api = context.read<ApiService>();
    final faceRecognitionService = context.read<FaceRecognitionService>();
    final s = context.sRead;

    final employee = pref.getEmployee();
    if (employee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.loginErrorLabel)),
      );
      return;
    }

    if (!_modelReady || !faceRecognitionService.isModelLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.errorWithMessage('Face model not loaded')), backgroundColor: Colors.red),
      );
      return;
    }

    if (!_isInit || _cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.errorWithMessage('Camera not ready')), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _saving = true);
    _captureLocked = true;

    try {
      final captureInfo = _captureInfo;
      if (captureInfo == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.errorWithMessage('Camera not ready')), backgroundColor: Colors.red),
          );
        }
        return;
      }

      List<double>? embeddingList;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await Future<void>.delayed(Duration(milliseconds: attempt * 200));
          final file = await _cameraController!.takePicture();
          embeddingList = await faceRecognitionService.getEmbeddingFromCameraFile(
            file.path,
            captureInfo: captureInfo,
          );
          if (embeddingList != null) break;
        } catch (e) {
          if (attempt == 2 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.errorWithMessage(e)), backgroundColor: Colors.red),
            );
          }
        }
      }

      if (embeddingList == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.noFaceDetectedLabel), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final embeddingString = embeddingList.join(',');
      final employeeJson = pref.getEmployeeRawJson().isNotEmpty
          ? pref.getEmployeeRawJson()
          : jsonEncode(employee.toJson());
      final username = employee.userName ?? employee.username ?? '';

      await api.saveFace(_buildFacePayload(
        employee: employee,
        employeeJson: employeeJson,
        embeddingString: embeddingString,
      ));

      await pref.saveRegisteredFaceEmbedding(embeddingString);
      await pref.saveRegisteredFaceUsername(username);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.faceMatchedSuccessfully), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.errorWithMessage(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      _captureLocked = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          s.registerFace,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_cameras != null && _cameras!.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
              onPressed: _toggleCamera,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isInit && _cameraController != null)
                    ClipOval(
                      child: SizedBox(
                        width: 250,
                        height: 250,
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                    )
                  else if (_hasError)
                    Container(
                      width: 250,
                      height: 250,
                      decoration: const BoxDecoration(
                        color: Color(0xFF212121),
                        shape: BoxShape.circle,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_off, color: Colors.white54, size: 60),
                          if (_errorText.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                _errorText,
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                                textAlign: TextAlign.center,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    Container(
                      width: 250,
                      height: 250,
                      decoration: const BoxDecoration(
                        color: Color(0xFF212121),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  Container(
                    width: 258,
                    height: 258,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF5231A7), width: 4),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _scanAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: 20 + (_scanAnimation.value * 210),
                        child: Container(
                          width: 220,
                          height: 3,
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFD32940).withValues(alpha: 0.6),
                                blurRadius: 4,
                                spreadRadius: 2,
                              ),
                            ],
                            gradient: const LinearGradient(
                              colors: [Color(0xFF5231A7), Color(0xFFD32940)],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.alignFaceInCircle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _saving
                      ? s.pleaseWaitItemsLoading
                      : _faceDetected
                          ? 'Face detected — tap Save'
                          : s.scanningFace,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: _faceDetected ? const Color(0xFF4CAF50) : Colors.white54,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: (_saving || !_isInit || !_modelReady) ? null : _onSaveFace,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFFD32940),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          s.saveFaceLabel,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
