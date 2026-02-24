import 'package:flutter/material.dart';

/// Painter to draw face detection overlay on camera preview
class FaceOverlayPainter extends CustomPainter {
  final Rect? faceRect;
  final Size imageSize;
  final bool isFront;
  final Color color;
  
  FaceOverlayPainter({
    this.faceRect,
    required this.imageSize,
    this.isFront = true,
    this.color = Colors.green,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (faceRect == null || imageSize.isEmpty) return;
    
    // Scale factors to convert from image coordinates to canvas coordinates
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;
    
    // Mirror horizontally for front camera
    double left = faceRect!.left * scaleX;
    double right = faceRect!.right * scaleX;
    
    if (isFront) {
      // Mirror the coordinates for front camera
      final temp = left;
      left = size.width - right;
      right = size.width - temp;
    }
    
    final scaledRect = Rect.fromLTRB(
      left,
      faceRect!.top * scaleY,
      right,
      faceRect!.bottom * scaleY,
    );
    
    // Draw corner brackets instead of full rectangle for modern look
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    
    final cornerLength = scaledRect.width * 0.2;
    
    // Top-left corner
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.top + cornerLength),
      Offset(scaledRect.left, scaledRect.top),
      paint,
    );
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.top),
      Offset(scaledRect.left + cornerLength, scaledRect.top),
      paint,
    );
    
    // Top-right corner
    canvas.drawLine(
      Offset(scaledRect.right - cornerLength, scaledRect.top),
      Offset(scaledRect.right, scaledRect.top),
      paint,
    );
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.top),
      Offset(scaledRect.right, scaledRect.top + cornerLength),
      paint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.bottom - cornerLength),
      Offset(scaledRect.left, scaledRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(scaledRect.left, scaledRect.bottom),
      Offset(scaledRect.left + cornerLength, scaledRect.bottom),
      paint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      Offset(scaledRect.right - cornerLength, scaledRect.bottom),
      Offset(scaledRect.right, scaledRect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(scaledRect.right, scaledRect.bottom),
      Offset(scaledRect.right, scaledRect.bottom - cornerLength),
      paint,
    );
    
    // Draw subtle fill
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(scaledRect, const Radius.circular(8)),
      fillPaint,
    );
  }
  
  @override
  bool shouldRepaint(FaceOverlayPainter oldDelegate) {
    return faceRect != oldDelegate.faceRect || color != oldDelegate.color;
  }
}

/// Widget that displays face overlay on top of camera preview
class FaceOverlay extends StatelessWidget {
  final Rect? faceRect;
  final Size imageSize;
  final bool isFront;
  final bool faceDetected;
  
  const FaceOverlay({
    super.key,
    this.faceRect,
    required this.imageSize,
    this.isFront = true,
    this.faceDetected = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: FaceOverlayPainter(
        faceRect: faceRect,
        imageSize: imageSize,
        isFront: isFront,
        color: faceDetected ? Colors.green : Colors.orange,
      ),
      child: Container(),
    );
  }
}
