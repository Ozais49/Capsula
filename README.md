# Capsula

A personal bookmark and content library for Android and the web, by YG Tech.
Save links from any app, organize them with collections and tags, read them in a clean
reader view, highlight passages, and search the text of saved pages.

- **Web app:** https://capsula-ygtech.web.app
- **Android package:** `com.ygtech.capsula`
- **Repository:** https://github.com/Ozais49/Capsula (work happens on `develop`)
- **Product plan:** [plan.md](plan.md)

## Features

- **Save from anywhere.** Android share sheet (with a "Save to Capsula" Direct Share
  shortcut), copied links (offered when you open the app), the add button, or browser
  bookmark import.
- **Real titles.** Titles come from the source (YouTube, Reddit, Instagram, X, TikTok,
  Facebook, and any page's `og:title`), not from the URL.
- **Organize.** Unsorted (links without tags or a collection), favorites, nested
  collections (collapsible), tags, reminders and archive, with filters by source, tag and
  reading status. List, card or grid layout; bulk edit.
- **Sources.** Built in: Reddit, YouTube, Instagram, Facebook, X, TikTok, Telegram, GitHub
  and Webpage. Add your own by domain.
- **Rules.** Tag, file and star links automatically as they are saved or imported, by
  source, domain, link, title or kind of content (video, post, product, …). Links no rule
  recognizes stay in Unsorted.
- **Trash.** Deleted bookmarks go to the Trash, where they can be restored for 30 days.
- **Read.** Reader view for articles, YouTube, Reddit posts and GitHub READMEs, with
  highlights and notes.
- **Search.** Titles and links, plus the full text of pages you've opened or indexed.
- **Maintain.** Find broken links and duplicates, rebuild indexes.
- **Import / export.** Import from Chrome, Firefox, Edge, Safari, Raindrop, Pocket, or any
  bookmark HTML, CSV or JSON file. Export a JSON backup or a browser bookmarks file.
- **Share.** Public read-only links for collections (needs the API server).
- **API.** A self-hosted REST API for scripts and integrations.
- **Two ways to store your library:**
  - **With an account:** Firebase sign-in, synced across devices.
  - **Without an account:** kept on this device only. No Firebase, no sign-in.

## Quick start

With the [development environment](docs/setup.md) installed, from the repository root:

```
flutter pub get
flutter run -d <device-id> --dart-define-from-file=config/dev.json
```

Run `flutter devices` to find device IDs. Use `-d edge` or `-d chrome` for the web app.

Or use the scripts, which find the tools, get dependencies and start everything:

```
scripts\phone\run.cmd       # app on the connected phone, with hot reload
scripts\phone\install.cmd   # install a release build on the phone
scripts\api\start.cmd       # API server, with the local Firebase emulators
scripts\web\run.cmd         # web app in the browser
scripts\web\serve.cmd       # release web build, served like Firebase Hosting
```

See [Running](docs/running.md#scripts) for their options.

## Documentation

| Guide | What it covers |
|---|---|
| [Setup](docs/setup.md) | Installing Flutter, the JDK, the Android SDK and the Firebase CLI on Windows |
| [Running](docs/running.md) | Running the app on a phone, in a browser or against the emulators; config files; storage modes |
| [Building](docs/building.md) | Android APK / App Bundle and web release builds, versioning, signing |
| [Hosting](docs/hosting.md) | Firebase project, web hosting, Firestore rules and indexes, hosting the API server |
| [Architecture](docs/architecture.md) | Code layout, layers, data model, share target, reader, security |
| [Testing](docs/testing.md) | App, API and security rules tests |
| [Troubleshooting](docs/troubleshooting.md) | Known issues and fixes |
| [API](api/README.md) | REST API endpoints, authentication and configuration |

## Repository layout

| Path | What |
|---|---|
| `lib/` | Flutter app (Android and web) |
| `packages/capsula_core/` | Pure-Dart domain model and logic, shared by the app and the API |
| `api/` | Self-hosted REST API server |
| `rules_test/` | Firestore security rules tests (Node, run against the emulator) |
| `test/` | App tests |
| `android/`, `web/` | Platform projects |
| `config/` | Build-time settings passed with `--dart-define-from-file` |
| `firebase.json`, `.firebaserc` | Firebase CLI config: hosting, rules, indexes, emulators |
| `firestore.rules`, `firestore.indexes.json` | Firestore security rules and composite indexes |
| `docs/` | Documentation |

## Common commands

```
flutter analyze                                     # static analysis
flutter test                                        # app tests
flutter build apk --release --dart-define-from-file=config/prod.json
flutter build web --release --dart-define-from-file=config/prod.json
firebase deploy --only hosting                      # publish the web app
firebase deploy --only firestore                    # publish rules and indexes
cd api && dart test                                 # API tests
cd rules_test && npm test                           # security rules tests
```
