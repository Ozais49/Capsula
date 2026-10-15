# Capsula API

Self-hosted REST API for remote integrations (scripts, browser extensions, other services)
and the web app. It's written in Dart and shares models and logic with the app through
`packages/capsula_core`.

It reads and writes the same Firestore data as the app, with the Firebase Admin SDK, so
bookmarks saved through the API show up in the app immediately and the other way round.

## Authentication

Every endpoint except `/v1/health` needs `Authorization: Bearer <credential>`, where the
credential is either:

- **A Firebase ID token** from a signed-in Capsula user (used by the web app), or
- **A personal API token** (`cap_…`) for scripts and integrations. Create tokens with
  `POST /v1/tokens` while signed in. The token is shown once, and only its SHA-256 hash is
  stored. API tokens can use every endpoint except token management.

Each request only ever reaches the caller's own `users/{uid}` data. Requests are
rate-limited per user (default 120 per minute).

## Endpoints (v1)

| Method | Path | Description |
|---|---|---|
| GET | `/v1/health` | Liveness check, no auth |
| GET | `/v1/me` | The caller's user ID and auth type |
| GET | `/v1/bookmarks?view=&q=&limit=` | List. `view`: `inbox`, `all` (default), `archived`, `source:reddit`, `tag:<id>`, `collection:<id>`. `q`: search. `limit`: up to 500 |
| GET | `/v1/bookmarks/export` | Every bookmark |
| POST | `/v1/bookmarks` | Save `{url, title?, tags?, collections?, fetchDetails?}`. The real title is fetched from the source. Returns 409 with the existing bookmark if already saved |
| GET / PATCH / DELETE | `/v1/bookmarks/{id}` | PATCH accepts `title`, `description`, `readingStatus`, `archived`, `inInbox`, `tags` / `collections` (names, created if missing) or `tagIds` / `collectionIds` |
| GET / POST | `/v1/tags`, `/v1/collections` | List, or create `{name}` (returns the existing one for the same name) |
| PATCH / DELETE | `/v1/tags/{id}`, `/v1/collections/{id}` | Rename `{name}`, or delete (bookmarks are kept) |
| GET | `/v1/page-info?url=` | Title, description and image of any link, fetched by the server |
| GET | `/v1/reader?url=` | Reader view of any link (article blocks, video, preview, or reason it's unavailable) |
| GET / POST | `/v1/tokens` | List or create API tokens (`{name}`). Firebase sign-in only |
| DELETE | `/v1/tokens/{id}` | Revoke a token |

Errors look like `{"error": {"code": "not_found", "message": "…"}}`.

Example:

```
curl -X POST https://api.example.com/v1/bookmarks \
  -H "Authorization: Bearer cap_…" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://youtu.be/lHhRhPV--G0", "tags": ["dev"]}'
```

## Configuration

| Variable | Required | Description |
|---|---|---|
| `FIREBASE_PROJECT_ID` | yes | e.g. `capsula-ygtech` |
| `GOOGLE_APPLICATION_CREDENTIALS` | yes, for production | Path to a Firebase service account key (JSON) |
| `PORT` | no | Default `8787` |
| `CORS_ORIGINS` | no | Comma-separated browser origins allowed to call the API, e.g. `https://capsula-ygtech.web.app`. Default `*` |
| `RATE_LIMIT_PER_MINUTE` | no | Default `120` |
| `USE_FIREBASE_EMULATORS` | no | `true` to use the local emulators (development) |

**Getting the service account key:** Firebase console → Project settings → Service accounts →
Generate new private key. Keep this file secret and out of git, because it grants full
access to the project.

## Running

Locally, against the emulators:

```
firebase emulators:start --only auth,firestore --project demo-capsula
cd api
FIREBASE_PROJECT_ID=demo-capsula USE_FIREBASE_EMULATORS=true dart run bin/server.dart
```

In production with Docker (run from the repository root):

```
docker build -f api/Dockerfile -t capsula-api .
docker run -p 8787:8787 \
  -e FIREBASE_PROJECT_ID=capsula-ygtech \
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/key.json \
  -e CORS_ORIGINS=https://capsula-ygtech.web.app \
  -v /path/to/key.json:/secrets/key.json:ro \
  capsula-api
```

Put it behind HTTPS (for example Caddy or nginx with Let's Encrypt). Browsers only send
the web app's sign-in token to an `https://` API.

## Tests

```
cd api
dart test
```

The tests run the real HTTP handlers with in-memory storage. They cover auth, user
isolation, validation, tokens, rate limiting and CORS.
