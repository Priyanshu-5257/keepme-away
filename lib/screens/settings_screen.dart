import 'package:flutter/material.dart';
import '../utils/prefs.dart';

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
  }

  Future<void> _saveSettings() async {
    await PrefsHelper.setThresholdFactor(_thresholdFactor);
    await PrefsHelper.setHysteresisGap(_hysteresisGap);
    await PrefsHelper.setWarningTime(_warningTime);
    await PrefsHelper.setDetectionThreshold(_detectionThreshold);
    
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
    });
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
