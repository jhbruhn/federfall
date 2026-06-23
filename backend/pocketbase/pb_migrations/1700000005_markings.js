/// <reference path="../pb_data/types.d.ts" />

// FED-1.5 — markings: rings, bands, microchips and temporary markers carried by
// an animal over its whole lifetime. This is what drives re-identification: at
// intake a scanned/entered `code` is searched against active markings to surface
// a returning animal and its prior history (FED-4.10). An animal has many
// markings; they belong to the animal (cascade on delete).
//
// Access rules stay superuser-only; real rules in FED-1.11.

migrate(
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");
    const users = app.findCollectionByNameOrId("users");
    const cases = app.findCollectionByNameOrId("cases");
    const organisations = app.findCollectionByNameOrId("organisations");

    const markings = new Collection({
      type: "base",
      name: "markings",
      // Re-identification lookups search by code; index it (non-unique — codes
      // can repeat across schemes / be reused after removal).
      indexes: ["CREATE INDEX `idx_markings_code` ON `markings` (`code`)"],
      fields: [
        {
          name: "animal",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: animals.id,
          cascadeDelete: true,
        },
        {
          name: "type",
          type: "select",
          required: true,
          maxSelect: 1,
          values: ["finder_ring", "temporary_marker", "release_ring", "association_ring", "microchip"],
        },
        { name: "code", type: "text", required: false, presentable: true, max: 100 },
        // Issuing organisation (DV/RPRA, or the association's own scheme).
        { name: "scheme_org", type: "text", required: false, max: 200 },
        { name: "colour", type: "text", required: false, max: 100 },
        { name: "applied_at", type: "date", required: false },
        {
          name: "applied_by",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: users.id,
          cascadeDelete: false,
        },
        // The episode during which the marking was added.
        {
          name: "applied_in_case",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: cases.id,
          cascadeDelete: false,
        },
        { name: "removed_at", type: "date", required: false },
        { name: "removed_reason", type: "text", required: false, max: 300 },
        { name: "is_active", type: "bool", required: false },
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
    app.save(markings);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("markings"));
  },
);
