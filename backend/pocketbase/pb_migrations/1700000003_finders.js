/// <reference path="../pb_data/types.d.ts" />

// FED-1.4 — finders: the rescuer/finder of a bird — an EXTERNAL person, distinct
// from staff `users`. GDPR/DSGVO-sensitive PII: the access rules (FED-1.11) keep
// these visible only to users who can view the parent case, and FED-8.1 adds a
// retention policy. Created before `cases` (FED-1.3) because cases relate to it.
//
// All contact fields are optional — a finder is often captured from a single
// phone number or just a first name. Access rules stay superuser-only until
// FED-1.11.

migrate(
  (app) => {
    const finders = new Collection({
      type: "base",
      name: "finders",
      fields: [
        { name: "first_name", type: "text", required: false, max: 100 },
        { name: "last_name", type: "text", required: false, presentable: true, max: 100 },
        { name: "organisation", type: "text", required: false, max: 200 },
        { name: "phone", type: "text", required: false, max: 50 },
        { name: "alt_phone", type: "text", required: false, max: 50 },
        { name: "email", type: "email", required: false },
        { name: "address", type: "text", required: false, max: 300 },
        { name: "postal_code", type: "text", required: false, max: 20 },
        { name: "city", type: "text", required: false, max: 150 },
        // Subdivision / Bundesland / region.
        { name: "region", type: "text", required: false, max: 150 },
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
    app.save(finders);
  },
  (app) => {
    const finders = app.findCollectionByNameOrId("finders");
    app.delete(finders);
  },
);
