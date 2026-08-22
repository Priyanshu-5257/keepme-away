import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../services/protection_service.dart';
import '../utils/prefs.dart';
import '../utils/page_transitions.dart';
import '../utils/theme_provider.dart';
import '../widgets/app_ui.dart';
import 'calibration_screen.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _active = false;
  bool _loading = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (!Platform.isAndroid) return;
    final running = await ProtectionService.isRunning();
    if (!mounted) return;
    setState(() => _active = running);
    PrefsHelper.setIsProtectionActive(running);
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (!PrefsHelper.getIsCalibrated()) {
      _goCalibrate();
      return;
    }
    setState(() => _loading = true);
    try {
      if (_active) {
        final ok = await ProtectionService.stop();
        if (ok) {
          await PrefsHelper.setIsProtectionActive(false);
          setState(() => _active = false);
          _toast('Protection paused');
        } else {
          _toast('Couldn’t stop protection');
        }
      } else {
        final ok = await ProtectionService.start(
          baselineIod: PrefsHelper.getBaselineIod(),
          thresholdFactor: PrefsHelper.getThresholdFactor(),
          hysteresisGap: PrefsHelper.getHysteresisGap(),
          warningTime: PrefsHelper.getWarningTime(),
          detectionThreshold: PrefsHelper.getDetectionThreshold(),
        );
        if (ok) {
          await PrefsHelper.setIsProtectionActive(true);
          setState(() => _active = true);
          _toast('Protection is on — you can leave the app');
        } else {
          _toast('Couldn’t start protection');
        }
      }
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _goCalibrate() {
    Navigator.of(context).push(
      PageTransitions.fadeScale(const CalibrationScreen()),
    );
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset calibration?'),
        content: const Text(
          'This clears your comfortable distance and stops protection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ProtectionService.stop();
    await PrefsHelper.clearCalibration();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CalibrationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final closer = PrefsHelper.percentCloser(PrefsHelper.getThresholdFactor());
    final calibrated = PrefsHelper.getIsCalibrated();

    return Scaffold(
      appBar: AppBar(
        title: const Text('KeepMe Away'),
        actions: [
          IconButton(
            tooltip: 'Statistics',
            onPressed: () => Navigator.of(context).push(
              PageTransitions.fadeScale(const StatisticsScreen()),
            ),
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              PageTransitions.slideFromRight(const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          AppCard(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Column(
              children: [
                BrandRings(
                  size: 148,
                  color: _active ? const Color(0xFF3DDC97) : AppColors.ring,
                  child: Icon(
                    _active ? Icons.shield_rounded : Icons.shield_outlined,
                    size: 48,
                    color: _active ? const Color(0xFF3DDC97) : scheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _active ? 'Protection on' : 'Protection off',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  _active
                      ? 'Watching your viewing distance in the background.'
                      : calibrated
                          ? 'Start when you sit down with a screen.'
                          : 'Calibrate once, then start protection.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.62),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: _active ? 'Stop protection' : 'Start protection',
            icon: _active ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: _active ? const Color(0xFFD64545) : null,
            loading: _loading,
            onPressed: _toggle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Recalibrate',
                  onPressed: _goCalibrate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  label: 'Reset',
                  onPressed: _reset,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How it works', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _HowRow(
                  icon: Icons.visibility_outlined,
                  text: 'Uses the distance between your eyes, not a face box.',
                ),
                _HowRow(
                  icon: Icons.tune_rounded,
                  text: calibrated
                      ? 'Warns when you sit about $closer% closer than calibrated.'
                      : 'Calibrate at the distance that feels easy on your eyes.',
                ),
                _HowRow(
                  icon: Icons.lock_outline,
                  text: 'Frames never leave this phone. Nothing is saved or uploaded.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HowRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
