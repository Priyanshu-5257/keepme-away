import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static const brand = Color(0xFF2F7AB5);
  static const brandSoft = Color(0xFF5BA3D0);
  static const navy = Color(0xFF16324F);
  static const ring = Color(0xFF8EC8E6);
  static const lightBg = Color(0xFFF3F7FB);
  static const darkBg = Color(0xFF0B1220);
  static const darkSurface = Color(0xFF151D2E);
}

class AppTheme {
  static const String _keyThemeMode = 'theme_mode';

  static ButtonStyle get _filledButton => FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );

  static ButtonStyle get _tonalButton => FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color seed,
    required Color scaffold,
    required Color surface,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: surface,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(style: _filledButton),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _filledButton),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _tonalButton.copyWith(
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.primary.withValues(alpha: 0.28)),
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData lightTheme = _build(
    brightness: Brightness.light,
    seed: AppColors.brand,
    scaffold: AppColors.lightBg,
    surface: Colors.white,
  );

  static ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    seed: AppColors.brandSoft,
    scaffold: AppColors.darkBg,
    surface: AppColors.darkSurface,
  );

  static Future<ThemeMode> getSavedThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_keyThemeMode) ?? 'system') {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await prefs.setString(_keyThemeMode, value);
  }
}
