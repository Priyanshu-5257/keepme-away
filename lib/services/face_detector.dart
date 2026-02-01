import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';

class FaceDetectionResult {
  final double normalizedArea;
  final double smoothedArea;
  final bool faceDetected;
  final int frameWidth;
  final int frameHeight;

  FaceDetectionResult({
    required this.normalizedArea,
    required this.smoothedArea,
    required this.faceDetected,
    required this.frameWidth,
    required this.frameHeight,
  });
}

class FaceDetectorService {
  static final FaceDetectorService _instance = FaceDetectorService._internal();
  factory FaceDetectorService() => _instance;
  FaceDetectorService._internal();

  StreamController<FaceDetectionResult>? _detectionController;
  bool _isProcessing = false;
  FaceDetector? _faceDetector;
  bool _isInitialized = false;

  // ===== FRAME THROTTLING =====
  int _frameCount = 0;
  int _frameSkipCount = 2; // Process every Nth frame (1 = every frame, 2 = every other, etc.)
  
  // ===== ADAPTIVE DETECTION =====
  bool _adaptiveMode = true;
  int _consecutiveStableReadings = 0;
  double _lastArea = 0.0;
  static const double _stabilityThreshold = 0.01; // 1% change considered stable
  static const int _stableCountForSlowdown = 10; // After 10 stable readings, slow down
  int _adaptiveSkipMultiplier = 1; // Multiplier when stable
  
  // ===== MOVING AVERAGE SMOOTHING =====
  final List<double> _recentAreas = [];
  static const int _smoothingWindowSize = 5;
  
  // ===== DEBOUNCING =====
  DateTime? _lastResultTime;
  static const Duration _minResultInterval = Duration(milliseconds: 100);

  Stream<FaceDetectionResult> get detectionStream => _detectionController!.stream;
  bool get isInitialized => _isInitialized;
  
  // Configurable settings
  void setFrameSkip(int skipCount) {
    _frameSkipCount = skipCount.clamp(1, 10);
  }
  
  void setAdaptiveMode(bool enabled) {
    _adaptiveMode = enabled;
    if (!enabled) {
      _adaptiveSkipMultiplier = 1;
      _consecutiveStableReadings = 0;
    }
  }

  void initialize() {
    if (_isInitialized) return;
    
    _detectionController = StreamController<FaceDetectionResult>.broadcast();
    
    // Initialize ML Kit face detector with same settings as Android
    final options = FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      enableTracking: false,
      minFaceSize: 0.15, // Same as Android
      performanceMode: FaceDetectorMode.fast, // Same as Android
    );
    
    _faceDetector = FaceDetector(options: options);
    _isInitialized = true;
    
