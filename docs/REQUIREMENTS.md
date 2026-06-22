# Federfall — Pigeon Rehab Case Management — Requirements & Planning

> Name: **Federfall** (chosen).
> Status: requirements baseline (rev. 2) · Date: 2026-06-22 · Author: requirements gathered with Claude

A digital case-management app for a German pigeon-rehabilitation association (Taubenhilfe / Wildtierhilfe Verein) to record and share the medical history of animals in rehab. Flutter frontend (Web + Android + iOS), PocketBase backend, self-hosted.

---

## 1. Vision & problem statement

Feral-pigeon rehabbers in Germany today coordinate via spreadsheets, paper, web forms and Facebook groups. There is no purpose-built shared clinical record. This app digitalizes the **case record of each animal** — from intake (Aufnahme) through treatment to disposition (release / death / euthanasia / returned to owner) — so that:

- a carer (Pflegestelle) can record everything about a case in one place,
- that information can be **shared with specific other members when desired**,
- supervisors can **oversee and review** cases,
- and the association gets **aggregate statistics** for annual reports.

**Primary value (the one thing that must work):** record an animal's treatment/medical history and share it with others.

**Project nature:** side project, but built to a **rigorous bar** — secure, tested, well-structured — because it handles personal data (finder contacts) and medical records.

---

## 2. Naming

**Final name: Federfall** ("feather case" — *Fall* = case, in the medical/legal sense). German, professional, memorable, and not pigeon-locked so it still fits if the species scope broadens.

Code identifiers: package `federfall`, app id **`de.jhbruhn.federfall`**.

---

## 3. Decisions locked in (interview summary)

| Area | Decision |
|---|---|
| Species scope | **Pigeon-first**, but `species` is a first-class field → extensible to other birds without remodeling |
| Owned/racing pigeons (Brieftauben) | **Lightweight**: `has_ring` + `ring_number`, and a `returned_to_owner` disposition. No heavy owner workflow |
| Medical record depth | **Hybrid**: structured weight / medications / conditions / disposition **+** free-text dated journal |
| Diagnoses | **Editable German code list** (suspected/confirmed) **+** free-text fallback |
| Organisation structure | **Single association**, but records carry a light tenant/org tag so multi-org later isn't a painful migration |
| Roles | **Carer/Pflegestelle, Coordinator, Supervisor** (vet = data on a case, not a login role — revisit if a vet should log in) |
| Default visibility | **Private** to carer + supervisors; **opt-in sharing** to specific members |
| Co-care | **Handoff chain** — one active carer at a time; transfers recorded as handoff events. On handoff the **previous carer keeps read access** (auto-share) |
| Disposition | Distinguish **outside release** (wild release, with date + location/geo) from **placement in a named aviary** (a Voliere belonging to someone). An aviary placement makes the bird a **resident** that may keep receiving care entries in the same tool |
| Find-location | **Full address + map pin**, with geocoding (address ⇄ coordinates) |
| Re-admission | An **animal can return to treatment** repeatedly. Persistent `animals` identity is separated from `cases` (a single admission→disposition episode); an animal has many cases |
| Auth | **Email + password** (always, esp. dev) **+ OAuth2/OIDC**, with **Nextcloud OIDC** as a planned future provider |
| Registration | **Invite / approval only** |
| Security | Standard + **optional MFA** (encouraged for supervisors); GDPR/DSGVO-aware throughout |
| Public finder form | **Not at launch**, but intake modeled as a pipeline that can accept external submissions later |
| Hosting | **Self-host** on own VPS/server (sits next to existing Nextcloud) |
| Existing data | Minor — **manual re-entry is fine**; no formal importer required (schema still WRMD-compatible) |
| Language | **German now**, built **i18n-ready** (Flutter l10n) |
| Offline | **Light offline**: recently-viewed cases readable offline; edits require connection |
| Reporting | **Yes** — dashboard + exportable stats for annual reports |
| Reminders/notifications | **None at launch**; keep dates structured so reminders are easy to add |
| Intake exam | **Light by default**, with an **optional expandable structured exam** |
| Extensibility priority | Design **people/membership** to generalize toward **association management** later |

---

## 4. Roles & permissions

