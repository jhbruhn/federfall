# Demo videos

Scripted walkthroughs of the Federfall web app, recorded in German and English
and polished into short phone-format clips. One script per video drives the
real production build in a headless-but-real browser; the screen is captured,
and [OpenScreen](https://github.com/getopenscreen/openscreen) (v2.2.2, pinned by
checksum) adds the cursor, zooms, on-screen titles and burned-in captions.
Everything runs in containers: no host browser, no host display, no host
toolchain beyond docker or podman.

```sh
# from the repo root — record A3 in German
podman compose -f tools/demo-videos/compose.yaml run --rm record A3 --locale de
# both languages, every video
docker compose -f tools/demo-videos/compose.yaml run --rm record all
# afterwards (the backend keeps running between `run`s)
podman compose -f tools/demo-videos/compose.yaml down -v
```

Clips land in `tools/demo-videos/out/` as `<id>-<slug>.<locale>.mp4`
(`A3-first-intake.de.mp4`), 1080×1920 H.264.

**No compose provider?** `tools/demo-videos/nocompose.sh A3 --locale de`
runs the same two images with the same mounts and environment through plain
`podman` (or `ENGINE=docker`). It builds the images first unless
`FFDEMO_SKIP_BUILD=1`.

**Did it work?** Check `out/last-run.json` (`"ok": true`) — not only the exit
status. Some compose wrappers (podman-compose 1.5.0, measured in federfall-1h9z.1)
exit 0 when the container failed. A failed video never leaves a clip under its
final name: an older clip of that name is removed.

## Commands

Everything after `record` (the compose service) or after `nocompose.sh` is
passed to the harness. A first argument that is not a command means `record`,
so `run --rm record A3` and `run --rm record record A3` are the same:

| Command | What it does |
|---|---|
| `record <ID…\|all> [--locale de,en]` | Records and exports. Default: both languages. |
| `record … --no-export` | Records only (capture, cursor track, OpenScreen document in `out/work/`). |
| `export <ID…\|all> [--locale …]` | Re-renders the last capture with the current look/document code, without driving the app again. For tuning the look. |
| `check [--locale de,en] [--times N]` | Seeds the demo dataset from scratch N times per language, asserts its derived state (`harness/lib/verify.mjs`) and compares fingerprints. No recording. |
| `list` | Lists the videos. |

Environment (compose passes these through):

| Variable | Effect |
|---|---|
| `FFDEMO_TILES=offline` | Never fetch a map tile; a tile missing from the cache is drawn plain. |
| `FFDEMO_NO_SANDBOX=1` | Force Chromium's/OpenScreen's sandbox off. Normally decided automatically (see "Docker"). |
| `FFDEMO_RUN_DAY=YYYY-MM-DD` | The day the demo dataset is relative to (default: today, Europe/Berlin). Only a day in the past works (a disposition may not be dated in the future), and the app's own clock does not move — use it to compare seedings, not to record. |

## Output

```
out/
  A3-first-intake.de.mp4      the clips (only ever complete, only from a passing run)
  last-run.json               verdict, per-clip status, error, timings, tile cache stats
  work/A3.de/                 everything of the last A3/de run:
    run.log                   what happened, step by step
    capture.mp4               the raw x11grab capture (824×1600)
    capture.mp4.cursor.json   cursor track for OpenScreen
    timeline.json             steps with their times, boxes, zooms, narration
    project.openscreen        the generated OpenScreen document
    export.mp4                OpenScreen's render (copied to out/ on success)
    failure.png               on failure: the screen at that moment
    failure-semantics.txt     on failure: every node Playwright could see
  .cache/tiles/               map tile cache (see "Map tiles")
backend.log                   nocompose.sh only, on failure: the backend's log
```

## How the pieces fit

```
compose.yaml / nocompose.sh
├─ backend   localhost/ffdemo-federfall:local — the repo's own Dockerfile (full
│            target: PocketBase + migrations + hooks + the web build in
│            /pb/pb_public). Entrypoint replaced by backend/serve.sh, which
│            serves a THROWAWAY data dir and wipes it on request.
└─ record    localhost/ffdemo-studio:local — runner/Containerfile. Joins the
             backend's network namespace, so the app is http://localhost:8090
             (a secure context: skwasm's cross-origin isolation works).
             /demo = this directory (read-only), /arb = the app's ARB files,
             /out = out/.
```

Per video and language, the harness (`harness/`):

