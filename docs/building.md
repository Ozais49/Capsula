# Building releases

Run Android builds from `app\` and web builds from `web\`. Release builds use
`app/config/prod.json`. To publish a release, use the GitHub Actions workflows instead
(see [Releasing](releasing.md)); these commands are for local builds.

## Android

### APK (install directly)

```
flutter build apk --release --dart-define-from-file=config/prod.json
```

Output: `build\app\outputs\flutter-apk\app-release.apk` (about 60 MB, all CPU types).
Install it on a connected phone:

```
adb -s <device-id> install -r build\app\outputs\flutter-apk\app-release.apk
```

For smaller APKs, build one per CPU type:

```
flutter build apk --release --split-per-abi --dart-define-from-file=config/prod.json
```

Most current phones use `app-arm64-v8a-release.apk`.

### App Bundle (Google Play)

```
flutter build appbundle --release --dart-define-from-file=config/prod.json
```

Output: `build\app\outputs\bundle\release\app-release.aab`. Google Play only accepts bundles
signed with your own key, so set up [release signing](#release-signing) first.

### Version numbers

The version is `version:` in `app/pubspec.yaml`, for example `1.0.0+1`. The part before `+`
is the version name users see. The number after `+` is the version code, which must go up
with every Play Store upload. Releases from GitHub Actions take the name from the tag and
use the workflow's run number as the code. Change it in `app/pubspec.yaml`, or override it
for one build:

```
flutter build appbundle --release --build-name=1.1.0 --build-number=2 --dart-define-from-file=config/prod.json
```

### Release signing

Without a key, `app/android/app/build.gradle.kts` signs release builds with the debug key.
That's fine for installing on your own phones, but Google Play rejects it, and a phone
won't update an app signed with a different key without uninstalling it first.

1. Create an upload key once. Keep it **outside** the repository and back it up: losing it
   means you can't update the app.
   ```
   keytool -genkey -v -keystore C:\Users\<you>\keys\capsula-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `app/android/key.properties`. It's ignored by git; never commit it.
   ```properties
   storePassword=<keystore password>
   keyPassword=<key password>
   keyAlias=upload
   storeFile=C:/Users/<you>/keys/capsula-upload.jks
   ```
   Use forward slashes in `storeFile`, because backslashes are escape characters in
   `.properties` files. A relative path is resolved from `app/android/app/`.
3. Build as usual. When `app/android/key.properties` exists, release builds are signed with
   that key.

Switching from debug-signed to release-signed builds means uninstalling the old app from
test phones once. Uninstalling deletes data kept without an account; export it first.

### App icon and name

The launcher name is `Capsula`, set in `app/android/app/src/main/AndroidManifest.xml`. The icon
is the default Flutter icon in `app/android/app/src/main/res/mipmap-*`. Replace those images,
or generate them with the `flutter_launcher_icons` package.

## Web

The web project in `web\` builds the app for the browser. Its own files (`index.html`,
icons, manifest) are in `web\web\`.

```
cd web
flutter build web --release --dart-define-from-file=../app/config/prod.json
```

Output: `web\build\web`. It's a static site: serve it from any static host that sends every
path to `index.html`, so links like `/bookmarks/<id>` work. To publish on Firebase Hosting,
see [Hosting](hosting.md#web-app).

To try the release build locally the way Firebase Hosting serves it, run
`scripts\web\serve.cmd`.

## API server

See [Hosting → API server](hosting.md#api-server). To build a standalone executable:

```
cd api
dart compile exe bin/server.dart -o build/capsula-api.exe
```

## Before releasing

```
cd app && flutter analyze && flutter test
cd web && flutter analyze && flutter test
cd api && dart analyze && dart test
cd rules_test && npm test
```

The workflows run the same checks on every push.

Then build, install on a phone, and check signing in, saving a link through the share
sheet, opening the reader, and using the app without an account.
