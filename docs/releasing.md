# Releasing

Each part of Capsula is released on its own, from its own folder, by its own GitHub Actions
workflow:

| Part | Folder | Workflow | Release tag | A release… |
|---|---|---|---|---|
| Android app | `app/` | `.github/workflows/app.yml` | `app-v1.2.0` | builds a signed APK and App Bundle, attaches them to a GitHub release, and sends the APK to testers (Firebase App Distribution, when set up) |
| Web app | `web/` | `.github/workflows/web.yml` | `web-v1.2.0` | builds the site and deploys it to Firebase Hosting |
| API server | `api/` | `.github/workflows/api.yml` | `api-v1.2.0` | builds the Docker image and publishes it to GitHub Container Registry |
| Firestore rules and indexes | repository root | `.github/workflows/firebase.yml` | `firebase-v1.2.0` | deploys `firestore.rules` and `firestore.indexes.json` |

On every push and pull request, each workflow also runs its part's checks (analysis and
tests), but only when files that part uses have changed. A change to
`packages/capsula_core` is checked by all three code workflows, because all three use it.

## Making a release

```
scripts\release.cmd -Component app -Version 1.1.0
```

This sets the version in that part's `pubspec.yaml`, commits, and tags `app-v1.1.0`. Push
to start the release:

```
git push origin HEAD
git push origin app-v1.1.0
```

Or add `-Push` to do both. Follow the run under **Actions** on GitHub; the release appears
under **Releases**.

The workflow refuses to run if the tag doesn't match the version in `pubspec.yaml`. For the
Android app, the build number (version code) is the workflow's run number, so it always goes
up.

**Order matters when the data changes.** If a version needs new Firestore rules or indexes,
release `firebase` first and wait for it to finish, then the app and web.

## One-time setup

All of this is under the GitHub repository's **Settings → Secrets and variables → Actions**.

### Android signing (required for app releases)

Releases must be signed with your upload key; the app workflow stops without it.

1. Create the key once, as described in [Building → Release signing](building.md#release-signing).
   Back it up somewhere safe: losing it means you can't update the app.
2. Add these secrets:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The `.jks` file, base64-encoded. In PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Users\<you>\keys\capsula-upload.jks')) \| Set-Clipboard`, then paste |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password |
| `ANDROID_KEY_PASSWORD` | The key password |
| `ANDROID_KEY_ALIAS` | The key alias (`upload` if you followed the guide) |

### Firebase access (web, rules, and App Distribution)

1. In the Google Cloud console for `capsula-ygtech`: IAM & Admin → Service accounts →
   **Create service account**, for example `github-releases`.
2. Give it these roles:
   - **Firebase Hosting Admin**: web releases
   - **Firebase Rules Admin** and **Cloud Datastore Index Admin**: rules and index releases
   - **Firebase App Distribution Admin**: sending the app to testers
   - **Service Account User** and **API Keys Viewer**: needed by the Firebase CLI
3. Create a JSON key for it (Keys → Add key → JSON) and add the whole file's contents as
   the secret `FIREBASE_SERVICE_ACCOUNT`. Then delete the downloaded file.

This key can change the live project, so keep it only in GitHub's secrets.

### Testers (optional)

App releases go to Firebase App Distribution when `FIREBASE_SERVICE_ACCOUNT` is set. In the
Firebase console, open **App Distribution**, accept the terms, and create a tester group
(for example `testers`) with your testers' emails. If the group isn't called `testers`, add
a repository **variable** `FIREBASE_TESTER_GROUPS` with its name (several, comma-separated).
Testers get an email for each release and can install it through the App Tester app.

### API image

API releases need no secrets: they publish to GitHub Container Registry with the
workflow's own token, as `ghcr.io/<owner>/capsula-api:<version>` and `:latest`. The first
image is private; to let a server pull it without signing in, open the package on GitHub
(your profile → Packages → capsula-api → Package settings) and make it public. Running the
image: [Hosting → API server](hosting.md#api-server).

## Versions

Each part has its own version, in its own file:

| Part | Version in |
|---|---|
| App | `app/pubspec.yaml` (`1.1.0+7`: name and local build number) |
| Web | `web/pubspec.yaml` |
| API | `api/pubspec.yaml` |
| Firebase rules | The tag only |

Use [semantic versions](https://semver.org): raise the last number for fixes, the middle
one for new features, the first for changes that break older versions (for the API, a
change existing scripts must adapt to).
