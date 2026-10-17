# Hosting

What runs where:

| Part | Hosted on | Needed for |
|---|---|---|
| Web app | Firebase Hosting: https://capsula-ygtech.web.app | Using Capsula in a browser |
| Database and sign-in | Firebase (Firestore in `asia-south1` / Mumbai, Firebase Auth) | Using Capsula with an account |
| API server | Self-hosted (Docker on a server, or Google Cloud Run) | Optional: REST API, public collection links, reading pages from the web app without cross-origin limits |
| Android app | Installed APK (later Google Play) | — |

Using Capsula without an account needs none of these except the web app (for the browser
version).

## Firebase project

| | |
|---|---|
| Project ID | `capsula-ygtech` (the default in `.firebaserc`) |
| Console | https://console.firebase.google.com/project/capsula-ygtech |
| Android app | `com.ygtech.capsula` |
| Web app | Capsula (web) |
| Firestore location | `asia-south1` (Mumbai). It can't be changed once the database exists |
| Sign-in method | Email/Password (Authentication → Sign-in method) |

The CLI commands below use the default project from `.firebaserc`. Add
`--project capsula-ygtech` to be explicit.

### Setting up a new Firebase project

To run your own copy of Capsula:

1. Create a project in the Firebase console and set it as the default:
   ```
   firebase use --add
   ```
2. Create a Firestore database (Build → Firestore Database) in the region closest to your
   users.
