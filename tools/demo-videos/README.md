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
| `list` | Lists the videos. |

Environment (compose passes these through):

| Variable | Effect |
|---|---|
| `FFDEMO_TILES=offline` | Never fetch a map tile; a tile missing from the cache is drawn plain. |
| `FFDEMO_NO_SANDBOX=1` | Force Chromium's/OpenScreen's sandbox off. Normally decided automatically (see "Docker"). |

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
2. **Seed.** `harness/lib/seed.mjs` as the superuser: names the organisation,
   translates the code lists into the run's language, creates one account per
   role. Then the video's own `setup()`.
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
  signInAs: 'carer',              // supervisor | coordinator | carer | carer2
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

Every video starts on a **fresh backend** and gets the base
(`harness/lib/seed.mjs`, `harness/data/base.mjs`): the organisation
(„Wildvogelhilfe Elbmarsch"), its code lists in the run's language, and the
people — Johanna Brandt (supervisor, bootstrapped by the backend itself),
Malte Riedel (coordinator), Lena Vogt and Tarek Aydin (carers). All fictional;
addresses use `.example`. Then `setup({ seed, locale })` adds what the video
needs and may return data the steps read as `s.data`.

`seed.as(role)` is an API client signed in as that person; `seed.su` is the
superuser; `seed.intakes(role, [...])` admits birds through the real intake
route. Rules for new helpers (the demo dataset, federfall-1h9z.3, plugs in
here):

- Go through the routes whose hooks derive state (intake, dispositions,
  placements), as the person who would do it. Use the superuser only for what
  no client may write (accounts, the organisation).
- Code lists are database rows, seeded German by the migrations. Every list a
  video shows needs its English labels in `CODE_LISTS`, or the English video
  shows German chips. A row without a translation fails the setup.
- Free text a viewer reads (species, notes) needs a `de` and an `en` value.

### Viewports

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
