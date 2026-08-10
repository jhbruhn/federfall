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
# From the REPO ROOT — this is a pub workspace, so the root run covers the app
# AND both packages. Running `flutter analyze` inside apps/federfall analyses
# the app only, which is how 9 issues once shipped in federfall_data.
flutter analyze            # MUST be clean — CI uses very_good_analysis (strict)
dart format --output=none --set-exit-if-changed .

# From apps/federfall:
flutter run --flavor development --target lib/main_development.dart \
  --dart-define-from-file=dart_defines/development.json
flutter test               # widget/unit tests
flutter gen-l10n           # regenerate l10n after editing lib/l10n/arb/*.arb
dart run build_runner build  # regenerate riverpod (.g.dart) + freezed (.freezed.dart)

# Packages (pure Dart) — `dart analyze` here hangs/crashes the analysis server;
# the root `flutter analyze` above is their lint gate:
cd packages/federfall_data && dart test
cd packages/federfall_models && dart run build_runner build && dart test
```

**Codegen is required, not optional.** After editing:
- an `.arb` file → run `flutter gen-l10n` (config is `l10n.yaml`; CLI args are ignored).
- a `@riverpod` provider or a `@freezed` model → run `dart run build_runner build`
  (note: the `--delete-conflicting-outputs` flag was removed; just `build`).
Generated `*.g.dart` / `*.freezed.dart` / `lib/l10n/gen/*` are gitignored and rebuilt.

**Quality gates before committing, all from the repo root:**
`dart format --output=none --set-exit-if-changed .` clean, `flutter analyze` clean (it
covers the packages — a subdirectory run does not), and `flutter test` green from
`apps/federfall` plus `dart test` for any touched package. Run a suite so its OWN exit
code survives — piping it through `grep` reports the filter's status and has hidden real
failures here. `flutter test --coverage` on the app
must stay above 75% (CI's `min_coverage` gate in `.github/workflows/ci.yml`, hand-written
code only — generated files are excluded); check before committing if you touched
`apps/federfall/lib/`.

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
(case `status`, animal `lifetime_status`). They also enforce the invariants rules
*cannot* express, because a plain field reference in an UPDATE rule resolves against
the STORED record (1700000043's finding): `org_scope.pb.js` + `lib_org_scope.js`
reject ANY relation naming a row in another org (federfall-jo1l — it folded in the
`animal`-only `animal_org_scope.pb.js`, is registered for every collection rather
than a list, and asks the SCHEMA which relations are org-scoped: a target
collection carrying an `org`. Hook-only collections — both rules null, e.g.
`aviary_stays` — are out of scope, a record whose own `org` is unset falls back to
its parent case's (`exams`), and it only fires when a field actually changes, so
pre-existing rows pointing at a hard-deleted animal stay saveable). Its scope is
restated in `test_rules.py`'s `[relation guards]` registry, which fails BOTH ways:
a `hook:org_scope.pb.js` classification naming a target the hook does not look at,
and a plain `mutable:` one naming a target it does. **Deletion is supervisor-only
and cascades:** `animals.delete` / `cases.delete` are `SUP`-gated in
1700000010, `cases.animal` cascades since 1700000057, and every `case` relation
already did — so deleting an animal takes its cases and their whole timeline
with it, while `weights` / `markings` / `egg_records` are animal-level and
survive a *case* delete. Hooks that reconcile a parent on delete must tolerate
that parent being gone (`main.pb.js`'s disposition reconcile) — it runs
`onRecordAfterDeleteSuccess`, so throwing there turns a committed delete into a
400 rather than rolling anything back. That cascade is also why
`merge_animals.pb.js` must re-point EVERY collection with a direct `animal`
relation (cases / markings / weights / exams / egg_records / aviary_stays)
before it deletes the duplicate: one left out is not left behind, it is
destroyed inside the merge transaction and answered with a 200 (federfall-0ua6
— `egg_records` and `aviary_stays` were both added after that list was written).
`test_rules.py`'s `[animal merge]` block is the guard, and the merge screen's
own moves summary lists the same collections. Note also that the survivor is
saved ONCE there: after-success hooks are deferred to the commit and re-read the
same record object, so two saves deliver two transitions off one stale
`original()` — which is how one aviary move opened two residencies.
**A bird's state has ONE derivation** (`pb_hooks/lib_derive.js`), shared by every
writer — the disposition create/update/delete hooks, `merge_animals.pb.js`, and the
three case events in `main.pb.js` §2c. It is the LATEST EVENT across two kinds:
dispositions ordered by `COALESCE(NULLIF(disposed_at,''), created)` (federfall-sinp,
the expression `case_summaries` and `case_report_rows` always used) weighed against
the latest admission of a still-OPEN case, `COALESCE(NULLIF(admitted_at,''), created)`
(federfall-8f1m). A later admission means `in_care` — that is what stops a returning
bird reading "Released" through its whole second stay — while an open case dated
EARLIER changes nothing, or one case somebody forgot to close would pin a bird to
`in_care` forever. `current_aviary` never follows a case event (a case decides whether
the bird is in care, never where it lives), so `lifetime_status = in_care` WITH an
enclosure is a legitimate, reachable pair: the dashboard's aviary tile therefore counts
`current_aviary`, not the label. Because that ordering decides `current_aviary`, which
since 1700000077 is a custody pointer, `disposition_dates.pb.js` refuses a
`disposed_at` more than a day in the future (federfall-j163) — a day, not an instant,
because the client sends its own clock's UTC and may sit at UTC+14. **Two guards close
the routes back INTO a stale carer's custody**, because `active_carer` of a disposed
case never expires: `case_status.pb.js` refuses a `status` that would contradict the
case's outcome (a case with a disposition is disposed, one without is not — so
re-opening means deleting the outcome, the correction path that already re-opens it,
federfall-epkf), and `disposition_custody.pb.js` refuses a disposition write that would
change the animal's derived `current_aviary` (or, on delete, re-open its case) unless
the writer holds the bird — or nobody else does once that row is set aside AND the write
does not end with the bird in the writer's own care (federfall-mpm4). That second branch
is what keeps correcting your own outcome possible, and it asks about the DESTINATION
because setting a placement row aside always answers "nobody holds it", for an honest fix
and a grab alike; the predicate is `lib_custody.js`'s `requireOutcomeWrite`, and it asks
`lib_derive.js`'s `prospectiveAviary` what the pending write would derive. Both are
`*Request` hooks, so the server-side writers and the Admin UI stay exempt.
Multi-record writes are atomic server-side:
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
**`cronAdd` jobs are invisible to that suite** (nothing can trigger them): `finder_retention`
(PII scrub + deletion of finders no case references), `geocodeCachePurge` and
`idempotencyKeyPurge`. Verify one by copying `pb_hooks` to a tempdir, rewriting its schedule
to `* * * * *`, and running a throwaway container against that copy —
`tests/run_cron.sh` + `test_cron.py` do exactly that for `auditRetention` and are the
template for the rest (one `sed` line per job). Kept out of `run.sh`/CI because it waits for
a wall-clock minute boundary. A window measured in days cannot be reached by backdating
(`created` is a server-owned autodate), so the test makes the window vanishingly small
(`0.000001` days = 86 ms) instead. Assert per-org windows, not just one: the window is read
from a JSON field, i.e. through the `getString()`+`JSON.parse` trap
(federfall-jumi), and a single-org test cannot tell a working settings read from a broken one.

**Case timeline pattern:** every clinical record (weight, condition, medication +
administration, journal, marking, placement, disposition) is one unified chronology. Each
kind = a provider + a `showXSheet()` bottom sheet (create/edit) + a tile built on the shared
`TimelineItem` + a sealed `_Event` subclass in `case_timeline.dart`. The case detail is a
name-first header over Overview / History tabs. See
`federfall-ui-prefers-unified-consistent-views` memory — favor one consistent view over
fragmented sections.

**Long lists filter server-side and page by cursor** (federfall-trep): no screen reads a
collection to narrow it on the device. The case browser and the animals registry both follow
the audit log's shape — a pure query object → `filterFor()` → `PbReadOnlyRepository.page()`
(keyset, never `?page=`, because the thing being read grows while it is read) → a feed
notifier with `loadMore`/`retryPage` → a scroll listener plus the shared `PagedListTail`.
Consequences: search fields are debounced (~300 ms) because a keystroke is a request; the
empty state tells "nothing yet" from "no matches" by whether the QUERY narrows anything, not
by counting loaded rows; the filter pickers read the small vocabulary views
(`animal_species`, `condition_labels`) rather than the loaded page; and the animals registry
pages by `+name,+id`, i.e. in SQLite's BINARY collation, so its order is case-sensitive in a
way the old `toLowerCase()` compare was not. Two facets do not survive translation intact
and are documented where they are built (`PbCasesRepository.filterFor`): a back-relation
cannot be constrained twice (two clauses match independently), so a marking-code search
deliberately matches removed markings too; and `dispositions_via_case.type ?= x` is a
SUPERSET of "its terminal disposition is x", so `CaseBrowseFeed` narrows the page it gets
back with `terminalDispositionByCase` — which is what keeps the outcome facet agreeing with
`case_report_rows` and the statistics screen. The "active" split is an explicit status set
(`in_care || ready_for_release || ""`) rather than `status != "disposed"` — because the
facet IS a set and names the statuses it wants, not because `!=` is untrustworthy:
federfall-jt5u probed that against a live 0.39.8 and cleared it (the 25-vs-24 that started
the doubt was an org-blind count of a carer who also held a case in another org).
`test_rules.py`'s `[case browser filters]` block pins all of it against a live PocketBase,
including that a carer's widened scope still returns nothing of another carer's.

**The audit log stores snapshots, never relations** (federfall-qt96 / by7w / ybua):
`audit_events` is append-only (no write rules; a tamper guard in 1700000068 blocks even a
superuser UPDATE) and supervisor-only, emitted exclusively from `pb_hooks/lib_audit.js` —
`emit()` never throws, so a failed log cannot break the write it observes. Everything a
reader sees is TEXT captured at emit time: `actor_label`, `subject_label`, `case_label`, and
`from_label`/`to_label` on a relation-valued change. That is deliberate and the app must not
"improve" it by resolving an id — the target may be deleted, and if it was renamed since, a
live lookup would change what the row says about the past. So **an id in an audit row is a
bug unless a label sits beside it**: `RELATION_TARGETS`/`RELATION_FIELDS` + `labelOf()` cover
the relations, and `detail` payloads carry `*_label` next to each id. Values stay WIRE
strings (`"in_care"`), translated on the way out in
`features/admin/audit/audit_labels.dart` — the server has no business picking the reader's
language. Two guards keep it honest: `test_rules.py`'s sweep fails on an event too empty to
be worth reading and on an action outside the registry, and `audit_labels_test.dart` parses
`CONTENT_FIELDS` out of `lib_audit.js` and fails on any recorded field that renders as its
raw column name in either language. Adding an action or a field is additive — an older client
renders an unknown one from the envelope alone — so it ships as `feat:`, not `feat!:`.
**Never log finder PII**: `SENSITIVE.finders` must stay in step with
`finder_retention.pb.js`'s `PII_FIELDS`, or the scrub is defeated by a table nothing can
delete from.

**Reporting is server-side, and the table is defined once** (federfall-dk0c): the
`case_report_rows` view (1700000063 + 1700000066 + 1700000067) IS the annual report's
per-case table. `pb_hooks/annual_report.pb.js` reads it for BOTH outputs of
`GET /api/federfall/reports/annual` — the Typst PDF (`typst/annual_report.typ`: portrait
summary + landscape case list) and, via `?format=csv`, the same columns as a spreadsheet —
so the two cannot drift. Its `markings` column is evaluated **at each case's own end** (the
terminal disposition, or now while open), not on `is_active`: a row must say what that bird
carried at release — including a ring it arrived wearing and kept — and must not print a
ring from a *later* admission or drop one removed after release. There is deliberately no
separate markings roster; the column is the record. Nothing on the summary page is
truncated (no top-N), so a long breakdown simply continues in its column. `?year=` selects the cases **admitted** in that calendar year
(the intake cohort, boundaries in the caller's zone via `?tzOffsetMinutes=`); omitting it
reports everything. The app just picks a period and a format
(`features/statistics/annual_report_sheet.dart`) and hands the bytes to the share sheet —
there is deliberately no client-side CSV encoder any more. Because the CSV has no template
to translate in, `typst/shared_strings.json` holds the column titles + the `caseStatus` /
`disposition` label maps, read by the hook AND merged into `report_common.typ`'s `STRINGS`;
it is the one place in `pb_hooks/` that localizes anything. `tests/run.sh` bind-mounts
`typst/` (the image is cached by tag, so a template edit would otherwise go untested).

**The statistics screen and the annual report are one implementation** (federfall-nmwi):
`pb_hooks/lib_stats.js` owns the period (`?year=` + `?tzOffsetMinutes=` → caller-local
boundaries), the `case_report_rows` read, and every aggregate. `annual_report.pb.js` and
`stats.pb.js` (`GET /api/federfall/stats`, coordinator/supervisor, the whole statistics
screen in one payload) both `require()` it — a required module is the ONE thing isolated
hook handlers can share, so this is how "2026" is made to mean the same instant range in
the PDF and on screen (`test_rules.py` asserts a New Year's Eve admission lands in the same
year for both). Consequences worth keeping: the app aggregates **nothing** client-side any
more (no `computeStatistics`; `statisticsProvider` is a fetch, and both the screen and the
export sheet drive one `PeriodSelector` off `statisticsPeriodProvider`); outcome **rates**
are shares of ENDED cases, never of intakes, and are null — not 0 % — while nothing has
ended; the diagnosis breakdown is period-scoped there, unlike the org-wide
`condition_labels` view the case browser's facet still reads. `stats.pb.js` loads the org's
rows once and partitions in JS so the comparison period, the selected one and `intakeYears`
cost one query. The period is `?year=` plus an optional `?month=` (a month without a year is
refused — it names no period): buckets follow it (days / months / years), and the comparison
is always the SAME period a year earlier, never the one before, because seasonality is the
question a rehab asks. The report route takes `?month=` too and titles itself
*Monatsbericht* rather than *Jahresbericht* for one. **Pie/donut colours are capped at three
hues + a neutral "Other"** (`ui/widgets/breakdown_pie.dart`): a pie is an all-pairs form, and
three hues is what clears CVD/normal-vision/contrast against BOTH surfaces — light and dark
are separately validated steps, not a flip. Do not add a fourth hue; the card's rows below
the chart carry every category and its exact count.

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
- **One function renders every date** (federfall-yok0): `MaterialLocalizations` and intl's
  `DateFormat` format the fields they are handed and do **not** convert time zones, while
  every PocketBase timestamp arrives UTC — so `materialL10n.formatMediumDate(c.admittedAt)`
  prints the UTC calendar day, which in CET/CEST is the *previous* day for anything after
  22:00 UTC. It fails invisibly on a UTC-clocked dev machine and CI. So `formatLocalDate`
  (`ui/widgets/date_field.dart`, with `DateStyle.medium`/`.short` and `withTime:`) is the
  only place in `lib/` that turns a `DateTime` into a date string: it converts first, and
  `toLocal()` is idempotent, so form state and picker results pass through it unchanged and
  no call site has to know which kind it holds. `date_field_test.dart` sweeps `lib/` and
  fails on any other Material date formatter, and on any `DateFormat…format(x)` statement
  lacking `toLocal()` — a `DateTime(…)` built inside the same statement is exempt, which is
  what lets the charts keep formatting `DateTime(2000, month)` for a month name.
- **Fonts are bundled, never downloaded** (federfall-sbtx): web has no system fonts —
  CanvasKit/skwasm resolves a codepoint no loaded font covers by fetching a per-glyph Noto
  slice from `fonts.gstatic.com`, which `web_headers.pb.js`'s CSP blocks and the engine then
  **retries on every layout of that text** (one `→` in an ARB string produced an endless
  console error stream on a deployed instance). So `assets/fonts/` holds Roboto plus Noto Sans
  Symbols / Symbols 2 / Color Emoji (COLRv1 — what the engine's own slices use), declared in
  `pubspec.yaml`. Declaring them is only half of it: the engine tests coverage against the
  families a `TextStyle` names, so they must ALSO be in `AppTheme.fontFamilyFallback`
  (`test/theme/app_theme_fallbacks_test.dart` pins both halves). Roboto itself covers only 923
  codepoints — arrows, `✓`/`★`/`⚠` and emoji come from those fallbacks — so a new non-ASCII
  character in an ARB string is only safe if the bundled set covers it; CJK/Arabic/Indic are
  not bundled (~12 MB) and still render as boxes on web.
- **PocketBase JSVM gotcha:** each hook route handler / `onRecord*` callback runs in an
  isolated context — **file-level helpers/consts are NOT in scope inside a handler**. Define
  everything a handler needs inside it (expect `ReferenceError` otherwise). That isolation is
  also why one route serves two output formats where the payload is shared (`case_report.pb.js`
  branches on `?widthDots=`, `annual_report.pb.js` on `?format=`) — two routes could not share
  the gathering code.
- **Reading a VIEW collection from a hook** (federfall-dk0c): PocketBase only infers a view
  column's type when it traces back to a real collection field. A plain `c.status` is typed;
  anything computed (`COALESCE(...)`, `group_concat(...)`) falls back to type **`json`**, and
  `getString()` on a json field returns the raw JSON — `"Hohltaube"` *with* the quotes. The
  REST API decodes that on the way out, so only a server-side reader sees it, and it fails
  quietly: a date won't parse, an enum won't match its label map, a CSV formula guard inspects
  `"` instead of `=`. Ask the collection which fields are `json` (`field.type()`) and decode
  those — do not sniff per value, a city legitimately named `true` parses as JSON too.
- **Reading a JSON FIELD from a hook** (federfall-jumi) — the same trap outside views:
  `record.get("settings")` hands JS a `types.JSONRaw`, i.e. a **byte array**, not a decoded
  object. `settings.someKey` is therefore always `undefined` and the code falls through to
  its default in silence. Passing `get()`'s value straight back to Go
  (`e.json(200, rec.get("response"))`) is fine — JSONRaw marshals correctly; only property
  access in JS is broken. It had silently disabled the org-configurable windows in
  `finder_retention.pb.js` and `main.pb.js`, so **`organisations.settings` now has exactly
  one reader**: `pb_hooks/lib_org.js` (`settingsOf` / `positiveNumber` / `flag`) — go through
  it rather than writing a fifth `getString()`+`JSON.parse`. Both windows it once broke are
  covered now: the quarantine default in `test_rules.py`, the finder scrub in `test_cron.py`
  (a cron, so `run_cron.sh` makes it due every minute — it now rewrites BOTH retention
  schedules).
- **Build-time config** (`AppEnvironment`): `POCKETBASE_URL`, `MAP_TILE_URL`,
  `MAP_ATTRIBUTION` come from `dart_defines/<flavor>.json` as compile-time constants — they
  need a rebuild, not hot reload (a stale build silently falls back to defaults).
- **Map source is runtime, not build-time** (federfall-el1f): the `MAP_*` defines are only a
  fallback. `/api/federfall/info` may carry a `map` block (`FEDERFALL_MAP_MODE` +
  the URL for that mode + `FEDERFALL_MAP_ATTRIBUTION`, optionally `_ATTRIBUTION_URL` /
  `_API_KEY`) and it wins. Read the effective values from `mapConfigProvider` /
  `MapConfig`, never `AppEnvironment.map*` directly. Three invariants: the block is
  **all-or-nothing** (mode+URL+attribution, else `info.pb.js` drops it with a warning —
  a half-applied override credits the wrong provider, which is a licensing problem, and
  there is no per-mode default attribution to fall back to); `web_headers.pb.js`
  **derives** the CSP origins from the same `FEDERFALL_MAP_*` URLs, so a prescribed source
  can't be blocked by the policy that server sent (`FEDERFALL_MAP_TILE_ORIGINS` remains for
  sprite/glyph hosts on another origin, and replaces the two shipped defaults);
  and `MapTileLayer` is **keyed on the resolved config** because the vector path reads its
  style in `initState` — the router only awaits `serverInfoProvider` on the
  *unauthenticated* path, so a warm start can build a map before `/info` lands and the
  layer has to be replaced, not updated in place. `apiKey` is served over an
  unauthenticated endpoint, i.e. deliberately public (documented in `info.pb.js`).
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
- **The major version IS the app↔server wire contract.** App and backend ship from this one
  repo under a single release-please version, so a client and a server interoperate exactly
  when their majors match (minor/patch may differ in either direction). Therefore: **any change
  that breaks the wire contract MUST be a breaking Conventional Commit** (`feat!:` / `fix!:` or
  a `BREAKING CHANGE:` footer) — that is what bumps the major and forces the update. Breaking
  means a changed request/response shape on a `/api/federfall/*` hook route, a removed or
  renamed collection field the app reads, a newly required field, or an access-rule tightening
  that rejects a call an older client still makes. Adding optional fields or new routes is not
  breaking. Conversely, do NOT mark purely internal Dart refactors breaking (a
  `federfall_models` enum rename is wire-safe — enums carry a `wire` value precisely so it is):
  the major bump would force every user to update for nothing. Note `0.x` is treated as an
  ordinary major here, so the first wire-breaking commit cuts `1.0.0`
  (`bump-minor-pre-major: false`, pinned explicitly in `release-please-config.json`).
  Enforcement is `lib/core/server/server_compatibility.dart` vs `/api/federfall/info`'s
  `version`: the login screen replaces every sign-in control with an update notice on a
  mismatch, and the message names whichever side must move (an auto-updated APK ahead of its
  container is the common case for self-hosters — telling *that* user to update the app is a
  dead end). It fails **open** — unreachable `/info`, an unversioned dev build on either side
  (`0.0`), or an unparseable version never blocks. `minClient` is derived server-side from the
  running major (`<major>.0.0`); `FEDERFALL_MIN_CLIENT` overrides it upward for a floor *within*
  a major. It is not hand-maintained — it was hardcoded `1.0.0` through the whole 0.x line,
  i.e. above every client that existed.
- **Releases** (`.github/workflows/release-please.yml`): version is driven by Conventional
  Commits via release-please — never hand-bump `apps/federfall/pubspec.yaml`'s `version:` or
  create tags manually. Merging the standing release PR tags `vX.Y.Z`, then builds/pushes the
  Docker image to `ghcr.io/<repo>` (tags `latest`/`vX.Y.Z`/`vX.Y`/`vX`) and attaches signed
  release APKs to the GitHub Release: a universal (fat) `federfall-<v>-universal.apk` plus
  per-ABI `-arm64-v8a`/`-armeabi-v7a` splits (built in a second `flutter build apk
  --split-per-abi` pass; x86_64 split is skipped, the universal covers it). Flutter offsets the
  per-ABI versionCode (armeabi-v7a→1xxx, arm64-v8a→2xxx) and its legacy override wins over an
  AGP `onVariants` reset, so the offset stays — Obtainium users should keep their APK filter on
  ONE variant (cross-variant switches like arm64→universal read as a downgrade). The image build
  is split across `docker-build` (a matrix:
  amd64 on `ubuntu-latest`, arm64 on the native `ubuntu-24.04-arm` runner — no QEMU, since this
  repo is public those hosted arm64 runners are free) and `docker-merge` (stitches both digests
  into one multi-arch manifest via `docker buildx imagetools create`). Provenance/SBOM
  attestation is deliberately NOT enabled here — it complicates digest-based merge — so if you
  need it back, that has to be re-added per-leg and merged too, not just flipped on. The `android`
  job requires the `ANDROID_KEYSTORE_*` repo secrets — it fails loudly on the Gradle signing step
  if they're missing, rather than skipping silently. The image gets `FEDERFALL_VERSION` baked in
  as a build-arg → runtime env; `info.pb.js` reads it
  via `$os.getenv` and reports only `major.minor` on the unauthenticated `/api/federfall/info`
  endpoint (patch withheld to avoid fingerprinting). Local/dev builds never set that build-arg,
  so they report `"0.0"` — expected, not a bug. `MIN_CLIENT` in `info.pb.js` stays a manually
  bumped policy value (oldest client build still served), independent of the release version.
