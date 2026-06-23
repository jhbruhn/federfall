/// <reference path="../pb_data/types.d.ts" />

// FED-1.8 — aviaries (named permanent-care enclosures / Volieren where
// non-releasable birds live as residents) + dispositions (the outcome of a case;
// typically one final row, history allowed). Also wires up the `current_aviary`
// relation on `animals` that was deferred from FED-1.2 (aviaries didn't exist
// yet).
//
// A `placed_in_aviary` disposition makes the animal a resident; the case stays
// "alive" and can keep receiving clinical entries (permanent care = the resident
// state, not a disposition type of its own).
//
// Access rules stay superuser-only; real rules in FED-1.11.

migrate(
  (app) => {
    const organisations = app.findCollectionByNameOrId("organisations");
    const users = app.findCollectionByNameOrId("users");
    const cases = app.findCollectionByNameOrId("cases");

    // ── aviaries ────────────────────────────────────────────────────────────
    const aviaries = new Collection({
      type: "base",
      name: "aviaries",
      fields: [
        { name: "name", type: "text", required: true, presentable: true, max: 200 },
        // Owner / responsible person.
        {
          name: "keeper",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: users.id,
          cascadeDelete: false,
        },
        { name: "location", type: "text", required: false, max: 300 },
        { name: "location_geo", type: "geoPoint", required: false },
        { name: "capacity", type: "number", required: false, min: 0 },
        { name: "active", type: "bool", required: false },
        { name: "notes", type: "text", required: false, max: 2000 },
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
    app.save(aviaries);

    // ── dispositions (case outcome) ─────────────────────────────────────────
    const dispositions = new Collection({
      type: "base",
      name: "dispositions",
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
          name: "type",
          type: "select",
          required: true,
          maxSelect: 1,
          values: ["released", "placed_in_aviary", "died", "euthanized", "transferred", "returned_to_owner"],
        },
        { name: "disposed_at", type: "date", required: false },
        { name: "reason", type: "text", required: false, max: 2000 },
        {
          name: "performed_by",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: users.id,
          cascadeDelete: false,
        },
        // released (wild / outside release)
        { name: "release_location", type: "text", required: false, max: 300 },
        { name: "release_geo", type: "geoPoint", required: false },
        { name: "release_type", type: "text", required: false, max: 100 },
        // placed_in_aviary
        {
          name: "aviary",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: aviaries.id,
          cascadeDelete: false,
        },
        // transferred
        { name: "transfer_type", type: "text", required: false, max: 100 },
        { name: "transfer_destination", type: "text", required: false, max: 300 },
        // optional vet sign-off flag (no vet login)
        { name: "vet_signed_off", type: "bool", required: false },
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
    app.save(dispositions);

    // ── deferred from FED-1.2: animals.current_aviary ───────────────────────
    const animals = app.findCollectionByNameOrId("animals");
    animals.fields.add(
      new RelationField({
        name: "current_aviary",
        required: false,
        maxSelect: 1,
        collectionId: aviaries.id,
        cascadeDelete: false,
      }),
    );
    app.save(animals);
  },
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");
    animals.fields.removeByName("current_aviary");
    app.save(animals);

    app.delete(app.findCollectionByNameOrId("dispositions"));
    app.delete(app.findCollectionByNameOrId("aviaries"));
  },
);
