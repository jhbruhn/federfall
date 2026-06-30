/// <reference path="../pb_data/types.d.ts" />

// federfall — animal_species: a read-only view of the DISTINCT species (animal
// kinds) recorded per org, so the case-intake species field can autocomplete
// from kinds the team has already used instead of every carer re-typing them.
//
// One row per (org, species). `id` is MIN(animals.id) within the group — a real,
// unique record id (each animal belongs to exactly one group), which keeps the
// view a valid PocketBase collection without a synthetic key. Empty species are
// excluded.
//
// Org-scoped readable for any active member; animals are already org-wide
// readable (the shared identity layer), so the distinct kinds leak nothing new.
// Read-only by nature (view collection); the species field itself stays free
// text on `animals` — this only powers suggestions.

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const orgScoped = `${AUTH} && org = @request.auth.org`;

    const view = new Collection({
      type: "view",
      name: "animal_species",
      listRule: orgScoped,
      viewRule: orgScoped,
      viewQuery: `
        SELECT
          MIN(a.id) AS id,
          a.org     AS org,
          a.species AS species
        FROM animals a
        WHERE a.species != ''
        GROUP BY a.org, a.species
      `,
    });
    app.save(view);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("animal_species"));
  },
);
