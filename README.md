# Screen Protector App

A Flutter application that protects users' eyes by monitoring face proximity using the front camera to prevent sitting too close to the screen.

## Features

- **Face Proximity Detection**: Uses the front camera to detect when users are too close to the screen
- **Calibration System**: One-time calibration to establish comfortable viewing distance
- **Background Monitoring**: Runs as a foreground service on Android for continuous protection
- **Warning System**: Shows countdown warning before blocking the screen
- **Full-Screen Overlay**: Blocks the screen with a black overlay when user is too close
- **Privacy-First**: All detection is done on-device, no images are saved or transmitted
- **Notification Controls**: Stop/recalibrate from persistent notification
- **Configurable Settings**: Adjust sensitivity, warning time, and thresholds

## How It Works

1. **First-time Setup**: Grant camera and overlay permissions
2. **Calibration**: Position yourself at a comfortable distance and calibrate
3. **Start Protection**: The app monitors in the background using a foreground service
4. **Warning System**: When you get too close, a countdown warning appears
5. **Screen Blocking**: If you stay too close after the warning, the screen is blocked with a black overlay
6. **Return to Safety**: Move back to a safe distance to resume normal use

## Installation

### Prerequisites
- Flutter 3.19+ 
- Android SDK (API level 24+)
- Java 17
- Kotlin 1.9+

### Setup
1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## Privacy & Security

- All face detection is performed on-device
- No images are saved, stored, or transmitted
- No network connectivity required for core functionality
- Camera access is only used for face size measurement

## Platform Support

- **Android**: Full functionality with background monitoring
- **iOS**: In-app protection only (iOS doesn't allow background camera access)

Built following the comprehensive guide from app.md
