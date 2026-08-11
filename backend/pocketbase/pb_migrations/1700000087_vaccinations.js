/// <reference path="../pb_data/types.d.ts" />

// federfall — vaccinations: a shot given to a bird, as a longitudinal property
// of the ANIMAL. The stance 1700000020 took for weights and 1700000056 for
// eggs, and for the same reason: a PMV vaccination given during a spring case
// is exactly what a keeper needs to see two years later, in an aviary, under a
// different case and a different carer. Until now the only place to put one was
// a journal note, which is case-scoped prose — invisible to the next holder and
// impossible to ask a question of ("is this bird due?").
//
// There is deliberately NO `case` field, following egg_records: timeline
// membership is COMPUTED from the animal, never stored, so nothing has to be
// re-pointed when a bird changes hands. Consequence accepted, unchanged from
// eggs: vaccinations are absent from the `case_activity` view (1700000022),
// which unions on case columns — recording one does not bump a case's activity
// timestamp.
//
// `aviary` is likewise absent. aviary_stays (1700000052) already answers "where
// was this bird on that date", and a denormalised copy would drift — this
// matters more here than for eggs, because the intended second step is a batch
// vaccination across an enclosure's residents, which is N of these rows and not
// a row with an aviary on it.
//
// ── Free text, with a view for the vocabulary ───────────────────────────────
// `vaccine` and `target` are free TEXT, not a code list and not a select. The
// alternative — a supervisor-managed `vaccine_products` list — was considered
// and rejected: it needs seeding (and would inherit federfall-buqb, where code
// lists are not seeded for orgs created after their migration), it needs
// per-org curation before anyone can record anything, and a dosing figure
// seeded from anywhere but the package insert would be read as instruction.
//
// The vocabulary problem free text creates is solved the way this repo already
// solves it twice: 1700000088 adds a `vaccine_labels` VIEW over the DISTINCT
// (vaccine, target) pairs actually recorded per org, exactly as
// `animal_species` (1700000042) and `condition_labels` (1700000062) do. The
// list therefore builds itself out of use, offers nothing dead, and — because
// the pair is one row — picking a product can prefill the target it covers.
//
// `target` is one text field rather than a repeated one because combination
// vaccines exist (Colombovac PMV/Pox covers two diseases) and a single row is
// still ONE administration. What that costs is stated plainly: a per-disease
// roll-up ("PMV: geimpft, Auffrischung fällig") groups on the recorded string,
// so "Paramyxovirose" and "PMV" are two answers. The view is what makes them
// converge in practice; nothing normalises them behind the user's back, which
// is the same honesty `condition_labels` documents.
//
// ── next_due_at is stored, not derived ──────────────────────────────────────
// The booster interval belongs to the product, which is not a record here — but
// even if it were, a plan is a fact: what was scheduled at the time must not
// move because somebody later edited an interval. So the date is written on the
// row. It is also what a batch/worklist step will read.
//
// ── Who gave it: `vet` (text), and `author` for everyone else ───────────────
// The person who administered a vaccine is frequently NOT a `users` row — an
// external practice, or the vet who dispensed and injected it. That half is
// `vet`, a plain text field, exactly as `vet_appointments.vet` and
// `medications.prescribed_by` already are. The in-house half needs no field at
// all: `author` records who entered the row and is server-pinned to the
// authenticated caller by authorship.pb.js, so a keeper vaccinating their own
// bird is already named.
//
// The obvious name, `administered_by`, is deliberately NOT used: lib_audit.js's
// RELATION_TARGETS is keyed by field name GLOBALLY and already maps
// `administered_by` → `users` (for medication_administrations). A TEXT field of
// that name would contradict a table the audit log treats as schema-wide truth
// — the same trap that forced microscopy's child relation to be called `sample`
// rather than `exam` (1700000073).
//
// ── Born correct ────────────────────────────────────────────────────────────
// `attachments` declares protected + MIME allowlist + thumbs INLINE, and the
// update rule carries its boundary guards INLINE. 1700000027 / 1700000048 /
// 1700000049 are three separate repair passes over file fields that shipped
// without one of those, and 1700000043 is the same for the guards; all four
// carry hardcoded target lists, so a field created without the treatment simply
// never gets it. It is multi (maxSelect 3) rather than maxSelect 1 because
// PocketBase stores a string for single and an array for multi, and switching
// later would change `List<String>` back and forth at every call site. Its job
// is the vial label / Chargenaufkleber and a paper Impfausweis brought along
// with a bird.
//
// No NEW relation FIELD NAME is introduced: `animal`, `route`, `author` and
// `org` all already exist elsewhere pointing at the same collections. That
// matters because lib_audit.js's RELATION_TARGETS is keyed by field name
// GLOBALLY (the trap that forced microscopy's child relation to be called
// `sample`) — so this collection needs no override entry.
//
// ── Access ──────────────────────────────────────────────────────────────────
// The identity-layer stance, in the custody-gated form 1700000079 gave weights
// / markings / egg_records: org-wide READ (knowing a bird's vaccination status
// is exactly the cross-case, cross-keeper question this exists to answer), and
// writes gated on holding the bird. DELETE is author-or-supervisor on top —
// destruction is the part worth restricting, contribution is not — with custody
// as a floor, so once a bird has left your care its history is not yours to
// erase.
//
// `animal` is FROZEN on update (`@request.body.animal:isset = false`), which is
// 1700000082's treatment for weights / markings / exams. The custody predicate
// is reached through `animal.`, so on UPDATE it resolves against the STORED
// record (1700000043's finding) and authorises custody of the bird the row is
// moving AWAY FROM — meaning a free `animal` field could be used in two calls
// to inject a row onto anyone else's bird. egg_records escapes the freeze only
// because re-attribution is a shipped feature there (a presumed layer being
// corrected); moving a vaccination to a different bird is not a feature, it is
// a mistake to be deleted and re-entered. So this one is frozen, and needs no
// entry in animal_custody_scope.pb.js.
//
// Rules use the guest-safe AUTH form required since 1700000045 — the guest
// sweep in tests/test_rules.py fails loudly without it.
//
// PocketBase has no schema-level field defaults, so the documented default
// (`dose_unit` "ml") lives in the Dart model and the entry sheet.

