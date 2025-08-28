import 'package:shared_preferences/shared_preferences.dart';

class PrefsHelper {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Calibration settings
  static Future<void> setBaselineArea(double value) async {
    await _prefs?.setDouble('baseline_area', value);
  }

  static double getBaselineArea() {
    return _prefs?.getDouble('baseline_area') ?? 0.0;
  }

  static Future<void> setThresholdFactor(double value) async {
    await _prefs?.setDouble('threshold_factor', value);
  }

  static double getThresholdFactor() {
    return _prefs?.getDouble('threshold_factor') ?? 2.0;  // Improved default: trigger when face doubles in size
  }

  static Future<void> setHysteresisGap(double value) async {
    await _prefs?.setDouble('hysteresis_gap', value);
  }

  static double getHysteresisGap() {
    return _prefs?.getDouble('hysteresis_gap') ?? 0.3;  // Improved default: exit at 1.7x baseline
  }

  static Future<void> setWarningTime(int value) async {
    await _prefs?.setInt('warning_time', value);
  }

  static int getWarningTime() {
    return _prefs?.getInt('warning_time') ?? 3;
  }

  static Future<void> setDetectionThreshold(double value) async {
    await _prefs?.setDouble('detection_threshold', value);
  }

  static double getDetectionThreshold() {
    return _prefs?.getDouble('detection_threshold') ?? 0.5;
  }

  // App state
  static Future<void> setIsCalibrated(bool value) async {
    await _prefs?.setBool('is_calibrated', value);
  }

  static bool getIsCalibrated() {
    return _prefs?.getBool('is_calibrated') ?? false;
  }

  static Future<void> setIsProtectionActive(bool value) async {
    await _prefs?.setBool('is_protection_active', value);
  }

  static bool getIsProtectionActive() {
    return _prefs?.getBool('is_protection_active') ?? false;
  }

  // Clear all calibration data
  static Future<void> clearCalibration() async {
    await _prefs?.remove('baseline_area');
    await _prefs?.setBool('is_calibrated', false);
    await _prefs?.setBool('is_protection_active', false);
  }
}
