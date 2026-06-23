/// <reference path="../pb_data/types.d.ts" />

// FED-1.1 — organisations (single seed row) + users auth collection extensions.
//
// PocketBase ships a default `users` auth collection on first run; rather than
// recreate it (and lose the built-in email/password auth wiring) we extend it
// with the app-level fields the data model needs: role, org, is_active,
// invited_by, phone. The `organisations` collection is created first and seeded
// with a single deterministic row so `users.org` (and future collections) can
// reference a stable id.
//
// Access rules are intentionally left at the safe superuser-only default here;
// real private-by-default + role/share rules land in FED-1.11.

const ORG_ID = "org00000default"; // 15-char stable id for the single launch org

migrate(
  (app) => {
    // ── organisations ─────────────────────────────────────────────────────
    const organisations = new Collection({
      type: "base",
      name: "organisations",
      // rules null => superuser-only until FED-1.11 sets real access rules.
      // Field definitions are plain objects (the documented JSVM pattern for the
      // Collection constructor — Field class instances are not persisted here).
      fields: [
        { name: "name", type: "text", required: true, presentable: true, max: 200 },
        { name: "contact_email", type: "email", required: false },
        { name: "contact_phone", type: "text", required: false, max: 50 },
        // Free-form org settings (default release rules, etc.).
        { name: "settings", type: "json", required: false, maxSize: 200000 },
        { name: "created", type: "autodate", onCreate: true, onUpdate: false },
        { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
      ],
    });
    app.save(organisations);

    // ── seed the single launch organisation ───────────────────────────────
    const org = new Record(organisations);
    org.set("id", ORG_ID);
    org.set("name", "Federfall");
    app.save(org);

    // ── extend the default `users` auth collection ────────────────────────
    const users = app.findCollectionByNameOrId("users");

    users.fields.add(
      new SelectField({
        name: "role",
        required: true,
        maxSelect: 1,
        values: ["carer", "coordinator", "supervisor"],
      }),
    );
    users.fields.add(
      new RelationField({
        name: "org",
        required: true,
        maxSelect: 1,
        collectionId: organisations.id,
        cascadeDelete: false,
      }),
    );
    users.fields.add(new BoolField({ name: "is_active" }));
    users.fields.add(
      new RelationField({
        name: "invited_by",
        required: false,
        maxSelect: 1,
        collectionId: users.id, // self-reference: the supervisor who invited
        cascadeDelete: false,
      }),
    );
    users.fields.add(new TextField({ name: "phone", required: false, max: 50 }));

    app.save(users);
  },
  (app) => {
    // ── down: strip the added user fields, then drop organisations ────────
    const users = app.findCollectionByNameOrId("users");
    for (const name of ["role", "org", "is_active", "invited_by", "phone"]) {
      users.fields.removeByName(name);
    }
    app.save(users);

    const organisations = app.findCollectionByNameOrId("organisations");
    app.delete(organisations);
  },
);