1. **Fresh backend.** Writes the current generation to the shared control
   volume; `serve.sh` stops PocketBase, copies a pristine migrated data dir
   into place and starts it again. The runner waits for that itself — it never
   relies on compose to order anything.
2. **Dataset.** The video's `dataset` (`base` or `demo`, see "Data") is
   seeded through the API on the first video of each language, saved by
   `serve.sh` as a template, and handed to every later video of that language
   as a fresh copy (`harness/lib/dataset.mjs`). Then the video's own `setup()`.
3. **Stage.** Xvfb at exactly the viewport's device-pixel size; Chromium headed
   in app mode at 0,0 (no tabs, no address bar, no window manager), so the X
   screen *is* the viewport. Semantics are switched on by clicking Flutter's
   off-screen "Enable accessibility" placeholder from JS — the production build,
   unchanged.
4. **Capture.** `ffmpeg -f x11grab -draw_mouse 0`, 30 fps. Steps run; clicks
   move the real X pointer (xdotool), so hover states are real; typing goes
   through Playwright's keyboard at a readable pace.
5. **Document.** The capture and script clocks are aligned on their common end,
   then `harness/lib/openscreen.mjs` writes the cursor sidecar and an OpenScreen
   document (schemaVersion 9): frame-pinned titles, zooms, and a transcript
   written from the narration, which OpenScreen burns in as captions.
6. **Export.** `openscreen export` on Mesa lavapipe (no GPU), then the clip is
   copied to `out/` under its final name.

Stand-ins served by the runner on the shared loopback
(`harness/lib/services.mjs`): a fixed-answer geocoder on :8091 (the backend's
geocode proxy points at it) and the map tile cache on :8092.

## Writing a video

A video is one file in `videos/`, default-exporting `defineVideo({...})`. The
file name does not matter; the `id` does. `videos/a3-first-intake.mjs` is the
worked example — read it next to this section.

```js
import { defineVideo, signIn } from '../harness/video.mjs';

export default defineVideo({
  id: 'B4',                       // matches the beads issue title ("Video B4: …")
  slug: 'markings',               // → B4-markings.de.mp4
  title: { de: 'Markierungen', en: 'Markings' },   // shown at the start
  viewport: 'phone',              // or 'desktop' (C7 only)
  dataset: 'demo',                // base (default) | demo — see "Data"
  signInAs: 'carer',              // supervisor | coordinator | carer | carer2 (| guest in demo)
  assets: ['pigeon.svg'],         // files from assets/ to prepare before recording
  setup: async ({ seed, locale }) => { /* see "Data" */ },
  steps: [
    ...signIn({ title: { de: 'Anmelden', en: 'Sign in' } }),
    {
      name: 'open the bird',      // for logs and error messages
      title: { de: 'Der Vogel', en: 'The bird' },   // optional on-screen heading
      say: {                       // optional caption, per language
        de: 'Kurze Sätze. Einer pro Gedanke.',
        en: 'Short sentences. One idea each.',
      },
      zoom: { depth: 3 },          // optional; aims at the step's focus
      run: async (s) => {
        await s.click(s.role('tab', s.t('navAnimals')));
        await s.waitFor(s.textbox('animalsSearchHint'));
      },
    },
  ],
});
```

### A step

A step does something, then **holds** so a viewer can follow. Its duration is
the longest of: what `run` takes; `run` plus `hold` (default 700 ms); the
caption's reading time (about 62 ms per character, at least 1.8 s); `minMs`.
Each step has a timeout (`timeoutMs`, default 30 s); the whole run has one too
(`maxMs`, default 8 min).

- `title` — on-screen text in the band above the app. It stays until the next
  step with a title, so give the first step on a new screen one.
- `say` — the narration, burned in as captions below the app. Long text is
  split into lines at sentence breaks. Write it like a calm product
  walkthrough: short sentences, present tense, `du` in German. German is the
  primary language — write it first and make it idiomatic; do not translate
  English word for word. A value may be a function of `t` to quote a UI label
  exactly: `(t) => `„${t('caseCreateAction')}“ speichert alles.``.
- `zoom` — `{ depth }` (OpenScreen's 1–6 = 1.25×–5×; 3 = 1.8× is the
  sensible maximum for the phone source, see "Look"). The zoom lasts the whole
  step and aims at `s.focus(…)` if the step called it, else at the last thing
  the step clicked or typed into. So keep a zoomed step on one screen: put the
  "Next" click that leaves it into the following step.

