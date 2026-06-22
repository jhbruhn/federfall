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
├─ apps/
│  └─ federfall/            # Flutter app (very_good_cli scaffold)
├─ packages/
│  ├─ federfall_models/     # shared freezed models + RecordModel mappers
│  └─ federfall_data/       # repository interfaces + PocketBase implementations
├─ backend/
│  └─ pocketbase/           # Dockerfile, docker-compose.yml, pb_migrations/, pb_hooks/, seed data
├─ docs/
│  ├─ REQUIREMENTS.md       # source-of-truth specification
│  └─ IMPLEMENTATION_PLAN.md# phased build plan + dependency graph
├─ AGENTS.md / CLAUDE.md    # instructions for AI coding agents
└─ .beads/                  # bd (beads) issue tracker — run `bd ready`
```

> The `apps/` and `packages/*` Dart packages are created in subsequent Phase-0 tasks
> (FED-0.2 scaffolds the app + pub workspace, FED-0.4 adds core dependencies).

## Getting started

> Full setup lands incrementally through Phase 0 (see `docs/IMPLEMENTATION_PLAN.md`).

```bash
# Issue tracker — what to work on next
bd ready

# Backend (after FED-0.5): run a local PocketBase in Docker
cd backend/pocketbase && docker compose up

# App (after FED-0.2): run the Flutter app
cd apps/federfall && flutter run --flavor dev --dart-define-from-file=dart_defines/dev.json
```

## Documentation

- [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) — vision, data model, roles, access control, GDPR.
- [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) — phases, tasks, dependencies, milestones.

## License

[GNU AGPL-3.0](LICENSE) — a network-copyleft license fitting a self-hosted, openly-shared
association tool: anyone who runs a modified version as a service must share their changes.
