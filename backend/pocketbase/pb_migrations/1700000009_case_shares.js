/// <reference path="../pb_data/types.d.ts" />

// FED-1.9 — case_shares: the opt-in sharing rows that implement "private by
// default, shared if desired". A row grants one user read or edit access to a
// case; the FED-1.11 rules and the share-on-handoff hook (FED-1.12) consume it.
// One share per (case, user) — enforced by a unique index.
//
// Access rules stay superuser-only; real rules in FED-1.11.

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    const caseShares = new Collection({
      type: "base",
      name: "case_shares",
      indexes: [
        "CREATE UNIQUE INDEX `idx_case_shares_case_user` ON `case_shares` (`case`, `shared_with`)",
      ],
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
          name: "shared_with",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: users.id,
          cascadeDelete: true,
        },
        { name: "access", type: "select", required: true, maxSelect: 1, values: ["read", "edit"] },
        {
          name: "shared_by",
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
    app.save(caseShares);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("case_shares"));
  },
);
