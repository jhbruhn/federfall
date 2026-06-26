# Federfall

Case-management app for a feral-pigeon rehabilitation association (*Taubenhilfe-Verein*).
Track admissions, treatment history, markings/re-identification, handoffs between carers,
and dispositions (wild release vs. placement in a named aviary) — securely, self-hosted,
with **no Big-Tech dependencies**.

- **Frontend:** Flutter (Web, Android, iOS) — MVVM + Repository, Riverpod, go_router, freezed.
- **Backend:** self-hosted [PocketBase](https://pocketbase.io) (SQLite), **fully containerized** — Docker Compose for both local dev and deploy (no host binary/systemd).
- **Maps/geocoding:** OpenStreetMap tiles + Nominatim (no Google).
- **App id:** `de.jhbruhn.federfall`

## Repository layout

This is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces) monorepo:

```
federfall/
├─ Dockerfile              # unified single-container image (PocketBase + Flutter web SPA)
├─ docker-compose.yml      # root stack (+ docker-compose.override.yml for dev)
├─ apps/
│  └─ federfall/            # Flutter app (very_good_cli scaffold)
├─ packages/
│  ├─ federfall_models/     # shared freezed models + RecordModel mappers
│  └─ federfall_data/       # repository interfaces + PocketBase implementations
├─ backend/
│  └─ pocketbase/           # pb_migrations/, pb_hooks/, rule tests (committed schema)
├─ docs/
│  ├─ REQUIREMENTS.md       # source-of-truth specification
│  └─ IMPLEMENTATION_PLAN.md# phased build plan + dependency graph
├─ AGENTS.md / CLAUDE.md    # instructions for AI coding agents
└─ .beads/                  # issue tracker (internal)
```

## Getting started

```bash
# Whole app, from the repo root — PocketBase serves the API, Admin UI and the
# Flutter web SPA on http://localhost:8090:
docker compose up

# Or run the Flutter app on the host for UI hot-reload (against that backend):
cd apps/federfall && flutter run --flavor development \
  --target lib/main_development.dart \
  --dart-define-from-file=dart_defines/development.json
```

## Documentation

- [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) — vision, data model, roles, access control, GDPR.
- [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) — phases, tasks, dependencies, milestones.

## License

[GNU AGPL-3.0](LICENSE) — a network-copyleft license fitting a self-hosted, openly-shared
association tool: anyone who runs a modified version as a service must share their changes.
