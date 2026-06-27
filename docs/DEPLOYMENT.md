# Self-hosting Federfall

Federfall runs as a single Docker container.
One version-pinned PocketBase image serves the API, the admin dashboard and the Flutter web app, all on the same port.
There is no separate database server and no web server to wire up — you run one container, put a reverse proxy in front of it for HTTPS, and that is the whole stack.

This guide walks through a production deployment on your own machine.

## What you need

- A host with Docker and the Compose plugin.
- A domain name pointing at that host, if you want HTTPS (you do).
- A reverse proxy to terminate TLS. The stack speaks plain HTTP on a host port; it deliberately does not handle certificates itself, so you can use whatever proxy you already run. Caddy is the least effort and is used in the examples below.

## Getting it running

Clone the repository and start the stack from its root:

```bash
git clone https://github.com/jhbruhn/federfall.git
cd federfall
docker compose -f docker-compose.yml up -d --build
```

The `-f docker-compose.yml` matters: it runs the production file explicitly and skips `docker-compose.override.yml`, which only exists for local development.
The first build compiles the Flutter web app and takes a few minutes.
Once it is up, the app answers on `http://<host>:8090`.

That port is HTTP only. Don't expose it to the internet directly — put a proxy in front of it (see [HTTPS](#https) below).

## Configuration

All configuration is done with environment variables, set directly in `docker-compose.yml` under the `app` service.
There is no `.env` file to copy; you edit the compose file and the values live there.
Secrets you would rather not keep in that file (SMTP passwords, for instance) can be set in your shell or your orchestrator instead — Compose reads them from the environment if you leave them unquoted there.

The variables are grouped by what they do. None of them are required to *start* the container, but a few are required for it to be useful.

### App URL

```yaml
FEDERFALL_APP_URL: "https://federfall.yourdomain.tld"
```

This is your instance's public address.
It is used in the links inside outgoing emails, so password-reset and invite mails point at the right place.
Set it to the same URL your users will open.

### Mail

Invites and password resets are sent by email, so without SMTP a freshly invited user never receives their link.
The stack leaves mail off until you give it a host:

```yaml
FEDERFALL_SMTP_HOST: "smtp.yourprovider.tld"
FEDERFALL_SMTP_PORT: "587"            # 465 for implicit TLS
FEDERFALL_SMTP_USERNAME: "..."
FEDERFALL_SMTP_PASSWORD: "..."
FEDERFALL_SMTP_TLS: "false"           # "true" for implicit TLS (port 465)
FEDERFALL_SMTP_SENDER_ADDRESS: "noreply@yourdomain.tld"
FEDERFALL_SMTP_SENDER_NAME: "Federfall"
```

These are applied on every start, so changing them means editing the file and recreating the container.

### Geocoding and maps

Address search goes through the backend, which forwards to a Nominatim-compatible geocoder:

```yaml
FEDERFALL_NOMINATIM_URL: "https://nominatim.yourdomain.tld"
FEDERFALL_USER_AGENT: "Federfall/1.0 (you@yourdomain.tld)"
FEDERFALL_GEOCODER_KEY: ""            # only for keyed mirrors
```

A word of warning: the default is the public OpenStreetMap Nominatim, and that server blocks most server-to-server traffic.
Address search will likely fail against it.
For real use, run your own Nominatim instance or use a mirror that permits backend traffic, and set a real contact address in the user agent.

Map *tiles* are a separate matter. They are baked into the web build, not read from the environment, and default to the public OpenStreetMap tile server.
To change them you edit `apps/federfall/dart_defines/production.json` (`MAP_TILE_URL`, `MAP_ATTRIBUTION`) and rebuild the image.

### Time zone

```yaml
TZ: "Europe/Berlin"
```

Set this to your local zone so timestamps in logs read sensibly.

## HTTPS

The container does not do TLS. Point a reverse proxy at `localhost:8090` and let it handle certificates.

With Caddy, the whole configuration is two lines:

```caddyfile
federfall.yourdomain.tld {
    reverse_proxy localhost:8090
}
```

Caddy obtains and renews the certificate on its own, streams the realtime updates the app relies on, and does not cap upload sizes — so photo uploads and live updates work without further tuning.

If you prefer nginx, two settings matter: raise `client_max_body_size` (photos can be a few megabytes) and turn off proxy buffering for `/api/realtime` so server-sent events are not held back.

## First login

Registration is invite-only, and every invite is sent by an existing supervisor.
That leaves the first supervisor as a chicken-and-egg problem, so the stack can create one for you on first start.
Set both of these before bringing the container up:

```yaml
FEDERFALL_SUPERVISOR_EMAIL: "you@yourdomain.tld"
FEDERFALL_SUPERVISOR_PASSWORD: "a-strong-password"
FEDERFALL_SUPERVISOR_NAME: "Your Name"
```

A supervisor is created the next time the container starts, but only while no active supervisor exists.
That makes it safe to leave in place — it does nothing once a supervisor is present — and it also gives you a way back in if you ever lock yourself out.
Once you have logged in, you can remove the two variables.

From there you invite the rest of your team from inside the app.

The mobile apps ask for your server's address on first launch, so give your users the same URL you set in `FEDERFALL_APP_URL`.

## The admin dashboard

PocketBase ships an admin dashboard at `/_/`. You do not need it for normal operation: the database schema is fixed by the image and the settings above are applied from the environment.

It is there if you want it — to browse data, read logs or make a manual fix.
A dashboard login (a PocketBase *superuser*, which is not the same as an app supervisor) is created on demand:

```bash
docker compose exec app pocketbase superuser upsert you@yourdomain.tld <password>
```

If you never use the dashboard, you can block `/_/` at your reverse proxy and forget about it.

## Updating

Pull the latest code and rebuild:

```bash
git pull
docker compose -f docker-compose.yml up -d --build
```

Database migrations are applied automatically when the new container starts.
To move to a newer PocketBase, bump `PB_VERSION` in the root `Dockerfile` and the image tag in `docker-compose.yml`, then run the same command.

## Sign-in options

Two extra sign-in features are available beyond email and password.

**Two-factor authentication** is opt-in per user. Anyone can turn it on from their profile in the app; once on, signing in asks for a one-time code sent to their email after the password. It needs SMTP (see [Mail](#mail)) — without it the code can't be delivered. Nothing to configure on the server side; it is on offer to every user out of the box.

**OAuth2** lets people sign in through an external provider instead of a password. The capability is enabled, but no providers are registered by default — that part is yours to set up. Add a provider (its client id and secret) in the admin dashboard under the `users` collection's auth settings. Once registered, it becomes available as a sign-in option.

## Finder data retention

A finder — the person who brought a bird in — is stored with their contact details so a carer can follow up.
Once their cases are closed there is no longer a reason to keep that personal data, so a daily job anonymises finders whose cases all ended longer ago than a retention window.
It clears the identifying fields (name, organisation, phone, email and the free-text notes) and keeps the rest, including the location, so you still know where birds tend to come from without holding anyone's personal data.

The window defaults to two years.
You can change it per organisation by setting `finder_retention_years` in the organisation's settings.

## Backups

All persistent state — the SQLite database and uploaded photos — lives in the `pb_data` Docker volume.
Backing that volume up is enough to capture everything.

PocketBase also has its own backup feature in the admin dashboard, which can produce and restore snapshots and can be put on a schedule.
Whichever you use, restore a backup into a throwaway instance at least once.
A backup you have never restored is a guess, not a backup.
