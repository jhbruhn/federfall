/// <reference path="../pb_data/types.d.ts" />

// federfall-4agw.1 — egg_records: egg-laying as a longitudinal property of the
// ANIMAL, the stance 1700000020 took for weights. A laying history belongs to
// the bird when it moves between carers, cases and aviaries, and chronic laying
// is the input to calcium-depletion / egg-binding risk.
//
// One row = one laying event, with `count` for "found 2, exact dates unknown".
// A clutch is DERIVED client-side (gap > 5 days ⇒ new clutch), not stored — no
// second collection, no hook.
//
// There is deliberately NO `case` field. `markings` is the precedent: it owns
// `animal` only, and the case timeline shows markings by pulling
// `animal.markings_via_animal` through the case bundle — timeline membership is
// computed from the animal, never stored. Eggs drop even markings'
// `applied_in_case` breadcrumb: a ring never changes owner, but an egg's whole
// point is that attribution moves, and a stale case pointer is worse than none.
// Payoff: reassigning an egg is a single field write, and the row automatically
// leaves the old bird's case timeline and appears on the new bird's.
// Consequence accepted: eggs are absent from the `case_activity` view
// (1700000022), which unions on case columns — logging an egg does not bump a
// case's activity timestamp.
//
// `aviary` is likewise absent: aviary_stays (1700000052) already answers "where
// was this bird on that date", and a denormalized copy would drift. Egg binding
// / Legenot is an acute finding and belongs in case_conditions, not here.
//
// `photos` is born correct — protected + MIME allowlist + thumbs, all inline.
// 1700000027 / 1700000048 / 1700000049 are each a repair pass over file fields
// that shipped without one of those, and they carry hardcoded target lists, so a
// new field only gets the treatment if it is created with it. It is multi
// (maxSelect 3) rather than maxSelect 1 because PocketBase stores a string for
// single and an array for multi: switching later would change `List<String>
// photos` back and forth in the model and at every call site.
//
// Access is the animal identity layer (5yg.4), in the guest-safe form required
// since 1700000045: org-wide read/create/update because a laying date is
// low-sensitivity animal-identity data that must stay visible across cases and
// aviary residency. Delete is author-or-supervisor, copying 1700000047 —
// destruction is the part worth restricting, contribution isn't.
//
// IMPORTANT: `animal` is deliberately NOT guarded with
// `@request.body.animal:isset = false`. Reassignment IS a PATCH of `animal`, so
// that guard would remove the feature. This is the same exemption 1700000043
// grants the org-wide identity-layer collections (weights / animals /
// markings): re-pointing a row grants the writer nothing they don't already
// have org-wide. `org` DOES carry the guard — re-scoping a row across orgs is
// never legitimate.
//
// The one thing rules cannot cover as a result: re-pointing `animal` at ANOTHER
// org's bird. A field reference in an update rule is evaluated against the
// STORED record (1700000043), so `animal.org = @request.auth.org` here would
// check the old animal, not the new one. That invariant is enforced in
// pb_hooks/animal_org_scope.pb.js instead (federfall-ti77, which found the same
// hole in cases / weights / markings / exams), the way intake.pb.js and
// exam.pb.js validate their other referenced records.
//
// PocketBase has no schema-level field defaults, so the documented defaults
// (`count` 1, `fertility`/`fate` "unknown", `attribution` "confirmed") live in
// the Dart model and the entry sheet. `count` is required so a missing value
// fails loudly instead of silently storing a 0-egg laying event.

migrate(
  (app) => {
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';

    const animals = app.findCollectionByNameOrId("animals");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    const orgScoped = `${AUTH} && org = @request.auth.org`;

    app.save(
      new Collection({
        type: "base",
        name: "egg_records",
        listRule: orgScoped,
        viewRule: orgScoped,
        createRule: orgScoped,
        // `animal` stays mutable on purpose — see the note above.
        updateRule: `${orgScoped} && @request.body.org:isset = false`,
        deleteRule:
          `${orgScoped} && ` +
          '(@request.auth.role = "supervisor" || author = @request.auth.id)',
        fields: [
          // The owning relation, and the one this feature exists to move.
          {
            name: "animal",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: animals.id,
            cascadeDelete: true,
          },
          // The UI always sets this; the model falls back to `created`, like
          // weights.measured_at.
          { name: "laid_at", type: "date", required: false },
          {
            name: "count",
            type: "number",
            required: true,
            min: 1,
            onlyInt: true,
          },
          {
            name: "fertility",
            type: "select",
            required: false,
            maxSelect: 1,
            values: ["unknown", "fertile", "infertile"],
          },
          {
            name: "fate",
            type: "select",
            required: false,
            maxSelect: 1,
            values: [
              "in_nest",
              "dummy_swapped",
              "removed",
              "hatched",
              "broken",
              "discarded",
              "unknown",
            ],
          },
          // Records the doubt instead of silently asserting a guess: in a pair
          // you often don't know which hen laid a clutch until later.
          // Reassignment flips this to "confirmed".
          {
            name: "attribution",
            type: "select",
            required: false,
            maxSelect: 1,
            values: ["confirmed", "presumed"],
          },
          // Optional documentation of an abnormal egg (e.g. a Windei).
          {
            name: "photos",
            type: "file",
            required: false,
            maxSelect: 3,
            maxSize: 10485760,
            mimeTypes: ["image/jpeg", "image/png", "image/webp", "image/gif"],
            thumbs: ["200x200"],
            protected: true,
          },
          { name: "notes", type: "text", required: false, max: 2000 },
          // Drives the delete rule.
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
      }),
    );
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("egg_records"));
  },
);
