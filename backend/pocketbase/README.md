# Federfall — PocketBase backend (containerized)

Self-hosted [PocketBase](https://pocketbase.io) **v0.39.4**, run entirely via Docker —
no host binary, no `.env` files. Orchestration lives in the **repo-root compose stack**
(`../../docker-compose.yml` + `../../docker-compose.override.yml`); this directory only
holds the committed schema (migrations + hooks) and the backend rule tests.

The whole app ships as a **single container**: PocketBase serves the REST/Realtime API,
the Admin UI (`/_/`) **and** the built Flutter web SPA (from `/pb/pb_public`, with SPA
index-fallback) on one origin. The image is built by the unified **repo-root
`Dockerfile`** (`../../Dockerfile`), which has two targets:

- `--target backend` — lean PocketBase image (binary + migrations + hooks, no web).
  Used by the rule tests (`tests/run.sh`).
- default (`full`) — `backend` plus the production Flutter web bundle. What the compose
  stack ships, for both dev and production.

## Layout

```
backend/pocketbase/
├─ pb_migrations/      # schema migrations (.js) — COMMITTED, baked into image
├─ pb_hooks/           # JS hooks (*.pb.js)     — COMMITTED, baked into image
├─ pb_data/            # SQLite DB, uploads, logs — gitignored (dev bind mount)
└─ tests/              # backend rule/hook tests (need a live PB — see run.sh)
```

## Run locally (dev) — from the repo root

```bash
docker compose up --build      # full app on http://localhost:8090
docker compose logs -f app
docker compose down
```

`docker compose up` auto-merges `docker-compose.override.yml`, which builds the same full
image as production but relaxes the runtime for dev: it bind-mounts `pb_migrations/` +
`pb_hooks/` + `pb_data/` and turns automigrate **on** — so hooks hot-reload and Admin-UI
schema changes are written back as `.js` files to commit. For UI hot-reload, run the
Flutter app on the host with `flutter run` (the dev flavor points `POCKETBASE_URL` at
`localhost:8090`).

- Admin UI / setup: <http://localhost:8090/_/>
- Health check: <http://localhost:8090/api/health>
- REST/Realtime API base: <http://localhost:8090/api/>

### Testing OAuth2 / OIDC locally

To exercise the OAuth2 sign-in + self-registration flow without a real identity
provider, add the dev OIDC profile, which runs a throwaway mock OpenID provider:

```bash
docker compose -f docker-compose.yml \
               -f docker-compose.override.yml \
               -f docker-compose.oidc.yml up --build
```

Open <http://localhost:8090>, click "Continue with Mock SSO", and at the mock's
login enter any email — add `{"groups":["federfall-admins"]}` in the optional
claims to land as a supervisor, or leave it empty to land as a guest on the
pending screen. See `docker-compose.oidc.yml` for details.

## Run in production — from the repo root

```bash
docker compose -f docker-compose.yml up -d --build
```

Running the base file **explicitly** skips the dev override and builds the `full` image:
PocketBase serves the API, Admin UI and the Flutter SPA together on `:8090`. Migrations,
hooks and the web bundle are baked in (no bind mounts), automigrate is OFF (schema only
ever changes via committed migration files). The only persisted state is the `pb_data`
volume. Ship changes by rebuilding + recreating; pending migrations apply on startup.

> **TLS / compression are not in the stack.** Put your own reverse proxy
> (Caddy/Traefik/nginx) in front of host `:8090` to terminate HTTPS and add gzip +
> cache-control headers.

## PocketBase superuser (Admin UI) — optional

A PocketBase **superuser** logs into the Admin UI (`/_/`). It is **not** needed for normal
operation: the schema is migration-driven and settings are env-driven, and the app
authenticates against the `users` collection (see "First Supervisor" below). Create one
only when you want the dashboard for maintenance (browse data, logs, manual fixes):

```bash
docker compose exec app pocketbase superuser upsert you@yourdomain.tld <password>
```

Leaving zero superusers is safe: first-superuser creation is gated behind a one-time
installer token PocketBase prints to the server log (`/_/#/pbinstall/<token>`), so an
exposed `/_/` can't be claimed without it. For extra hardening, block `/_/` at your
reverse proxy if you never use the Admin UI.

## First Supervisor (app login)

A superuser is **not** an app-level **Supervisor** — it has no org/role and can't send
invites or own cases. Registration is invite-only and invites are sent *by* a supervisor,
so the first one is a chicken-and-egg that must be created out-of-band. Two ways:

- **Recommended — from env.** Set `FEDERFALL_SUPERVISOR_EMAIL` +
  `FEDERFALL_SUPERVISOR_PASSWORD` (optional `…_NAME`) in `docker-compose.yml`.
  `pb_hooks/bootstrap_supervisor.pb.js` creates a supervisor (active, attached to the
  seeded org) on the next start — but only while no active supervisor exists, so it's
  idempotent and doubles as lockout recovery. Unset the vars once you're in.
  (The dev compose override sets dev credentials automatically.)

- **Manual runbook.** In the Admin UI → `users` → New record: set `email` + password,
  `role = supervisor`, `is_active = true`, `org = ` the seeded organisation
  (`org00000default`), and `verified = true`.

## Configuration (env vars)

PocketBase has no native env-based settings, so operator config is applied on boot by
hooks that read env vars (PocketBase's own recommended pattern — load settings in an
`onBootstrap` hook; see PB discussion #1551). Set these in the root `docker-compose.yml`
(no `.env` is shipped):

- **App URL + SMTP** (`pb_hooks/settings.pb.js`) — `FEDERFALL_APP_URL` sets the public
  origin used in email links (e.g. the password-reset link). SMTP stays OFF unless
  `FEDERFALL_SMTP_HOST` is set, then invite/password-reset mail can be delivered:
  `FEDERFALL_SMTP_HOST`, `…_PORT` (default 587), `…_USERNAME`, `…_PASSWORD`, `…_TLS`
  (`true` ⇒ implicit TLS / port 465), `…_SENDER_ADDRESS`, `…_SENDER_NAME` (defaults to the
  app name). Re-applied each start — change the env + restart to update. Secrets never
  touch the repo.
- **OAuth2 providers + password toggle** (`pb_hooks/settings.pb.js`) —
  `FEDERFALL_OAUTH2_PROVIDERS` is a comma list of provider names; each `<NAME>` reads
  `FEDERFALL_OAUTH2_<NAME>_CLIENT_ID` + `…_CLIENT_SECRET`, and a generic OIDC
  (`oidc`/`oidc2`/`oidc3`) also reads `…_DISPLAY_NAME`, `…_AUTH_URL`, `…_TOKEN_URL`,
  `…_USERINFO_URL`, `…_PKCE`. When set, env is the source of truth; leave it unset to manage
  providers in the Admin UI. `FEDERFALL_PASSWORD_AUTH=false` disables password sign-in
  (OAuth2-only).
- **OAuth2 self-registration** (`pb_hooks/oauth2_provisioning.pb.js`) — new OAuth2 users
  default to a walled-off `guest` role; the first user (no supervisor yet) becomes
  supervisor. With IdP groups, map them to roles via `FEDERFALL_OIDC_SUPERVISOR_GROUP` /
  `…_COORDINATOR_GROUP` / `…_CARER_GROUP` (claim name `FEDERFALL_OIDC_GROUPS_CLAIM`, default
  `groups`), and gate registration with `FEDERFALL_OIDC_ALLOWED_GROUPS`. The account is
  only marked `verified` when the IdP verified the email (`email_verified`);
  `FEDERFALL_OIDC_TRUST_EMAIL=true` trusts the claim from a vetted private IdP. NOTE the
  bootstrap race: with a provider configured and the server exposed before anyone signs
  in, the FIRST sign-in becomes supervisor — claim the instance first (see
  docs/DEPLOYMENT.md).
- **Geocoding proxy** (`pb_hooks/geocode.pb.js`) — `FEDERFALL_NOMINATIM_URL`,
  `FEDERFALL_GEOCODER_KEY`, `FEDERFALL_USER_AGENT`. Rate-limited per client IP via
  PocketBase's limiter: `FEDERFALL_GEOCODE_RATE_MAX` (default 30, `0` disables) per
  `FEDERFALL_GEOCODE_RATE_WINDOW` seconds (default 60).

Set by migration (committed, reproducible):

- `appName` → **Federfall** (`1700000029_app_branding.js`; PocketBase's default is "Acme").
  Shown in the Admin UI and the default email templates.
- The users password-reset email (`1700000030_reset_password_template.js`) — German, with
  its action URL pointed at the app route `{APP_URL}/auth/confirm-reset?token={TOKEN}`
  (PocketBase's default links to the Admin UI instead).
- Optional per-user MFA + OAuth2 enabled on `users` (`1700000032_mfa_otp_oauth2.js`):
  email-OTP second factor gated by the per-user `mfa_enabled` flag, and OAuth2 turned on so
  providers (above) can be registered.
- `guest` role + access-rule wall-off (`1700000033_guest_role.js`): a guest can authenticate
  but every collection rule excludes `role = "guest"`, so self-registered OAuth2 users have
  no access until a supervisor promotes them.

## Migrations & hooks

- **Dev:** both dirs are bind-mounted (via the override) so edits take effect without
  a rebuild. Automigrate is on — Admin-UI schema changes are written as `.js` migration
  files into `pb_migrations/` on the host; commit them. Hooks hot-reload.
- **Production:** the dirs are baked into the image and automigrate is off. There is no
  bind mount, so nothing on the host can shadow or drift from the committed schema. Ship
  changes by rebuilding the image; pending migrations apply on container startup.

## Backend rule/hook tests

```bash
backend/pocketbase/tests/run.sh
```

Builds the lean `backend` target, spins up a throwaway PocketBase, and runs the Python
assertion suite against it.

## Upgrading PocketBase

Bump the version in **two** places, then rebuild:

1. root `Dockerfile` → `ARG PB_VERSION=...`
2. root `docker-compose.yml` → `app.build.args.PB_VERSION` and the `image:` tag

```bash
docker compose -f docker-compose.yml up -d --build
```