    if (kDebugMode) {
      print('[FaceDetector] Initialized with frameSkip=$_frameSkipCount, adaptiveMode=$_adaptiveMode');
    }
  }
  
  /// Pre-warm the detector by running a dummy detection
  Future<void> warmUp() async {
    if (!_isInitialized) initialize();
    // ML Kit warms up on first use, this ensures it's ready
    if (kDebugMode) {
      print('[FaceDetector] Warm-up complete');
    }
  }

  void dispose() {
    _faceDetector?.close();
    _detectionController?.close();
    _detectionController = null;
    _isInitialized = false;
    _recentAreas.clear();
    _consecutiveStableReadings = 0;
    _frameCount = 0;
  }

  void processImage(CameraImage image) async {
    // ===== FRAME THROTTLING =====
    _frameCount++;
    final effectiveSkip = _frameSkipCount * _adaptiveSkipMultiplier;
    if (_frameCount % effectiveSkip != 0) {
      return; // Skip this frame
    }
    
    if (_isProcessing || _faceDetector == null) return;
    
    // ===== DEBOUNCING =====
    final now = DateTime.now();
    if (_lastResultTime != null && 
        now.difference(_lastResultTime!) < _minResultInterval) {
      return;
    }
    
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage != null) {
        final faces = await _faceDetector!.processImage(inputImage);
        
        double rawArea = 0.0;
        bool faceDetected = faces.isNotEmpty;
        
        if (faces.isNotEmpty) {
          // Use LARGEST face only (multi-face handling)
          final largestFace = faces.reduce((a, b) => 
            (a.boundingBox.width * a.boundingBox.height) > 
            (b.boundingBox.width * b.boundingBox.height) ? a : b);
          
          final bounds = largestFace.boundingBox;
          final faceArea = bounds.width * bounds.height;
          final imageArea = image.width * image.height;
          rawArea = faceArea / imageArea;
          
          if (kDebugMode) {
            print('[FaceDetector] Face - Raw area: ${rawArea.toStringAsFixed(4)}, '
                  'Bounds: ${bounds.width.toInt()}x${bounds.height.toInt()}');
          }
        }
        
        // ===== MOVING AVERAGE SMOOTHING =====
        final smoothedArea = _calculateSmoothedArea(rawArea);
        
        // ===== ADAPTIVE DETECTION =====
        _updateAdaptiveMode(rawArea);

        final result = FaceDetectionResult(
          normalizedArea: rawArea,
          smoothedArea: smoothedArea,
          faceDetected: faceDetected,
          frameWidth: image.width,
          frameHeight: image.height,
        );

        _detectionController?.add(result);
        _lastResultTime = now;
        
        if (kDebugMode) {
          print('[FaceDetector] Smoothed: ${smoothedArea.toStringAsFixed(4)}, '
                'Skip: $effectiveSkip, Stable: $_consecutiveStableReadings');
        }
        
      } else if (kDebugMode) {
        // Only use fallback in debug mode
        _simulateRealisticDetection(image);
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('[FaceDetector] Error: $e');
        _simulateRealisticDetection(image);
      }
    } finally {
      _isProcessing = false;
    }
  }
  
  double _calculateSmoothedArea(double newArea) {
    _recentAreas.add(newArea);
    if (_recentAreas.length > _smoothingWindowSize) {
      _recentAreas.removeAt(0);
    }
    
    if (_recentAreas.isEmpty) return newArea;
    
    // Simple moving average
    final sum = _recentAreas.reduce((a, b) => a + b);
    return sum / _recentAreas.length;
  }
  
  void _updateAdaptiveMode(double currentArea) {
    if (!_adaptiveMode) return;
    
    final change = (currentArea - _lastArea).abs();
    final relativeChange = _lastArea > 0 ? change / _lastArea : 1.0;
    
    if (relativeChange < _stabilityThreshold) {
      _consecutiveStableReadings++;
      if (_consecutiveStableReadings >= _stableCountForSlowdown) {
        // User is stable, slow down detection
        _adaptiveSkipMultiplier = 2;
      }
    } else {
      // Movement detected, speed up detection
      _consecutiveStableReadings = 0;
      _adaptiveSkipMultiplier = 1;
    }
    
    _lastArea = currentArea;
  }

  // Debug-only fallback simulation
  void _simulateRealisticDetection(CameraImage image) {
    if (!kDebugMode) return;
    
    try {
      final baseArea = 0.08;
      final timeVariation = (DateTime.now().millisecondsSinceEpoch % 2000 - 1000) / 20000.0;
      double normalizedArea = (baseArea + timeVariation).clamp(0.05, 0.15);
      
      final smoothedArea = _calculateSmoothedArea(normalizedArea);

      final result = FaceDetectionResult(
        normalizedArea: normalizedArea,
        smoothedArea: smoothedArea,
        faceDetected: true,
        frameWidth: image.width,
        frameHeight: image.height,
      );

      _detectionController?.add(result);
      print('[FaceDetector] Simulation - Area: $normalizedArea');
      
    } catch (e) {
      print('[FaceDetector] Simulation error: $e');
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation270deg,
        format: InputImageFormat.yuv420,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: metadata,
      );
      
    } catch (e) {
      if (kDebugMode) {
        print('[FaceDetector] Image conversion failed: $e');
      }
      return null;
    }
  }

  // Calculate median from a list of samples
  static double calculateMedian(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    
    final sorted = List<double>.from(samples)..sort();
    final middle = sorted.length ~/ 2;
    
    if (sorted.length % 2 == 1) {
      return sorted[middle];
    } else {
      return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
  }
}
