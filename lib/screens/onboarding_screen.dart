import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../utils/prefs.dart';
import 'calibration_screen.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  bool _cameraPermissionGranted = false;
  bool _overlayPermissionGranted = false;
  bool _isCheckingPermissions = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions when user returns from settings
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkInitialState() async {
    // Use addPostFrameCallback to avoid navigation during build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Check if already calibrated and navigate accordingly
      if (PrefsHelper.getIsCalibrated()) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
          return;
        }
      }
      
      await _checkPermissions();
    });
  }

  Future<void> _checkPermissions() async {
    setState(() => _isCheckingPermissions = true);

    // Check camera permission
    final cameraStatus = await Permission.camera.status;
    _cameraPermissionGranted = cameraStatus.isGranted;

    // Check overlay permission (Android only)
    if (Platform.isAndroid) {
      _overlayPermissionGranted = await _checkOverlayPermission();
    } else {
      _overlayPermissionGranted = true; // iOS doesn't need overlay permission for this demo
    }

    setState(() => _isCheckingPermissions = false);
  }

  Future<bool> _checkOverlayPermission() async {
    try {
      const platform = MethodChannel('protection_service');
      final result = await platform.invokeMethod('checkOverlayPermission');
      return result == true;
    } catch (e) {
      print('Error checking overlay permission: $e');
      return false;
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _cameraPermissionGranted = status.isGranted;
    });
  }

  Future<void> _requestOverlayPermission() async {
    try {
      const platform = MethodChannel('protection_service');
      await platform.invokeMethod('requestOverlayPermission');
      // Check again after user returns from settings
      await Future.delayed(const Duration(seconds: 1));
      _overlayPermissionGranted = await _checkOverlayPermission();
      setState(() {});
    } catch (e) {
      print('Error requesting overlay permission: $e');
    }
  }

  Future<void> _requestBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    
    try {
      const platform = MethodChannel('protection_service');
      await platform.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      print('Error requesting battery optimization: $e');
    }
  }

  void _navigateToCalibration() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const CalibrationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermissions) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screen Protector Setup'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome to Screen Protector',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'This app helps protect your eyes by monitoring your distance from the screen using the front camera. All detection is done on-device - no images are saved or transmitted.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            const Text(
              'Required Permissions:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Camera Permission
            _buildPermissionTile(
              title: 'Camera Access',
              description: 'Required to detect your face proximity',
              isGranted: _cameraPermissionGranted,
              onRequest: _requestCameraPermission,
            ),
            
            // Overlay Permission (Android only)
            if (Platform.isAndroid)
              _buildPermissionTile(
                title: 'Display over other apps',
                description: 'Required to show protection overlay',
                isGranted: _overlayPermissionGranted,
                onRequest: _requestOverlayPermission,
              ),
            
            const SizedBox(height: 32),
            
            // Battery Optimization (Optional)
            if (Platform.isAndroid) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.battery_saver),
                  title: const Text('Battery Optimization'),
                  subtitle: const Text('Recommended: Disable for reliable background monitoring'),
                  trailing: ElevatedButton(
                    onPressed: _requestBatteryOptimization,
                    child: const Text('Configure'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            const Spacer(),
            
            // Continue Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canContinue() ? _navigateToCalibration : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Continue to Calibration',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(
          isGranted ? Icons.check_circle : Icons.warning,
          color: isGranted ? Colors.green : Colors.orange,
        ),
        title: Text(title),
        subtitle: Text(description),
        trailing: isGranted
            ? const Icon(Icons.done, color: Colors.green)
            : ElevatedButton(
                onPressed: onRequest,
                child: const Text('Grant'),
              ),
      ),
    );
  }

  bool _canContinue() {
    if (Platform.isAndroid) {
      return _cameraPermissionGranted && _overlayPermissionGranted;
    } else {
      return _cameraPermissionGranted;
    }
  }
}
