import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../services/protection_service.dart';
import '../utils/prefs.dart';
import '../utils/page_transitions.dart';
import 'calibration_screen.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isProtectionActive = false;
  bool _isLoading = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _checkProtectionStatus();
    _startStatusUpdates();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  void _startStatusUpdates() {
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkProtectionStatus();
    });
  }

  Future<void> _checkProtectionStatus() async {
    if (Platform.isAndroid) {
      final isRunning = await ProtectionService.isRunning();
      if (mounted) {
        setState(() {
          _isProtectionActive = isRunning;
        });
        
        // Update preferences
        PrefsHelper.setIsProtectionActive(isRunning);
      }
    }
  }

  Future<void> _toggleProtection() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_isProtectionActive) {
        // Stop protection
        final success = await ProtectionService.stop();
        if (success) {
          await PrefsHelper.setIsProtectionActive(false);
          setState(() => _isProtectionActive = false);
          _showSnackBar('Protection stopped');
        } else {
          _showSnackBar('Failed to stop protection');
        }
      } else {
        // Start protection
        final success = await ProtectionService.start(
          baselineArea: PrefsHelper.getBaselineArea(),
          thresholdFactor: PrefsHelper.getThresholdFactor(),
          hysteresisGap: PrefsHelper.getHysteresisGap(),
          warningTime: PrefsHelper.getWarningTime(),
          detectionThreshold: PrefsHelper.getDetectionThreshold(),
        );
        
        if (success) {
          await PrefsHelper.setIsProtectionActive(true);
          setState(() => _isProtectionActive = true);
          _showSnackBar('Protection started');
        } else {
          _showSnackBar('Failed to start protection');
        }
      }
    } catch (e) {
      _showSnackBar('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _navigateToCalibration() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const CalibrationScreen()),
    );
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      PageTransitions.slideFromRight(const SettingsScreen()),
    );
  }

  void _navigateToStatistics() {
    Navigator.of(context).push(
      PageTransitions.fadeScale(const StatisticsScreen()),
    );
  }

  Future<void> _resetCalibration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Calibration'),
        content: const Text('This will clear your current calibration and stop protection. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Stop protection first
      await ProtectionService.stop();
      
      // Clear calibration
      await PrefsHelper.clearCalibration();
      
      // Navigate to calibration
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const CalibrationScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseline = PrefsHelper.getBaselineArea();
    final isCalibrated = PrefsHelper.getIsCalibrated();

    return Scaffold(
      appBar: AppBar(
        title: const Text('KeepMe Away'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _navigateToStatistics,
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Statistics',
          ),
          IconButton(
            onPressed: _navigateToSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isProtectionActive ? Icons.shield : Icons.shield_outlined,
                          color: _isProtectionActive ? Colors.green : Colors.grey,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Protection Status',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              _isProtectionActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: _isProtectionActive ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    
                    if (_isProtectionActive) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '✓ Your screen is being protected. You can minimize the app.',
                          style: TextStyle(color: Colors.green),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Calibration Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calibration Info',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Calibrated: ${isCalibrated ? 'Yes' : 'No'}'),
                    if (isCalibrated) ...[
                      Text('Baseline Area: ${baseline.toStringAsFixed(4)}'),
                      Text('Threshold Factor: ${PrefsHelper.getThresholdFactor()}'),
                      Text('Warning Time: ${PrefsHelper.getWarningTime()}s'),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Main Control Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _toggleProtection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isProtectionActive ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        _isProtectionActive ? 'Stop Protection' : 'Start Protection',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Secondary Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _navigateToCalibration,
                    child: const Text('Recalibrate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resetCalibration,
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
            
            const Spacer(),
            
            // Help Text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How it works:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• The app monitors your face distance using the front camera\n'
                    '• When you get too close, you\'ll see a warning countdown\n'
                    '• If you stay too close, the screen will be blocked\n'
                    '• All processing is done on-device for privacy\n'
                    '• Powered by open-source models (no Google services)',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Note: The protection runs in the background. You can use the notification to stop or recalibrate.',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
