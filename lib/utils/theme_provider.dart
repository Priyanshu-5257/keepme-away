import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App theme definitions and provider
class AppTheme {
  static const String _keyThemeMode = 'theme_mode';
  
  // Light Theme
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
  
  // Dark Theme - optimized for eye protection app
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF121212),
      primary: Colors.blue.shade300,
    ),
    scaffoldBackgroundColor: const Color(0xFF0D0D0D),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1A1A1A),
      foregroundColor: Colors.grey.shade200,
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      color: Color(0xFF1E1E1E),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
  
  /// Get saved theme mode
  static Future<ThemeMode> getSavedThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyThemeMode) ?? 'system';
    switch (mode) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }
  
  /// Save theme mode preference
  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String value;
    switch (mode) {
      case ThemeMode.light: value = 'light'; break;
      case ThemeMode.dark: value = 'dark'; break;
      default: value = 'system';
    }
    await prefs.setString(_keyThemeMode, value);
  }
}

/// Theme notifier for state management
class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  
  ThemeNotifier() {
    _loadTheme();
  }
  
  Future<void> _loadTheme() async {
    _themeMode = await AppTheme.getSavedThemeMode();
    notifyListeners();
  }
  
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await AppTheme.saveThemeMode(mode);
    notifyListeners();
  }
  
  bool get isDark => _themeMode == ThemeMode.dark;
}
