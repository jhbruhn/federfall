# Federfall

Federfall is a case-management app for a feral-pigeon rehabilitation association — a *Taubenhilfe-Verein*.
When the association takes in an injured or orphaned pigeon there is a fair amount to keep track of: where the bird was found, its weight and condition over time, treatments and medication, markings so it can be recognised again, handoffs between carers, and how the case ends — released back to the wild or placed in an aviary.
Federfall keeps all of that in one place.

It is meant to be self-hosted and has no Big-Tech dependencies.
The app is written in Flutter and runs on the web, Android and iOS.
The backend is [PocketBase](https://pocketbase.io) — a single Go binary with a SQLite database — and the whole thing runs as one Docker container.
Maps and address lookup use OpenStreetMap rather than Google.

## Repository layout

This is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces) monorepo:

```
federfall/
├─ Dockerfile              # single-container image (PocketBase + Flutter web app)
├─ docker-compose.yml      # the stack (+ docker-compose.override.yml for dev)
├─ apps/
│  └─ federfall/           # the Flutter app
├─ packages/
│  ├─ federfall_models/    # shared domain models + PocketBase record mappers
│  └─ federfall_data/      # repositories over the PocketBase API
├─ backend/
│  └─ pocketbase/          # migrations, hooks and rule tests (the committed schema)
└─ docs/                   # documentation
```

## Running it locally

From the repository root:

```bash
docker compose up
```

That builds and starts everything on `http://localhost:8090` — PocketBase serving the API, the admin dashboard and the Flutter web app together.
The development override creates a supervisor account for you, so you can log in straight away.

For UI work it is nicer to run the app on the host with hot reload, pointed at that same backend:

```bash
cd apps/federfall
flutter run --flavor development \
  --target lib/main_development.dart \
  --dart-define-from-file=dart_defines/development.json
```

## Self-hosting

To run your own instance, see [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).
It is one container with a reverse proxy in front for HTTPS, configured through environment variables.

## License

Federfall is licensed under the [GNU AGPL-3.0](LICENSE).
This is a network-copyleft license: if you run a modified version as a service, you have to share your changes.
That fits a tool meant to be self-hosted and shared between associations.
