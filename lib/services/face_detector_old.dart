import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionResult {
  final double normalizedArea;
  final bool faceDetected;
  final int frameWidth;
  final int frameHeight;

  FaceDetectionResult({
    required this.normalizedArea,
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

  Stream<FaceDetectionResult> get detectionStream => _detectionController!.stream;

  void initialize() {
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
  }

  void dispose() {
    _faceDetector?.close();
    _detectionController?.close();
    _detectionController = null;
  }

  // Real ML Kit face detection - IDENTICAL to Android logic
  void processImage(CameraImage image) async {
    if (_isProcessing || _faceDetector == null) return;
    _isProcessing = true;

    try {
      // Convert CameraImage to InputImage for ML Kit
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      // Process with ML Kit - same as Android
      final faces = await _faceDetector!.processImage(inputImage);
      
      double totalArea = 0.0;
      for (final face in faces) {
        final bounds = face.boundingBox;
        final faceArea = bounds.width * bounds.height;
        final imageArea = image.width * image.height;
        final relativeArea = faceArea / imageArea;
        totalArea += relativeArea;
        
        print('Flutter Face detected - Area: $relativeArea, Bounds: ${bounds.width}x${bounds.height}');
      }

      final result = FaceDetectionResult(
        normalizedArea: totalArea,
        faceDetected: faces.isNotEmpty,
        frameWidth: image.width,
        frameHeight: image.height,
      );

      _detectionController?.add(result);
    } catch (e) {
      print('Error processing image: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // Convert CameraImage to InputImage for ML Kit
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

      const InputImageRotation imageRotation = InputImageRotation.rotation0deg;

      final InputImageFormat inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final planeData = image.planes.map(
        (Plane plane) {
          return InputImageMetadata(
            size: imageSize,
            rotation: imageRotation,
            format: inputImageFormat,
            bytesPerRow: plane.bytesPerRow,
          );
        },
      ).toList();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      print('Error converting camera image: $e');
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
