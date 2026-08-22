import 'package:shared_preferences/shared_preferences.dart';

class PrefsHelper {
  static SharedPreferences? _prefs;

  /// 0 = face-box area (legacy), 1 = inter-ocular distance.
  static const int iodMetricVersion = 1;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrateToIodIfNeeded();
  }

  /// Old installs were calibrated on bounding-box area. IOD is a different
  /// signal, so force a fresh calibration and IOD-scaled defaults.
  static Future<void> _migrateToIodIfNeeded() async {
    if (_prefs?.getBool('iod_migrated') == true) return;
    final version = _prefs?.getInt('detection_metric') ?? 0;
    if (version < iodMetricVersion) {
      await _prefs?.remove('baseline_area');
      await _prefs?.remove('baseline_iod');
      await _prefs?.setBool('is_calibrated', false);
      await _prefs?.setBool('is_protection_active', false);
      await setThresholdFactor(1.4);
      await setHysteresisGap(0.12);
    }
    await _prefs?.setBool('iod_migrated', true);
  }

  static Future<void> setBaselineIod(double value) async {
    await _prefs?.setDouble('baseline_iod', value);
    await _prefs?.setInt('detection_metric', iodMetricVersion);
  }

  static double getBaselineIod() {
    return _prefs?.getDouble('baseline_iod') ??
        _prefs?.getDouble('baseline_area') ??
        0.0;
  }

  static Future<void> setThresholdFactor(double value) async {
    await _prefs?.setDouble('threshold_factor', value);
  }

  static double getThresholdFactor() {
    return _prefs?.getDouble('threshold_factor') ?? 1.4;
  }

  static Future<void> setHysteresisGap(double value) async {
    await _prefs?.setDouble('hysteresis_gap', value);
  }

  static double getHysteresisGap() {
    return _prefs?.getDouble('hysteresis_gap') ?? 0.12;
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

  static Future<void> setIsCalibrated(bool value) async {
    await _prefs?.setBool('is_calibrated', value);
  }

  static bool getIsCalibrated() {
    if (!(_prefs?.getBool('is_calibrated') ?? false)) return false;
    return (_prefs?.getInt('detection_metric') ?? 0) >= iodMetricVersion;
  }

  static Future<void> setIsProtectionActive(bool value) async {
    await _prefs?.setBool('is_protection_active', value);
  }

  static bool getIsProtectionActive() {
    return _prefs?.getBool('is_protection_active') ?? false;
  }

  static Future<void> clearCalibration() async {
    await _prefs?.remove('baseline_iod');
    await _prefs?.remove('baseline_area');
    await _prefs?.remove('detection_metric');
    await _prefs?.setBool('is_calibrated', false);
    await _prefs?.setBool('is_protection_active', false);
  }

  static Future<void> setHapticsEnabled(bool value) async {
    await _prefs?.setBool('haptics_enabled', value);
  }

  static bool getHapticsEnabled() {
    return _prefs?.getBool('haptics_enabled') ?? true;
  }

  /// How much closer than calibrated distance this factor represents.
  /// distance ∝ 1/IOD, so factor 1.4 ≈ 29% closer.
  static int percentCloser(double factor) {
    if (factor <= 1) return 0;
    return ((1 - 1 / factor) * 100).round();
  }
}

double median(List<double> samples) {
  if (samples.isEmpty) return 0.0;
  final sorted = List<double>.from(samples)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2.0;
}
