import 'package:flutter/material.dart';
import 'screens/onboarding_screen.dart';
import 'utils/prefs.dart';
import 'utils/theme_provider.dart';
import 'services/face_detector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize preferences
  await PrefsHelper.init();
  
  // Pre-warm ML Kit face detector to reduce cold-start latency
  final faceDetector = FaceDetectorService();
  faceDetector.initialize();
  await faceDetector.warmUp();
  
  // Load saved theme
  final themeMode = await AppTheme.getSavedThemeMode();
  
  runApp(ScreenProtectorApp(initialThemeMode: themeMode));
}

class ScreenProtectorApp extends StatefulWidget {
  final ThemeMode initialThemeMode;
  
  const ScreenProtectorApp({super.key, required this.initialThemeMode});
  
  // Global key for theme changes
  static final GlobalKey<_ScreenProtectorAppState> appKey = GlobalKey();
  
  static void setThemeMode(BuildContext context, ThemeMode mode) {
    final state = context.findAncestorStateOfType<_ScreenProtectorAppState>();
    state?.setThemeMode(mode);
  }
  
  static ThemeMode getThemeMode(BuildContext context) {
    final state = context.findAncestorStateOfType<_ScreenProtectorAppState>();
    return state?._themeMode ?? ThemeMode.system;
  }

  @override
  State<ScreenProtectorApp> createState() => _ScreenProtectorAppState();
}

class _ScreenProtectorAppState extends State<ScreenProtectorApp> {
  late ThemeMode _themeMode;
  
  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
  }
  
  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    AppTheme.saveThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeepMe Away',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: const OnboardingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
