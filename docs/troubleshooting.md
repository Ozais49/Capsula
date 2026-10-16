# Troubleshooting

## `flutter: command not found`

Flutter's `bin` folder isn't on the `Path` of that terminal. Add `C:\src\flutter\bin` to
your user `Path` (see [Setup](setup.md#steps)), then open a **new** terminal. Terminals
and tools started before the change keep the old `Path`, so restart them too.

## `Target file "lib\main.dart" not found`

`flutter run` was started outside the repository root. Run `cd` to the folder that contains
`pubspec.yaml` first.

## Gradle download times out

On some networks `release-assets.githubusercontent.com` (where `services.gradle.org`
redirects) can't be reached, so the Gradle wrapper fails with `Connection timed out`.

1. Download the same distribution from a mirror, for example
   `https://mirrors.cloud.tencent.com/gradle/gradle-<version>-all.zip`.
2. Check its SHA-256 against
   `https://services.gradle.org/distributions/gradle-<version>-all.zip.sha256`:
   ```
   certutil -hashfile gradle-<version>-all.zip SHA256
   ```
3. Delete the `.part` file in the folder the wrapper created under
   `%USERPROFILE%\.gradle\wrapper\dists\gradle-<version>-all\<hash>\`, copy the zip there,
   and rerun the build.

## The phone isn't listed in `flutter devices`

- Check that USB debugging is on, and accept the prompt on the phone.
- Run `adb devices`. If the phone shows as `unauthorized`, unplug it, revoke USB debugging
  authorizations in Developer options, and plug it in again.
- Try another cable or port. Some cables only charge.

## `INSTALL_FAILED_UPDATE_INCOMPATIBLE`

The installed app was signed with a different key (for example a debug build over a
release-signed build). Uninstall it first. This deletes data kept without an account, so
export it first.

```
adb -s <device-id> uninstall com.ygtech.capsula
```

## Lists show an error after deploying

A new Firestore index is still building. Wait a few minutes, and check Firestore → Indexes
in the Firebase console. Make sure `firebase deploy --only firestore` was run after
`firestore.indexes.json` changed.

## Sign-in fails with "Email sign-in is not enabled"

Enable **Email/Password** under Authentication → Sign-in method in the Firebase console.

## The web app can't read a page, or the title stays as the link

Many sites block requests from other websites (CORS). Android isn't affected. On the web,
either open the page in the browser, or run the [API server](hosting.md#api-server) and set
its address under **Settings → API & integrations**.

## Capsula doesn't appear in Reddit's or Instagram's share row

Those apps choose their own share targets, and other apps can't be added. Use their system
share button instead, or copy the link and open Capsula. See
[Running → Sharing from Reddit and Instagram](running.md#sharing-from-reddit-and-instagram).

## New Firebase settings don't take effect

Firebase can be initialized only once per run. Restart the app after saving new connection
settings.

## Rules tests fail to start

The Firestore emulator needs JDK 21 or newer. Check with `java -version` and that
`JAVA_HOME` points to it.
