/// <reference path="../pb_data/types.d.ts" />

// FED-1.6 — conditions (editable, supervisor-managed code list) + case_conditions
// (the diagnoses recorded on a case; many per case). A case_condition points at a
// `conditions` code-list row OR carries `free_text`. The default conditions list
// is seeded later in FED-1.10.
//
// `label` is a single free-text name in the user's own language (these are
// user-authored data, not translated app-UI strings — the German UI chrome is
// i18n'd separately via ARB files).
//
// Access rules stay superuser-only; real rules in FED-1.11.

migrate(
  (app) => {
    const organisations = app.findCollectionByNameOrId("organisations");

    // ── conditions code list ────────────────────────────────────────────────
    const conditions = new Collection({
      type: "base",
      name: "conditions",
      fields: [
        { name: "label", type: "text", required: true, presentable: true, max: 200 },
        // Notifiable disease (e.g. PMV / Paramyxovirose).
        { name: "is_notifiable", type: "bool", required: false },
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
    app.save(conditions);

    // ── case_conditions (diagnoses on a case) ───────────────────────────────
    const cases = app.findCollectionByNameOrId("cases");
    const caseConditions = new Collection({
      type: "base",
      name: "case_conditions",
      fields: [
        {
          name: "case",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: cases.id,
          cascadeDelete: true,
        },
        // Either a code-list condition OR free text (validated at the app layer).
        {
          name: "condition",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: conditions.id,
          cascadeDelete: false,
        },
        { name: "free_text", type: "text", required: false, max: 300 },
        { name: "certainty", type: "select", required: false, maxSelect: 1, values: ["suspected", "confirmed"] },
        { name: "onset_date", type: "date", required: false },
        { name: "resolved_date", type: "date", required: false },
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
    app.save(caseConditions);
  },
  (app) => {
    // case_conditions references conditions → delete it first.
    app.delete(app.findCollectionByNameOrId("case_conditions"));
    app.delete(app.findCollectionByNameOrId("conditions"));
  },
);