| Role | Capabilities |
|---|---|
| **Carer / Pflegestelle** | Create cases; full edit on cases they actively hold; log weights, meds, journal, photos; initiate handoffs; share a case with specific members |
| **Coordinator** | View/assign across cases; route incoming animals to carers; manage handoffs/placements; broad read |
| **Supervisor / Admin** | Everything; review all cases; manage users & invites; manage code lists (conditions, medications, species); manage sign-off gates; access reports |
| **Vet** *(not a login role at launch)* | Recorded as referral data on a case (findings, prescriptions, sign-off). Promote to a real role later if vets need access |

PocketBase **superusers** (admin UI) ≠ in-app "Supervisor." Keep them separate: superusers administer the server; Supervisors are an app-level role flag.

---

## 5. User stories

### Carer / Pflegestelle
- As a carer, I can **create a new case** for an animal I've taken in, recording species, age class, sex, intake date/location, reason for admission, finder contact, intake weight, and a photo — quickly, without vet-level detail.
- As a carer, I can **log a weight** and see the **weight trend** over time (key health/readiness signal).
- As a carer, I can **record medications** (drug, dose, route, frequency, start/end) and conditions/diagnoses (from the code list, suspected/confirmed, or free text).
- As a carer, I can **add dated journal entries** with text and photos for anything that doesn't fit a structured field.
- As a carer, I can **record where the animal is held** (placement/enclosure) and when it moves.
- As a carer, I can **hand off the animal** to another carer/coordinator, recording the condition at handoff.
- As a carer, I can **share a case** with a specific member for a second opinion, keeping it private from everyone else.
- As a carer, I can **record the disposition/outcome** (released, died, euthanized, returned to owner, permanent care) with date, location and reason.
- As a carer, I can **mark a ringed (owned) pigeon** so it routes toward "returned to owner" instead of release.
- As a carer, I can **apply a ring/marker** to a bird (a temporary in-care marker, or an association release-ring before release/aviary placement) and record its code, so the bird can be re-identified later.
- As a carer, at intake I can **search a ring number or chip id** and, if it matches a known animal, **link this new case to that animal** and see its full prior history (so re-admissions build one lifetime record).

### Coordinator
- As a coordinator, I can **see active cases** I have access to and **assign/route** animals to carers.
- As a coordinator, I can **manage handoffs** and see the chain of custody.

### Supervisor
- As a supervisor, I can **review any case** and oversee carers.
- As a supervisor, I can **invite new members** and assign roles; there is no open self-registration.
- As a supervisor, I can **maintain the code lists** (conditions/diseases, medications, species, reasons for admission).
- As a supervisor, I can **view dashboards and export reports** (intakes per period, outcome rates, breakdown by species/condition) for the annual report.

### Cross-cutting
- As any user, I can **sign in** with email+password (and later via Nextcloud OIDC).
- As any user, I can **view recently-opened cases offline** (read-only) when I have no connection.
- As any user, the UI is **in German**.

---

## 6. Data model

Designed for PocketBase collections. Field names in English (code), labels in German (UI). `created`/`updated` are PocketBase built-ins. Every user-authored record carries an **author** + timestamp for the audit trail.

### Core entities

**`organisations`** *(single row at launch; present for future multi-org)*
- name, contact info, settings (default release rules, etc.)

**`users`** *(PocketBase auth collection)*
- email, password / OAuth identity, name, phone
- `role`: `carer | coordinator | supervisor`
- `is_active`, `invited_by`, `org` (→ organisations)
- *(future association-management fields: `is_member`, `is_volunteer`, address, postal_code, dues — modeled now as a generalizable `person` so membership extension is additive)*

**`finders`** *(rescuer — external person, distinct from staff; GDPR-sensitive)*
- first_name, last_name, organisation, phone, alt_phone, email
- address, postal_code, city, region (subdivision), notes

> **Animal vs. care episode — the key structural choice.** A bird can be admitted, dispositioned, and then **return to treatment a second or third time** (re-found after release, or an aviary resident that falls ill). So the persistent **`animals`** identity is separated from the **`cases`** (= one admission→disposition *care episode*). An animal **has many cases**. Almost everything clinical (weights, meds, journal, conditions, placements, disposition) attaches to a **case/episode**, but rolls up to the animal for a full lifetime history.

