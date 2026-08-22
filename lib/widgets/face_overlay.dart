import 'package:flutter/material.dart';
import '../utils/theme_provider.dart';

/// Face-ID style oval used while positioning for calibration.
class FaceGuideOverlay extends StatelessWidget {
  final bool aligned;

  const FaceGuideOverlay({super.key, this.aligned = false});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OvalGuidePainter(
        color: aligned ? const Color(0xFF3DDC97) : AppColors.ring,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _OvalGuidePainter extends CustomPainter {
  final Color color;
  _OvalGuidePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.46),
      width: size.width * 0.62,
      height: size.height * 0.58,
    );

    final dim = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      dim,
      Paint()..color = Colors.black.withValues(alpha: 0.38),
    );

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const sweep = 0.42;
    for (final start in [0.95, 2.52, 4.08, 5.65]) {
      canvas.drawArc(oval, start, sweep, false, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _OvalGuidePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Abstract two-eye visual used while sampling (no live camera).
class EyeScanVisual extends StatelessWidget {
  final double progress;
  final bool faceDetected;

  const EyeScanVisual({
    super.key,
    required this.progress,
    required this.faceDetected,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _EyeScanPainter(
        progress: progress,
        faceDetected: faceDetected,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _EyeScanPainter extends CustomPainter {
  final double progress;
  final bool faceDetected;

  _EyeScanPainter({required this.progress, required this.faceDetected});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final color = faceDetected ? const Color(0xFF5BA3D0) : const Color(0x66FFFFFF);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 1; i <= 4; i++) {
      ring.color = color.withValues(alpha: 0.12 + i * 0.08);
      canvas.drawCircle(c, 36.0 + i * 28, ring);
    }

    final eyePaint = Paint()..color = color;
    final eyeY = c.dy - 8;
    final spread = 36 + progress * 18;
    canvas.drawCircle(Offset(c.dx - spread, eyeY), 7, eyePaint);
    canvas.drawCircle(Offset(c.dx + spread, eyeY), 7, eyePaint);

    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(c.dx - spread + 10, eyeY),
      Offset(c.dx + spread - 10, eyeY),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _EyeScanPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.faceDetected != faceDetected;
}
