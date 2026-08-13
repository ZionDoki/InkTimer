# Build Guide

## Prerequisites

- Flutter 3.24 or later
- Dart 3.5 or later
- For Android: JDK 17, Android SDK
- For iOS: Xcode 15+, CocoaPods
- For Web: Chrome, Edge, or Safari

## Quick Start

```bash
# Install dependencies
flutter pub get

# Run on connected device
flutter run

# Run tests
flutter test

# Code analysis
flutter analyze
```

## Platform-Specific Builds

### Android

**Debug APK:**
```bash
flutter build apk --debug
```

**Release APK:**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Split APKs by architecture:**
```bash
flutter build apk --release --split-per-abi
# Outputs: armeabi-v7a, arm64-v8a, x86_64
```

**App Bundle (for Play Store):**
```bash
flutter build appbundle --release
```

**Signing:**  
Place `keystore.properties` in `android/` with:
```properties
storeFile=/path/to/uptimer-release.keystore
storePassword=your_password
keyAlias=uptimer
keyPassword=your_password
```

The build will automatically sign the release if `keystore.properties` exists.

### iOS

```bash
flutter build ios --release
# Then open ios/Runner.xcworkspace in Xcode to archive
```

### Web

```bash
flutter build web --release
# Output: build/web/
```

Serve locally:
```bash
flutter run -d chrome
# or
flutter run -d web-server --web-port 8080
```

### macOS

```bash
flutter build macos --release
# Output: build/macos/Build/Products/Release/uptimer.app
```

### Windows

```bash
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

### Linux

```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

## Environment Setup

### Android

**macOS:**
```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin
```

**Linux:**
```bash
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin
```

**Windows:**
```
set ANDROID_HOME=C:\Users\YourName\AppData\Local\Android\Sdk
set PATH=%PATH%;%ANDROID_HOME%\platform-tools;%ANDROID_HOME%\cmdline-tools\latest\bin
```

### iOS

Install CocoaPods:
```bash
sudo gem install cocoapods
cd ios && pod install
```

## Troubleshooting

**Gradle build fails:**
- Ensure JDK 17 is installed and `JAVA_HOME` is set
- Run `cd android && ./gradlew clean`

**iOS build fails:**
- Run `cd ios && pod install`
- Clean build folder in Xcode

**Web build fails:**
- Clear cache: `flutter clean && flutter pub get`

**Permission denied on Linux:**
- `chmod +x linux/flutter/ephemeral/.plugin_symlinks/*/linux/*.so`

## CI/CD

Example GitHub Actions workflow:

```yaml
name: Build
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter test
      - run: flutter analyze
```