**`animals`** *(persistent identity across all admissions)*
- `species` (default Feral pigeon / Stadttaube; first-class field)
- `sex`: `male | female | unknown`
- **`name`** — birds have names! A given name (e.g. "Romeo") that persists across every admission. This is the **primary human-facing label** throughout the UI (case/episode number is secondary). Optional but encouraged; falls back to case number when unnamed.
- `is_owned` (racing pigeon flag — set when a finder/owner ring identifies an owned bird)
- `keywords/tags`
- `current_aviary` (→ aviaries, nullable — set while the animal lives as a resident)
- `lifetime_status`: `in_care | at_large_released | in_aviary | deceased` (derived from latest case/disposition)
- `org` (→ organisations), notes
- *Identity is carried by its **markings** (rings/microchip), below — not by flat fields here.*
- *Identifying a returning bird:* reliable when a ring/microchip matches an existing animal; for an unringed feral it's a carer judgment call. Linking is **optional** — a new case may attach to an existing animal or create a fresh one, and animals can be **merged** later if a duplicate is discovered (supervisor action).

**`markings`** *(rings, bands, microchips, temporary markers — many per animal, over the whole lifetime)*
- `animal` (→ animals)
- `type`:
  - `finder_ring` — an owner/racing ring already on the bird at intake (→ may set `is_owned`, route toward `returned_to_owner`)
  - `temporary_marker` — coloured ring or head paint dab to tell group-reared squabs apart in care
  - `release_ring` / `association_ring` — a ring **the association applies** (typically before release or aviary placement); the primary key for re-identification on return
  - `microchip`
- `code` (ring number / chip id / colour-code), `scheme_org` (issuing organisation, e.g. DV/RPRA, or the association's own), `colour` (for coloured markers)
- `applied_at`, `applied_by` (→ users), `applied_in_case` (→ cases — the episode during which it was added)
- `removed_at`, `removed_reason` (lost, replaced, etc.), `is_active`
- **Re-identification:** at intake, searching a scanned/entered code against active `markings` surfaces the matching animal and its full prior history so the carer can link the new case to it.
- *Note:* `release_ring` for **feral** pigeons is the association's own marking, not a national bird-ringing-scheme ring (feral pigeons aren't eligible for those). Record the scheme honestly.

**`cases`** *(one care episode / admission — the unit carers work on)*
- `animal` (→ animals; created or linked at intake)
- `case_number` (auto, per-year e.g. `2026-014`) — unique per episode
- `age_class`: `squab | fledgling | immature | adult` (Nestling / Ästling / Jungvogel / Altvogel) — *on the episode, since it changes between admissions*
- intake: `admitted_at`, `found_at`, `admitted_by` (→ users), `transported_by`, `finder` (→ finders)
- `find_location` (address + geo pin, geocoded — matters for "release where found"), `city`, `region`
- `reasons_for_admission` (multi-select from code list: injury, illness, orphaned, trauma, poisoning, trapped, cat-attack…)
- `intake_weight_g`, intake notes / free-text assessment, intake photos
- `quarantine_until` (date; default +14 days)
- `status`: `in_care | in_treatment | rehab | ready_for_release | disposed` (derived/maintained)
- `is_releasable` (bool; PMV survivors etc. → aviary/permanent care)
- `active_carer` (→ users; the one person who currently "has" the animal for this episode)
- `org` (→ organisations)
- **Optional structured intake exam** (expandable section, all optional): BCS, dehydration, attitude, temperature, mm_color, mm_texture, and body-system findings (head, CNS, cardiopulmonary, GI, musculoskeletal, integument, forelimb, hindlimb) each with a finding note.

**`case_conditions`** *(diagnoses — many per case)*
- case (→ cases), `condition` (→ conditions code list) OR `free_text`
- `certainty`: `suspected | confirmed`, onset_date, resolved_date, notes

**`conditions`** *(editable code list, German labels)*
- label_de (e.g. Trichomonadose, Paramyxovirose, Salmonellose, Fadenfuß, Spreizbein, Fraktur, MBD), label_en, `is_notifiable` (e.g. PMV), description, active

**`weights`** *(time series — drives the trend chart)*
- case (→ cases), `measured_at`, `weight_g`, author, notes

**`journal_entries`** *(free-text dated log + photos)*
- case (→ cases), `entry_at`, `text`, attachments (→ files), author

**`medications`** *(prescriptions)*
- case (→ cases), `drug` (→ medications code list or free text), concentration, dose, dose_unit, frequency, `route`, `started_at`, `ended_at`, `is_controlled`, instructions, prescribed_by

