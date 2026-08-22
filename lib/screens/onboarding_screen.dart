import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../services/protection_service.dart';
import '../utils/prefs.dart';
import '../widgets/app_ui.dart';
import 'calibration_screen.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  bool _cameraGranted = false;
  bool _overlayGranted = false;
  bool _notificationsGranted = true;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissions();
  }

  Future<void> _boot() async {
    if (PrefsHelper.getIsCalibrated()) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }
    await _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _checking = true);
    _cameraGranted = await Permission.camera.isGranted;
    if (Platform.isAndroid) {
      _overlayGranted = await ProtectionService.checkOverlayPermission();
      _notificationsGranted = await Permission.notification.isGranted;
    } else {
      _overlayGranted = true;
      _notificationsGranted = true;
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    setState(() => _cameraGranted = status.isGranted);
  }

  Future<void> _requestOverlay() async {
    try {
      await ProtectionService.requestOverlayPermission();
      await Future.delayed(const Duration(milliseconds: 800));
      _overlayGranted = await ProtectionService.checkOverlayPermission();
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) print('Overlay permission: $e');
    }
  }

  Future<void> _requestNotifications() async {
    final status = await Permission.notification.request();
    setState(() => _notificationsGranted = status.isGranted);
  }

  Future<void> _requestBattery() async {
    if (!Platform.isAndroid) return;
    await ProtectionService.requestIgnoreBatteryOptimizations();
  }

  bool get _canContinue =>
      _cameraGranted && (!Platform.isAndroid || _overlayGranted);

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: BrandRings(
                      size: 128,
                      child: Icon(Icons.visibility_outlined, size: 42, color: scheme.primary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'KeepMe Away',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your personal screen space',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'The front camera watches how far your eyes are from the screen. If you drift in too close, you get a warning — then the screen dims until you sit back. Everything stays on this device.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                  ),
                  const SizedBox(height: 28),
                  const SectionLabel('Permissions'),
                  _PermissionRow(
                    icon: Icons.photo_camera_outlined,
                    title: 'Camera',
                    subtitle: 'Measure the distance between your eyes',
                    granted: _cameraGranted,
                    onGrant: _requestCamera,
                  ),
                  const SizedBox(height: 10),
                  if (Platform.isAndroid)
                    _PermissionRow(
                      icon: Icons.layers_outlined,
                      title: 'Display over other apps',
                      subtitle: 'Show a block screen when you sit too close',
                      granted: _overlayGranted,
                      onGrant: _requestOverlay,
                    ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 10),
                    _PermissionRow(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Keep protection running in the background',
                      granted: _notificationsGranted,
                      onGrant: _requestNotifications,
                      optional: true,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  if (Platform.isAndroid) ...[
                    SecondaryButton(
                      label: 'Allow background running',
                      icon: Icons.battery_saver_outlined,
                      onPressed: _requestBattery,
                    ),
                    const SizedBox(height: 12),
                  ],
                  PrimaryButton(
                    label: 'Continue to calibration',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _canContinue
                        ? () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const CalibrationScreen(),
                              ),
                            )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onGrant;
  final bool optional;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onGrant,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
                    ),
                    if (optional) ...[
                      const SizedBox(width: 6),
                      Text(
                        'optional',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.45),
                            ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          granted
              ? Icon(Icons.check_circle_rounded, color: Colors.teal.shade400)
              : FilledButton(
                  onPressed: onGrant,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Grant'),
                ),
        ],
      ),
    );
  }
}
