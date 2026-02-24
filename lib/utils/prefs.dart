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

  // Scheduled protection settings
  static Future<void> setScheduledEnabled(bool value) async {
    await _prefs?.setBool('scheduled_enabled', value);
  }

  static bool getScheduledEnabled() {
    return _prefs?.getBool('scheduled_enabled') ?? false;
  }

  static Future<void> setScheduleStartHour(int hour) async {
    await _prefs?.setInt('schedule_start_hour', hour);
  }

  static int getScheduleStartHour() {
    return _prefs?.getInt('schedule_start_hour') ?? 9; // Default 9 AM
  }

  static Future<void> setScheduleEndHour(int hour) async {
    await _prefs?.setInt('schedule_end_hour', hour);
  }

  static int getScheduleEndHour() {
    return _prefs?.getInt('schedule_end_hour') ?? 21; // Default 9 PM
  }

  /// Check if current time is within scheduled protection hours
  static bool isWithinSchedule() {
    if (!getScheduledEnabled()) return false;
    
    final now = DateTime.now();
    final currentHour = now.hour;
    final startHour = getScheduleStartHour();
    final endHour = getScheduleEndHour();
    
    if (startHour <= endHour) {
      // Normal range (e.g., 9 AM - 9 PM)
      return currentHour >= startHour && currentHour < endHour;
    } else {
      // Overnight range (e.g., 10 PM - 6 AM)
      return currentHour >= startHour || currentHour < endHour;
    }
  }

  // Feedback settings
  static Future<void> setHapticsEnabled(bool value) async {
    await _prefs?.setBool('haptics_enabled', value);
  }

  static bool getHapticsEnabled() {
    return _prefs?.getBool('haptics_enabled') ?? true; // Enabled by default
  }

  static Future<void> setSoundEnabled(bool value) async {
    await _prefs?.setBool('sound_enabled', value);
  }

  static bool getSoundEnabled() {
    return _prefs?.getBool('sound_enabled') ?? false; // Disabled by default
  }

  // Break reminder settings
  static Future<void> setBreakReminderEnabled(bool value) async {
    await _prefs?.setBool('break_reminder_enabled', value);
  }

  static bool getBreakReminderEnabled() {
    return _prefs?.getBool('break_reminder_enabled') ?? false;
  }

  static Future<void> setBreakReminderInterval(int minutes) async {
    await _prefs?.setInt('break_reminder_interval', minutes);
  }

  static int getBreakReminderInterval() {
    return _prefs?.getInt('break_reminder_interval') ?? 20; // Default 20 minutes
  }
}
