# Mikroskopie — design

Structured microscopic analysis of a crop swab (*Kropfabstrich*) or a faecal
sample (*Kotprobe*), graded per finding (`+` / `++` / `+++`), with a
supervisor-configurable finding vocabulary, a record of who did the analysis
(in-house / vet / lab), and photo **or video** documentation.

Status: design, not yet implemented. Everything below is placed against the
conventions already in this repo; the "why" lines exist so the implementation
does not re-discover a trap the schema already stepped in once.

---

## 1. Domain shape

Three collections. This is `case_conditions` (code-list **or** free text)
crossed with `exams` + `exam_findings` (a parent with a sparse child set that is
replaced wholesale on save).

```
microscopy_finding_types     supervisor code list, per org, pre-seeded
      ▲
      │ finding_type (optional — the other path is free_text)
      │
microscopy_findings          one graded finding
      │ sample
      ▼
microscopy_samples           one examination of one sample
      │ case                  (no `animal` — §2.2)
      ▼
cases
```

### Why not one row with a multi-select

Because the grade is **per finding** — "Trichomonaden ++, Hefen +" is two
independent facts — and "Sonstiges" needs its own row carrying its own grade.
A multi-select cannot hold a value per selected option, and a `json` column
would put the clinical payload behind PocketBase's JSON-field trap
(federfall-jumi/dk0c: a hook reading it gets a byte array or a quoted string)
for no benefit.

### Naming trap worth stating before anything is written

`lib_audit.js`'s `RELATION_TARGETS` is keyed by **field name globally**, with
only a per-collection override table (`RELATION_FIELDS`) beside it. `exam` is
already taken by `exams`. So the child's parent relation is called `sample`,
never `exam` or `microscopy_exam`. Likewise the parent collection is
`microscopy_samples`, not `microscopy_exams`, so nobody reading a hook has to
work out which "exam" is meant.

---

## 2. Collections

### 2.1 `microscopy_finding_types` — the configurable vocabulary

| field | type | notes |
|---|---|---|
| `label` | text, required, presentable, max 200 | user-language (German UI), like `conditions.label` |
| `sample_types` | select, multi, maxSelect 2, `["crop_swab","fecal"]` | which sample kinds offer this finding |
| `description` | text, max 2000 | optional supervisor definition |
| `active` | bool | |
| `org` | relation → organisations, required | |
| `created` / `updated` | autodate | |

`sample_types` is the one field this list has beyond the shared
`{label, active}` shape, and it exists because the two lists the requirement
gives are **different but overlapping** — *Hefen* appears under both. One list
with an applicability flag beats two lists that must be kept in step, and it
means a supervisor adding "Kokzidien" once decides where it shows up.

**Seeded per org** (like 1700000039 does for `admission_reasons`), German
labels, all `active`:

| label | applies to |
|---|---|
| Trichomonaden | crop_swab |
| Hefen | crop_swab, fecal |
| Haarwurmeier | fecal |
| Spulwurmeier | fecal |
| Kokzidien-Oozysten | fecal |

Two things deliberately **not** in this list:

- **"Sonstiges"** — it is not a vocabulary entry, it is the `free_text` path on
  the finding row (exactly `case_conditions.free_text`). As a code-list row a
  supervisor could rename, deactivate or delete it, and the escape hatch would
  vanish.
- **"Ohne Befund"** — see §2.2. It is an assertion about the whole sample, not a
  thing that was found.

