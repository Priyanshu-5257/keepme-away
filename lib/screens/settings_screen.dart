import 'package:flutter/material.dart';
import '../utils/prefs.dart';
import '../main.dart';

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
  
  // Schedule settings
  late bool _scheduledEnabled;
  late int _scheduleStartHour;
  late int _scheduleEndHour;
  
  // Feedback settings
  late bool _hapticsEnabled;
  late bool _soundEnabled;
  late bool _breakReminderEnabled;
  late int _breakReminderInterval;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _thresholdFactor = PrefsHelper.getThresholdFactor();
    _hysteresisGap = PrefsHelper.getHysteresisGap();
    _warningTime = PrefsHelper.getWarningTime();
    _detectionThreshold = PrefsHelper.getDetectionThreshold();
    _scheduledEnabled = PrefsHelper.getScheduledEnabled();
    _scheduleStartHour = PrefsHelper.getScheduleStartHour();
    _scheduleEndHour = PrefsHelper.getScheduleEndHour();
    _hapticsEnabled = PrefsHelper.getHapticsEnabled();
    _soundEnabled = PrefsHelper.getSoundEnabled();
    _breakReminderEnabled = PrefsHelper.getBreakReminderEnabled();
    _breakReminderInterval = PrefsHelper.getBreakReminderInterval();
  }

  Future<void> _saveSettings() async {
    await PrefsHelper.setThresholdFactor(_thresholdFactor);
    await PrefsHelper.setHysteresisGap(_hysteresisGap);
    await PrefsHelper.setWarningTime(_warningTime);
    await PrefsHelper.setDetectionThreshold(_detectionThreshold);
    await PrefsHelper.setScheduledEnabled(_scheduledEnabled);
    await PrefsHelper.setScheduleStartHour(_scheduleStartHour);
    await PrefsHelper.setScheduleEndHour(_scheduleEndHour);
    await PrefsHelper.setHapticsEnabled(_hapticsEnabled);
    await PrefsHelper.setSoundEnabled(_soundEnabled);
    await PrefsHelper.setBreakReminderEnabled(_breakReminderEnabled);
    await PrefsHelper.setBreakReminderInterval(_breakReminderInterval);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  void _resetToDefaults() {
    setState(() {
      _thresholdFactor = 1.6;
      _hysteresisGap = 0.15;
      _warningTime = 3;
      _detectionThreshold = 0.5;
      _scheduledEnabled = false;
      _scheduleStartHour = 9;
      _scheduleEndHour = 21;
    });
  }

  String _formatHour(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour < 12 ? 'AM' : 'PM';
    return '$h:00 $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Appearance Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      ScreenProtectorApp.getThemeMode(context) == ThemeMode.dark
                          ? Icons.dark_mode
                          : ScreenProtectorApp.getThemeMode(context) == ThemeMode.light
                              ? Icons.light_mode
                              : Icons.brightness_auto,
                    ),
                    title: const Text('Theme'),
                    subtitle: const Text('Choose your preferred appearance'),
                    trailing: DropdownButton<ThemeMode>(
                      value: ScreenProtectorApp.getThemeMode(context),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                        DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                        DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          ScreenProtectorApp.setThemeMode(context, mode);
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detection Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  // Threshold Factor
                  Text(
                    'Threshold Factor: ${_thresholdFactor.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Higher values = need to be closer to trigger (less sensitive)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: _thresholdFactor,
                    min: 1.2,
                    max: 2.5,
                    divisions: 26,
                    onChanged: (value) {
                      setState(() => _thresholdFactor = value);
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Hysteresis Gap
                  Text(
                    'Hysteresis Gap: ${_hysteresisGap.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Prevents flickering between warning states',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: _hysteresisGap,
                    min: 0.05,
                    max: 0.3,
                    divisions: 25,
                    onChanged: (value) {
                      setState(() => _hysteresisGap = value);
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Detection Threshold
                  Text(
                    'Detection Threshold: ${_detectionThreshold.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Minimum confidence for face detection',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: _detectionThreshold,
                    min: 0.3,
                    max: 0.8,
                    divisions: 25,
                    onChanged: (value) {
                      setState(() => _detectionThreshold = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Timing Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  // Warning Time
                  Text(
                    'Warning Time: $_warningTime seconds',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'How long to show warning before blocking screen',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: _warningTime.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (value) {
                      setState(() => _warningTime = value.round());
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Calibration',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('Baseline Area: ${PrefsHelper.getBaselineArea().toStringAsFixed(4)}'),
                  Text('Calibrated: ${PrefsHelper.getIsCalibrated() ? 'Yes' : 'No'}'),
                  const SizedBox(height: 12),
                  const Text(
                    'Current thresholds (calculated):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('Enter threshold: ${(PrefsHelper.getBaselineArea() * _thresholdFactor).toStringAsFixed(4)}'),
                  Text('Exit threshold: ${(PrefsHelper.getBaselineArea() * (_thresholdFactor - _hysteresisGap).clamp(0.8, double.infinity)).toStringAsFixed(4)}'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Scheduled Protection Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.schedule, color: Colors.purple),
                      const SizedBox(width: 8),
                      Text(
                        'Scheduled Protection',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Automatically enable protection during set hours',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  
                  SwitchListTile(
                    title: const Text('Enable Schedule'),
                    subtitle: Text(
                      _scheduledEnabled 
                          ? 'Protection auto-starts ${_formatHour(_scheduleStartHour)} - ${_formatHour(_scheduleEndHour)}'
                          : 'Manual control only',
                    ),
                    value: _scheduledEnabled,
                    onChanged: (value) {
                      setState(() => _scheduledEnabled = value);
                    },
                  ),
                  
                  if (_scheduledEnabled) ...[
                    const SizedBox(height: 8),
                    
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Start Time', style: TextStyle(fontWeight: FontWeight.bold)),
                              DropdownButton<int>(
                                value: _scheduleStartHour,
                                isExpanded: true,
                                items: List.generate(24, (i) => DropdownMenuItem(
                                  value: i,
                                  child: Text(_formatHour(i)),
                                )),
                                onChanged: (v) => setState(() => _scheduleStartHour = v!),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('End Time', style: TextStyle(fontWeight: FontWeight.bold)),
                              DropdownButton<int>(
                                value: _scheduleEndHour,
                                isExpanded: true,
                                items: List.generate(24, (i) => DropdownMenuItem(
                                  value: i,
                                  child: Text(_formatHour(i)),
                                )),
                                onChanged: (v) => setState(() => _scheduleEndHour = v!),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Feedback & Alerts Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Feedback & Alerts',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  SwitchListTile(
                    title: const Text('Haptic Feedback'),
                    subtitle: const Text('Vibrate on warnings'),
                    secondary: const Icon(Icons.vibration),
                    value: _hapticsEnabled,
                    onChanged: (value) {
                      setState(() => _hapticsEnabled = value);
                    },
                  ),
                  
                  SwitchListTile(
                    title: const Text('Sound Alerts'),
                    subtitle: const Text('Play sound on warnings'),
                    secondary: const Icon(Icons.volume_up),
                    value: _soundEnabled,
                    onChanged: (value) {
                      setState(() => _soundEnabled = value);
                    },
                  ),
                  
                  const Divider(),
                  
                  SwitchListTile(
                    title: const Text('Break Reminders'),
                    subtitle: Text(
                      _breakReminderEnabled
                          ? 'Remind every $_breakReminderInterval minutes'
                          : 'Disabled',
                    ),
                    secondary: const Icon(Icons.timer),
                    value: _breakReminderEnabled,
                    onChanged: (value) {
                      setState(() => _breakReminderEnabled = value);
                    },
                  ),
                  
                  if (_breakReminderEnabled) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reminder interval: $_breakReminderInterval minutes'),
                          Slider(
                            value: _breakReminderInterval.toDouble(),
                            min: 10,
                            max: 60,
                            divisions: 10,
                            label: '$_breakReminderInterval min',
                            onChanged: (value) {
                              setState(() => _breakReminderInterval = value.toInt());
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetToDefaults,
                  child: const Text('Reset to Defaults'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  child: const Text('Save Settings'),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // About Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'About',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.apps),
                    title: Text('KeepMe Away'),
                    subtitle: Text('Version 1.0.0'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.gavel),
                    title: Text('License'),
                    subtitle: Text('MIT License'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.code),
                    title: Text('Source Code'),
                    subtitle: Text('github.com/Priyanshu-5257/keepme-away'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.psychology),
                    title: Text('Face Detection'),
                    subtitle: Text('MediaPipe BlazeFace (Apache 2.0)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings Help:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  '• Threshold Factor: Higher = less sensitive (need to be very close)\n'
                  '• Hysteresis Gap: Prevents rapid on/off switching\n'
                  '• Warning Time: Grace period before screen blocks\n'
                  '• Detection Threshold: Face detection confidence level',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
