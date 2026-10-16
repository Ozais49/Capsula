# Testing

There are three test suites. Run all three before merging or releasing.

| Suite | Command | Runs |
|---|---|---|
| App | `flutter test` (repository root) | Unit and widget tests for the app and `capsula_core` |
| API | `cd api && dart test` | The real HTTP handlers, with in-memory storage |
| Security rules | `cd rules_test && npm test` | `firestore.rules` against the Firestore emulator |

Static analysis:

```
flutter analyze
cd api && dart analyze
cd packages/capsula_core && dart analyze
```

Formatting: `dart format lib test packages api`.

## App tests

```
flutter test                                    # everything
flutter test test/features/settings             # one folder
flutter test --name "copied link"               # tests whose name matches
```

- Tests never touch Firebase or the network. `test/fakes/` has fakes for auth, the backend,
  page fetching, the share intake, the API and storage.
- Most screen tests pump the whole app (`CapsulaApp`) with a `FakeBackendConnector`, whose
  in-memory repositories the test can fill and inspect.
- `test/fakes/navigation.dart` has helpers for the drawer (`openNavigation`,
  `tapNavigationItem`) and for Settings (`openSettingsItem`).
- `test/fakes/memory_local_storage.dart` stands in for device storage when testing the
  library kept without an account.

## API tests

```
cd api
dart test
```

These cover auth (Firebase tokens and API tokens), keeping each user to their own data,
validation, tokens, rate limiting, CORS and public share links.

## Security rules

```
cd rules_test
npm install      # first time
npm test
```

This starts the Firestore emulator (JDK 21+ required) and tries cross-user reads, writes and
deletes, invalid fields and server-only paths. All of them must be denied. Run it after
every change to `firestore.rules`.

## Manual checks on a phone

The automated tests don't cover the Android share sheet, the system clipboard, or real
device storage. After changes in those areas, install a build (see
[Building](building.md)) and check:

- Sharing a link from YouTube, Reddit (**Share via…**) and a browser saves it with the real
  title.
- Copying a link and opening Capsula offers to save it.
- **Use without an account** keeps the library after closing and reopening the app.
- Switching between an account and the device library in Settings.
