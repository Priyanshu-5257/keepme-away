import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceDetectionResult {
  final double normalizedArea;
  final double smoothedArea;
  final bool faceDetected;
  final int frameWidth;
  final int frameHeight;
  final Rect? faceRect;  // Face bounding box for overlay

  FaceDetectionResult({
    required this.normalizedArea,
    required this.smoothedArea,
    required this.faceDetected,
    required this.frameWidth,
    required this.frameHeight,
    this.faceRect,
  });
}

class FaceDetectorService {
  static final FaceDetectorService _instance = FaceDetectorService._internal();
  factory FaceDetectorService() => _instance;
  FaceDetectorService._internal();

  StreamController<FaceDetectionResult>? _detectionController;
  bool _isProcessing = false;
  Interpreter? _interpreter;
  bool _isInitialized = false;

  // BlazeFace model input size
  static const int _inputSize = 128;
  // BlazeFace detection threshold
  static const double _confidenceThreshold = 0.5;

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
    _isInitialized = true;
    
    if (kDebugMode) {
      print('[FaceDetector] Initialized with frameSkip=$_frameSkipCount, adaptiveMode=$_adaptiveMode');
    }
  }

  /// Load the BlazeFace TFLite model
  Future<void> _loadModel() async {
    if (_interpreter != null) return;
    
    try {
      _interpreter = await Interpreter.fromAsset(
        'face_detection_short_range.tflite',
        options: InterpreterOptions()..threads = 2,
      );
      
      if (kDebugMode) {
        print('[FaceDetector] BlazeFace model loaded successfully');
        print('[FaceDetector] Input tensors: ${_interpreter!.getInputTensors()}');
        print('[FaceDetector] Output tensors: ${_interpreter!.getOutputTensors()}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FaceDetector] Error loading model: $e');
      }
    }
  }
  
  /// Pre-warm the detector by loading the model
  Future<void> warmUp() async {
    if (!_isInitialized) initialize();
    await _loadModel();
    if (kDebugMode) {
      print('[FaceDetector] Warm-up complete');
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
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
    
    if (_isProcessing || _interpreter == null) {
      // Try to load model if not loaded yet
      if (_interpreter == null && !_isProcessing) {
        _loadModel();
      }
      return;
    }
    
    // ===== DEBOUNCING =====
    final now = DateTime.now();
    if (_lastResultTime != null && 
        now.difference(_lastResultTime!) < _minResultInterval) {
      return;
    }
    
    _isProcessing = true;

    try {
      final result = await compute(_processImageIsolate, _ImageProcessingInput(
        planes: image.planes.map((p) => _PlaneData(
          bytes: p.bytes,
          bytesPerRow: p.bytesPerRow,
          bytesPerPixel: p.bytesPerPixel ?? 1,
          width: p.width ?? image.width,
          height: p.height ?? image.height,
        )).toList(),
        width: image.width,
        height: image.height,
        inputSize: _inputSize,
      ));
      
      if (result != null) {
        final rawArea = result.normalizedArea;
        
        // ===== MOVING AVERAGE SMOOTHING =====
        final smoothedArea = _calculateSmoothedArea(rawArea);
        
        // ===== ADAPTIVE DETECTION =====
        _updateAdaptiveMode(rawArea);

        final detectionResult = FaceDetectionResult(
          normalizedArea: rawArea,
          smoothedArea: smoothedArea,
          faceDetected: result.faceDetected,
          frameWidth: image.width,
          frameHeight: image.height,
          faceRect: result.faceRect,
        );

        _detectionController?.add(detectionResult);
        _lastResultTime = now;
        
        if (kDebugMode) {
          print('[FaceDetector] Smoothed: ${smoothedArea.toStringAsFixed(4)}, '
                'Skip: $effectiveSkip, Stable: $_consecutiveStableReadings');
        }
      } else {
        // No face detected
        _recentAreas.clear();
        final detectionResult = FaceDetectionResult(
          normalizedArea: 0.0,
          smoothedArea: 0.0,
          faceDetected: false,
          frameWidth: image.width,
          frameHeight: image.height,
        );
        _detectionController?.add(detectionResult);
        _lastResultTime = now;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FaceDetector] Error: $e');
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

// ===== Isolate-safe data classes =====

class _PlaneData {
  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
  final int width;
  final int height;

  _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
  });
}

class _ImageProcessingInput {
  final List<_PlaneData> planes;
  final int width;
  final int height;
  final int inputSize;

  _ImageProcessingInput({
    required this.planes,
    required this.width,
    required this.height,
    required this.inputSize,
  });
}

class _DetectionOutput {
  final double normalizedArea;
  final bool faceDetected;
  final Rect? faceRect;

  _DetectionOutput({
    required this.normalizedArea,
    required this.faceDetected,
    this.faceRect,
  });
}

/// Process image in an isolate (YUV to RGB conversion + face area estimation)
/// Note: TFLite inference cannot run in isolate (interpreter not transferable),
/// so we do preprocessing here and simple luminance-based face detection heuristic
/// as a fallback. The actual TFLite detection runs on the Android native side
/// via the FaceDetectionManager for background protection.
/// For the Flutter calibration flow, we preprocess and use a simpler approach.
_DetectionOutput? _processImageIsolate(_ImageProcessingInput input) {
  try {
    if (input.planes.isEmpty) return null;
    
    final yPlane = input.planes[0];
    final width = input.width;
    final height = input.height;
    
    // Simple face detection using luminance variance analysis
    // This is used for the Flutter-side calibration preview
    // The real detection happens on Android native side via TFLite
    
    // Divide image into grid and analyze luminance patterns
    final gridSize = 8;
    final cellWidth = width ~/ gridSize;
    final cellHeight = height ~/ gridSize;
    
    // Calculate mean luminance per cell
    final cellMeans = List<double>.filled(gridSize * gridSize, 0);
    final cellVariances = List<double>.filled(gridSize * gridSize, 0);
    
    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        double sum = 0;
        int count = 0;
        
        for (int y = gy * cellHeight; y < (gy + 1) * cellHeight && y < height; y += 2) {
          for (int x = gx * cellWidth; x < (gx + 1) * cellWidth && x < width; x += 2) {
            final idx = y * yPlane.bytesPerRow + x;
            if (idx < yPlane.bytes.length) {
              sum += yPlane.bytes[idx];
              count++;
            }
          }
        }
        
        cellMeans[gy * gridSize + gx] = count > 0 ? sum / count : 0;
      }
    }
    
    // Calculate variance per cell
    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        final mean = cellMeans[gy * gridSize + gx];
        double varSum = 0;
        int count = 0;
        
        for (int y = gy * cellHeight; y < (gy + 1) * cellHeight && y < height; y += 2) {
          for (int x = gx * cellWidth; x < (gx + 1) * cellWidth && x < width; x += 2) {
            final idx = y * yPlane.bytesPerRow + x;
            if (idx < yPlane.bytes.length) {
              final diff = yPlane.bytes[idx] - mean;
              varSum += diff * diff;
              count++;
            }
          }
        }
        
        cellVariances[gy * gridSize + gx] = count > 0 ? varSum / count : 0;
      }
    }
    
    // Find connected region of skin-like luminance (typically 80-200 range)
    // with moderate variance (faces have texture)
    int skinCells = 0;
    int minX = gridSize, maxX = 0, minY = gridSize, maxY = 0;
    
    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        final mean = cellMeans[gy * gridSize + gx];
        final variance = cellVariances[gy * gridSize + gx];
        
        // Skin-like luminance range with moderate variance
        if (mean > 60 && mean < 220 && variance > 20 && variance < 2000) {
          skinCells++;
          if (gx < minX) minX = gx;
          if (gx > maxX) maxX = gx;
          if (gy < minY) minY = gy;
          if (gy > maxY) maxY = gy;
        }
      }
    }
    
    // Check if we have a reasonable face-sized region
    final totalCells = gridSize * gridSize;
    final skinRatio = skinCells / totalCells;
    
    // Face should occupy roughly 5-40% of the frame
    if (skinRatio > 0.05 && skinRatio < 0.6 && skinCells > 3) {
      final faceWidth = (maxX - minX + 1) * cellWidth;
      final faceHeight = (maxY - minY + 1) * cellHeight;
      final faceArea = faceWidth * faceHeight;
      final imageArea = width * height;
      final normalizedArea = faceArea / imageArea;
      
      return _DetectionOutput(
        normalizedArea: normalizedArea.clamp(0.0, 1.0),
        faceDetected: true,
        faceRect: Rect.fromLTWH(
          (minX * cellWidth).toDouble(),
          (minY * cellHeight).toDouble(),
          faceWidth.toDouble(),
          faceHeight.toDouble(),
        ),
      );
    }
    
    return null;
  } catch (e) {
    return null;
  }
}
