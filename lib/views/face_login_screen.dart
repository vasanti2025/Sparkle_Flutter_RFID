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

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInit = false;
  bool _hasError = false;
  String _errorText = '';
  bool _matching = false;
  bool _modelReady = false;
  int _selectedCameraIndex = 0;

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
    if (mounted && _isInit) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) await _performFaceMatching();
    }
  }

  Future<void> _initCamera() async {
    final granted = await ensureCameraPermission();
    if (!granted) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorText = 'Camera permission is required for face login';
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
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isInit = true;
          _hasError = false;
        });
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
    setState(() => _isInit = false);
    await _startCamera(_selectedCameraIndex);
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  List<dynamic> _extractFaceList(Map<String, dynamic>? response) {
    if (response == null) return const [];
    final data = response['Data'] ?? response['data'];
    if (data is List) return data;
    return const [];
  }

  Future<Map<String, dynamic>?> _findBestFaceMatch({
    required List<double> liveEmbedding,
    required List<dynamic> dataList,
  }) async {
    Map<String, dynamic>? bestFace;
    var bestDistance = double.maxFinite;

    for (final rawFace in dataList) {
      if (rawFace is! Map) continue;
      final face = Map<String, dynamic>.from(rawFace as Map);
      final embString = (face['Embedding'] ?? face['embedding'])?.toString() ?? '';
      if (embString.isEmpty) continue;

      final remoteEmbedding = FaceRecognitionService.parseEmbedding(embString);
      if (remoteEmbedding.length != liveEmbedding.length) continue;

      final distance = FaceRecognitionService.euclideanDistance(liveEmbedding, remoteEmbedding);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestFace = face;
      }
    }

    if (bestFace != null && bestDistance < FaceRecognitionService.matchThreshold) {
      return bestFace;
    }
    return null;
  }

  Future<void> _completeLogin(Map<String, dynamic> matchedFace) async {
    final pref = context.read<PrefService>();
    final s = context.sRead;

    final employeeJson = (matchedFace['EmployeeJson'] ?? matchedFace['employeeJson'])?.toString() ?? '';
    if (employeeJson.isEmpty) {
      throw Exception('Employee profile missing from face record');
    }

    final employee = Employee.fromJson(jsonDecode(employeeJson) as Map<String, dynamic>);
    await pref.saveToken('face_login_token');
    await pref.saveEmployee(employee);
    await pref.setUserId(employee.id);
    await pref.setLoggedIn(true);
    await pref.saveBranchId(employee.defaultBranchId);
    if (employee.clients != null) {
      await pref.saveClient(employee.clients!);
    }

    final matchedUsername = (matchedFace['Username'] ?? matchedFace['username'])?.toString() ??
        employee.userName ??
        employee.username ??
        '';
    await pref.saveLoginCredentials(
      username: matchedUsername,
      password: pref.getSavedPassword(),
      rememberMe: true,
      rfidType: employee.clients?.rfidType ?? '',
      userId: employee.id,
      branchId: employee.defaultBranchId,
      organisationName: employee.clients?.organisationName ?? '',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.faceMatchedSuccessfully), backgroundColor: Colors.green),
      );
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  CameraCaptureInfo? get _captureInfo {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return null;
    return CameraCaptureInfo(
      sensorOrientation: controller.description.sensorOrientation,
      lensDirection: controller.description.lensDirection,
    );
  }

  Future<void> _performFaceMatching() async {
    if (!mounted || _matching) return;
    final pref = context.read<PrefService>();
    final api = context.read<ApiService>();
    final faceRecognitionService = context.read<FaceRecognitionService>();
    final s = context.sRead;

    if (!_modelReady || !faceRecognitionService.isModelLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.errorWithMessage('Face model not loaded'))),
      );
      return;
    }

    if (!_isInit || _cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.errorWithMessage('Camera not ready'))),
      );
      return;
    }

    setState(() => _matching = true);

    try {
      final captureInfo = _captureInfo;
      if (captureInfo == null) {
        throw Exception(s.errorWithMessage('Camera not ready'));
      }

      List<double>? liveEmbedding;
      for (var attempt = 0; attempt < 3; attempt++) {
        await Future<void>.delayed(Duration(milliseconds: attempt * 200));
        final file = await _cameraController!.takePicture();
        liveEmbedding = await faceRecognitionService.getEmbeddingFromCameraFile(
          file.path,
          captureInfo: captureInfo,
        );
        if (liveEmbedding != null && liveEmbedding.isNotEmpty) break;
      }

      if (liveEmbedding == null || liveEmbedding.isEmpty) {
        throw Exception(s.noFaceDetectedLabel);
      }

      // Kotlin loads all faces with empty clientCode.
      var dataList = _extractFaceList(await api.getAllFaceLogin(''));
      if (dataList.isEmpty) {
        final clientCode = pref.getClient()?.clientCode ?? pref.getEmployee()?.clientCode ?? '';
        if (clientCode.isNotEmpty) {
          dataList = _extractFaceList(await api.getAllFaceLogin(clientCode));
        }
      }

      Map<String, dynamic>? matchedFace;
      if (dataList.isNotEmpty) {
        matchedFace = await _findBestFaceMatch(
          liveEmbedding: liveEmbedding,
          dataList: dataList,
        );
      }

      // Offline fallback: compare with locally saved registration.
      if (matchedFace == null) {
        final localEmbedding = FaceRecognitionService.parseEmbedding(pref.getRegisteredFaceEmbedding());
        if (localEmbedding.length == liveEmbedding.length) {
          final distance = FaceRecognitionService.euclideanDistance(liveEmbedding, localEmbedding);
          if (distance < FaceRecognitionService.matchThreshold) {
            final employee = pref.getEmployee();
            if (employee != null) {
              await _completeLogin({
                'EmployeeJson': pref.getEmployeeRawJson().isNotEmpty
                    ? pref.getEmployeeRawJson()
                    : jsonEncode(employee.toJson()),
                'Username': pref.getRegisteredFaceUsername(),
              });
              return;
            }
          }
        }
      }

      if (matchedFace == null) {
        throw Exception(dataList.isEmpty ? s.noSavedFaceDataFound : s.faceNotRecognised);
      }

      await _completeLogin(matchedFace);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => _matching = false);
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
          s.faceLogin,
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (_isInit && _cameraController != null)
                  ClipOval(
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  )
                else if (_hasError)
                  Container(
                    width: 200,
                    height: 200,
                    decoration: const BoxDecoration(
                      color: Color(0xFF212121),
                      shape: BoxShape.circle,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.videocam_off, size: 60, color: Colors.white54),
                        if (_errorText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _errorText,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: 200,
                    height: 200,
                    decoration: const BoxDecoration(
                      color: Color(0xFF212121),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.face_unlock_rounded, size: 100, color: Colors.white54),
                  ),
                Container(
                  width: 208,
                  height: 208,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0077D4), width: 3),
                  ),
                ),
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (context, child) {
                    return Positioned(
                      top: 10 + (_scanAnimation.value * 180),
                      child: Container(
                        width: 170,
                        height: 3,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0077D4).withValues(alpha: 0.6),
                              blurRadius: 4,
                              spreadRadius: 2,
                            ),
                          ],
                          color: const Color(0xFF0077D4),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              s.alignFaceInCircle,
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              _matching ? s.pleaseWaitItemsLoading : s.scanningFace,
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.white54),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_matching || !_isInit || !_modelReady) ? null : _performFaceMatching,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0077D4),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: Text(
                _matching ? s.pleaseWaitItemsLoading : s.faceLogin,
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