### Finding things: labels by ARB key

The browser sees Flutter's semantics tree: roles (`button`, `textbox`,
`checkbox`, `tab`, `menuitem`, …) with accessible names. **Scripts never spell
a UI string.** They name the ARB key and the harness reads the label from
`apps/federfall/lib/l10n/arb/app_<locale>.arb` (ICU placeholders, `plural` and
`select` are rendered: `s.t('caseStepLabel', { current: 1, total: 3 })`). One
script serves both languages, a reworded label is followed automatically, and
a removed key fails the run at lookup.

| Locator | Use for |
|---|---|
| `s.button('authSignInAction')` | a button by its label — or an icon button by its tooltip |
| `s.textbox('authEmailLabel')` | a text field by its label (or its hint, if it has no label) |
| `s.buttonStartingWith('caseFieldAgeClass')` | a node whose name carries more, e.g. a dropdown (`"Altersklasse\nAltvogel"`) |
| `s.role('menuitem', s.t('ageClassAdult'))` | any role, exact name |
| `s.role('button', 'Rathausmarkt 1,', { startsWith: true })` | a row whose text is DATA the video seeded |
| `s.id('case-detail-…')` | a `Semantics(identifier:)` — see the rule below |
| `s.pick({ de: …, en: … })` | this run's value of per-language data |

Data is not an ARB string. Code-list labels, species, names come from what
the run seeded (`harness/data/base.mjs`, the video's `setup()`), so the script
names them through the same constants it seeded them with.

**Semantics identifiers** are the exception, not the default. Add
`Semantics(identifier: '<screen>-<element>', child: …)` in the app (kebab-case,
e.g. `case-detail-photo`) only where a label cannot do the job:

1. the control has **no label** (icon-only, no tooltip);
2. the label is **ambiguous** — two widgets with the same name on one screen;
3. the text is **data-driven** — a row or tab whose name comes from records or
   carries extra text such as a count — and the video cannot know it in advance.

Do not tag a widget a label already reaches. Wrap at the federfall call site:
the shared widgets live in `zugvogel_ui` and are pinned by commit. App edits
put the repo's gates in force (`dart format`, `flutter analyze`,
`flutter test`). A3 needed no identifier.

### Actions

| Action | |
|---|---|
| `await s.click(loc)` | waits for it, scrolls it into view with the real wheel, moves the pointer onto it, clicks |
| `await s.type(loc, text, { clear })` | clicks, waits for Flutter's editor to take focus, types visibly |
| `await s.press('Enter')` | a key |
| `await s.chooseFile(loc, await s.asset('pigeon.svg'))` | clicks, answers the native file chooser (an `.svg` asset is rendered to JPEG first) |
| `await s.waitFor(loc)` / `s.gone(loc)` | the next screen is there / the old one is gone |
| `await s.waitForUrl(/re/)` | the app navigated |
| `await s.expectText('Paula')` | something on screen shows this text |
| `await s.focus(loc)` | the step's zoom aims here (no click) |
| `await s.rest({ x, y })` | move the pointer out of the way |
| `await s.hold(ms)` | wait on camera |
| `await s.dump('tag')` | authoring aid: `dump-tag.png` + every semantics node with its role/name/box in `out/work/<id>.<locale>/`. Remove when done — it costs time on camera. |

**End every step on proof.** A step that navigates should wait for something
only the next screen has (`waitFor`, `waitForUrl`, `expectText`). That is what
makes a wrong screen fail the run instead of becoming a video. Nothing is
retried: an action whose target is missing, ambiguous (two matches — strict
mode) or never visible fails the run with that locator in the message, plus a
screenshot and a semantics dump. A flaky step is a bug to find, not to retry.

### Data

Every video starts on a **fresh backend** holding one of two datasets, chosen
with `dataset:` in `defineVideo` (default `base`):

