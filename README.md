# bookmark_app

Universal personal bookmark and content library for Android and Web.
See [plan.md](plan.md) for the product plan and development phases.

## Development environment (Windows)

| Tool | Version | Location |
|---|---|---|
| Git | 2.56 | system install |
| Flutter (stable) | 3.47.7 / Dart 3.13.5 | `C:\src\flutter` (git clone, `stable` branch) |
| JDK | Microsoft OpenJDK 17 | `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot` |
| Android SDK | platform 36, build-tools 36.0.0, platform-tools | `%LOCALAPPDATA%\Android\Sdk` |
| IDE | VS Code + Dart/Flutter extensions | |

Android Studio is not required.

### Setup steps

1. Install Git and VS Code.
2. Install the JDK: `winget install Microsoft.OpenJDK.17`
3. Clone Flutter: `git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter`
4. Download the Android command-line tools zip from
   <https://developer.android.com/studio#command-line-tools-only> and extract it so that
   `sdkmanager.bat` is at `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest\bin`.
5. Set user environment variables:
   - `JAVA_HOME` = JDK folder
   - `ANDROID_HOME` = `%LOCALAPPDATA%\Android\Sdk`
   - Add to `Path`: `C:\src\flutter\bin`, `%ANDROID_HOME%\cmdline-tools\latest\bin`,
     `%ANDROID_HOME%\platform-tools`, `%JAVA_HOME%\bin`
6. Install SDK packages and accept licenses:
   ```
   sdkmanager --licenses
   sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
   ```
7. Point Flutter at the SDK/JDK and disable unused targets:
   ```
   flutter config --android-sdk "%ANDROID_HOME%" --jdk-dir "%JAVA_HOME%"
   flutter config --no-enable-windows-desktop --no-enable-linux-desktop --no-enable-macos-desktop --no-enable-ios
   ```
8. Install the VS Code extension: `code --install-extension Dart-Code.flutter`
9. Verify: `flutter doctor` and `flutter devices`

The first Android build downloads the NDK and Gradle dependencies and takes several minutes.

### Known issue: Gradle download times out

On some networks `release-assets.githubusercontent.com` (where `services.gradle.org`
redirects) is unreachable, so the Gradle wrapper fails with `Connection timed out`.
Workaround: download the same distribution from a mirror (for example
`https://mirrors.cloud.tencent.com/gradle/gradle-<version>-all.zip`), verify its SHA-256
against `https://services.gradle.org/distributions/gradle-<version>-all.zip.sha256`,
and copy the zip into the directory the wrapper created under
`%USERPROFILE%\.gradle\wrapper\dists\gradle-<version>-all\<hash>\` (delete the `.part`
file first). Then rerun the build.

## Running

```
flutter run -d <android-device-id>   # physical device (USB debugging enabled)
flutter run -d edge                  # web (Chrome also works if installed)
```

## Checks

```
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```
