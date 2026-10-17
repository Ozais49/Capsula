# Hosting

What runs where:

| Part | Hosted on | Needed for |
|---|---|---|
| Web app | Firebase Hosting: https://capsula-ygtech.web.app | Using Capsula in a browser |
| Database and sign-in | Firebase (Firestore in `asia-south1` / Mumbai, Firebase Auth) | Using Capsula with an account |
| API server | Your own server (`deploy/vps`), or Google Cloud Run | Optional: REST API, public collection links, reading pages from the web app without cross-origin limits |
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
5. Put the Android app's values in `app/config/dev.json` and `app/config/prod.json` (see
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

Releases deploy automatically: push a `web-v<version>` tag (see [Releasing](releasing.md)).
To deploy by hand, build in `web/`, then deploy from the repository root:

```
cd web
flutter build web --release --dart-define-from-file=../app/config/prod.json
cd ..
firebase deploy --only hosting
```

`firebase.json` configures hosting:

- **Public folder:** `web/build/web`.
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

### Option A: Your own server

`deploy/vps/` runs the API on a Linux server: two API containers behind
[Caddy](https://caddyserver.com), which gets the HTTPS certificate and sends each request
to a container that's up. One container can restart or fail without the API going down.
The setup script targets AlmaLinux 9 (Rocky Linux and RHEL 9 work the same). The server
needs about 300 MB of memory for all three containers.

| File | What it is |
|---|---|
| `setup.sh` | One-time setup, run as root: Docker, firewall (SSH, HTTP, HTTPS), automatic security updates, the `capsula` deploy user, and `/opt/capsula` |
| `compose.yaml` | The API containers and Caddy |
| `Caddyfile` | HTTPS and load balancing |
| `env.example` | Settings; copied to `/opt/capsula/.env` |
| `deploy.sh` | Updates to a version, one container at a time |

#### 1. A domain

Point a DNS `A` record, such as `api.example.com`, at the server's IP address. Without a
domain, use `<ip>.sslip.io` (for example `203.0.113.7.sslip.io`), which points at that
IP and also gets a certificate.

#### 2. Set up the server

Copy the folder to the server and run the setup as root:

```
scp -r deploy/vps root@<server-ip>:/root/capsula-setup
ssh root@<server-ip> bash /root/capsula-setup/setup.sh
```

Then, on the server:

1. Set `API_DOMAIN` in `/opt/capsula/.env`.
2. Copy the service account key (see [Credentials](#credentials)) to
   `/opt/capsula/secrets/service-account.json`, owned by `capsula` with mode `600`. It
   stays on the server only.

#### 3. Let GitHub deploy

Create an SSH key for deploys on your PC, without a passphrase:

```
ssh-keygen -t ed25519 -f capsula-deploy -N "" -C capsula-deploy
```

- Add `capsula-deploy.pub` to `/home/capsula/.ssh/authorized_keys` on the server.
- On GitHub, **Settings → Secrets and variables → Actions**:
  - secret `VPS_SSH_KEY`: the contents of `capsula-deploy` (the private key)
  - secret `VPS_KNOWN_HOSTS`: the output of `ssh-keyscan <server-ip>`. Optional, but
    without it the workflow trusts whichever server answers first.
  - variable `VPS_HOST`: the server's IP address or name
  - variable `VPS_USER`: only if the user isn't `capsula`
- Delete the private key from your PC once it's in GitHub.

From then on, each API release (`scripts\release.cmd -Component api -Version 1.2.0
-Push`) builds the image, deploys it to the server and checks that
`https://<API_DOMAIN>/v1/health` answers. The first release starts everything. The image
can stay private: the workflow signs the server in to GitHub's registry just for the pull.

#### Running it by hand

On the server, as `capsula`, in `/opt/capsula`:

| Task | Command |
|---|---|
| Status | `docker compose ps` |
| Logs | `docker compose logs -f api1 api2` |
| Restart | `docker compose restart` |
| Go back to a version | `./deploy.sh 1.1.0` |

The containers start again by themselves after a reboot. A private image can only be pulled
after `docker login ghcr.io` with a GitHub token that has `read:packages`, or make the
package public (see [Releasing → API image](releasing.md#api-image)).

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
Run scales them automatically; `deploy/vps` runs two behind Caddy, and you can add more to
`compose.yaml` and the `Caddyfile`; elsewhere, run several containers behind a load
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
