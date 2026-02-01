import 'package:flutter/material.dart';
import 'screens/onboarding_screen.dart';
import 'utils/prefs.dart';
import 'services/face_detector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize preferences
  await PrefsHelper.init();
  
  // Pre-warm ML Kit face detector to reduce cold-start latency
  final faceDetector = FaceDetectorService();
  faceDetector.initialize();
  await faceDetector.warmUp();
  
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