No clinical numbers are shipped, only names — the 1700000060 stance ("a bundled
formulary makes this repository the source of a figure that killed a bird")
does not bite here, because a vocabulary term carries no dosage.

> **Pre-existing gap this inherits:** nothing seeds code lists for an org
> created *after* a migration ran — no hook does it, and `conditions`,
> `admission_reasons`, `marking_types` and `medication_routes` all have the same
> hole today. A second org would start with empty lists. Worth its own issue;
> not this feature's job to fix, but the seed migration must not pretend
> otherwise in its comments.

### 2.2 `microscopy_samples` — one examination

| field | type | notes |
|---|---|---|
| `case` | relation → cases, required, cascadeDelete | |
| `sample_type` | select, required, `["crop_swab","fecal"]` | Kropfabstrich / Kotprobe |
| `method` | select, `["direct_smear","flotation"]` | Direktabstrich / Flotation — **fecal only**, cleared server-side otherwise |
| `examined_at` | date | drives timeline placement |
| `examined_by` | select, `["in_house","vet","lab"]` | the "was this done by a vet or lab, or not" requirement |
| `examiner` | relation → users | who looked down the microscope (in-house); `examiner` already resolves to `users` in `RELATION_TARGETS` |
| `external_lab` | text, max 200 | practice / lab name when `examined_by != in_house` |
| `no_findings` | bool | *ohne Befund* — a positive assertion |
| `attachments` | file, maxSelect 5, protected, MIME allowlist, thumbs `200x200` | photos **and** video — see §5 |
| `notes` | text, max 2000 | |
| `author` | relation → users | provenance |
| `org` | relation → organisations, required | |
| `created` / `updated` | autodate | |

**There is deliberately no `animal` field.** `exams` and `weights` denormalize
one so the animal lifetime view can aggregate across cases; that roll-up is not
wanted yet (§9), and without it the field is dead weight with a sharp edge —
every collection carrying a direct `animal` relation MUST be re-pointed by
`merge_animals.pb.js`, and one left out is not left behind, it is **destroyed**
inside the merge transaction and answered with a `200` (federfall-0ua6). Not
having the field removes that entire failure mode: a sample follows its case,
and the merge already re-points cases.

Adding it later is cheap and exactly backfillable — `sample.animal =
case.animal` — so this is a deferral, not a door closing. The four places that
would move with it are named in §7.

**`no_findings` is a boolean on the sample, not a code-list row.** Three
reasons: it is mutually exclusive with every finding (a row cannot express
that); it must never be renameable or deletable by a supervisor; and it gives
statistics/report a stable column to count instead of a label match. It is also
what separates the three states the workflow actually has:

| state | meaning |
|---|---|
| `no_findings = false`, no findings | **result pending** — sample taken and sent to the lab |
| `no_findings = true`, no findings | **ohne Befund** — looked, found nothing |
| `no_findings = false`, N findings | N graded findings |

The pending state is not decoration: with `examined_by = lab` it is the normal
state for a day or two, and collapsing it into "ohne Befund" would assert a
clean result that nobody has seen yet.

### 2.3 `microscopy_findings` — one graded finding

| field | type | notes |
|---|---|---|
| `sample` | relation → microscopy_samples, required, cascadeDelete | |
| `finding_type` | relation → microscopy_finding_types | **or** `free_text` |
| `free_text` | text, max 300 | "Sonstiges zum Selbst eintragen" |
| `severity` | select, required, `["plus","plus_plus","plus_plus_plus"]` | rendered `+` / `++` / `+++` |
| `org` | relation → organisations, required | |
| `created` / `updated` | autodate | |

`severity` wire values are spelled out rather than `"+"` / `"++"` / `"+++"`:
they end up in filter expressions, CSV cells and audit rows, where a bare `+`
is at best unreadable and at worst needs escaping. The Dart enum carries the
wire value as always, so renaming the Dart side stays free.

`severity` is **required** on a finding, because "ohne Befund" lives on the
sample — a finding that exists at all was found at some strength.

---

## 3. Access rules (migration `1700000073_microscopy.js`)

Case-private clinical, the `exams` stance verbatim: microscopy findings are
sensitive case detail, not the org-wide identity layer that `weights` and
`markings` sit in.

```
AUTH   = @request.auth.id != "" && @request.auth.is_active = true
         && @request.auth.role != "guest"          ← 1700000045, mandatory for
                                                     anything new; the guest
                                                     sweep in test_rules.py
                                                     fails without it
SUP        = @request.auth.role = "supervisor"
COORD_SUP  = (coordinator || supervisor)

samples view : AUTH && case.org = auth.org && (case.active_carer = auth.id
                || COORD_SUP || case.case_shares_via_case.shared_with ?= auth.id)
samples edit : AUTH && case.org = auth.org && (case.active_carer = auth.id
                || SUP || (share ?= auth.id && share.access ?= "edit"))

findings     : the same, traversing `sample.case` (grandchild, cf. exam_findings)
```

Three things the migration must get right **at creation**, because each is
otherwise a later repair migration that carries a hardcoded target list and
therefore would not cover a field added afterwards:

1. **Boundary guards inline** (the 1700000043 finding — a plain field reference
   in an UPDATE rule resolves against the *stored* record):

   ```
   microscopy_samples.updateRule  += && @request.body.case:isset = false
                                     && @request.body.org:isset = false
   microscopy_findings.updateRule += && @request.body.sample:isset = false
                                     && @request.body.org:isset = false
   ```

   `animal_org_scope.pb.js` needs no new entry, because there is no `animal`
   relation to re-point at another org's bird (§2.2). If the lifetime view is
   ever added, that hook gains an entry in the same commit as the field.

2. **File field born correct** — `protected: true` + `mimeTypes` + `thumbs`
   declared inline (1700000027 / 1700000048 / 1700000049 are each a repair pass
   for a field that shipped without one of the three).

3. **The code list is supervisor-managed**: `listRule`/`viewRule` org-scoped,
   `create`/`update`/`delete` supervisor-only, mirroring `medication_routes`.

`microscopy_finding_types.delete` should be allowed even while in use:
`finding_type` is optional on a finding (the free-text path exists), so
PocketBase will null it rather than refuse, and the finding keeps its severity.
That is the `conditions` behaviour, **not** `marking_types`' — so the admin
spec sets `deleteBlockedWhenInUse: false` (the default) and the confirm dialog
reports the reference count.

**Cascade consequences**, stated so nobody is surprised later: deleting a case
takes its samples and their findings; deleting an animal cascades through its
cases (1700000057) and so takes the samples too. Both are supervisor-only
already (1700000010).

---

## 4. Write path — `POST /api/federfall/microscopy`

One route, one transaction, mirroring `/api/federfall/exam` (federfall-lov0:
the exam sheet used to write parent-then-children as separate client calls, and
in an online-only app a network drop mid-sequence permanently lost the clinical
findings). Microscopy has exactly the same shape *plus* file uploads, so it is
multipart with `@jsonPayload`, the way `/api/federfall/intake` already does it.

**Request** (multipart: `@jsonPayload` + zero or more `attachments` files)

```jsonc
{
  "id": "…",                 // present → update; absent → create
  "case": "…",               // create only
  "sample": {
    "sample_type": "fecal",
    "method": "flotation",
    "examined_at": "2026-08-09T09:12:00Z",
    "examined_by": "lab",
    "examiner": "",          // in-house only
    "external_lab": "Tierarztpraxis Müller",
    "no_findings": false,
    "notes": ""
  },
  "findings": [              // the COMPLETE set — replaced wholesale
    {"finding_type": "…", "severity": "plus_plus"},
    {"free_text": "Ziliaten", "severity": "plus"}
  ],
  "keep_attachments": ["a.jpg"]  // edit: the survivors; omitted names are dropped
}
```

**Response** `200 {"id": "…"}`.

Invariants the route enforces — every one of these is something an access rule
*cannot* express, which is the standing reason this codebase puts them in hooks:

- `assertCanEditCase` — copied from `exam.pb.js`; the route bypasses collection
  rules, so it re-checks org + active carer / supervisor / edit-share itself.
- `no_findings === true` **and** a non-empty `findings` array → `400`. Both
  empty is fine; that is the pending state.
- every finding carries exactly one of `finding_type` / `free_text`, plus a
  `severity` from the allowed set.
- `finding_type` resolves in the caller's org. Applicability to `sample_type`
  is **not** enforced — a supervisor narrowing a type later must not invalidate
  history, and an inactive type stays valid on rows that already reference it.
- `method` is cleared unless `sample_type === "fecal"`, so a stale client cannot
  store "Kropfabstrich, Flotation".
- findings are deleted and re-created as a set inside the transaction (the
  assessed set is small; a clean replace beats diffing — `exam.pb.js`'s call).

**JSVM reminder:** every helper the handler uses must be defined *inside* it.
File-level consts are not in scope in a hook handler (`ReferenceError`), which
is also why the shared bits live in `lib_auth.js` / `lib_audit.js` and are
`require(`${__hooks}/…`)`d inside the body.

**Deletes** go through the ordinary collection API (`DELETE
/api/collections/microscopy_samples/records/:id`, findings cascade), so
`audit_domain.pb.js` picks them up with no extra code.

**Rate limiting:** nothing to add. `rate_limits.pb.js` only carries entries for
the two expensive Typst routes and geocoding; microscopy is an ordinary write.
But note the *prefix-matching* trap documented there — if a limit is ever added,
`/api/federfall/microscopy` must not be shadowed by a shorter label.

---

## 5. Attachments — photo **and** video

This is the part with the most sharp edges, so each one is named.

**Field**

```js
{
  name: "attachments", type: "file", required: false,
  maxSelect: 5,
  maxSize: 52428800,                       // 50 MB (decided) — video, not a
                                           // 10 MB photo
  mimeTypes: [
    "image/jpeg", "image/png", "image/webp", "image/gif",
    "video/mp4", "video/quicktime", "video/webm"
  ],
  thumbs: ["200x200"],
  protected: true
}
```

**1. Thumbs do nothing for video.** PocketBase generates a `?thumb=WxH` variant
for images only; for anything else it silently serves the **original**
(1700000049 found exactly this failure for images whose size wasn't whitelisted).
So requesting a thumbnail for a 50 MB `.mp4` downloads 50 MB to paint an 88 px
tile. The attachment strip must branch on the filename extension and render an
icon placeholder for video — never an `Image.network` / `CachedFileImage`.

**2. Protected files need a token.** `protected: true` means the URL is only
served with a short-lived file token (`POST /api/files/token`, ~2 min TTL),
which `pb.files.getURL(record, name, token:)` appends. That is already how case
intake photos work; video inherits it unchanged, including for a URL handed to
an external player.

**3. Playback: `url_launcher`, no in-app player.** *(decided)* The app has no
`video_player` dependency and does not gain one here. Tapping a video attachment
opens the tokenised URL with `url_launcher`, handing playback to the OS or the
browser. The ~2 min token TTL is ample for a launch.

An inline player is filed as follow-up work, not designed away. Whoever picks it
up needs to know that `web_headers.pb.js` has **no `media-src`** directive
today: it falls back to `default-src 'self'`, so a same-origin `<video src>`
would work, but the `blob:` URL `video_player` produces on web is blocked. That
is a one-line CSP change — it just has to be a *deliberate* one rather than a
mystery to debug.

**4. Capture needs no new package.** `image_picker` is already a dependency and
`pickVideo(source: camera | gallery)` covers both. But the existing staging
widgets (`StagedPhotos`, `EditablePhotoStrip`) decode the picked local file with
`Image.memory`, which throws for a video — they need the same extension branch
as (1), and the `errorBuilder` the test conventions already require.

**5. Body size is a deployment concern.** 50 MB × 5 exceeds the default body
limit of most reverse proxies (nginx `client_max_body_size` defaults to 1 MB).
`docs/DEPLOYMENT.md` says TLS and proxying are the operator's job, so it needs a
line telling operators to raise the limit — otherwise the failure is a `413`
from a component Federfall doesn't ship.

**6. Fonts / rendering:** nothing new. No non-ASCII character beyond what the
bundled Roboto + Noto Symbols set already covers is introduced by the German
labels here (federfall-sbtx).

---

## 6. Audit log

`audit_events` is append-only and label-snapshotted; every one of these is
required or a test fails.

**Actions** (`lib_audit.js` `ACTIONS`) — additive, so this ships as `feat:`:

```
MICROSCOPY_SAVED:   "microscopy.saved"     ← emitted from the route, in-tx,
                                             like exam.saved
MICROSCOPY_DELETED: "microscopy.deleted"   ← via COLLECTION_ACTIONS
```

The findings ride inside `microscopy.saved` (as `exam.saved` does) — per-row
events would bury the one fact worth reading. Its `detail` carries
`{created, sample_type, method, no_findings, findings: N, worst: "plus_plus"}`
plus a `*_label` beside any id, per the "an id in an audit row is a bug unless a
label sits beside it" rule.

**Registries to extend:**

- `COLLECTION_ACTIONS` / `AUDITED_COLLECTIONS`: `microscopy_samples` →
  created/updated/deleted; `microscopy_finding_types` → the generic
  `code_list.*` triple (the renderer stays generic, `subject_collection` says
  which list).
- `CONTENT_FIELDS`: `microscopy_samples: ["sample_type","method","examined_at","examined_by","no_findings"]`,
  `microscopy_findings: ["severity"]`, `microscopy_finding_types: ["label","active"]`.
- `RELATION_TARGETS`: `finding_type: "microscopy_finding_types"`.
- `LABEL_FIELDS`: `microscopy_finding_types: ["label"]`.
- `LABEL_RELATIONS`: `microscopy_findings: { finding_type: "microscopy_finding_types" }`.
- `test_rules.py`'s `RELATION_UNLABELLED_BY_DESIGN`: `("microscopy_findings",
  "sample")` — a sample has no name of its own, exactly the exemption
  `exam_findings.exam` already holds.
- `FREE_TEXT`: `notes` and `free_text` are already covered by name; `notes` is
  in the list, and the prose sweep only fires at `max >= 1000`, so `free_text`
  (300) and `external_lab` (200) stay verbatim — which is right, they are short
  structured strings, not prose.
- `audit_labels.dart`: a translated label for **every** field above, in both
  languages. `audit_labels_test.dart` parses `CONTENT_FIELDS` out of
  `lib_audit.js` and fails on any field rendering as its raw column name.

**No finder PII is anywhere near this feature** — nothing to add to `SENSITIVE`.

---

## 7. Animal merge — nothing to do, on purpose

`merge_animals.pb.js` re-points every collection with a direct `animal`
relation (cases / markings / weights / exams / egg_records / aviary_stays), and
federfall-0ua6 is the record of what happens when one is missed: it is not left
behind, it is **destroyed** inside the merge transaction and the caller gets a
`200`. Both collections here are reached through `case` / `sample`, so the merge
already carries them when it re-points cases, and nothing is added to that list.

This is the payoff for having no `animal` field (§2.2), and it is the thing that
must move **in the same commit** if the lifetime view is ever built:

1. the collection list in `merge_animals.pb.js`,
2. `test_rules.py`'s `[animal merge]` block (the guard that would have caught it),
3. the moves summary on the merge screen, which lists the same collections to
   the user,
4. plus `animal_org_scope.pb.js` (§3) and a backfill of `sample.animal =
   case.animal`.

---

## 8. Flutter side

### Models (`packages/federfall_models`)

`MicroscopySample`, `MicroscopyFinding`, `MicroscopyFindingType` — freezed +
`fromRecord`. Enums with `wire` values: `MicroscopySampleType`,
`MicroscopyMethod`, `MicroscopySeverity`, `MicroscopyExaminedBy`.

`CaseBundle` gains `microscopySamples` and `microscopyFindings`, and
`caseBundleExpand` gains:

```
microscopy_samples_via_case,
microscopy_samples_via_case.microscopy_findings_via_sample
```

(the nested form `exams_via_case.exam_findings_via_exam` already proves works).
Findings are grouped by sample id in the provider, like `examFindingsForCase`.

### Data (`packages/federfall_data`)

`MicroscopySamplesRepository` (CRUD + `forCase` + the multipart `save()` route
call — no `forAnimal`, there is no animal relation to query by),
`MicroscopyFindingTypesRepository` (code list, with `countForType` for the
delete dialog).

### App (`apps/federfall/lib/features/cases/microscopy/`)

Following the timeline pattern one-for-one: a provider, a
`showMicroscopySheet()`, a `MicroscopyTile` built on `TimelineItem`, and a
`_MicroscopyEvent` in `case_timeline.dart` ordered by
`examinedAt ?? created ?? epoch`.

Also to touch:

- `add_entry_sheet.dart` — a `_AddKind.microscopy` entry in the **Klinisch**
  group, `Icons.biotech_outlined`, label *Mikroskopie*.
- `case_realtime.dart` — add `microscopy_samples` (and `microscopy_findings`) to
  the subscribed collection list.
- `codelist_specs.dart` + `management_screen.dart` — a
  `microscopyFindingTypesCodelistSpec`. It is the first list whose editor needs
  an extra control (the `sample_types` applicability chips), so `CodelistSpec`
  either grows an optional extra-fields slot or this list gets its own small
  screen; the former is preferable and is the shape `conditions`' notifiable /
  contagious flags already established.
- `app_de.arb` + `app_en.arb` + `flutter gen-l10n`; label helpers next to
  `cases_labels.dart`'s `admissionReasonLabel`.
- every date through `formatLocalDate` — `date_field_test.dart` sweeps `lib/`
  and fails on any other Material date formatter (federfall-yok0).

---

## 9. The sheet — UX

The requirement describes a sequence of questions. Implemented as **one
scrolling sheet with progressive reveal**, not a wizard:

```
┌ Mikroskopie ──────────────────────────────────────┐
│ Datum/Zeit            [ 09.08.2026, 09:12 ]       │
│                                                    │
│ Probe        (  Kropfabstrich  |  Kotprobe  )     │  segmented, required
│ Untersuchung (  Direktabstrich |  Flotation )     │  ← only when Kotprobe
│                                                    │
│ Untersucht von  ( Eigene | Tierarzt | Labor )     │
│   Labor/Praxis  [ ______________________ ]        │  ← only when ≠ Eigene
│                                                    │
│ ── Befunde ─────────────────────────────────────── │
│ [ ] Ohne Befund                                    │  clears + disables below
│                                                    │
│   Trichomonaden        (  +  | ++ | +++ )  ⨯       │  unset by default
│   Hefen                (  +  | ++ | +++ )  ⨯       │
│   + Sonstiges …                                    │  → text field + grades
│                                                    │
│ Anhänge   [📷] [🎬]   ▢ ▢ ▶                        │
│ Notiz     [ ______________________________ ]       │
│                                       [Speichern]  │
└────────────────────────────────────────────────────┘
```

- The findings list is filtered by `sample_types` against the chosen probe, so
  switching Kropfabstrich → Kotprobe swaps the rows. A grade already set on a
  row that disappears is dropped with an undo-able snackbar rather than
  silently.
- **Ohne Befund** is a single checkbox at the top of the findings block, not a
  list row, because it is about the sample. Ticking it clears and disables the
  grades; setting any grade unticks it. The mutual exclusion is enforced twice —
  here for feel, in the route for truth.
- Saving with neither ticked nor graded is allowed and the tile reads
  *Ergebnis ausstehend*.
- A wizard was considered and rejected: `federfall-ui-prefers-unified-consistent-views`
  favours one view, and the intake wizard exists because it has ~20 fields —
  this has five, of which two are conditional.

**Timeline tile** reads at a glance, worst finding first:

> 🔬 **Kotprobe · Flotation** — Spulwurmeier ++, Kokzidien-Oozysten +
> *Labor Müller · 09.08.2026*

and for a clean one:

> 🔬 **Kropfabstrich** — ohne Befund · *Eigene Untersuchung · 09.08.2026*

**Deliberately not automated:** a positive *Trichomonaden* finding does **not**
create a `case_conditions` entry for "Trichomonadose (Gelber Knopf)". The
microscopy result is evidence; the diagnosis is a human call, and the seeded
conditions list already holds the diagnosis. The tile can offer a *Diagnose
anlegen* shortcut that pre-fills the condition sheet — an offer, not a side
effect.

---

## 10. Out of scope, and why each stays cheap to add later

Three things are deliberately deferred. None of them is designed away — each
has its re-entry point named, and all three are additive (`feat:`, not
`feat!:`).

**Animal lifetime view** (§2.2, §7). Re-entry: add `animal`, backfill from
`case.animal`, and move the four places §7 lists in the same commit.

**In-app video player** (§5). Re-entry: add `video_player`, add `media-src
blob:` to `web_headers.pb.js`.

**Statistics and the annual report.** Both read `case_report_rows` through
`lib_stats.js`; adding a column there or an aggregate beside it is a new field
on a hook response, which is not a wire break. The obvious candidates are
"samples taken / positive rate" and a parasite breakdown — both are period
questions `lib_stats.js` already knows how to partition.

---

## 11. Version impact

**`feat:`, not `feat!:`.** New collections, a new route, new optional expands.
Nothing existing changes shape, no field is removed or renamed, no access rule
tightens against a call an older client makes. An older client simply does not
render microscopy. (CLAUDE.md's wire-contract rule: a major bump would force
every user to update for nothing.)

---

## 12. Implementation order

| # | step | gate |
|---|---|---|
| 1 | `1700000073_microscopy.js` — 3 collections, rules, guards, file field born correct, per-org seed | `tests/run.sh` against a live stack |
| 2 | `test_rules.py` — a `[microscopy]` block: org scoping, carer/share/coordinator matrix, the guest sweep, boundary guards, `no_findings` XOR findings | red → green |
| 3 | `microscopy.pb.js` route (multipart, transactional) + audit emit | rule tests extended |
| 4 | `lib_audit.js` registries + `audit_labels.dart` | `audit_labels_test.dart`, audit sweep |
| 5 | models + repositories + bundle expand | `dart test` in both packages |
| 6 | sheet, tile, timeline event, add-entry entry, realtime | `flutter test`, coverage ≥ 75 % |
| 7 | admin code list (with `sample_types` chips) | widget test |
| 8 | attachment strip: video branch, `pickVideo`, `url_launcher` open | manual on device + web |
| 9 | `docs/DEPLOYMENT.md` proxy body-size note | — |

No `merge_animals.pb.js` step — see §7.

Quality gates from the repo root throughout: `dart format --output=none
--set-exit-if-changed .`, `flutter analyze` (root — it covers the packages, a
subdirectory run does not), `flutter test` from `apps/federfall`.

---

## Decisions

Settled 2026-08-09, all four open questions closed:

| # | question | decision |
|---|---|---|
| 1 | video playback | **`url_launcher`**, no in-app player; `video_player` filed as follow-up (§5, §10) |
| 2 | attachment size cap | **50 MB** per file, 5 files; needs the `DEPLOYMENT.md` proxy note (§5) |
| 3 | finding vocabulary | **one code list** with a `sample_types` applicability field, not two (§2.1) |
| 4 | animal lifetime view | **not yet** — and therefore no `animal` field at all (§2.2, §7) |

#4 is the one with teeth: it takes a field *out* of the schema rather than
merely leaving a screen unbuilt, which is what removes the merge-deletion
failure mode (§7). Re-entry for all three deferrals is in §10.
