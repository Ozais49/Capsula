# Running Capsula

Run all commands from the repository root (the folder with `pubspec.yaml`). Running
`flutter run` anywhere else fails with `Target file "lib\main.dart" not found`.

## On an Android phone

```
flutter devices                      # find the device ID
flutter run -d <device-id> --dart-define-from-file=config/dev.json
```

While it runs, press `r` to hot reload, `R` to hot restart, and `q` to quit.

To install a release build without keeping a debug session open:

```
flutter build apk --release --dart-define-from-file=config/prod.json
adb -s <device-id> install -r build\app\outputs\flutter-apk\app-release.apk
```

## In a browser

```
flutter run -d edge --dart-define-from-file=config/dev.json
flutter run -d chrome --dart-define-from-file=config/dev.json
```

When it runs locally, the web app isn't on Firebase Hosting, so it can't read the
project's settings automatically. The first time, it opens **Firebase connection**: paste
the Web app's `firebaseConfig` there, or choose **Use without an account**. See
[Firebase connection](#firebase-connection).

## Build-time config

Settings that are compiled in live in `config/<env>.json`. Pass them with
`--dart-define-from-file`.

| File | Use |
|---|---|
| `config/dev.json` | Development against the real Firebase project (`capsula-ygtech`) |
| `config/emulators.json` | Local Firebase emulators |
| `config/prod.json` | Release builds |

| Key | Meaning |
|---|---|
| `APP_ENV` | `dev` or `prod` |
| `USE_FIREBASE_EMULATORS` | `true` to use the local Auth and Firestore emulators |
| `FIREBASE_EMULATOR_HOST` | Emulator host (default `localhost`) |
| `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_STORAGE_BUCKET`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_ANDROID_API_KEY` | The Android app's built-in Firebase project. Used when nothing is saved in the app |
| `API_BASE_URL` | Optional default address of the API server |

The Firebase values are identifiers, not secrets: access is controlled by Firebase Auth and
`firestore.rules`, so the files are committed. Never put service account keys or other
secrets in `config/`.

VS Code has matching launch configurations in `.vscode/launch.json`: **Capsula (dev)**,
**Capsula (emulators)** and **Capsula (prod)**. Pick one in Run and Debug and press F5.

## Against the local emulators

```
firebase emulators:start --only auth,firestore
flutter run -d <device-id> --dart-define-from-file=config/emulators.json
```

The Emulator UI is at http://localhost:4000. From a physical phone, set
`FIREBASE_EMULATOR_HOST` in `config/emulators.json` to your computer's LAN IP. From an
Android emulator, use `10.0.2.2`.

## Storage: with or without an account

Capsula keeps your library in one of two places. Choose on the sign-in or connection
screen, and switch later in **Settings**.

| | With an account | Without an account |
|---|---|---|
| Where the library lives | Firestore (`capsula-ygtech`, Mumbai), plus an offline cache | On this device only: a file in the app's private folder (Android) or the browser's local storage (web) |
| Sign-in | Email and password | None |
| Sync across devices | Yes | No |
| Backup | In the cloud | Use **Settings → Export library** |
| API, public share links | Available | Not available (both identify you by your account) |

The two libraries are separate. Switching doesn't copy bookmarks. To move them, export
from one and import into the other. The choice is remembered on the device.

The web app's on-device library lives in that browser's storage for the site. Clearing
site data deletes it.

## Firebase connection

Android builds include the project from `config/*.json`. The hosted web app reads it from
Firebase Hosting (`/__/firebase/init.json`). To use a different Firebase project, open
**Settings → Connection settings** (or **Connection settings** on the sign-in screen):

- **Android:** paste the contents of `google-services.json`. It must contain the
  `com.ygtech.capsula` app.
- **Web:** paste the Web app's `firebaseConfig` object.
- Or fill in the fields by hand.

Saved settings take priority over the built-in ones. Changing them while connected takes
effect after an app restart, because Firebase can only be initialized once per run.

To print the configs with the CLI:

```
firebase apps:list --project capsula-ygtech
firebase apps:sdkconfig ANDROID <android-app-id> --project capsula-ygtech
firebase apps:sdkconfig WEB <web-app-id> --project capsula-ygtech
```

## Trying the share target

With a phone connected, simulate sharing a link to Capsula:

```
adb shell am start -a android.intent.action.SEND -t text/plain -n com.ygtech.capsula/.ShareActivity --es android.intent.extra.TEXT "https://www.reddit.com/r/FlutterDev/" --es android.intent.extra.SUBJECT "FlutterDev"
```

### Sharing from Reddit and Instagram

Reddit and Instagram show their own row of share targets that other apps can't join.
Use the system share sheet instead, where Capsula and its "Save to Capsula" shortcut
appear:

- **Reddit:** Share → **Share via…**
- **Instagram:** Share → scroll the bottom row to the end → the share icon
- **Or:** tap **Copy link**, then open Capsula. It offers to save the copied link.

On Samsung phones, long-press Capsula in the share sheet and choose **Pin** to keep it at
the top.
