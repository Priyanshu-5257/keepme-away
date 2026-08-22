import 'package:flutter/material.dart';
import 'dart:io';
import '../main.dart';
import '../services/protection_service.dart';
import '../utils/prefs.dart';
import '../widgets/app_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _thresholdFactor;
  late double _hysteresisGap;
  late int _warningTime;
  late double _detectionThreshold;
  late bool _hapticsEnabled;

  @override
  void initState() {
    super.initState();
    _thresholdFactor = PrefsHelper.getThresholdFactor();
    _hysteresisGap = PrefsHelper.getHysteresisGap();
    _warningTime = PrefsHelper.getWarningTime();
    _detectionThreshold = PrefsHelper.getDetectionThreshold();
    _hapticsEnabled = PrefsHelper.getHapticsEnabled();
  }

  Future<void> _persist() async {
    await PrefsHelper.setThresholdFactor(_thresholdFactor);
    await PrefsHelper.setHysteresisGap(_hysteresisGap);
    await PrefsHelper.setWarningTime(_warningTime);
    await PrefsHelper.setDetectionThreshold(_detectionThreshold);
    await PrefsHelper.setHapticsEnabled(_hapticsEnabled);

    if (Platform.isAndroid && PrefsHelper.getIsProtectionActive()) {
      await ProtectionService.start(
        baselineIod: PrefsHelper.getBaselineIod(),
        thresholdFactor: _thresholdFactor,
        hysteresisGap: _hysteresisGap,
        warningTime: _warningTime,
        detectionThreshold: _detectionThreshold,
      );
    }
  }

  Future<void> _save() async {
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  void _reset() {
    setState(() {
      _thresholdFactor = 1.4;
      _hysteresisGap = 0.12;
      _warningTime = 3;
      _detectionThreshold = 0.5;
      _hapticsEnabled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final closer = PrefsHelper.percentCloser(_thresholdFactor);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Theme'),
                  trailing: DropdownButton<ThemeMode>(
                    value: ScreenProtectorApp.getThemeMode(context),
                    underline: const SizedBox(),
                    borderRadius: BorderRadius.circular(12),
                    items: const [
                      DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                    ],
                    onChanged: (mode) {
                      if (mode == null) return;
                      ScreenProtectorApp.setThemeMode(context, mode);
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.visibility_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Sensitivity', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Warn when you are about $closer% closer than your calibrated distance.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
                Slider(
                  value: _thresholdFactor,
                  min: 1.15,
                  max: 2.0,
                  divisions: 17,
                  label: '$closer% closer',
                  onChanged: (v) => setState(() => _thresholdFactor = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sooner', style: Theme.of(context).textTheme.labelSmall),
                    Text('Later', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Warning time', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$_warningTime second${_warningTime == 1 ? '' : 's'} before the screen is blocked.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
                Slider(
                  value: _warningTime.toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  label: '$_warningTime s',
                  onChanged: (v) => setState(() => _warningTime = v.round()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SwitchListTile(
              title: const Text('Haptic feedback'),
              subtitle: const Text('Vibrate when a warning starts'),
              secondary: Icon(Icons.vibration, color: scheme.primary),
              value: _hapticsEnabled,
              onChanged: (v) => setState(() => _hapticsEnabled = v),
            ),
          ),
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                leading: Icon(Icons.tune_rounded, color: scheme.primary),
                title: const Text('Advanced'),
                children: [
                  Text(
                    'Stability gap: ${_hysteresisGap.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Stops the warning from flickering at the boundary.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                  Slider(
                    value: _hysteresisGap,
                    min: 0.05,
                    max: 0.25,
                    divisions: 20,
                    onChanged: (v) => setState(() => _hysteresisGap = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Face confidence: ${_detectionThreshold.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Higher ignores weak detections (dark rooms, angles).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                  Slider(
                    value: _detectionThreshold,
                    min: 0.3,
                    max: 0.8,
                    divisions: 10,
                    onChanged: (v) => setState(() => _detectionThreshold = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(label: 'Reset defaults', onPressed: _reset),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(label: 'Save', onPressed: _save),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.apps_outlined),
                  title: Text('KeepMe Away'),
                  subtitle: Text('Version 1.0.0'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('Distance signal'),
                  subtitle: Text('Inter-eye distance · BlazeFace (Apache 2.0)'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.code_outlined),
                  title: Text('Source'),
                  subtitle: Text('github.com/Priyanshu-5257/keepme-away'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
