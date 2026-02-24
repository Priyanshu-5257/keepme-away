import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:ui' as ui;
import '../services/face_detector.dart';
import '../utils/prefs.dart';
import '../widgets/face_overlay.dart';
import 'home_screen.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCalibrating = false;
  List<double> _samples = [];
  Timer? _calibrationTimer;
  int _countdown = 0;
  String _status = 'Position your face in the camera view at a comfortable distance';
  
  // Face overlay tracking
  ui.Rect? _currentFaceRect;
  bool _faceDetected = false;
  int _lastFrameWidth = 320;
  int _lastFrameHeight = 240;

  final FaceDetectorService _faceDetector = FaceDetectorService();
  StreamSubscription<FaceDetectionResult>? _detectionSubscription;
  
  // Platform channel for face detection communication
  static const platform = MethodChannel('io.github.priyanshu5257.keepmeaway/face_detection');
  bool _isImageStreamActive = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _faceDetector.initialize();
    _setupDetectionListener();
  }

  @override
  void dispose() {
    _calibrationTimer?.cancel();
    _detectionSubscription?.cancel();
    _controller?.dispose();
    _faceDetector.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _status = 'No cameras available');
        return;
      }

      // Find front camera
      CameraDescription? frontCamera;
      for (final camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      if (frontCamera == null) {
        setState(() => _status = 'Front camera not available');
        return;
      }

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.low, // Use low resolution for better battery (320x240 is enough for face detection)
        enableAudio: false,
      );

      await _controller!.initialize();
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _status = 'Camera ready. Position your face comfortably and tap "Start Calibration"';
        });
      }
    } catch (e) {
      setState(() => _status = 'Error initializing camera: $e');
    }
  }

  void _setupDetectionListener() {
    _detectionSubscription = _faceDetector.detectionStream.listen((result) {
      // Update face overlay even when not calibrating
      setState(() {
        _currentFaceRect = result.faceRect;
        _faceDetected = result.faceDetected;
        _lastFrameWidth = result.frameWidth;
        _lastFrameHeight = result.frameHeight;
      });
      
      if (!_isCalibrating) return;
      
      if (result.faceDetected && result.normalizedArea > 0) {
        setState(() {
          _samples.add(result.normalizedArea);
          _status = 'Calibrating... Sample ${_samples.length}/15 (Area: ${result.normalizedArea.toStringAsFixed(4)})';
        });
        
        if (kDebugMode) {
          print('Calibration sample: ${result.normalizedArea} (${result.frameWidth}x${result.frameHeight})');
        }
      } else {
        setState(() {
          _status = 'Calibrating... Please ensure your face is visible';
        });
      }
    });
  }

  void _startCalibration() {
    if (!_isCameraInitialized || _isCalibrating) return;

    setState(() {
      _isCalibrating = true;
      _samples.clear();
      _countdown = 2;
      _status = 'Get ready! Calibration starts in $_countdown seconds';
    });

    // Countdown timer
    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
        if (_countdown > 0) {
          _status = 'Get ready! Calibration starts in $_countdown seconds';
        } else {
          _status = 'Calibrating... Stay still and look at the camera';
          timer.cancel();
          _startSampling();
        }
      });
    });
  }

  void _startSampling() {
    // Use Android ML Kit for calibration - same as protection service
    _startAndroidFaceDetectionForCalibration();
    
    // Stop after 10 seconds or when we have enough samples
    Timer(const Duration(seconds: 10), () {
      _stopCalibration();
    });

    // Also check periodically if we have enough samples
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_samples.length >= 15) {
        timer.cancel();
        _stopCalibration();
      }
    });
  }

  void _startAndroidFaceDetectionForCalibration() async {
    try {
      // Start the Android face detection service temporarily for calibration
      await platform.invokeMethod('startCalibrationMode');
      
      // Listen for face detection results from Android
      Timer.periodic(const Duration(milliseconds: 200), (timer) {
        if (!_isCalibrating) {
          timer.cancel();
          platform.invokeMethod('stopCalibrationMode');
          return;
        }
        
        _getCalibrationSample();
      });
      
    } catch (e) {
      if (kDebugMode) print('Error starting Android face detection for calibration: $e');
      // Fallback to Flutter face detection if Android approach fails
      _startFlutterFaceDetection();
    }
  }

  void _getCalibrationSample() async {
    try {
      final result = await platform.invokeMethod('getCalibrationSample');
      if (result != null && result['faceDetected'] == true) {
        final area = result['normalizedArea'] as double;
        if (area > 0) {
          _samples.add(area);
          if (kDebugMode) print('Calibration sample: $area (${_samples.length}/15)');
          
          setState(() {
            _status = 'Calibrating... ${_samples.length}/15 samples collected\n'
                'Current area: ${area.toStringAsFixed(4)}';
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error getting calibration sample: $e');
    }
  }

  void _startFlutterFaceDetection() {
    // Fallback: Start image stream for face detection using Flutter TFLite
    try {
      if (_controller != null && _controller!.value.isInitialized) {
        _controller!.startImageStream((image) {
          if (kDebugMode) print('Camera image received: ${image.width}x${image.height}');
          _faceDetector.processImage(image);
        });
        _isImageStreamActive = true;
        if (kDebugMode) print('Image stream started successfully');
      } else {
        if (kDebugMode) print('Camera controller not ready for image stream');
        setState(() {
          _status = 'Camera not ready. Please try again.';
        });
        return;
      }
    } catch (e) {
      if (kDebugMode) print('Error starting image stream: $e');
      setState(() {
        _status = 'Error starting camera stream: $e';
      });
      return;
    }
  }

  void _stopCalibration() {
    if (!_isCalibrating) return;

    if (_isImageStreamActive) {
      try {
        _controller?.stopImageStream();
        _isImageStreamActive = false;
        if (kDebugMode) print('Image stream stopped');
      } catch (e) {
        if (kDebugMode) print('Error stopping image stream: $e');
      }
    }
    
    setState(() {
      _isCalibrating = false;
    });

    if (_samples.isNotEmpty) {
      _processCalibrationResults();
    } else {
      setState(() {
        _status = 'Calibration failed. No face detected. Please try again.';
      });
    }
  }

  void _processCalibrationResults() async {
    if (_samples.length < 5) {
      setState(() {
        _status = 'Not enough samples collected. Please try again.';
      });
      return;
    }

    // Calculate baseline using median for robustness
    final baseline = FaceDetectorService.calculateMedian(_samples);
    
    // Validate baseline - should be reasonable for face detection
    if (baseline < 0.005 || baseline > 0.3) {
      setState(() {
        _status = 'Invalid calibration data (baseline: ${baseline.toStringAsFixed(4)}). Please ensure your face is clearly visible and try again.';
      });
      return;
    }
    
    // Calculate some statistics for better feedback
    final minSample = _samples.reduce((a, b) => a < b ? a : b);
    final maxSample = _samples.reduce((a, b) => a > b ? a : b);
    final avgSample = _samples.reduce((a, b) => a + b) / _samples.length;
    
    setState(() {
      _status = 'Calibration successful!\n'
          'Baseline: ${baseline.toStringAsFixed(4)}\n'
          'Range: ${minSample.toStringAsFixed(4)} - ${maxSample.toStringAsFixed(4)}\n'
          'Average: ${avgSample.toStringAsFixed(4)}\n'
          'Samples: ${_samples.length}';
    });

    if (kDebugMode) {
      print('Calibration complete:');
      print('  Baseline (median): $baseline');
      print('  Average: $avgSample');
      print('  Min: $minSample, Max: $maxSample');
      print('  Samples: $_samples');
    }

    // Save calibration data
    PrefsHelper.setBaselineArea(baseline);
    PrefsHelper.setIsCalibrated(true);

    // Wait a moment to show results, then navigate
    await Future.delayed(const Duration(seconds: 2));

    // Dispose camera and navigate
    await _disposeCameraAndNavigate();
  }

  Future<void> _disposeCameraAndNavigate() async {
    // Stop image stream first to prevent further processing
    if (_isImageStreamActive) {
      try {
        await _controller?.stopImageStream();
        _isImageStreamActive = false;
      } catch (e) {
        if (kDebugMode) print('Error stopping image stream: $e');
      }
    }
    
    // Stop face detector
    _faceDetector.dispose();
    
    // Cancel subscriptions
    _calibrationTimer?.cancel();
    _detectionSubscription?.cancel();
    
    // Wait a moment for all operations to complete
    await Future.delayed(const Duration(milliseconds: 1000));
    
    // Dispose the controller
    try {
      await _controller?.dispose();
    } catch (e) {
      if (kDebugMode) print('Error disposing camera controller: $e');
    }
    
    if (mounted) {
      setState(() {
        _controller = null;
        _isCameraInitialized = false;
      });
    }

    // Give a moment for resources to release
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  void _skipCalibration() async {
    // For demo purposes, set a default baseline
    PrefsHelper.setBaselineArea(0.15); // Default baseline
    PrefsHelper.setIsCalibrated(true);
    
    await _controller?.dispose();
    if (mounted) {
      setState(() {
        _controller = null;
      });
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibration'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Camera Preview - fills space naturally like a modern camera app
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _isCameraInitialized && 
                     _controller != null && 
                     _controller!.value.isInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _controller!.value.previewSize?.height ?? 1,
                                height: _controller!.value.previewSize?.width ?? 1,
                                child: CameraPreview(_controller!),
                              ),
                            ),
                          ),
                        ),
                        // Face Overlay
                        FaceOverlay(
                          faceRect: _currentFaceRect,
                          imageSize: Size(
                            _lastFrameWidth.toDouble(),
                            _lastFrameHeight.toDouble(),
                          ),
                          isFront: true,
                          faceDetected: _faceDetected,
                        ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(),
                    ),
            ),
          ),
          
          // Status and Controls
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  if (_samples.isNotEmpty)
                    Column(
                      children: [
                        LinearProgressIndicator(
                          value: _samples.length / 15,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_samples.length}/15 samples',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isCameraInitialized && !_isCalibrating
                              ? _startCalibration
                              : null,
                          child: const Text('Start Calibration'),
                        ),
                      ),
                      
                      if (_isCalibrating) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _stopCalibration,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Stop'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  const Text(
                    'Instructions:\n'
                    '1. Sit at your comfortable viewing distance\n'
                    '2. Look directly at the camera\n'
                    '3. Stay still during calibration\n'
                    '4. This will be your baseline distance',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
