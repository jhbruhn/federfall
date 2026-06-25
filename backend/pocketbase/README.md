# Federfall — PocketBase backend (containerized)

Self-hosted [PocketBase](https://pocketbase.io) **v0.39.4**, run entirely via Docker —
no host binary, no `.env` files. All configuration is literal in `docker-compose.yml`
and the `Dockerfile`.

## Layout

```
backend/pocketbase/
├─ Dockerfile                  # pinned, multi-arch image; BAKES IN migrations + hooks
├─ docker-compose.yml          # production-safe BASE: image + pb_data only
├─ docker-compose.override.yml # LOCAL DEV ONLY: bind-mounts + automigrate (auto-merged)
├─ .dockerignore
├─ pb_migrations/      # schema migrations (.js) — COMMITTED, baked into image
├─ pb_hooks/           # JS hooks (*.pb.js)     — COMMITTED, baked into image
└─ pb_data/            # SQLite DB, uploads, logs — gitignored (Docker volume)
```

## Run locally (dev)

`docker compose up` auto-merges `docker-compose.override.yml`, which bind-mounts
`pb_migrations/` + `pb_hooks/` and turns automigrate on — so host edits hot-reload
and Admin-UI schema changes are written back as `.js` files to commit.

```bash
docker compose up --build      # build pinned image + serve on http://localhost:8090
docker compose down            # stop; pb_data/ persists on the host
docker compose logs -f         # follow logs
```

## Run in production

The image is self-contained: migrations and hooks are baked in (no bind mounts),
automigrate is OFF (schema only ever changes via committed migration files). Run
the base file **explicitly** so the dev override is NOT applied:

```bash
docker compose -f docker-compose.yml up -d --build
```

The only persisted host state is `pb_data/`. Rebuild + redeploy to ship new
migrations/hooks; they apply on startup.

- Admin UI / setup: <http://localhost:8090/_/>
- Health check: <http://localhost:8090/api/health>
- REST/Realtime API base: <http://localhost:8090/api/>

## First superuser (admin login)

On first launch, create one (or use the setup screen at `/_/`):

```bash
docker compose exec pocketbase pocketbase superuser upsert admin@federfall.local <password>
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
2. `docker-compose.yml` → `build.args.PB_VERSION` and the `image:` tag

```bash
docker compose up --build
```

> Deploy (VPS) uses the same image in a fuller Compose stack (Caddy auto-TLS +
> Litestream backups) — see `docs/IMPLEMENTATION_PLAN.md` FED-3.5.