- **`base`** (`harness/lib/seed.mjs`, `harness/data/base.mjs`): the
  organisation („Wildvogelhilfe Elbmarsch"), every code list in the run's
  language, and the people — Johanna Brandt (supervisor, bootstrapped by the
  backend itself), Malte Riedel (coordinator), Lena Vogt and Tarek Aydin
  (carers). Nothing else: A3 needs an empty case list.
- **`demo`** (`harness/data/demo/`): base plus a lived-in organisation — see
  "Demo dataset" below. Every video except A3 should use it.

Then `setup({ seed, locale })` adds what the video needs and may return data
the steps read as `s.data`. It runs on a COPY, so what one video adds is
never seen by the next.

`seed.as(role)` is an API client signed in as that person (`supervisor`,
`coordinator`, `carer`, `carer2`, and in `demo` also `guest`); `seed.su` is
the superuser; `seed.intakes(role, [...])` admits birds through the real
intake route; `seed.demo` holds the ids of everything the demo dataset seeded
(`seed.demo.cases.fiete`, `seed.demo.animals.erna`, `seed.demo.aviaries.loft`,
`seed.demo.medications.fieteDeworm`, `seed.demo.sponsorships.albers`, …).
Rules for anything that seeds:

- Go through the routes whose hooks derive state (intake, dispositions,
  placements, the batch routes), as the person who would do it. Use the
  superuser only for what no client may write (accounts, the organisation).
- Code lists are database rows, seeded German by the migrations. Every list
  has its English labels in `CODE_LISTS`; a row without a translation fails
  the setup.
- Free text a viewer reads (species, notes, names of organisations) needs a
  `de` and an `en` value. German first, idiomatic; then English.
- Select rows by the names in `harness/data/demo/cast.mjs` (import them), not
  by spelling a name again.

## Demo dataset

`harness/data/demo/`: `cast.mjs` (names — the interface videos use),
`vocab.mjs` (species, places, drug catalogue, vaccines, vets), `stories.mjs`
(the showcase birds), `bulk.mjs` (the history), `index.mjs` (the engine and
one helper per kind of write), `clock.mjs` / `rng.mjs`. The check is
`harness/lib/verify.mjs` (`check` command).

**How it is built.** Stories and bulk do not write: they *schedule* each step
at the moment it happened in the story, as the person who did it ("Lena weighs
Fiete at 07:20 three days ago"), and the engine runs all ~1,500 steps in that
order — ~1,600 API writes, **~9 s** (measured, rootless podman). Running in
story order is what keeps case numbers chronological (they are assigned at
creation per year of admission) and the audit log in a plausible order.
Everything is relative to the run day; randomness is seeded, so the same run
day gives the same data (`check` prints a fingerprint to prove it, plus a
"structure" hash that must match between de and en).

**Paid once per run and language**, not per video: the first `demo` video of
a language seeds and `serve.sh` saves the data dir as template `demo-<locale>`;
every later video gets a copy (a reset costs ~0.5 s). A template remembers its
run day and is re-seeded if a run crosses midnight.

**The people.** As in base, plus **Sven Kröger**, a guest who signed up and is
waiting for a role (A2, C8). Lena is a carer *and* keeps the pigeon loft;
Malte keeps the outdoor aviary.

**Showcase birds** (12 open cases; everything else is closed):

| Bird | Held by | What it is for | Videos |
|---|---|---|---|
| **Fiete** (feral pigeon) | Lena | The full timeline: 13 weights (238 → 292 g), two exams with findings, trichomonosis (resolved) and worms (contagious), three microscopy samples with photos, canker course with Faucalin (done), **the running deworming course (Nemakur) 5 days on / 2 off ×3 with a dose due today**, journal with a photo and a PDF, colour clip applied and removed, an attended vet visit (PDF) and **an upcoming one with an attachment**, a follow-up due today, intake photo + finder, edit share with Tarek | A1, A4, B1–B4, B6, B7, B11, C1 |
| **Kora** (wood pigeon) | Lena | Admitted this morning: fresh intake, quarantine just started | A5, B5 |
| **Hedwig** (carrion crow) | Lena | **Quarantine ends today**, **vet appointment this afternoon**, pain-relief dose (Plumadol) due, X-ray (image + PDF) on an attended visit, fracture | A5, B5, B6 |
| **Gustav** (feral pigeon) | Lena | Released in spring wearing our ring **EM 0412**, back after a cat attack and recognised by it: reads *in care* again; antibiotic (Peravin) due tonight; follow-up today | B4, C3 |
| **Bruno, Lotte, Mats** (young feral pigeons) | Lena | One find, **one group course** (prescribe-batch), seven **dose rounds** logged, the next one due today | A5, C1 |
| **Mika** (blackbird) | Lena, from Tarek | **Handed over** (holiday cover): Tarek kept read access, sees the read-only badge | C2 |
| **Hinkebein** (feral pigeon) | Tarek; lives in Lena's loft | Resident with two **patronages**, now ill: Lena admitted him, handed the case to Tarek — *in care* AND in an enclosure; his carer cannot see the patronages, his keeper can | C2, C4, C5 |
| **Pieps** (house sparrow) | Tarek | **Ready for release** | A6, C3 |
| **Tilda** (feral pigeon) | Tarek | Suspected **ornithosis — notifiable and contagious**; 21-day quarantine; lab follow-up; laid an egg during the case | B2, B5, B8 |
| Ringo duplicate (racing pigeon, unnamed) | Malte | Second record of **Ringo** — same club ring **DV-DEMO-001** (deliberately not a valid club number), found with it, on both | B4, C11 |

**Closed showcase cases:** **Momo** (blackbird, released 3 days ago), **Oskar**
(buzzard, transferred to a raptor centre yesterday), **Wilma** (collared dove,
died the night after admission) — C3. **Ringo** (racing pigeon, returned to its
owner last year) — C11.

**Aviaries.** *Taubenschlag / Pigeon loft* (Lena): **Erna** (lays eggs — six
clutches, latest with a photo, swapped for dummy eggs; PMV primary + booster
and a pox shot), **Frieda**, **Hinkebein**; Ole lived here until his release.
*Außenvoliere / Outdoor aviary* (Malte): **Kalle** (crow), **Tjark** (jackdaw,
added straight to the aviary, no case), **Smilla** (magpie, placed 12 days ago
for flight training). Both have a flock log; residencies are dated to the
story. The loft was vaccinated in one act (vaccinate-batch) — C4, B9.

**Markings** (the station rings feral pigeons only): Gustav's release ring
and Fiete's colour clip (removed) — both feral pigeons; the club ring both Ringo
records arrived wearing, recorded as found with it.

**Patronages** (7): Hinkebein — Familie Petersen 15 €/month, Ilse Brockmann
50 € one-off; Erna — a nursery group 30 €/quarter **ending in the future**;
Kalle — Henrik Jansen 120 €/year; Tjark — a school class 5 €/month; Frieda —
Anke Lorenz 10 €/month, **ended**; Ole — Jonas Albers 20 €/month, still running
although **Ole was released** (no keeper can reach it). Totals: 6 running,
60,00 € a month, 50,00 € one-off — C5, C6.

**Vocabulary.** Every code list in both languages; the drug catalogue
with INVENTED product names, each with what it is for as its note:
Plumadol (pain relief), Peravin (antibiotic), Faucalin (against
trichomonads), Brontalis (antifungal), Nemakur (dewormer, 5 on / 2 off × 3),
plus a balanced electrolyte solution. Clean demo doses: every concentration
equals the rate, so the volume is 1 ml per kg. Vaccines are invented products
too (Sentinova PMV, Sentinova Pocken/Pox) against the real diseases; org settings (14-day quarantine, 24
months finder retention, contact details) — C9.

**History.** ~214 cases last year and ~236 this year up to four days ago (430
on the run day 2026-11-16), all closed: species weighted like an urban rescue
(feral pigeons first), spring/summer peak of orphans and swifts, outcomes and
stays by kind of bird, conditions per reason, find locations in public places
around Hamburg and neighbouring towns, a few more intakes than last year in
every month — C7, A6, the case browser and the registry.

**What data cannot fix** (all measured on screen):

- `created` is the server's clock. Every case's History tab shows a
  **"Case created / Fall angelegt" milestone dated today** (the app reads
  `cases.created`), and the case list never shows the "no activity for N days"
  note (it reads `updated`). The **audit log** is all today, within the minute
  the dataset was seeded (its rows read sensibly otherwise — real actors,
  real actions, in story order).
- **Time of day.** Dues are fixed times (doses at 07:00–09:00, Hedwig's
  appointment at 15:30). Recorded in the afternoon, Today shows those as
  "overdue by n h"; recorded early in the morning, some of "this morning's"
  entries lie in the future.
- `aviary_stays` is written by a hook with the server clock and has no client
  API; the seeder re-dates those rows as the superuser (unaudited by design) so
  residencies start when the story placed the bird.

**Departures from "the real actors"**, all in tools/demo-videos: the request
budgets are raised during seeding and restored before the template is saved
(the backend's own test suite does the same); the superuser re-dates
`aviary_stays` (above) and, as before, writes accounts and code-list labels —
in an English run those relabels appear in the audit log as the superuser's.

**Attachments** are placeholders drawn for this purpose:
`assets/demo-data/` (`manifest.json` says which file is used where and under
which name per language; `generate.mjs` regenerates them). Replace a file to
use a real photo — no code change.

**Per-video additions** belong in that video's `setup()`, not in the base
dataset.


## Viewports

`harness/lib/stage.mjs`, `VIEWPORTS`:

| | CSS px | DPR | Capture | Export |
|---|---|---|---|---|
| `phone` | 412×800 | 2 | 824×1600 | 1080×1920, 9:16 |
| `desktop` | 1280×720 | 1.5 | 1920×1080 | 1920×1080, 16:9 — **not yet recorded** |

## Look

Decided by looking at exported frames (`out/work/*/` + `ffmpeg -ss … -frames:v 1`):

- **9:16 at 1080×1920**, the phone footage centred with rounded corners and a
  shadow on a gradient in the app's greens. No phone bezel: OpenScreen's
  `phone` frame (tried in federfall-1h9z.2) shrinks the app further and adds
  nothing a viewer needs.
- **Bands above and below the app** (`padding: 70`, i.e. the footage at 72 % of
  the frame height). The title sits in the top band, the captions in the
  bottom band, so neither covers the app's own app bar or bottom buttons —
  with captions over the footage they hid the wizard's
  "Next" button. Titles carry a dark plate because a zoom enlarges the footage
  into the band.
- **412×800 at DPR 2.** 412 CSS px is a common Android width and gets the
  phone layout. 800 rather than 915 high because the footage is height-bound
  in the frame: a shorter source is drawn larger. At this size the footage is
  shown at ~0.86 output px per source px, so OpenScreen's 2× source-magnification
  cap allows ~2.3×; depth 3 (1.8×) zooms stay sharp. DPR 3 would allow deeper
  zooms at 2.25× the pixels for SwiftShader to render and x11grab to encode;
  not needed for depth 3.
- **Text**: Roboto (the app's own face), from the image, so every host renders
  the same.

All of it is `LOOK` in `harness/lib/openscreen.mjs`; `export <ID>` re-renders
without re-recording.

## Map tiles

The app's tile source is runtime configuration: the backend prescribes it via
`/api/federfall/info` (`FEDERFALL_MAP_*`) and derives its CSP from the same
variables. The stack points it at the runner's tile service on
`127.0.0.1:8092`, a read-through cache in `out/.cache/tiles`: a miss is fetched
once from `tile.openstreetmap.org` (identified by its User-Agent), after which
the run needs no network for tiles — A3 uses 18 tiles. With
`FFDEMO_TILES=offline` a miss is drawn as a plain tile instead, so a run cannot
reach the internet at all. For CI, cache `out/.cache/` between runs (and run
offline once it is warm). The attribution shown is OSM's, which matches the
tiles.

## Docker, podman, Windows

- **Rootless podman**: what all verification so far ran on.
- **Ownership**: the runner starts as root only to hand results to `out/` with
  the ownership of whoever owns that directory on the host — right for rootless
  podman (container root = you) and for rootful docker alike. The work itself
  runs as uid 1000.
- **Sandbox**: Chromium and OpenScreen keep their sandbox where the engine
  allows unprivileged user namespaces (rootless podman does). Docker's default
  seccomp profile does not; the entrypoint detects that, prints a notice and
  passes `--no-sandbox` — acceptable here, since all that is rendered is our
  own app and our own project file.
- **arm64**: OpenScreen ships amd64 only, so `record` is `platform: linux/amd64`
  (emulated on arm64 — slow). The `runner` stage of the Containerfile has no
  OpenScreen and is multi-arch.
- **Windows**: nothing host-specific is required beyond docker/podman with a
  Linux engine; `.gitattributes` keeps the shell scripts LF in a Windows
  checkout. Untested.

## Known limits

- OpenScreen's document format is upstream-unstable; it is pinned to v2.2.2.
  Bumping means re-checking `openscreen.mjs` against a document that version
  writes itself.
- Captions are laid out by OpenScreen: a line breaks where the harness leaves a
  pause, and OpenScreen wraps inside the caption box.
- The app's intake wizard pre-fills the species with the German default
  „Stadttaube" in every language; the English A3 clears it on camera, but it is
  visible for about a second.
- The intake photo is an illustration (`assets/pigeon.svg`), not a photograph.
- Not shown on the web: anything native (camera, notifications, the device
  calendar, printing).
- Apt packages in the runner image float with the base image's Debian release
  (the base itself is pinned by digest).