migrate(
  (app) => {
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const ORG_SCOPED = `${AUTH} && org = @request.auth.org`;

    // Verbatim 1700000079: an OPEN case is one whose status has not moved on.
    const ACTIVE =
      '(animal.cases_via_animal.status ?= "in_care"' +
      ' || animal.cases_via_animal.status ?= "ready_for_release"' +
      ' || animal.cases_via_animal.status ?= "")';

    const CUSTODY =
      "(" +
      COORD_SUP +
      " || animal.current_aviary.keeper = @request.auth.id" +
      " || (animal.cases_via_animal.active_carer ?= @request.auth.id && " +
      ACTIVE +
      ")" +
      " || (animal.cases_via_animal.case_shares_via_case.shared_with" +
      " ?= @request.auth.id" +
      ' && animal.cases_via_animal.case_shares_via_case.access ?= "edit" && ' +
      ACTIVE +
      ")" +
      ")";

    const AUTHOR_OR_SUP =
      '(@request.auth.role = "supervisor" || author = @request.auth.id)';

    const animals = app.findCollectionByNameOrId("animals");
    const routes = app.findCollectionByNameOrId("medication_routes");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    app.save(
      new Collection({
        type: "base",
        name: "vaccinations",
        listRule: ORG_SCOPED,
        viewRule: ORG_SCOPED,
        createRule: `${ORG_SCOPED} && ${CUSTODY}`,
        updateRule:
          `(${ORG_SCOPED} && ${CUSTODY})` +
          " && @request.body.org:isset = false" +
          " && @request.body.animal:isset = false",
        deleteRule: `${ORG_SCOPED} && ${AUTHOR_OR_SUP} && ${CUSTODY}`,
        fields: [
          {
            name: "animal",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: animals.id,
            cascadeDelete: true,
          },
          // The product as it was written on the vial, snapshotted on the row.
          // `medications.drug` is the precedent: the vocabulary view suggests,
          // it does not own the value, so a row still reads correctly after the
          // team changes what it calls something.
          { name: "vaccine", type: "text", required: true, max: 200 },
          // What it protects against, e.g. "Paramyxovirose" or "PMV/Pocken".
          { name: "target", type: "text", required: false, max: 200 },
          // The UI always sets this; the model falls back to `created`, the way
          // weights.measured_at does.
          { name: "administered_at", type: "date", required: false },
          // Chargennummer — the field that makes a vaccine failure or a recall
          // traceable, and the reason a journal note was never good enough.
          { name: "batch", type: "text", required: false, max: 100 },
          { name: "dose", type: "number", required: false },
          { name: "dose_unit", type: "text", required: false, max: 50 },
          {
            name: "route",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: routes.id,
            cascadeDelete: false,
          },
          // Grundimmunisierung vs Auffrischung. Deliberately not a dose counter:
          // "2 of 3" is a property of a schedule this collection does not model.
          {
            name: "series",
            type: "select",
            required: false,
            maxSelect: 1,
            values: ["primary", "booster"],
          },
          { name: "next_due_at", type: "date", required: false },
          // The external practice or vet who gave it — see the note above.
          // In-house administration is carried by `author`.
          { name: "vet", type: "text", required: false, max: 200 },
          { name: "notes", type: "text", required: false, max: 2000 },
          {
            name: "attachments",
            type: "file",
            required: false,
            maxSelect: 3,
            maxSize: 10485760,
            mimeTypes: ["image/jpeg", "image/png", "image/webp", "image/gif"],
            thumbs: ["200x200"],
            protected: true,
          },
          // Drives the delete rule; pinned to the caller by authorship.pb.js.
          {
            name: "author",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: users.id,
            cascadeDelete: false,
          },
          {
            name: "org",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: organisations.id,
            cascadeDelete: false,
          },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
          { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
        ],
        indexes: [
          // The two reads this collection has: an animal's ledger (the detail
          // card, the case timeline window) and "who is due" (the batch and
          // worklist steps).
          "CREATE INDEX `idx_vaccinations_animal` ON `vaccinations` (`animal`)",
          "CREATE INDEX `idx_vaccinations_org_due` ON `vaccinations`" +
            " (`org`, `next_due_at`)",
        ],
      }),
    );
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("vaccinations"));
  },
);
