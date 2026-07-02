# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->


## Build & Test

Pub workspace: app in `apps/federfall`, packages in `packages/federfall_{models,data}`.

```bash
# From apps/federfall:
flutter run --flavor development --target lib/main_development.dart \
  --dart-define-from-file=dart_defines/development.json
flutter analyze            # MUST be clean — CI uses very_good_analysis (strict)
flutter test               # widget/unit tests
flutter gen-l10n           # regenerate l10n after editing lib/l10n/arb/*.arb
dart run build_runner build  # regenerate riverpod (.g.dart) + freezed (.freezed.dart)

# Packages (pure Dart):
cd packages/federfall_data && dart test && dart analyze
cd packages/federfall_models && dart run build_runner build && dart test
```

**Codegen is required, not optional.** After editing:
- an `.arb` file → run `flutter gen-l10n` (config is `l10n.yaml`; CLI args are ignored).
- a `@riverpod` provider or a `@freezed` model → run `dart run build_runner build`
  (note: the `--delete-conflicting-outputs` flag was removed; just `build`).
Generated `*.g.dart` / `*.freezed.dart` / `lib/l10n/gen/*` are gitignored and rebuilt.

**Quality gates before committing:** `flutter analyze` clean + `flutter test` green for
the app, and `dart analyze`/`dart test` for any touched package.

## Architecture Overview

Three layers (see `federfall-implementation-is-planned-in-beads-9-phase` memory for the plan):

- **`packages/federfall_models`** — immutable `freezed` domain models + `fromRecord`
  mappers from PocketBase `RecordModel`. Enums carry a `wire` value (the exact string PB
  stores) so Dart renames never break mapping. `GeoPoint.fromPb` treats `{lon:0,lat:0}` as null.
- **`packages/federfall_data`** — `PbRepository<T>` base over one collection: CRUD +
  `ClientException`→`RepositoryException`. **Online-only:** every read/write goes straight
  to the server (no local cache); a `networkTimeout` makes an unreachable server fail fast.
  File fields use
  `createWithFiles` / `updateWithFiles` (multipart) + `fileUrl(id, name, {thumb})`.
  Geocoding goes through `GeocodingRepository` (backend proxy), not a direct API call.
- **`apps/federfall`** — Riverpod codegen providers (`@riverpod`), `go_router`, feature
  folders under `lib/features/`. Repo providers in `lib/data/repository_providers.dart`
  bind each repo to the resolved `PocketBase` client.

**Backend** is fully container-based (see `federfall-backend-is-fully-container-based...`
memory): PocketBase with JS migrations (`backend/pocketbase/pb_migrations/*.js`, numbered,
committed) and hooks (`pb_hooks/*.pb.js`). Schema changes = new migration, never hand-edit.
Hooks own case-number/quarantine defaults, share-on-handoff, and disposition side-effects
(case `status`, animal `lifetime_status`). Multi-record writes are atomic server-side:
case intake goes through `POST /api/federfall/intake` (`pb_hooks/intake.pb.js`, one
transaction for animal+finder+case+weight+quarantine; `cases.finder` is locked against
direct client writes), and a handoff is just a placement with `to_user` — the hook derives
the `active_carer` change in the same transaction. Access rules in `1700000010_access_rules.js` are
the real security boundary (org-scoped, private-by-default + opt-in sharing). A migration
that copies the shared auth predicate MUST use the guest-safe form — append
`&& @request.auth.role != "guest"` (see `1700000045_guest_wall_refresh.js`; the guest sweep
in `test_rules.py` catches omissions). Rule tests are
Python (`backend/pocketbase/tests/test_rules.py`, run via `run.sh`) and **need a live PB** —
they can't run in the Flutter test suite, so verify migrations/hooks against a running stack.

**Case timeline pattern:** every clinical record (weight, condition, medication +
administration, journal, marking, placement, disposition) is one unified chronology. Each
kind = a provider + a `showXSheet()` bottom sheet (create/edit) + a tile built on the shared
`TimelineItem` + a sealed `_Event` subclass in `case_timeline.dart`. The case detail is a
name-first header over Overview / History tabs. See
`federfall-ui-prefers-unified-consistent-views` memory — favor one consistent view over
fragmented sections.

## Conventions & Patterns

- **Git:** commit directly on `main` (no feature branches); push only when asked — do NOT
  treat the beads "Session Completion" push step as automatic here (see
  `federfall-commit-directly-on-main` memory). End commit messages with the `Co-Authored-By` trailer.
- **Lint (very_good_analysis, strict — these bite):** 80-char lines; imports sorted
  alphabetically (`directives_ordering`); use Dart 3 null-aware elements — `'key': ?nullable`
  in maps, `?nullable` in lists — instead of `if (x != null)`; no redundant default args; no
  positional `bool` params; type non-obvious `static const`s; no unnecessary raw strings.
- **l10n:** every user-facing string lives in `app_en.arb` + `app_de.arb` (German is the
  primary UI language). Enum→label helpers in `features/cases/cases_labels.dart` (e.g.
  `admissionReasonLabel`), resolving `l10n` like `Validators` does.
- **PocketBase JSVM gotcha:** each hook route handler / `onRecord*` callback runs in an
  isolated context — **file-level helpers/consts are NOT in scope inside a handler**. Define
  everything a handler needs inside it (expect `ReferenceError` otherwise).
- **Build-time config** (`AppEnvironment`): `POCKETBASE_URL`, `MAP_TILE_URL`,
  `MAP_ATTRIBUTION` come from `dart_defines/<flavor>.json` as compile-time constants — they
  need a rebuild, not hot reload (a stale build silently falls back to defaults).
- **Geocoding** is proxied through PB hooks (`pb_hooks/geocode.pb.js`) for CORS + server-side
  rate-limiting; configurable via `FEDERFALL_NOMINATIM_URL` / `FEDERFALL_GEOCODER_KEY` /
  `FEDERFALL_USER_AGENT`. Public OSM Nominatim blocks server traffic and placeholder UA
  domains (e.g. `example.org`) — use a real contact or none, or self-host.
- **Tests:** widget tests override repo providers with `mocktail` mocks via
  `ProviderContainer(overrides: ...)`; inject the image picker via `imagePickerProvider`.
  Hide flutter_test's `Finder` when importing models (`import '...flutter_test.dart' hide
  Finder;`). `registerFallbackValue` for `<String,dynamic>{}` and `<MultipartFile>[]`. Fake
  image bytes throw "Invalid image data" — give `Image.memory` an `errorBuilder`; `XFile`
  `.name` can be empty in tests.
