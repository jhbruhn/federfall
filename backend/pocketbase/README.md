# Federfall — PocketBase backend (containerized)

Self-hosted [PocketBase](https://pocketbase.io) **v0.39.4**, run entirely via Docker —
no host binary, no `.env` files. Orchestration lives in the **repo-root compose stack**
(`../../docker-compose.yml` + `../../docker-compose.override.yml`); this directory only
holds the image build + the committed schema.

## Layout

```
backend/pocketbase/
├─ Dockerfile          # pinned, multi-arch image; BAKES IN migrations + hooks
├─ .dockerignore
├─ pb_migrations/      # schema migrations (.js) — COMMITTED, baked into image
├─ pb_hooks/           # JS hooks (*.pb.js)     — COMMITTED, baked into image
└─ pb_data/            # SQLite DB, uploads, logs — gitignored (dev bind mount)
```

The full stack (this backend + the nginx/Flutter web frontend) is defined once at the
repo root. See the root `docker-compose.yml` header and `apps/federfall/web.Dockerfile`.

## Run locally (dev) — from the repo root

```bash
docker compose up backend      # PocketBase only, on http://localhost:8090
docker compose logs -f backend
docker compose down
```

`docker compose up` auto-merges `docker-compose.override.yml`, which (for dev)
publishes `:8090`, bind-mounts `pb_migrations/` + `pb_hooks/` + `pb_data/`, and turns
automigrate **on** — so hooks hot-reload and Admin-UI schema changes are written back as
`.js` files to commit. Run the Flutter app itself on the host with `flutter run` (the
dev flavor points `POCKETBASE_URL` at `localhost:8090`); the `web` nginx image is only
built in production.

- Admin UI / setup: <http://localhost:8090/_/>
- Health check: <http://localhost:8090/api/health>
- REST/Realtime API base: <http://localhost:8090/api/>

## Run in production — from the repo root

```bash
docker compose -f docker-compose.yml up -d --build
```

Running the base file **explicitly** skips the dev override. The backend image is then
self-contained: migrations and hooks are baked in (no bind mounts), automigrate is OFF
(schema only ever changes via committed migration files), and the container has no
published port — the nginx `web` service proxies `/api` and `/_/` to it under one domain.
The only persisted state is the `pb_data` volume. Ship changes by rebuilding + recreating;
pending migrations apply on startup.

## First superuser (admin login)

On first launch, create one (or use the setup screen at `/_/`):

```bash
docker compose exec backend pocketbase superuser upsert admin@federfall.local <password>
```

## Migrations & hooks

- **Dev:** both dirs are bind-mounted (via the override) so edits take effect without
  a rebuild. Automigrate is on — Admin-UI schema changes are written as `.js` migration
  files into `pb_migrations/` on the host; commit them. Hooks hot-reload.
- **Production:** the dirs are baked into the image and automigrate is off. There is no
  bind mount, so nothing on the host can shadow or drift from the committed schema. Ship
  changes by rebuilding the image; pending migrations apply on container startup.

## Upgrading PocketBase

Bump the version in **two** places, then rebuild:

1. `Dockerfile` → `ARG PB_VERSION=...`
2. root `docker-compose.yml` → `backend.build.args.PB_VERSION` and the `image:` tag

```bash
docker compose -f docker-compose.yml up -d --build
```

> Remaining production work (TLS in front of nginx, Litestream backups, SMTP) is tracked
> in `docs/IMPLEMENTATION_PLAN.md` FED-3.5 (beads `federfall-bak`).
