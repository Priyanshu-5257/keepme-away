import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Service to track and persist protection statistics
class StatisticsService {
  static StatisticsService? _instance;
  static SharedPreferences? _prefs;
  
  StatisticsService._internal();
  
  static Future<StatisticsService> getInstance() async {
    _instance ??= StatisticsService._internal();
    _prefs ??= await SharedPreferences.getInstance();
    return _instance!;
  }
  
  // Statistics keys
  static const String _keyTodayWarnings = 'stats_today_warnings';
  static const String _keyTodayBlocks = 'stats_today_blocks';
  static const String _keyTodaySessionMinutes = 'stats_today_session_minutes';
  static const String _keyLastDate = 'stats_last_date';
  static const String _keyTotalWarnings = 'stats_total_warnings';
  static const String _keyTotalBlocks = 'stats_total_blocks';
  static const String _keyTotalSessionMinutes = 'stats_total_session_minutes';
  static const String _keyDailyHistory = 'stats_daily_history';
  
  /// Get today's date string for tracking
  String _getTodayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
  
  /// Reset daily stats if it's a new day
  Future<void> _checkAndResetDailyStats() async {
    final today = _getTodayString();
    final lastDate = _prefs?.getString(_keyLastDate) ?? '';
    
    if (lastDate != today) {
      // Save yesterday's stats to history before resetting
      if (lastDate.isNotEmpty) {
        await _saveDailyToHistory(lastDate);
      }
      
      // Reset daily counters
      await _prefs?.setInt(_keyTodayWarnings, 0);
      await _prefs?.setInt(_keyTodayBlocks, 0);
      await _prefs?.setInt(_keyTodaySessionMinutes, 0);
      await _prefs?.setString(_keyLastDate, today);
    }
  }
  
  Future<void> _saveDailyToHistory(String date) async {
    final historyJson = _prefs?.getString(_keyDailyHistory) ?? '[]';
    final history = List<Map<String, dynamic>>.from(jsonDecode(historyJson));
    
    history.add({
      'date': date,
      'warnings': _prefs?.getInt(_keyTodayWarnings) ?? 0,
      'blocks': _prefs?.getInt(_keyTodayBlocks) ?? 0,
      'sessionMinutes': _prefs?.getInt(_keyTodaySessionMinutes) ?? 0,
    });
    
    // Keep only last 30 days
    if (history.length > 30) {
      history.removeAt(0);
    }
    
    await _prefs?.setString(_keyDailyHistory, jsonEncode(history));
  }
  
  /// Increment warning count
  Future<void> recordWarning() async {
    await _checkAndResetDailyStats();
    
    final current = _prefs?.getInt(_keyTodayWarnings) ?? 0;
    await _prefs?.setInt(_keyTodayWarnings, current + 1);
    
    final total = _prefs?.getInt(_keyTotalWarnings) ?? 0;
    await _prefs?.setInt(_keyTotalWarnings, total + 1);
  }
  
  /// Increment block count
  Future<void> recordBlock() async {
    await _checkAndResetDailyStats();
    
    final current = _prefs?.getInt(_keyTodayBlocks) ?? 0;
    await _prefs?.setInt(_keyTodayBlocks, current + 1);
    
    final total = _prefs?.getInt(_keyTotalBlocks) ?? 0;
    await _prefs?.setInt(_keyTotalBlocks, total + 1);
  }
  
  /// Add session minutes
  Future<void> addSessionMinutes(int minutes) async {
    await _checkAndResetDailyStats();
    
    final current = _prefs?.getInt(_keyTodaySessionMinutes) ?? 0;
    await _prefs?.setInt(_keyTodaySessionMinutes, current + minutes);
    
    final total = _prefs?.getInt(_keyTotalSessionMinutes) ?? 0;
    await _prefs?.setInt(_keyTotalSessionMinutes, total + minutes);
  }
  
  /// Get today's statistics
  Future<DailyStats> getTodayStats() async {
    await _checkAndResetDailyStats();
    
    return DailyStats(
      date: _getTodayString(),
      warnings: _prefs?.getInt(_keyTodayWarnings) ?? 0,
      blocks: _prefs?.getInt(_keyTodayBlocks) ?? 0,
      sessionMinutes: _prefs?.getInt(_keyTodaySessionMinutes) ?? 0,
    );
  }
  
  /// Get total (all-time) statistics
  TotalStats getTotalStats() {
    return TotalStats(
      totalWarnings: _prefs?.getInt(_keyTotalWarnings) ?? 0,
      totalBlocks: _prefs?.getInt(_keyTotalBlocks) ?? 0,
      totalSessionMinutes: _prefs?.getInt(_keyTotalSessionMinutes) ?? 0,
    );
  }
  
  /// Get weekly history (last 7 days)
  Future<List<DailyStats>> getWeekHistory() async {
    await _checkAndResetDailyStats();
    
    final historyJson = _prefs?.getString(_keyDailyHistory) ?? '[]';
    final history = List<Map<String, dynamic>>.from(jsonDecode(historyJson));
    
    // Get last 7 days
    final last7 = history.length > 7 ? history.sublist(history.length - 7) : history;
    
    return last7.map((item) => DailyStats(
      date: item['date'] as String,
      warnings: item['warnings'] as int,
      blocks: item['blocks'] as int,
      sessionMinutes: item['sessionMinutes'] as int,
    )).toList();
  }
  
  /// Calculate "safe distance score" (0-100)
  /// Higher is better - fewer warnings per session time
  Future<int> getSafeDistanceScore() async {
    final today = await getTodayStats();
    
    if (today.sessionMinutes == 0) return 100;
    
    // Calculate warnings per hour
    final warningsPerHour = today.warnings / (today.sessionMinutes / 60.0);
    
    // Score: 100 = 0 warnings/hr, 0 = 10+ warnings/hr
    final score = (100 - (warningsPerHour * 10)).clamp(0, 100);
    
    return score.round();
  }
}

class DailyStats {
  final String date;
  final int warnings;
  final int blocks;
  final int sessionMinutes;
  
  DailyStats({
    required this.date,
    required this.warnings,
    required this.blocks,
    required this.sessionMinutes,
  });
}

class TotalStats {
  final int totalWarnings;
  final int totalBlocks;
  final int totalSessionMinutes;
  
  TotalStats({
    required this.totalWarnings,
    required this.totalBlocks,
    required this.totalSessionMinutes,
  });
  
  String get totalSessionTimeFormatted {
    final hours = totalSessionMinutes ~/ 60;
    final minutes = totalSessionMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}