3. Enable **Email/Password** under Authentication → Sign-in method.
4. Register an Android app with package `com.ygtech.capsula` and a Web app.
5. Put the Android app's values in `config/dev.json` and `config/prod.json` (see
   [Running → Build-time config](running.md#build-time-config)), or paste
   `google-services.json` into the app's connection screen.
6. Deploy the rules, indexes and web app as described below.

## Firestore rules and indexes

`firestore.rules` lets each signed-in user read and write only their own `users/{uid}`
data, and validates every write. `firestore.indexes.json` holds the composite indexes
behind the library's lists, filters and sorting.

```
firebase deploy --only firestore
```

New indexes take a few minutes to build. Until they finish, the affected lists show an
error. Check progress in the console under Firestore → Indexes.

Run the [rules tests](testing.md#security-rules) before deploying rule changes.

## Web app

Build, then deploy to Firebase Hosting:

```
flutter build web --release --dart-define-from-file=config/prod.json
firebase deploy --only hosting
```

`firebase.json` configures hosting:

- **Public folder:** `build/web`.
- **Rewrites:** every path goes to `index.html`, so app links like `/bookmarks/<id>` work
  when opened directly.
- **Caching:** `index.html` is never cached, so a deploy reaches users on their next visit.
  Scripts and WebAssembly are cached for an hour.
- **Security headers:** `X-Content-Type-Options: nosniff` and
  `Referrer-Policy: strict-origin-when-cross-origin`.
- **Firebase settings:** on Firebase Hosting, the app reads the project's web config from
  `/__/firebase/init.json` and connects without setup.

### Preview before publishing

Deploy to a temporary URL that expires after 7 days:

```
firebase hosting:channel:deploy preview --expires 7d
```

### Rolling back

Firebase console → Hosting → Release history → choose an earlier release → **Rollback**.

### Custom domain

1. Firebase console → Hosting → **Add custom domain**, then add the DNS records it shows.
2. Add the domain under Authentication → Settings → **Authorized domains**, so sign-in works
   there.
3. If the API server is used, add the domain to its `CORS_ORIGINS`.

## API server

The API is optional. The app works without it, but it adds:

- the REST API for scripts and integrations (see [api/README.md](../api/README.md))
- public read-only links for collections (`/p/<id>`)
- page reading and title lookups for the web app, which browsers otherwise often block

It reads and writes the same Firestore data as the app, using the Firebase Admin SDK.

### Credentials

The server needs permission to use the project's Firestore:

- **On your own server:** create a service account key (Firebase console → Project
  settings → Service accounts → Generate new private key) and point
  `GOOGLE_APPLICATION_CREDENTIALS` at it. The key grants full access to the project: keep
  it outside the repository (`.gitignore` blocks the usual key file names and
  `api/secrets/`), and never put it in a container image.
- **On Google Cloud:** leave `GOOGLE_APPLICATION_CREDENTIALS` unset. The server then uses
  the service's own identity, which needs the **Cloud Datastore User** role.

All settings are listed in [api/README.md → Configuration](../api/README.md#configuration).

### Option A: Docker on a server

Build from the repository root, because the image includes `packages/capsula_core`:

```
docker build -f api/Dockerfile -t capsula-api .
docker run -d --restart unless-stopped -p 8787:8787 \
  -e FIREBASE_PROJECT_ID=capsula-ygtech \
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/key.json \
  -e CORS_ORIGINS=https://capsula-ygtech.web.app \
  -v /path/to/key.json:/secrets/key.json:ro \
  --name capsula-api capsula-api
```

Put HTTPS in front of it. Browsers only send sign-in tokens to `https://` addresses. With
[Caddy](https://caddyserver.com), which gets certificates automatically, a `Caddyfile` like
this is enough:

```
api.example.com {
    reverse_proxy localhost:8787
}
```

Check it's running: `curl https://api.example.com/v1/health`.

### Option B: Google Cloud Run

Cloud Run requires the project to be on the Blaze (pay-as-you-go) plan. It scales to zero
when idle.

```
gcloud config set project capsula-ygtech
gcloud artifacts repositories create capsula --repository-format=docker --location=asia-south1
gcloud auth configure-docker asia-south1-docker.pkg.dev

docker build -f api/Dockerfile -t asia-south1-docker.pkg.dev/capsula-ygtech/capsula/api .
docker push asia-south1-docker.pkg.dev/capsula-ygtech/capsula/api

gcloud run deploy capsula-api \
  --image asia-south1-docker.pkg.dev/capsula-ygtech/capsula/api \
  --region asia-south1 \
  --allow-unauthenticated \
  --set-env-vars FIREBASE_PROJECT_ID=capsula-ygtech,CORS_ORIGINS=https://capsula-ygtech.web.app
```

`--allow-unauthenticated` lets requests reach the server, which checks every request's
sign-in or API token itself. Cloud Run sets `PORT`, which the server uses.

To serve the API from the web app's own domain (no CORS, same address), add a rewrite to
`firebase.json` **before** the catch-all rule, then deploy hosting:

```json
"rewrites": [
  { "source": "/v1/**", "run": { "serviceId": "capsula-api", "region": "asia-south1" } },
  { "source": "/p/**", "run": { "serviceId": "capsula-api", "region": "asia-south1" } },
  { "source": "**", "destination": "/index.html" }
]
```

### Running more than one instance

The server keeps no state of its own, so any number of instances can run at once (Cloud
Run scales them automatically; with Docker, run several containers behind a load
balancer). Each instance:

- finishes requests in flight when it receives `SIGTERM` (sent by Cloud Run and
  `docker stop`), waiting up to 8 seconds, then exits;
- applies the rate limit on its own. With several instances, a user can make up to the
  limit times the number of instances. To keep a firm limit on Cloud Run, cap instances
  with `--max-instances`.

Writes from several instances, the app and other devices don't overwrite each other:
updates change only the fields they're about (see `api/README.md`).

### Connecting the app

In the app: **Settings → API & integrations**, then enter the server address, for example
`https://api.example.com`. To build the address in, set `API_BASE_URL` in
`config/prod.json`. Create API tokens for scripts on the same screen.

If the server stops answering (3 failures in a row), the app stops calling it for a minute
and does the work on the device instead: it reads pages and looks up titles itself on
Android, and offers **Open in browser** on the web. Saving and organizing never depend on
the server.

## Backups

Account libraries live in Firestore. To be able to recover from a mistake:

- Turn on **point-in-time recovery**, which keeps 7 days of history (Blaze plan):
  `gcloud firestore databases update --database='(default)' --enable-pitr`
- Schedule a daily export to a Cloud Storage bucket:
  `gcloud firestore export gs://<bucket>/$(date +%F)`, for example from Cloud Scheduler.
- Or export from the app: **Settings → Export library**, which also works for on-device libraries.

The on-device library keeps the previous save as a backup and loads it if the current copy
can't be read. The unreadable copy is kept under a separate name rather than overwritten.

## Costs

On Firebase's free Spark plan, Hosting, Auth and Firestore are free within daily quotas,
which personal use stays well within. Cloud Run needs the Blaze plan, but its free tier
covers light use. A small VPS running the Docker image costs a few dollars a month.
