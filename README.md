<div align="center">

# Screen Protector App

Protect your eyes by keeping a healthy distance from the screen. This open‑source Flutter app uses on‑device ML to detect when you’re too close and gently nudges you back to safety.

</div>

## Highlights

- Real face proximity detection (on‑device, privacy‑first)
- One‑tap calibration for your comfortable viewing distance
- Android foreground service with screen‑dimming/block overlay when too close
- Configurable thresholds, warning time, and sensitivity
- Battery‑friendly and fast, with no network access required

## Demo (what to expect)

1) Grant camera and overlay permissions. 2) Calibrate once at a comfortable distance. 3) Start protection. 4) If you get too close, you’ll see a warning countdown, then a full‑screen overlay until you move back.

## Getting Started

### Prerequisites
- Flutter 3.32.x (stable) or newer
- Android SDK (API 24+)
- Java 17
- Kotlin 1.9+

### Setup
```bash
git clone <repo-url>
cd screen_protector_app
flutter pub get
# Optional: run tests
flutter test
```

### Run
```bash
# Debug run on a connected device or emulator
flutter run

# Build APK
flutter build apk --debug
```

## Permissions (Android)

The app requests and uses:

- Camera: for on‑device face size measurement (no images stored/transmitted)
- Overlay (SYSTEM_ALERT_WINDOW): to show a warning/black overlay when too close
- Ignore battery optimizations (optional): to keep the foreground service responsive

All processing happens on‑device using Google ML Kit. No data leaves your device.

## Features

- Face proximity detection using ML Kit (front camera)
- Dynamic thresholding based on your calibrated baseline
- Warning countdown before blocking
- Full‑screen overlay when too close, auto‑dismiss on recovery
- Settings to tune sensitivity, thresholds, and warning time
- Robust calibration with outlier‑resistant median

## Architecture (short)

- Flutter UI (Dart) for calibration, settings, and control screens
- Android service (Kotlin) does continuous detection in the background
- ML Kit Face Detection for bounding box area → normalized area
- Dynamic thresholds: trigger when area increases above baseline factor, with hysteresis

Key files:
- `lib/screens/`: UI (home, calibration, settings)
- `lib/services/face_detector.dart`: Flutter‑side detection (used for UI and fallback)
- `android/app/src/main/kotlin/.../ProtectionService.kt`: Foreground service with detection logic
- `android/app/src/main/kotlin/.../FaceDetectionManager.kt`: Camera+ML Kit pipeline
- `lib/utils/prefs.dart`: Persistent settings and thresholds

## Roadmap / Coming Soon

1. Showing service in notification bar
2. More smooth and fluid UI
3. Using eye detection instead of face for better accuracy

Contributions are welcome! See below.

## Contributing

Issues and PRs are appreciated. Suggested contributions:

- Bug fixes and performance improvements
- UI/UX refinements and animations
- Eye‑detection pipeline (ML Kit Eyes/Contours) and better calibration flows
- Accessibility and localization

Please open an issue to discuss significant changes before submitting a PR.

## Build Notes

- Keep Flutter and Android toolchains up to date
- If ML Kit camera format changes are encountered, prefer YUV_420/NV21 and ensure rotation is handled (front camera often requires 270°)
- Test on physical devices for accurate camera behavior

## Privacy

- 100% on‑device processing
- No photos or frames are stored or uploaded
- No network is required for core functionality

## License

This project is open source under the MIT License. See `LICENSE`.

## Release build and publishing

1) Create `android/key.properties` (local only; not committed)

Copy `android/key.properties.example` to `android/key.properties` and set values:

```
storePassword=your-store-pass
keyPassword=your-key-pass
keyAlias=screen_protector_key
storeFile=/home/<you>/my-release-key.jks
```

2) Build signed release APKs

```bash
flutter clean
flutter pub get
flutter build apk --release --split-per-abi
```

APKs will be in `build/app/outputs/flutter-apk/`.

3) Tag and create a GitHub Release (optional)

```bash
git tag -a v1.0.0+1 -m "Release v1.0.0+1"
git push origin v1.0.0+1
# If using GitHub CLI:
gh release create v1.0.0+1 \
	build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
	build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk \
	build/app/outputs/flutter-apk/app-x86_64-release.apk \
	-t "Screen Protector v1.0.0+1" \
	-n "Release notes here"
```

Alternatively, draft a release on GitHub and upload the APKs.

