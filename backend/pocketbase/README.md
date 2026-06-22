# Federfall — PocketBase backend (containerized)

Self-hosted [PocketBase](https://pocketbase.io) **v0.39.4**, run entirely via Docker —
no host binary, no `.env` files. All configuration is literal in `docker-compose.yml`
and the `Dockerfile`.

## Layout

```
backend/pocketbase/
├─ Dockerfile          # pinned, multi-arch (amd64/arm64) PocketBase image
├─ docker-compose.yml  # service + ports + volumes (config as literal values)
├─ .dockerignore
├─ pb_migrations/      # schema migrations (.js) — COMMITTED
├─ pb_hooks/           # JS hooks (*.pb.js)     — COMMITTED
└─ pb_data/            # SQLite DB, uploads, logs — gitignored (Docker volume)
```

## Run locally

```bash
docker compose up --build      # build pinned image + serve on http://localhost:8090
docker compose down            # stop; pb_data/ persists on the host
docker compose logs -f         # follow logs
```

- Admin UI / setup: <http://localhost:8090/_/>
- Health check: <http://localhost:8090/api/health>
- REST/Realtime API base: <http://localhost:8090/api/>

## First superuser (admin login)

On first launch, create one (or use the setup screen at `/_/`):

```bash
docker compose exec pocketbase pocketbase superuser upsert admin@federfall.local <password>
```

## Migrations & hooks

- **Automigrate (dev):** enabled by default. Schema changes you make in the Admin UI
  are written as `.js` migration files into `pb_migrations/` on the host — commit them.
- **Hooks:** drop `*.pb.js` files into `pb_hooks/`; they hot-reload in dev.
- Both directories are bind-mounted into the container, so edits on the host take
  effect without rebuilding the image.

## Upgrading PocketBase

Bump the version in **two** places, then rebuild:

1. `Dockerfile` → `ARG PB_VERSION=...`
2. `docker-compose.yml` → `build.args.PB_VERSION` and the `image:` tag

```bash
docker compose up --build
```

> Deploy (VPS) uses the same image in a fuller Compose stack (Caddy auto-TLS +
> Litestream backups) — see `docs/IMPLEMENTATION_PLAN.md` FED-3.5.
