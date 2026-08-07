# Federfall

Federfall is a case-management app for a feral-pigeon rehabilitation association — a *Taubenhilfe-Verein*.
When the association takes in an injured or orphaned pigeon there is a fair amount to keep track of: where the bird was found, its weight and condition over time, treatments and medication, markings so it can be recognised again, handoffs between carers, and how the case ends — released back to the wild or placed in an aviary.
Federfall keeps all of that in one place.

It is meant to be self-hosted.
The app is written in Flutter and runs on the web, Android and iOS; its interface is German.
The backend is [PocketBase](https://pocketbase.io) — a single Go binary with a SQLite database — and the whole thing runs as one Docker container.
Maps and address lookup use OpenStreetMap data.

## Installation

Federfall is a server plus a client, and the server comes first — the app has no offline mode, so it needs an instance to talk to.
Running one is a single container behind a reverse proxy: see [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).

That same container serves the web app, so once it is up, everyone can simply open its URL in a browser.
That is the least-effort way to use Federfall and it needs nothing installed.

For Android there are signed APKs on the [releases page](https://github.com/jhbruhn/federfall/releases/latest): a universal build plus smaller per-ABI splits (`arm64-v8a` for anything recent, `armeabi-v7a` for older phones).
If you take updates through [Obtainium](https://github.com/ImranR98/Obtainium), keep its filter on one of those variants — switching between them reads as a downgrade and the install fails.
There is no iOS download; that one you build and sign yourself.

The mobile apps ask for your server's address on first launch.

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
│  └─ pocketbase/          # migrations, hooks, report templates and rule tests
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

The backend's own development notes — schema migrations, hooks, the rule tests and a mock identity provider for trying OAuth2 locally — are in [`backend/pocketbase/README.md`](backend/pocketbase/README.md).

## Usage

Federfall is organised around four sections: **Dashboard**, **Cases**, **Animals** and **Aviaries**.
On a phone they are a bottom bar; on a tablet or a desktop browser they become a side rail and each list sits beside whatever you have opened.
The dashboard shows your caseload — active cases, intakes this year, birds ready for release, birds in aviary — over a preview of what is due today.
Each of those figures taps through to the list behind it.
Everything else about a bird's stay lives on its case.

### Admitting a case

Tap the _+_ button on the Cases tab, or _Admit a case_ if your list is still empty, to start the intake wizard.
It walks you through the animal (species, name, or a search to re-link a bird that has been in before), the intake details (reason, age class, dates, find location, weight, quarantine days), and finally photos, notes and the finder's contact details, if you have them.
Confirm with _Create case_ and you land straight on the new case.

### The case timeline

A case is one merged, newest-first chronology of everything that happened to the bird.
Weight checks, physical examinations, conditions and diagnoses, prescriptions and every dose given, markings, eggs laid, moves between locations, hand-offs, quarantine, scheduled rechecks and free-text journal notes all share the one list.
Add to it with the _Add entry_ button and pick whichever kind of event applies.

An examination records the vitals you always take, and below that a by-system findings checklist you can leave alone.
Nothing in it is required — only the systems you actually assessed are stored.

### Medication

A prescription says what the bird gets, how much, and how often.
The dose is either a flat amount or a rate per kilogram of body weight.
With a rate, Federfall works the actual dose out from the bird's latest weight, so the dose for a growing fledgling follows it up on its own.
Logging a dose that went as prescribed is one tap.

Supervisors can keep a drug catalogue for the organisation, so the preparations you reach for most come with their dosing prefilled and a prescription is a couple of taps.

On Android and iOS the app can also notify you when a dose is due, once you enable reminders in your profile.

### What is due

The _Today_ list is derived rather than maintained: it collects medication that is due, rechecks that have come around, quarantines about to end, and cases nobody has touched in a while.
It is ordered by when things came due, so whatever is furthest overdue sits at the top, and it is the same list the dashboard previews.

### Sharing a case

A case is private to its carer.
To let someone else in, open the sharing sheet from the case and grant an org member read or edit access; you can change or revoke that later.
Only the active carer and supervisors can share a case.

### Handing off a case

When another carer takes over, open _Hand off to carer_ from the timeline, pick who it goes to and when, and confirm.
You keep read access to everything that happens afterwards, but the case is now theirs to edit.

### Recording the outcome

When a case ends, use _Record outcome_ to say how: released back to the wild, placed in an aviary, transferred, returned to its owner, or — sometimes — died or was euthanised.
Once an outcome is recorded, the case is closed.

### Animals

Cases are episodes; the animal is the record that outlives them.
Linking a returning bird to its existing record at intake keeps its whole history together — earlier stays, every weight, its markings and any eggs — which is the point of the re-identification search.
When two records turn out to be the same bird after all, a supervisor can merge them.

### Aviaries

The aviary registry holds each aviary with its keeper, location and capacity.
An aviary shows who currently lives in it and keeps its own flock-care chronology — journal entries for the aviary plus a health rollup of its residents.
Everyone can look; coordinators and supervisors manage them.

### Reports and printing

Any case can be turned into a PDF report — the full chronology, rendered server-side, with a QR code that opens the case again in the app.
The same report also comes as a narrow slip for thermal receipt printers, which you can send straight to an ESC/POS printer over the network, Bluetooth or USB — handy for a slip that travels with the box.
Pair that with a hardware barcode scanner (Android) and scanning the slip opens its case.

Coordinators and supervisors also get statistics for the whole organisation: outcomes, intakes by species, the conditions recorded, average time in care, and a map of where birds were found.
For an annual report, the case list exports as CSV.

## Roles

Every user has one of four roles, assigned by a supervisor or mapped from an identity provider's groups (see [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)).

**Carer** (Pflegestelle) is the default role for anyone doing hands-on rehab work.
A carer can admit new cases and can see and edit any case where they are the active carer or where it has been shared with them.
Animals, markings and finder records are visible to every carer in the organisation — that's the shared identity layer re-identification depends on — but a case itself is private until it's yours or someone shares it with you.

**Coordinator** adds oversight on top of that: a coordinator can see every case in the organisation, not just their own, manages aviaries, and sees the statistics.
Editing a case still requires being its active carer or having been given edit access, same as a carer.

**Supervisor** is the administrative role.
Supervisors invite and manage users, edit or delete any record, merge duplicate animals, and are the only ones who can promote someone else to supervisor.
They also own everything under the management hub: the organisation's settings and its code lists — conditions, admission reasons, marking types, medication routes and the drug catalogue — so the vocabulary the forms offer is the association's own, not the app's.
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
