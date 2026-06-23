/// <reference path="../pb_data/types.d.ts" />

// FED-1.2 — animals: the persistent animal identity that spans every admission.
//
// An animal has many cases (care episodes). Clinical data attaches to a case but
// rolls up to the animal for a lifetime history. Re-identification is carried by
// `markings` (FED-1.5), not flat fields here.
//
// Deferred on purpose:
//   - `current_aviary` (→ aviaries): the aviaries collection only exists from
//     FED-1.8, so that relation field is added to `animals` there.
//   - `species` has no schema-level default (PocketBase text fields don't support
//     one); the intake form pre-fills "Stadttaube"/feral pigeon. A species code
//     list is a future extension.
//   - `lifetime_status` is maintained by hooks (FED-1.12) from the latest case
//     disposition; it is non-required so creation can leave it for the hook.
//
// Access rules stay at the superuser-only default; real rules land in FED-1.11.

migrate(
  (app) => {
    const animals = new Collection({
      type: "base",
      name: "animals",
      fields: [
        // Primary human-facing label across the UI (falls back to case number
        // when unnamed) — optional but encouraged.
        { name: "name", type: "text", required: false, presentable: true, max: 100 },
        // First-class species field; defaults to feral pigeon at the form layer.
        { name: "species", type: "text", required: true, max: 100 },
        { name: "sex", type: "select", required: false, maxSelect: 1, values: ["male", "female", "unknown"] },
        // Racing-pigeon flag — set when a finder/owner ring identifies an owned bird.
        { name: "is_owned", type: "bool", required: false },
        // Derived from the latest case/disposition by the FED-1.12 hooks.
        {
          name: "lifetime_status",
          type: "select",
          required: false,
          maxSelect: 1,
          values: ["in_care", "at_large_released", "in_aviary", "deceased"],
        },
        { name: "tags", type: "json", required: false, maxSize: 50000 },
        { name: "notes", type: "text", required: false, max: 5000 },
        {
          name: "org",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: app.findCollectionByNameOrId("organisations").id,
          cascadeDelete: false,
        },
        { name: "created", type: "autodate", onCreate: true, onUpdate: false },
        { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
      ],
    });
    app.save(animals);
  },
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");
    app.delete(animals);
  },
);
