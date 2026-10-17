# Architecture

## Overview

```
┌────────────────────┐   ┌────────────────────┐
│ Flutter app        │   │ API server (Dart)  │
│ Android + web      │   │ api/               │
│ lib/               │   │                    │
└──────┬──────┬──────┘   └─────────┬──────────┘
       │      │ uses               │ uses
       │      ▼                    ▼
       │   ┌──────────────────────────────┐
       │   │ packages/capsula_core        │
       │   │ models, rules, parsers,      │
       │   │ reader, search (pure Dart)   │
       │   └──────────────────────────────┘
       │ stores in either
       ▼
┌───────────────────────────┐    ┌──────────────────────────┐
│ Firebase Auth + Firestore │ or │ This device (no account) │
└───────────────────────────┘    └──────────────────────────┘
```

- **`packages/capsula_core`** is pure Dart, with no Flutter or Firebase. It holds the models
  (bookmarks, labels, highlights), the repository interfaces, and the logic both clients
  share: URL normalization, source and type detection, search tokens, import parsers,
  export, the reader and title lookups, and maintenance.
- **The app** (`lib/`) provides the UI and the storage implementations.
- **The API server** (`api/`) uses the same core with the Firebase Admin SDK, so data it
  writes looks exactly like data the app writes.

## App code layout

```
lib/
  main.dart            Composition root: config, backend choice, starts the app
  app/                 App shell: router, dependency scope, auth session, backend
                       controller, display preferences, theme
  config/              Build-time configuration (dart-defines)
  data/
    firebase/          Firestore and Firebase Auth repositories (the only code that
                       imports Firebase)
    local/             On-device storage: saved connection settings, and the file or
                       browser storage that holds a library without an account
    api/               Client for the API server
  features/            Screens, one folder per feature (bookmarks, reader, settings, …)
  platform/            Platform integrations: share intake, clipboard, file picking and
                       saving, hosted Firebase config
```

UI code depends on the interfaces in `capsula_core`, never on Firebase directly. Screens get
services from `AppDependencies` (an `InheritedWidget`), not from a DI package.

## Storage backends

`BackendController` (`lib/app/backend_controller.dart`) decides where the library lives and
exposes it as a `BackendServices` (auth, bookmarks, labels, highlights, content index):

| Mode | Implementation | Chosen when |
|---|---|---|
| Account | `FirebaseBackendConnector` → Firestore repositories | Settings are saved in the app, or built in (`config/*.json` on Android, `/__/firebase/init.json` on Firebase Hosting) |
| This device | `LocalLibrary` (`capsula_core/domain/local`) on `deviceStorage()` | The user chose **Use without an account** (remembered in `shared_preferences`) |

`LocalLibrary` keeps the library in memory and writes it as JSON after every change: to a
file in the app's support folder on Android (written to a temporary file, then renamed),
and to the browser's local storage on the web. Its auth repository is always signed in, as
a fixed local user.

Switching modes replaces the services while the app is running. The auth session follows
the new repository, and the router sends the user to the library or the sign-in screen.

## Routing

`go_router` with path URLs (`/`, `/bookmarks/<id>`, `/bookmarks/<id>/read`, `/settings`,
`/import`, `/maintenance`, `/highlights`, `/integrations`, `/connection`, `/sign-in`,
`/share`). `appRedirect` in `lib/app/router.dart` sends users to the connection screen
until a backend is ready, then to sign-in until signed in. The connection screen is always
reachable.

## Data model (Firestore)

All user data is under `users/{uid}`. Only the owner can read or write it.

| Path | Fields |
|---|---|
| `users/{uid}/bookmarks/{id}` | `url`, `canonicalUrl`, `title`, `description?`, `imageUrl?`, `source`, `sourceDomain`, `type`, `readingStatus`, `archived`, `inInbox`, `favorite?`, `note?`, `remindAt?`, `contentIndexedAt?`, `tagIds`, `collectionIds`, `importedFrom?`, `importedAt?`, `createdAt`, `updatedAt`, `searchTokens` |
| `users/{uid}/tags/{id}` | `name`, `createdAt`, `updatedAt?` |
| `users/{uid}/collections/{id}` | `name`, `parentId?` (nested collections), `shareId?` (set only by the API), `createdAt`, `updatedAt?` |
| `users/{uid}/highlights/{id}` | `bookmarkId`, `text`, `note?`, `color`, `createdAt` |
| `users/{uid}/contents/{bookmarkId}` | `words` (page text words for full-text search, up to 3000), `updatedAt` |
| `apiTokens/{sha256}` | API token hash → `uid`, `name`, `createdAt`, `lastUsedAt?`. Server only |
| `publicShares/{id}` | Public collection link → owner and collection. Server only |

- `canonicalUrl` (normalized URL, without tracking parameters) is used to detect
  duplicates.
