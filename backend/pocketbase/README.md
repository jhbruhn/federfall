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

## First superuser (admin login)

On first launch, create one (or use the setup screen at `/_/`):

```bash
docker compose exec app pocketbase superuser upsert admin@federfall.local <password>
```

Note: a PocketBase **superuser** (Admin UI) is not an app-level **Supervisor**. The first
app Supervisor must be bootstrapped separately (see the deployment guide).

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
