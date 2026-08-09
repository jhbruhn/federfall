/// <reference path="../pb_data/types.d.ts" />

// federfall-vl7g — microscopy: a crop swab (Kropfabstrich) or faecal sample
// (Kotprobe) looked at under the microscope, with each finding graded
// + / ++ / +++. Design: docs/MICROSCOPY_DESIGN.md.
//
// Three collections, shaped as `case_conditions` (a code-list reference OR free
// text) crossed with `exams` + `exam_findings` (a parent whose sparse child set
// is replaced wholesale on save):
//
//   microscopy_finding_types  supervisor-managed vocabulary, per org, seeded
//   microscopy_samples        one examination of one sample
//   microscopy_findings       one graded finding on that sample
//
// ── The grade is per finding, which is why this is not one row ───────────────
// "Trichomonaden ++, Hefen +" is two independent facts, and a multi-select
// cannot carry a value per selected option. A `json` column could, but it would
// put the clinical payload behind the JSON-field trap (federfall-jumi /
// federfall-dk0c: a hook reading it back gets a byte array or a quoted string)
// for no gain.
//
// ── `sample`, never `exam` ───────────────────────────────────────────────────
// lib_audit.js's RELATION_TARGETS is keyed by FIELD NAME globally, with only a
// small per-collection override table beside it, and `exam` already belongs to
// `exams`. So the child's parent relation is `sample` and the parent collection
// is `microscopy_samples` — nobody reading a hook has to work out which "exam"
// is meant.
//
// ── There is deliberately NO `animal` relation ───────────────────────────────
// `exams` and `weights` denormalize one so the animal lifetime view can
// aggregate across cases. That roll-up is deferred (federfall-h27q), and until
// it exists the field would be dead weight with a sharp edge: EVERY collection
// carrying a direct `animal` relation must be re-pointed by
// merge_animals.pb.js, and one left out of that list is not left behind — it is
// DESTROYED inside the merge transaction and answered with a 200
// (federfall-0ua6, which is how egg_records and aviary_stays were found
// missing). Without the relation a sample follows its case, and the merge
// already re-points cases. Adding it later is exactly backfillable
// (`sample.animal = case.animal`); federfall-h27q lists the five things that
// then have to move in one commit.
//
// ── Born correct ─────────────────────────────────────────────────────────────
// The `attachments` file field declares protected + mimeTypes + thumbs INLINE,
// and the update rules carry their boundary guards INLINE. 1700000027 /
// 1700000048 / 1700000049 are three separate repair passes over file fields
// that shipped without one of those, and 1700000043 is the same for the guards
// — all four carry hardcoded target lists, so a field created without the
// treatment simply never gets it.
//
// Access is the `exams` stance verbatim: case-private clinical, because a
// parasite load is sensitive case detail rather than the org-wide identity
// layer that weights and markings sit in. Rules use the guest-safe AUTH form
// required since 1700000045 — the guest sweep in tests/test_rules.py fails
// loudly without it.

// Findings are written through POST /api/federfall/microscopy in one
// transaction (pb_hooks/microscopy.pb.js), for the reason exam.pb.js exists
// (federfall-lov0): a client-side parent-then-children sequence loses the
// clinical findings outright when the network drops between the calls, and this
// app is online-only. The collection rules below still stand on their own — the
// route bypasses them and re-states the same boundary itself.

// [label, sample types it applies to] — the starting vocabulary, seeded per
// org. A supervisor edits, deactivates or extends it at runtime.
//
// `Hefen` is why this is ONE list with an applicability field rather than two
// lists: it occurs in both sample kinds, and two lists would have to be kept in
// step by hand.
//
// Two things are deliberately absent. "Sonstiges" is not vocabulary — it is the
// `free_text` path on a finding row (exactly case_conditions.free_text), and as
// a code-list row a supervisor could rename, deactivate or delete the escape
// hatch itself. "Ohne Befund" is not a thing that was found — it is an
// assertion about the whole sample, and lives as a bool on it.
//
// These are names, not clinical values: the 1700000060 stance (ship no dose a
// vet did not write) does not bite, because a vocabulary term carries no number.
const SEED_FINDING_TYPES = [
  ["Trichomonaden", ["crop_swab"]],
  ["Hefen", ["crop_swab", "fecal"]],
  ["Haarwurmeier", ["fecal"]],
  ["Spulwurmeier", ["fecal"]],
  ["Kokzidien-Oozysten", ["fecal"]],
];

