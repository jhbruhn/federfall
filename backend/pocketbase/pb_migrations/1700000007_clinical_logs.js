/// <reference path="../pb_data/types.d.ts" />

// FED-1.7 — the per-case clinical logs: weights (time series → trend chart),
// medications (prescriptions), journal_entries (dated free-text log + photo
// attachments) and placements (enclosure & handoff / chain-of-custody history).
// All belong to a case (cascade on case delete) and carry an org tag + author.
//
// Access rules stay superuser-only; real rules in FED-1.11.

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    const caseRel = () => ({
      name: "case",
      type: "relation",
      required: true,
      maxSelect: 1,
      collectionId: cases.id,
      cascadeDelete: true,
    });
    const orgRel = () => ({
      name: "org",
      type: "relation",
      required: true,
      maxSelect: 1,
      collectionId: organisations.id,
      cascadeDelete: false,
    });
    const userRel = (name) => ({
      name,
      type: "relation",
      required: false,
      maxSelect: 1,
      collectionId: users.id,
      cascadeDelete: false,
    });
    const created = { name: "created", type: "autodate", onCreate: true, onUpdate: false };
    const updated = { name: "updated", type: "autodate", onCreate: true, onUpdate: true };

    // ── weights (drives the trend chart) ────────────────────────────────────
    app.save(
      new Collection({
        type: "base",
        name: "weights",
        fields: [
          caseRel(),
          { name: "measured_at", type: "date", required: false },
          { name: "weight_g", type: "number", required: true, min: 0 },
          { name: "notes", type: "text", required: false, max: 1000 },
          userRel("author"),
          orgRel(),
          created,
          updated,
        ],
      }),
    );

    // ── medications (prescriptions) ─────────────────────────────────────────
    app.save(
      new Collection({
        type: "base",
        name: "medications",
        fields: [
          caseRel(),
          // Drug name — free text now; may point at a medications code list later.
          { name: "drug", type: "text", required: true, presentable: true, max: 200 },
          { name: "concentration", type: "text", required: false, max: 100 },
          { name: "dose", type: "number", required: false, min: 0 },
          { name: "dose_unit", type: "text", required: false, max: 50 },
          { name: "frequency", type: "text", required: false, max: 100 },
          {
            name: "route",
            type: "select",
            required: false,
            maxSelect: 1,
            values: ["oral", "subcutaneous", "intramuscular", "intravenous", "topical", "nebulized", "other"],
          },
          { name: "started_at", type: "date", required: false },
          { name: "ended_at", type: "date", required: false },
          { name: "is_controlled", type: "bool", required: false },
          { name: "instructions", type: "text", required: false, max: 2000 },
          // Vet referral data (no vet login) — the prescriber's name.
          { name: "prescribed_by", type: "text", required: false, max: 200 },
          orgRel(),
          created,
          updated,
        ],
      }),
    );

    // ── journal_entries (dated free-text log + attachments) ─────────────────
    app.save(
      new Collection({
        type: "base",
        name: "journal_entries",
        fields: [
          caseRel(),
          { name: "entry_at", type: "date", required: false },
          { name: "text", type: "text", required: true, max: 10000 },
          { name: "attachments", type: "file", required: false, maxSelect: 20, maxSize: 26214400 },
          userRel("author"),
          orgRel(),
          created,
          updated,
        ],
      }),
    );

    // ── placements (enclosure & handoff / chain of custody) ─────────────────
    app.save(
      new Collection({
        type: "base",
        name: "placements",
        fields: [
          caseRel(),
          { name: "moved_in_at", type: "date", required: false },
          // The holder/carer who has the animal after this placement.
          userRel("carer"),
          { name: "where_holding", type: "text", required: false, max: 200 },
          { name: "area", type: "text", required: false, max: 200 },
          { name: "enclosure", type: "text", required: false, max: 200 },
          userRel("from_user"),
          userRel("to_user"),
          { name: "condition_at_handoff", type: "text", required: false, max: 2000 },
          { name: "comments", type: "text", required: false, max: 2000 },
          orgRel(),
          created,
          updated,
        ],
      }),
    );
  },
  (app) => {
    for (const name of ["placements", "journal_entries", "medications", "weights"]) {
      app.delete(app.findCollectionByNameOrId(name));
    }
  },
);