- `searchTokens` holds word prefixes for title and link search.
- Encoding and decoding are shared by the app and the server (`bookmark_codec.dart`).
- The on-device library stores the same fields as JSON, with ISO-8601 dates.

## Saving a link

1. A link arrives from the share sheet, a copied link, the add button, an import or the API.
2. `BookmarkService.save` normalizes it, checks for a duplicate by `canonicalUrl`, detects
   the source and type, and saves it to the Inbox right away, with a title taken from the
   URL.
3. `fetchDetails` then looks up the real title, description and image (`PageInfoService`):
   oEmbed for YouTube, TikTok and X; Reddit's JSON or RSS; a crawler user agent for
   Instagram and Facebook; and `og:title` or `<title>` for everything else. Generic titles
   such as "Instagram" are rejected.
4. On sign-in, links saved without a real title (for example while offline) are looked up
   again.

## Concurrent changes

Several devices, browser tabs, the share window, the API server and background tasks (title
lookups, page indexing) can change the same bookmark at once. None of them may undo
another's change.

- **Edits change only their own fields.** `BookmarkRepository.modify(id, change)` applies
  `change` to the latest stored copy and writes the difference (`BookmarkPatch`): Firestore
  `update()` of the changed fields, with tag and collection lists written as
  `arrayUnion`/`arrayRemove`, so label changes made elsewhere merge. The app reads the
  latest copy from its cache, so this works offline. The API does the same in a
  transaction. `update(bookmark)` (writing everything) is only for restores.
- **Stable IDs.** New bookmarks are stored under an ID derived from the canonical URL
  (`bookmarkIdFor`), so two devices saving the same link write one bookmark. When the
  second write reaches the server, the rules refuse it because `createdAt` would change,
  and the app treats that as already saved.
- **Bulk writes** (bulk edits, re-indexing) go in batches of 450, one after another.
  Changes are idempotent, so a run that stopped part way can be repeated.
- **On-device library in several tabs.** The stored library has a `revision`. Before
  saving, a tab compares revisions; if another tab saved in between, it merges the stored
  library with its own unsaved changes (its version wins for items it changed, including
  deletions). Browser `storage` events, and file watching on Android for the share window,
  make tabs pick up each other's saves. Each save keeps the previous copy as a backup.
- **Pending writes.** The library shows a cloud icon while writes made on the device haven't
  reached Firestore yet.

## Android share target

- `ShareActivity` (Kotlin) receives `ACTION_SEND` `text/plain` shares and shows a
  transparent window over the sharing app. It passes the text to Flutter at `/share` over
  the `capsula/share` method channel. Flutter saves the links and closes.
- `ShareShortcuts.kt` publishes a "Save to Capsula" sharing shortcut, so Capsula appears in
  the Direct Share row of the system share sheet.
- Apps that use their own share sheet (Reddit, Instagram) list only the targets they choose.
  Their **Share via…** or system share button opens the Android sheet. Copied links are
  offered when Capsula opens (`LibraryScreen._offerCopiedLink`).

## Reader

`ReaderService` (`capsula_core/domain/reader`) chooses a presentation for each kind of
content:

| Content | Reader shows |
|---|---|
| Websites, blogs, docs | The article, extracted from the page (`article_extractor.dart`) |
| YouTube | Video card (thumbnail, and title from oEmbed) |
| Reddit posts | The post body, from Reddit's public JSON |
| GitHub repositories | The README, from the GitHub API |
| Instagram, Facebook, TikTok, X, Amazon | Preview from page metadata |
| Short pages | Preview from page metadata |
| Login pages, 404s, PDFs, network errors | An explanation and **Open in browser** |

Opening an article indexes its text for full-text search. Reading never changes a bookmark,
except to fill in a title that was taken from the URL.

On the web, many sites block cross-origin requests. When an API server is set, the app
fetches pages through it. Otherwise the reader explains the problem and offers
**Open in browser**.

## Security and privacy

- `firestore.rules` gives each user access only to `users/{uid}`, and validates every write:
  allowed fields, types and sizes, `http(s)` URLs only, and no changes to `createdAt`,
  `url` or `canonicalUrl`. `apiTokens` and `publicShares` are server-only. Everything else
  is denied. `rules_test/` checks that cross-user access fails.
- Firebase config values are identifiers, not secrets. Service account keys never go in the
  repository (see `.gitignore`).
- The app doesn't log URLs or bookmark contents. The API strips query strings from its logs.
- API tokens are stored only as SHA-256 hashes and shown once, when created.
- Public collection pages show only titles, links, descriptions and images.

## Known limitations

- Firestore's offline cache stays on the device after sign-out. On a shared computer, clear
  the site data (web) or the app's storage (Android).
- A library without an account isn't backed up. Uninstalling the app or clearing site data
  deletes it, so export it regularly.
- Not yet implemented: reminder notifications, collaborators on shared collections, a
  browser extension, account deletion, delete-all-data, email verification, App Check, and
  a real app icon.