const SAMPLE_TYPES = ["crop_swab", "fecal"];
const METHODS = ["direct_smear", "flotation"];
const EXAMINED_BY = ["in_house", "vet", "lab"];

// + / ++ / +++ spelled out rather than stored as literal plus signs: these end
// up in filter expressions, CSV cells and audit rows, where a bare "+" is at
// best unreadable and at worst needs escaping. The Dart enum carries the wire
// value as always, so renaming the Dart side stays free.
const SEVERITIES = ["plus", "plus_plus", "plus_plus_plus"];

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    // The shared predicate from 1700000010, in the guest-safe form 1700000045
    // requires of anything new: a self-registered account authenticates but
    // must see no org data until a supervisor grants it a real role.
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

    // ── 1. microscopy_finding_types — the configurable vocabulary ────────────
    // Read by every member (it fills their findings picker), maintained by
    // supervisors only — the conditions / medication_routes stance.
    const orgScoped = `${AUTH} && org = @request.auth.org`;
    const supervisorOnly = `${AUTH} && ${SUP} && org = @request.auth.org`;

    const findingTypes = new Collection({
      type: "base",
      name: "microscopy_finding_types",
      listRule: orgScoped,
      viewRule: orgScoped,
      createRule: supervisorOnly,
      updateRule: `${supervisorOnly} && @request.body.org:isset = false`,
      deleteRule: supervisorOnly,
      fields: [
        {
          name: "label",
          type: "text",
          required: true,
          presentable: true,
          max: 200,
        },
        // Which sample kinds offer this finding. Multi, because Hefen is both.
        {
          name: "sample_types",
          type: "select",
          required: false,
          maxSelect: SAMPLE_TYPES.length,
          values: SAMPLE_TYPES,
        },
        // A supervisor's own definition of the term. Deliberately logged
        // verbatim by the audit log (test_rules.py's PROSE_LOGGED_ON_PURPOSE):
        // org configuration, not a record about a bird or a person.
        { name: "description", type: "text", required: false, max: 2000 },
        { name: "active", type: "bool", required: false },
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
    });
    app.save(findingTypes);

    // ── 2. microscopy_samples — one examination ─────────────────────────────
    //
    // Case-private clinical, keyed on `case` (cf. exams / follow_ups). The
    // update rule carries the 1700000043 guards inline: a plain field
    // reference in an UPDATE rule resolves against the STORED record, so
    // without them an edit-share holder could PATCH `case` and move a record
    // into a foreign case's timeline. The app only ever sends these on create.
    const sampleView =
      `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id` +
      ` || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const sampleEdit =
      `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id` +
      ` || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id` +
      ` && case.case_shares_via_case.access ?= "edit"))`;

    const samples = new Collection({
      type: "base",
      name: "microscopy_samples",
      listRule: sampleView,
      viewRule: sampleView,
      createRule: sampleEdit,
      updateRule:
        `(${sampleEdit})` +
        " && @request.body.case:isset = false" +
        " && @request.body.org:isset = false",
      deleteRule: sampleEdit,
      fields: [
        {
          name: "case",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: cases.id,
          cascadeDelete: true,
        },
        {
          name: "sample_type",
          type: "select",
          required: true,
          maxSelect: 1,
          values: SAMPLE_TYPES,
        },
        // Faecal only (Direktabstrich / Flotation); the route clears it for a
        // crop swab, so a stale client cannot store an impossible pairing.
        {
          name: "method",
          type: "select",
          required: false,
          maxSelect: 1,
          values: METHODS,
        },
        // Drives timeline placement; the model falls back to `created`, like
        // exams.examined_at.
        { name: "examined_at", type: "date", required: false },
        // Who did the analysis — "was this done by a vet or a lab, or not".
        // Three-valued rather than a bool, because a practice is not a lab.
        {
          name: "examined_by",
          type: "select",
          required: false,
          maxSelect: 1,
          values: EXAMINED_BY,
        },
        // The person who looked down the microscope (in-house only).
        {
          name: "examiner",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: users.id,
          cascadeDelete: false,
        },
        // The practice or laboratory, when it was not done in-house.
        { name: "external_lab", type: "text", required: false, max: 200 },
        // "Ohne Befund" — a positive assertion about the WHOLE sample, which is
        // why it is a column and not a finding row: it is mutually exclusive
        // with every finding (a row cannot express that), it must never be
        // renameable or deletable by a supervisor, and it gives reporting a
        // stable thing to count instead of a label match.
        //
        // With `findings` it spans the three states this workflow actually has:
        //   false + no findings  → result pending (sample sent to the lab)
        //   true  + no findings  → ohne Befund (looked, found nothing)
        //   false + N findings   → N graded findings
        // Collapsing the first into the second would assert a clean result
        // nobody has seen yet. The route rejects true + findings.
        { name: "no_findings", type: "bool", required: false },
        // Photo AND video documentation. Born with protected + mimeTypes +
        // thumbs, see the header.
        //
        // NB thumbs are generated for IMAGES ONLY. `?thumb=200x200` on a video
        // silently serves the ORIGINAL (the 1700000049 finding), i.e. tens of
        // megabytes to paint an 88px tile — so the client must branch on the
        // file type and draw a placeholder for video rather than request one.
        //
        // 50 MB is well above any reverse proxy's default body limit (nginx
        // ships 1 MB); DEPLOYMENT.md tells operators to raise it, since the
        // resulting 413 comes from a component Federfall does not ship.
        {
          name: "attachments",
          type: "file",
          required: false,
          maxSelect: 5,
          maxSize: 52428800,
          mimeTypes: [
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "video/mp4",
            "video/quicktime",
            "video/webm",
          ],
          thumbs: ["200x200"],
          protected: true,
        },
        { name: "notes", type: "text", required: false, max: 2000 },
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
    });
    app.save(samples);

    // ── 3. microscopy_findings — one graded finding ─────────────────────────
    //
    // A grandchild, so its rules traverse `sample.case` (cf. exam_findings,
    // whose multi-level traversal test_rules.py verifies against a live stack).
    const savedSamples = app.findCollectionByNameOrId("microscopy_samples");
    const findView =
      `${AUTH} && sample.case.org = @request.auth.org && (sample.case.active_carer = @request.auth.id` +
      ` || ${COORD_SUP} || sample.case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const findEdit =
      `${AUTH} && sample.case.org = @request.auth.org && (sample.case.active_carer = @request.auth.id` +
      ` || ${SUP} || (sample.case.case_shares_via_case.shared_with ?= @request.auth.id` +
      ` && sample.case.case_shares_via_case.access ?= "edit"))`;

    app.save(
      new Collection({
        type: "base",
        name: "microscopy_findings",
        listRule: findView,
        viewRule: findView,
        createRule: findEdit,
        updateRule:
          `(${findEdit})` +
          " && @request.body.sample:isset = false" +
          " && @request.body.org:isset = false",
        deleteRule: findEdit,
        fields: [
          {
            name: "sample",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: savedSamples.id,
            cascadeDelete: true,
          },
          // Either a vocabulary entry OR free text — the case_conditions shape.
          // Optional on purpose: deleting a finding type nulls this and the
          // finding keeps its severity, rather than the delete being refused
          // (the `conditions` behaviour, not `marking_types`').
          {
            name: "finding_type",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: findingTypes.id,
            cascadeDelete: false,
          },
          // "Sonstiges zum Selbst eintragen".
          { name: "free_text", type: "text", required: false, max: 300 },
          // Required: "ohne Befund" lives on the sample, so a finding that
          // exists at all was found at some strength.
          {
            name: "severity",
            type: "select",
            required: true,
            maxSelect: 1,
            values: SEVERITIES,
          },
          {
            name: "org",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: organisations.id,
            cascadeDelete: false,
          },
          {
            name: "created",
            type: "autodate",
            onCreate: true,
            onUpdate: false,
          },
          { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
        ],
      }),
    );

    // ── 4. seed the vocabulary per org ──────────────────────────────────────
    //
    // Per existing org, like 1700000039 / 1700000041. NOTE the standing gap
    // this shares with every other code list (federfall-buqb): nothing seeds an
    // organisation created AFTER this migration runs, so a second org starts
    // with an empty list here exactly as it does for conditions,
    // admission_reasons, marking_types and medication_routes.
    const savedTypes = app.findCollectionByNameOrId("microscopy_finding_types");
    for (const org of app.findAllRecords("organisations")) {
      for (const [label, sampleTypes] of SEED_FINDING_TYPES) {
        const rec = new Record(savedTypes);
        rec.set("label", label);
        rec.set("sample_types", sampleTypes);
        rec.set("active", true);
        rec.set("org", org.id);
        app.save(rec);
      }
    }
  },
  (app) => {
    // microscopy_findings references both others → delete it first.
    app.delete(app.findCollectionByNameOrId("microscopy_findings"));
    app.delete(app.findCollectionByNameOrId("microscopy_samples"));
    app.delete(app.findCollectionByNameOrId("microscopy_finding_types"));
  },
);
