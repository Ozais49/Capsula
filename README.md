# Capsula

Universal personal bookmark and content library for Android and Web.
See [plan.md](plan.md) for the product plan and development phases.

## Development environment (Windows)

| Tool | Version | Location |
|---|---|---|
| Git | 2.56 | system install |
| Flutter (stable) | 3.47.7 / Dart 3.13.5 | `C:\src\flutter` (git clone, `stable` branch) |
| JDK | Microsoft OpenJDK 21 | `C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot` |
| Node.js + Firebase CLI | Node 24, firebase-tools 15 | `npm install -g firebase-tools` |
| Android SDK | platform 36, build-tools 36.0.0, platform-tools | `%LOCALAPPDATA%\Android\Sdk` |
| IDE | VS Code + Dart/Flutter extensions | |

Android Studio is not required.

### Setup steps

1. Install Git and VS Code.
2. Install the JDK: `winget install Microsoft.OpenJDK.21` (the Firebase emulator requires 21+)
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

Build-time settings live in `config/<env>.json` and are passed with `--dart-define-from-file`.
VS Code has matching launch configurations: **Capsula (dev)**, **Capsula (emulators)** and **Capsula (prod)**.

```
flutter run -d <android-device-id> --dart-define-from-file=config/dev.json
flutter run -d edge --dart-define-from-file=config/dev.json
```

| File | Use |
|---|---|
| `config/dev.json` | Development against the real Firebase project |
| `config/emulators.json` | Local Firebase emulators (`firebase emulators:start`) |
| `config/prod.json` | Release builds |

When using the emulators from a physical Android device, set `FIREBASE_EMULATOR_HOST`
in `config/emulators.json` to your computer's LAN IP (`10.0.2.2` from an Android emulator).

## Firebase setup

Firebase settings are entered in the app, not compiled in. On first launch the app opens
**Firebase connection**. It can also be opened later from the sign-in screen
(**Connection settings**) or the home screen's app bar.

- **Android:** paste the contents of `google-services.json`. It must contain the
  `com.ygtech.capsula` app.
- **Web:** paste the Web app's `firebaseConfig` object.
- Or fill in the fields by hand.

Settings are stored on the device (`shared_preferences`). Changing them while connected
takes effect after restarting the app, because Firebase can be initialized only once per run.

To get the configs from the CLI:

```
firebase apps:list --project capsula-ygtech
firebase apps:sdkconfig ANDROID <android-app-id> --project capsula-ygtech
firebase apps:sdkconfig WEB <web-app-id> --project capsula-ygtech
```

In the Firebase console, enable **Email/Password** under Authentication → Sign-in method.

## Architecture

```
lib/
  main.dart          Composition root: reads config, initializes Firebase, starts the app
  app/               App shell: routing, auth session, dependency scope, theme
  config/            Build-time configuration
  domain/            Provider-independent models and repository interfaces
  data/firebase/     Firebase implementations (the only code that imports Firebase SDKs)
  data/local/        On-device storage (saved connection settings)
  features/          Screens, grouped by feature
```

UI code depends on the repository interfaces in `domain/`, never on Firebase directly.
Tests use in-memory fakes of those interfaces (`test/fakes/`).

## Checks

```
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Firestore security rules tests. These start the emulator and attempt cross-user reads and
writes, which must all fail:

```
cd rules_test
npm install
npm test
```

## Android share target

`ShareActivity` (Kotlin) receives `ACTION_SEND` `text/plain` shares, shows a transparent
window over the sharing app, and passes the text to Flutter at `/share` over the
`capsula/share` method channel. Flutter extracts the links, saves them to the Inbox,
then closes.

To simulate a share from the command line with a device connected:

```
adb shell am start -a android.intent.action.SEND -t text/plain -n com.ygtech.capsula/.ShareActivity --es android.intent.extra.TEXT "https://www.reddit.com/r/FlutterDev/" --es android.intent.extra.SUBJECT "FlutterDev"
```

## Data

```
users/{uid}/bookmarks/{bookmarkId}
  url, canonicalUrl, title, description?, imageUrl?, source, sourceDomain,
  readingStatus, archived, inInbox, createdAt, updatedAt, searchTokens
```

- `firestore.rules` allows each signed-in user to access only their own `users/{uid}` data,
  and validates every bookmark write.
- `firestore.indexes.json` holds the composite indexes for listing and search.
- Deploy both with `firebase deploy --only firestore`.
- `canonicalUrl` is used for duplicate detection. `searchTokens` holds word prefixes for search.
