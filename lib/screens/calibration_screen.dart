import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import '../services/protection_service.dart';
import '../utils/prefs.dart';
import '../utils/theme_provider.dart';
import '../widgets/app_ui.dart';
import '../widgets/face_overlay.dart';
import 'home_screen.dart';

enum _CalPhase { preview, countdown, sampling, success, failed }

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const _channel =
      MethodChannel('io.github.priyanshu5257.keepmeaway/face_detection');
  static const _targetSamples = 15;

  CameraController? _controller;
  bool _cameraReady = false;
  _CalPhase _phase = _CalPhase.preview;
  String _status = 'Sit at a comfortable distance and align your face.';
  final List<double> _samples = [];
  int _countdown = 3;
  Timer? _timer;
  bool _faceDetected = false;

  @override
  void initState() {
    super.initState();
    ProtectionService.stop();
    _openPreview();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    _stopNative();
    super.dispose();
  }

  Future<void> _openPreview() async {
    try {
      final cameras = await availableCameras();
      CameraDescription? front;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          front = camera;
          break;
        }
      }
      front ??= cameras.isEmpty ? null : cameras.first;
      if (front == null) {
        if (!mounted) return;
        setState(() {
          _status = 'No camera available.';
          _phase = _CalPhase.failed;
        });
        return;
      }
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not open camera.';
        _phase = _CalPhase.failed;
      });
      if (kDebugMode) print('Camera init: $e');
    }
  }

  Future<void> _releasePreview() async {
    final controller = _controller;
    _controller = null;
    _cameraReady = false;
    try {
      await controller?.dispose();
    } catch (_) {}
  }

  Future<void> _stopNative() async {
    try {
      await _channel.invokeMethod('stopCalibrationMode');
    } catch (_) {}
  }

  void _begin() {
    if (!_cameraReady || _phase != _CalPhase.preview) return;
    setState(() {
      _phase = _CalPhase.countdown;
      _countdown = 3;
      _status = 'Hold still…';
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        _startSampling();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _startSampling() async {
    setState(() {
      _phase = _CalPhase.sampling;
      _samples.clear();
      _status = 'Look at the camera. Keep your usual viewing distance.';
    });
    await _releasePreview();
    await Future.delayed(const Duration(milliseconds: 350));
    try {
      await _channel.invokeMethod('startCalibrationMode');
    } catch (e) {
      setState(() {
        _phase = _CalPhase.failed;
        _status = 'Could not start face detection. Try again.';
      });
      return;
    }

    _timer?.cancel();
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    _timer = Timer.periodic(const Duration(milliseconds: 180), (t) async {
      if (!mounted || _phase != _CalPhase.sampling) {
        t.cancel();
        return;
      }
      if (_samples.length >= _targetSamples || DateTime.now().isAfter(deadline)) {
        t.cancel();
        await _finishSampling();
        return;
      }
      await _pullSample();
    });
  }

  Future<void> _pullSample() async {
    try {
      final result = await _channel.invokeMethod('getCalibrationSample');
      if (result is! Map) return;
      final detected = result['faceDetected'] == true;
      final iod = (result['iod'] as num?)?.toDouble() ?? 0;
      if (!mounted) return;
      setState(() => _faceDetected = detected);
      if (detected && iod > 0.02 && iod < 0.55) {
        _samples.add(iod);
      }
    } catch (e) {
      if (kDebugMode) print('Sample: $e');
    }
  }

  Future<void> _finishSampling() async {
    await _stopNative();
    if (_samples.length < 5) {
      setState(() {
        _phase = _CalPhase.failed;
        _status = 'We couldn’t see both eyes clearly. Sit facing the camera and try again.';
      });
      return;
    }

    final baseline = median(_samples);
    if (baseline < 0.03 || baseline > 0.45) {
      setState(() {
        _phase = _CalPhase.failed;
        _status = 'That distance didn’t look right. Sit a little farther back and retry.';
      });
      return;
    }

    await PrefsHelper.setBaselineIod(baseline);
    await PrefsHelper.setIsCalibrated(true);

    if (!mounted) return;
    setState(() {
      _phase = _CalPhase.success;
      _status = 'Nice. This is your comfortable distance.';
    });
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _retry() async {
    _timer?.cancel();
    await _stopNative();
    setState(() {
      _phase = _CalPhase.preview;
      _samples.clear();
      _status = 'Sit at a comfortable distance and align your face.';
    });
    if (_controller == null) await _openPreview();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildStage(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () async {
                          _timer?.cancel();
                          await _stopNative();
                          if (!mounted) return;
                          if (PrefsHelper.getIsCalibrated()) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const HomeScreen()),
                            );
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                      const Spacer(),
                      Text(
                        'Calibration',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                            ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                const Spacer(),
                _bottomSheet(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage() {
    switch (_phase) {
      case _CalPhase.preview:
      case _CalPhase.countdown:
        if (_cameraReady &&
            _controller != null &&
            _controller!.value.isInitialized) {
          return Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize?.height ?? 1,
                  height: _controller!.value.previewSize?.width ?? 1,
                  child: CameraPreview(_controller!),
                ),
              ),
              const FaceGuideOverlay(),
              if (_phase == _CalPhase.countdown)
                Center(
                  child: Text(
                    '$_countdown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 88,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          );
        }
        return const Center(child: CircularProgressIndicator());
      case _CalPhase.sampling:
        return EyeScanVisual(
          progress: (_samples.length / _targetSamples).clamp(0, 1),
          faceDetected: _faceDetected,
        );
      case _CalPhase.success:
        return const Center(
          child: BrandRings(
            size: 220,
            child: Icon(Icons.check_rounded, color: Color(0xFF3DDC97), size: 64),
          ),
        );
      case _CalPhase.failed:
        return const Center(
          child: BrandRings(
            size: 200,
            color: Color(0xFFFF8A80),
            child: Icon(Icons.visibility_off_outlined, color: Colors.white70, size: 48),
          ),
        );
    }
  }

  Widget _bottomSheet(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      decoration: const BoxDecoration(
        color: Color(0xF2151D2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _status,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
          ),
          if (_phase == _CalPhase.sampling) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _samples.length / _targetSamples,
                minHeight: 8,
                backgroundColor: Colors.white12,
                color: AppColors.brandSoft,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _faceDetected
                  ? '${_samples.length}/$_targetSamples  ·  eyes found'
                  : 'Looking for both eyes…',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          if (_phase == _CalPhase.preview)
            PrimaryButton(
              label: 'Start calibration',
              icon: Icons.center_focus_strong,
              onPressed: _cameraReady ? _begin : null,
            ),
          if (_phase == _CalPhase.failed)
            PrimaryButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: _retry,
            ),
          if (_phase == _CalPhase.countdown || _phase == _CalPhase.sampling)
            SecondaryButton(
              label: 'Cancel',
              onPressed: _retry,
            ),
        ],
      ),
    );
  }
}
