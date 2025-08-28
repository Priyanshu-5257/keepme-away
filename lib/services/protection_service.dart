import 'package:flutter/services.dart';

class ProtectionService {
  static const MethodChannel _channel = MethodChannel('protection_service');

  static Future<bool> start({
    required double baselineArea,
    required double thresholdFactor,
    required double hysteresisGap,
    required int warningTime,
    required double detectionThreshold,
  }) async {
    try {
      final result = await _channel.invokeMethod('start', {
        'baselineArea': baselineArea,
        'thresholdFactor': thresholdFactor,
        'hysteresisGap': hysteresisGap,
        'warningTime': warningTime,
        'detectionThreshold': detectionThreshold,
      });
      return result == true;
    } on PlatformException catch (e) {
      print('Failed to start protection service: ${e.message}');
      return false;
    }
  }

  static Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod('stop');
      return result == true;
    } on PlatformException catch (e) {
      print('Failed to stop protection service: ${e.message}');
      return false;
    }
  }

  static Future<bool> isRunning() async {
    try {
      final result = await _channel.invokeMethod('status');
      return result == true;
    } on PlatformException catch (e) {
      print('Failed to get protection service status: ${e.message}');
      return false;
    }
  }

  static Future<bool> showOverlay() async {
    try {
      final result = await _channel.invokeMethod('showOverlay');
      return result == true;
    } on PlatformException catch (e) {
      print('Failed to show overlay: ${e.message}');
      return false;
    }
  }

  static Future<bool> hideOverlay() async {
    try {
      final result = await _channel.invokeMethod('hideOverlay');
      return result == true;
    } on PlatformException catch (e) {
      print('Failed to hide overlay: ${e.message}');
      return false;
    }
  }
}
