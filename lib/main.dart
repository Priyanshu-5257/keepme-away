import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/onboarding_screen.dart';
import 'screens/calibration_screen.dart';
import 'utils/prefs.dart';
import 'utils/page_transitions.dart';
import 'utils/theme_provider.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PrefsHelper.init();
  final themeMode = await AppTheme.getSavedThemeMode();
  runApp(ScreenProtectorApp(initialThemeMode: themeMode));
}

class ScreenProtectorApp extends StatefulWidget {
  final ThemeMode initialThemeMode;

  const ScreenProtectorApp({super.key, required this.initialThemeMode});

  static void setThemeMode(BuildContext context, ThemeMode mode) {
    context.findAncestorStateOfType<_ScreenProtectorAppState>()?.setThemeMode(mode);
  }

  static ThemeMode getThemeMode(BuildContext context) {
    return context.findAncestorStateOfType<_ScreenProtectorAppState>()?._themeMode ??
        ThemeMode.system;
  }

  @override
  State<ScreenProtectorApp> createState() => _ScreenProtectorAppState();
}

class _ScreenProtectorAppState extends State<ScreenProtectorApp> {
  static const _channel = MethodChannel('protection_service');
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openCalibration') {
        navigatorKey.currentState?.push(
          PageTransitions.fadeScale(const CalibrationScreen()),
        );
      }
    });
  }

  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    AppTheme.saveThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeepMe Away',
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: const OnboardingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
