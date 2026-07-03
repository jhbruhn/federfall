# Federfall

Federfall is a case-management app for a feral-pigeon rehabilitation association — a *Taubenhilfe-Verein*.
When the association takes in an injured or orphaned pigeon there is a fair amount to keep track of: where the bird was found, its weight and condition over time, treatments and medication, markings so it can be recognised again, handoffs between carers, and how the case ends — released back to the wild or placed in an aviary.
Federfall keeps all of that in one place.

It is meant to be self-hosted.
The app is written in Flutter and runs on the web, Android and iOS.
The backend is [PocketBase](https://pocketbase.io) — a single Go binary with a SQLite database — and the whole thing runs as one Docker container.
Maps and address lookup use OpenStreetMap.

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

## Usage

Federfall is organised around four tabs: **Dashboard**, **Cases**, **Animals** and **Aviaries**.
The dashboard shows your caseload — active cases, intakes this year, birds in aviary — and a worklist of what is due.
Everything else about a bird's stay lives on its case.

### Admitting a case

Tap the _+_ button on the Cases tab, or _Admit a case_ if your list is still empty, to start the intake wizard.
It walks you through the animal (species, name, or a search to re-link a bird that has been in before), the intake details (reason, age class, dates, find location, weight, quarantine days), and finally photos, notes and the finder's contact details, if you have them.
Confirm with _Create case_ and you land straight on the new case.

### The case timeline

A case is one merged, newest-first chronology of everything that happened to the bird — weight checks, exams, diagnoses, medication, markings, location changes, hand-offs, all in one place.
Add to it with the _Add entry_ button and pick whichever kind of event applies.

### Handing off a case

When another carer takes over, open _Hand off to carer_ from the timeline, pick who it goes to and when, and confirm.
You keep read access to everything that happens afterwards, but the case is now theirs to edit.

### Recording the outcome

When a case ends, use _Record outcome_ to say how: released back to the wild, placed in an aviary, transferred, returned to its owner, or — sometimes — died or was euthanised.
Once an outcome is recorded, the case is closed.

## Roles

Every user has one of four roles, assigned by a supervisor or mapped from an identity provider's groups (see [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)).

**Carer** (Pflegestelle) is the default role for anyone doing hands-on rehab work.
A carer can admit new cases and can see and edit any case where they are the active carer or where it has been shared with them.
Animals, markings and finder records are visible to every carer in the organisation — that's the shared identity layer re-identification depends on — but a case itself is private until it's yours or someone shares it with you.

**Coordinator** adds oversight on top of that: a coordinator can see every case in the organisation, not just their own, and manages aviaries.
Editing a case still requires being its active carer or having been given edit access, same as a carer.

**Supervisor** is the administrative role: supervisors invite and manage users, own the code lists (conditions), can edit or delete any record, and are the only ones who can promote someone else to supervisor.
The first supervisor is created from the environment on first start (see [First login](docs/DEPLOYMENT.md#first-login)).

**Guest** exists only for self-registration through OAuth2: a guest can sign in but sees nothing until a supervisor grants them a real role.

## Vibe Code Warning

For reasons of fairness and possibly also as a warning, be aware that almost all of the code in this project has been written using LLMs, specifically Claude Code.

That does not mean that the code is untested, bad or dysfunctional.
The backend access rules have a test suite, and the app has widget and unit tests.

This project wouldn't have happened in its current form without LLMs.
So, while LLMs are still being heavily oversold and the circular economy of the big AI companies is not exactly a healthy market IMO, they do still offer _some_ benefits.

## License

Federfall is licensed under the [GNU AGPL-3.0](LICENSE).
This is a network-copyleft license: if you run a modified version as a service, you have to share your changes.
That fits a tool meant to be self-hosted and shared between associations.
