# Development environment (Windows)

Everything needed to run, build and deploy Capsula. Android Studio isn't required.

| Tool | Version used | Location |
|---|---|---|
| Git | 2.56 | system install |
| Flutter (stable) | 3.47.7 / Dart 3.13.5 | `C:\src\flutter` (git clone, `stable` branch) |
| JDK | Microsoft OpenJDK 21 | `C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot` |
| Android SDK | platform 36, build-tools 36.0.0, platform-tools | `%LOCALAPPDATA%\Android\Sdk` |
| Node.js | 24 | via nvm or the installer |
| Firebase CLI | firebase-tools 15 | `npm install -g firebase-tools` |
| IDE | VS Code with the Dart and Flutter extensions | |

The Firebase emulator (used by the rules tests) needs JDK 21 or newer.

## Steps

1. Install Git and VS Code.
2. Install the JDK:
   ```
   winget install Microsoft.OpenJDK.21
   ```
3. Clone Flutter:
   ```
   git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
   ```
4. Download the Android command-line tools from
   <https://developer.android.com/studio#command-line-tools-only> and extract them so that
   `sdkmanager.bat` is at `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest\bin`.
5. Set user environment variables (Settings → System → About → Advanced system settings →
   Environment Variables):
   - `JAVA_HOME` = the JDK folder
   - `ANDROID_HOME` = `%LOCALAPPDATA%\Android\Sdk`
   - Add to `Path`:
     - `C:\src\flutter\bin`
     - `%ANDROID_HOME%\cmdline-tools\latest\bin`
     - `%ANDROID_HOME%\platform-tools`
     - `%JAVA_HOME%\bin`
6. Open a **new** terminal (already-open terminals keep the old `Path`). Install the SDK
   packages and accept the licenses:
   ```
   sdkmanager --licenses
   sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
   ```
7. Point Flutter at the SDK and JDK, and turn off targets Capsula doesn't use:
   ```
   flutter config --android-sdk "%ANDROID_HOME%" --jdk-dir "%JAVA_HOME%"
   flutter config --no-enable-windows-desktop --no-enable-linux-desktop --no-enable-macos-desktop --no-enable-ios
   ```
8. Install the Firebase CLI and sign in. The Google account needs access to the
   `capsula-ygtech` project.
   ```
   npm install -g firebase-tools
   firebase login
   ```
9. Install the VS Code extension:
   ```
   code --install-extension Dart-Code.flutter
   ```
10. Check everything:
    ```
    flutter doctor
    flutter devices
    ```

The first Android build downloads the NDK and Gradle dependencies, which takes several
minutes. If the Gradle download times out, see
[Troubleshooting](troubleshooting.md#gradle-download-times-out).

## Git Bash

Git Bash takes its `Path` from Windows, so after step 5 `flutter`, `adb` and `java` work in
new Git Bash windows too. To set them explicitly, add this to `~/.bashrc`:

```bash
export JAVA_HOME="/c/Program Files/Microsoft/jdk-21.0.12.101-hotspot"
export PATH="/c/src/flutter/bin:/c/Users/<you>/AppData/Local/Android/Sdk/platform-tools:$JAVA_HOME/bin:$PATH"
```

## Phone setup (Android)

1. On the phone, open Settings → About phone → Software information and tap
   **Build number** seven times to enable Developer options.
2. In Settings → Developer options, turn on **USB debugging**.
3. Connect the phone by USB and accept the "Allow USB debugging" prompt.
4. Check that it's listed: `adb devices` or `flutter devices`.

## Getting the code

```
git clone https://github.com/Ozais49/Capsula.git
cd Capsula
git checkout develop
cd app
flutter pub get
```

The web project, the API server and the rules tests have their own dependencies (from
the repository root):

```
cd web && flutter pub get
cd api && dart pub get
cd rules_test && npm install
```

The scripts in `scripts\` get dependencies themselves.
