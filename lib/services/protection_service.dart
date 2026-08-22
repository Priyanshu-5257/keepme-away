import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ProtectionService {
  static const MethodChannel _channel = MethodChannel('protection_service');

  static Future<bool> start({
    required double baselineIod,
    required double thresholdFactor,
    required double hysteresisGap,
    required int warningTime,
    required double detectionThreshold,
  }) async {
    try {
      final result = await _channel.invokeMethod('start', {
        'baselineIod': baselineIod,
        'thresholdFactor': thresholdFactor,
        'hysteresisGap': hysteresisGap,
        'warningTime': warningTime,
        'detectionThreshold': detectionThreshold,
      });
      return result == true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Failed to start protection service: ${e.message}');
      }
      return false;
    }
  }

  static Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod('stop');
      return result == true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Failed to stop protection service: ${e.message}');
      }
      return false;
    }
  }

  static Future<bool> isRunning() async {
    try {
      final result = await _channel.invokeMethod('status');
      return result == true;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Failed to get protection service status: ${e.message}');
      }
      return false;
    }
  }

  static Future<bool> checkOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod('checkOverlayPermission');
      return result == true;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    await _channel.invokeMethod('requestOverlayPermission');
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }
}
