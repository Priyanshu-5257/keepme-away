import 'package:flutter/material.dart';
import 'screens/onboarding_screen.dart';
import 'utils/prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize preferences
  await PrefsHelper.init();
  
  runApp(const ScreenProtectorApp());
}

class ScreenProtectorApp extends StatelessWidget {
  const ScreenProtectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeepMe Away',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const OnboardingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