**`placements`** *(location/enclosure & handoff history — chain of custody)*
- case (→ cases), `moved_in_at`, `carer`/holder (→ users), `where_holding`, `area`, `enclosure`, `from_user`, `to_user`, `condition_at_handoff`, comments

**`dispositions`** *(outcome — typically one final, allow history)*
- case (→ cases), `type`: `released | placed_in_aviary | died | euthanized | transferred | returned_to_owner`
- `disposed_at`, `reason`, `performed_by`
- **for `released`** (wild/outside release): `release_location` (address + geo pin), `release_type` (e.g. hard/soft; released-where-found)
- **for `placed_in_aviary`**: `aviary` (→ aviaries). The case stays "alive" as a resident under `permanent_care` status and can keep receiving weight/med/journal entries
- **for `transferred`**: `transfer_type`, destination org/facility
- (note: `permanent_care` is now expressed as the *state* of an aviary resident, rather than a disposition type of its own)

**`aviaries`** *(named permanent-care enclosures / Volieren — where non-releasable birds live)*
- `name`, `keeper` (owner/responsible person — → users or a person/contact), `location` (address + geo), `capacity`, active, notes
- Residents = cases with a `placed_in_aviary` disposition pointing here. A resident-count / occupancy view falls out of this.
- *Open scope:* whether to manage the aviary **population** beyond individual rehab cases (flock health, routine care of long-term residents) is a possible future extension — see [§11](#11-extensibility-roadmap-designed-for-not-built-now). For now an aviary is just a destination with named residents.

**`case_shares`** *(opt-in sharing — implements "shared if desired")*
- case (→ cases), shared_with (→ users), `access`: `read | edit`, shared_by, created

**`attachments` / files**
- PocketBase file fields on cases and journal_entries (photos/video/documents), with uploader + timestamp.

### Notes
- The denormalized WRMD import templates map cleanly onto these normalized collections (patient+rescuer+exam → cases+finders; treatment_logs → weights+journal; prescriptions → medications; location-enclosure-history → placements). Schema stays **WRMD-import-compatible** for free even though no importer ships at launch.
- Vet involvement is captured via `medications.prescribed_by`, a referral note in journal, and an optional `vet_signed_off` flag on disposition — without a vet login.

---

## 7. Access control (PocketBase API rules)

Implements **private-by-default + opt-in sharing + handoff chain + supervisor oversight**, scoped by `org`.

A user may **view** a case if:
- they are the `active_carer`, OR
- they are listed in `case_shares` for that case, OR
- they have role `coordinator` or `supervisor` (within the same `org`).

A user may **edit** a case (and add weights/meds/journal/placements) if:
- they are the `active_carer`, OR
- they have a `case_shares` row with `access = edit`, OR
- they are a `supervisor`.

- **Create case:** any authenticated carer/coordinator/supervisor (sets self as `active_carer`).
- **Handoff:** writing a `placements`/transfer row updates `active_carer`; old carer keeps read via an automatic share (or loses access — *decision: see open questions*).
- **Code lists & user management:** supervisor-only.
- **Finders (PII):** visible only to users who can view the parent case; consider field-level care and a data-retention policy.
- Enforce these as **collection API rules** (server-side, not just UI). PocketBase rules are the security boundary.

---

## 8. Architecture & tech stack

### Backend — PocketBase (self-hosted)
- Latest stable PocketBase (v0.39.x line), single Go binary, SQLite + local file storage.
- **Schema as versioned migrations**, committed to the repo (reproducible across dev/prod).
- **Extension:** start with **JS hooks (`pb_hooks`)** for case-number generation, quarantine-date defaults, share-on-handoff logic, and report aggregation endpoints. Move to the Go framework only if a real performance/complexity ceiling appears.
- **Auth:** password collection + OIDC; add Nextcloud as a custom OIDC provider when ready. MFA available (encourage for supervisors).
- **Realtime (SSE)** for live case updates (works on Flutter Web since Dart SDK ≥0.22).
- **Files** stored locally on the VPS (option to move to S3-compatible later).

### Frontend — Flutter (Web + Android + iOS)
- Architecture: **MVVM + Repository** (official Flutter guidance), **feature-first** folder layout. Add a domain/use-case layer only where logic spans repositories.
- State management: **Riverpod 3.x**.
- Routing: **go_router** with typed routes; `usePathUrlStrategy()` + server rewrites for clean web URLs.
- Models/serialization: **freezed + json_serializable + build_runner** (Dart macros are cancelled; codegen is the path).
- PocketBase integration: official **`pocketbase` Dart SDK**, wrapped in repositories that map `RecordModel` → typed freezed models. Never let raw `RecordModel` leak into the UI.
- **Auth token storage:** `AsyncAuthStore` over `flutter_secure_storage` (Keychain/Keystore on native; LocalStorage+WebCrypto on web — weaker, requires HTTPS/HSTS).
- **Light offline:** cache recently-viewed cases (local store / `pocketbase_drift` or a simple cache repository); reads work offline, edits require connection.
- **Maps & geocoding:** **`flutter_map` with OpenStreetMap tiles** (not google_maps_flutter), and **Nominatim** for address ⇄ coordinate geocoding — self-hosted where practical. No Google Maps / Big Tech dependency. Used for find-location and release/aviary locations.
- **i18n:** Flutter `gen-l10n`, German default, structured so English/others are additive.

### Tooling & rigor
- Scaffold with **very_good_cli** (`very_good create flutter_app`) → flavors, lint, CI, l10n out of the box.
- **Pub workspace** (Dart 3.6+) for the Flutter app + a shared models package (+ PocketBase migrations dir). Add **melos** only if cross-package CI/release automation is needed.
- Lint: **very_good_analysis** (strict, pinned version) given the rigor bar.
- Testing: `flutter_test` + **mocktail** (unit/widget), **alchemist** (golden), **patrol**/`integration_test` (E2E). Repository layer unit-tested against a real/mock PocketBase.
- Flavors/envs: `--flavor` + `--dart-define-from-file` for dev/prod API URLs.
- CI: GitHub Actions (format / analyze / test+coverage). Set a realistic coverage target (not blindly 100%) given side-project effort.

### Deployment
- VPS (e.g. Hetzner) + **Caddy** (auto-TLS) reverse-proxying PocketBase; systemd unit.
- **Backups:** Litestream (continuous SQLite replication) or scheduled `pb_data` snapshots to off-box/S3. Set this up *before* real data goes in.
- Flutter Web served as static files (same domain or subdomain) with SPA rewrites to `index.html`.
- Restrict CORS `--origins` to the web app's domain.

---

## 9. Non-functional requirements

- **Self-hosted-first, no Big Tech:** a guiding principle. Prefer self-hostable, open, GDPR-clean components over US Big-Tech services — OpenStreetMap/Nominatim for maps/geocoding, Nextcloud OIDC for SSO, own VPS for hosting. (Implication: the earlier "Google social login" option is **de-prioritised / likely dropped** in favour of Nextcloud OIDC; email+password remains the baseline.)
- **Security & GDPR/DSGVO:** finder personal data is in scope. HTTPS everywhere; server-side API rules as the real boundary; invite-only accounts; optional MFA; least-privilege visibility. Plan for: data-subject deletion/export, a retention policy for finder contacts, and an audit trail (author+timestamp on entries). Hosting in own infra aids data residency.
- **Usability:** non-technical volunteers. Light intake by default, German UI, big-tap-target mobile-friendly forms, fast "new case + weight + photo" flow.
- **Reliability/scale:** single association → single PocketBase box is ample (read-heavy, modest writes). No HA needed at launch; backups are the priority.
- **Cross-platform:** one codebase for Web/Android/iOS; adaptive layouts (≈600px breakpoint), CanvasKit/skwasm web renderer, conditional imports for any platform-specific bits.

---

## 10. Reporting

- **Dashboard:** active cases, intakes this year, cases by status, quarantine ending soon.
- **Statistics:** intakes over time, **outcome breakdown** (released / died / euthanized / returned / permanent care), counts by **species** and by **condition**, average time-in-care.
- **Export:** CSV (and PDF for the annual report).
- Implement aggregation via a PocketBase JS-hook endpoint or computed client-side over filtered queries; keep disposition/condition/intake data structured so reports stay cheap to build.

---

## 11. Extensibility roadmap (designed-for, not built now)

1. **Association management** *(primary)* — generalize `users`→`persons` with `is_member`/`is_volunteer`, dues/contributions, full contact records. Membership DB grows out of the people model already present.
2. **Public finder portal** — intake modeled as a pipeline that can ingest a public submission (photo + location + contact) into a "pending intake" queue for a coordinator.
3. **Multi-org network** — `org` tag already on records; tighten rules to org-scoped sharing and add cross-org sharing controls.
4. **Reminders/notifications** — prescription end dates, weigh-in cadence, `quarantine_until` are structured now; add scheduling + push/email later.
5. **Vet as login role** — promote vet from data to an account with case-scoped access.
6. **Data import** — formal Excel/WRMD importer (schema already compatible).
7. **Aviary population management** *(planned)* — routine/flock-level management of long-term aviary residents (beyond per-bird case history): occupancy, group health, recurring care. The `aviaries` + resident model is built so this is additive when it's time.

---

## 12. MVP scope

**In:** auth (email+password, invite-only), cases with light intake + optional structured exam, conditions (code list + free text), weights + trend, medications, journal + photos, placements/handoff, dispositions, private-by-default + opt-in sharing, supervisor user/code-list management, basic dashboard + CSV export, German UI (i18n-ready), light offline reads, self-hosted deploy with backups.

**Out (later):** Nextcloud OIDC, MFA enforcement, public finder portal, reminders/notifications, rich PDF reports, multi-org, vet login, formal importer, full offline-with-sync.

---

## 13. Resolved decisions & remaining questions

**Resolved (this revision):**
1. **Name** → **Federfall**, app id `de.jhbruhn.federfall`.
2. **Handoff & old carer access** → previous carer **keeps read** (auto-share); revisable later.
3. **Find-location** → **full address + map pin + geocoding**.
4. **Finder PII retention** → **configurable, default 2 years** after case/episode closes (DSGVO). Surfaces as an org setting; supports purge/anonymize of finder contacts past the window.
5. **Coordinator visibility** → **all org cases, read**.
6. **Species list** → **pigeons only** for now (species field still first-class for later).
7. **Vet sign-off gate** → **not implemented** now; keep the idea (see [§11](#11-extensibility-roadmap-designed-for-not-built-now)).
8. **Coverage bar** → **~80%** (focused on domain/repository layer, not a blanket 100%).
9. **Re-admission** → animal/episode split (see [§6](#6-data-model)).
10. **Disposition** → release vs aviary placement distinguished; aviaries are named with residents (see [§6](#6-data-model)).

**Deferred (decide during build / later):**
- **Identifying returning unringed birds** — UX for "is this the same animal?" at intake. **Deferred** — to be designed once we see real intake flows; ring/microchip search + later merge is enough to start.
- **Aviary population management depth** — **planned for the future, not yet.** Long-term residents will eventually get routine/flock-level management; moved to the extensibility roadmap ([§11](#11-extensibility-roadmap-designed-for-not-built-now)). For now an aviary is a destination with named residents tracked as individual cases.
- *(resolved)* **Geocoding & maps** → **OpenStreetMap / Nominatim**, self-hosted where practical. No Big Tech. See [§9](#9-non-functional-requirements) principle.

---

## 14. Suggested next steps

1. Decide the name + resolve §13 open questions.
2. Lock the PocketBase schema (collections + API rules) from §6/§7 and write it as migrations.
3. Scaffold the Flutter app with very_good_cli; set up the repository layer + auth + one vertical slice (create case → log weight → view trend).
4. Stand up a dev PocketBase locally; wire light offline read cache.
5. Build out remaining case features, then dashboard/export.
6. Deploy PocketBase to the VPS with Caddy + Litestream backups before onboarding real cases.

---

### Reference sources
- PocketBase docs: https://pocketbase.io/docs/ · Dart SDK: https://pub.dev/packages/pocketbase
- Flutter app architecture: https://docs.flutter.dev/app-architecture/guide · go_router: https://pub.dev/packages/go_router
- WRMD (field-model benchmark): https://www.wrmd.org · https://wrmd.org/importing
- RSPCA pigeon rehab protocol: https://rspca-brighton.org.uk/wp-content/uploads/2022/05/Pigeons-including-collared-and-turtle-doves.pdf
- German: https://wp.wildvogelhilfe.org/ · https://taubenrettunghannover.de/taube-gefunden/ · https://pro-palomas.de/haeufige-taubenkrankheiten/
