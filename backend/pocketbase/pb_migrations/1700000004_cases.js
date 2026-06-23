/// <reference path="../pb_data/types.d.ts" />

// FED-1.3 — cases: one care episode (admission → disposition), the unit carers
// work on. An animal has many cases (re-admission supported). Most clinical data
// (weights, meds, journal, conditions, placements, disposition) attaches to a
// case and rolls up to the animal.
//
// Maintained by the FED-1.12 hooks, so left non-required here:
//   - `case_number` — auto per-year (e.g. "2026-014"); a unique index enforces it.
//   - `quarantine_until` — defaults to admitted_at + 14 days.
//   - `status` — derived/maintained from the case lifecycle (default in_care).
//
// `find_geo` is a geoPoint pin (OSM/Nominatim geocoded, FED-4.2) alongside the
// textual `find_location` address. The optional structured intake exam is a set
// of `exam_*` fields (all optional; surfaced by the expandable FED-4.8 form).
//
// Access rules stay superuser-only; private-by-default + share/role rules in
// FED-1.11.

migrate(
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");
    const users = app.findCollectionByNameOrId("users");
    const finders = app.findCollectionByNameOrId("finders");
    const organisations = app.findCollectionByNameOrId("organisations");

    const cases = new Collection({
      type: "base",
      name: "cases",
      indexes: ["CREATE UNIQUE INDEX `idx_cases_case_number` ON `cases` (`case_number`)"],
      fields: [
        {
          name: "animal",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: animals.id,
          cascadeDelete: false,
        },
        // Auto per-year identifier; populated by the FED-1.12 hook before insert.
        { name: "case_number", type: "text", required: false, presentable: true, max: 20 },
        {
          name: "age_class",
          type: "select",
          required: false,
          maxSelect: 1,
          values: ["squab", "fledgling", "immature", "adult"],
        },

        // ── intake ──────────────────────────────────────────────────────────
        { name: "admitted_at", type: "date", required: false },
        { name: "found_at", type: "date", required: false },
        {
          name: "admitted_by",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: users.id,
          cascadeDelete: false,
        },
        { name: "transported_by", type: "text", required: false, max: 200 },
        {
          name: "finder",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: finders.id,
          cascadeDelete: false,
        },

        // ── find location (address + geocoded pin) ──────────────────────────
        { name: "find_location", type: "text", required: false, max: 300 },
        { name: "find_geo", type: "geoPoint", required: false },
        { name: "city", type: "text", required: false, max: 150 },
        { name: "region", type: "text", required: false, max: 150 },

        {
          name: "reasons_for_admission",
          type: "select",
          required: false,
          maxSelect: 12,
          values: [
            "injury",
            "illness",
            "orphaned",
            "trauma",
            "poisoning",
            "trapped",
            "cat_attack",
            "collision",
            "oiled",
            "entangled",
            "weak_emaciated",
            "other",
          ],
        },
        { name: "intake_weight_g", type: "number", required: false, min: 0 },
        { name: "intake_notes", type: "text", required: false, max: 5000 },
        { name: "intake_photos", type: "file", required: false, maxSelect: 20, maxSize: 10485760 },

        { name: "quarantine_until", type: "date", required: false },
        {
          name: "status",
          type: "select",
          required: false,
          maxSelect: 1,
          values: ["in_care", "in_treatment", "rehab", "ready_for_release", "disposed"],
        },
        { name: "is_releasable", type: "bool", required: false },
        {
          name: "active_carer",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: users.id,
          cascadeDelete: false,
        },

        // ── optional structured intake exam (all optional; FED-4.8) ─────────
        { name: "exam_bcs", type: "number", required: false, min: 0, max: 9 },
        { name: "exam_dehydration", type: "text", required: false, max: 100 },
        { name: "exam_attitude", type: "text", required: false, max: 200 },
        { name: "exam_temperature", type: "number", required: false },
        { name: "exam_mm_color", type: "text", required: false, max: 100 },
        { name: "exam_mm_texture", type: "text", required: false, max: 100 },
        { name: "exam_head", type: "text", required: false, max: 1000 },
        { name: "exam_cns", type: "text", required: false, max: 1000 },
        { name: "exam_cardiopulmonary", type: "text", required: false, max: 1000 },
        { name: "exam_gi", type: "text", required: false, max: 1000 },
        { name: "exam_musculoskeletal", type: "text", required: false, max: 1000 },
        { name: "exam_integument", type: "text", required: false, max: 1000 },
        { name: "exam_forelimb", type: "text", required: false, max: 1000 },
        { name: "exam_hindlimb", type: "text", required: false, max: 1000 },

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
    app.save(cases);
  },
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    app.delete(cases);
  },
);
