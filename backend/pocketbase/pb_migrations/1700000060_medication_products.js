/// <reference path="../pb_data/types.d.ts" />

// federfall-6d3a.3 — an org-managed drug catalogue behind the prescription form.
//
// A carer should not have to re-type "20 mg/kg, 15 mg/ml, subkutan, 2× täglich"
// from a bottle every time a plan is written, and the numbers that decide a dose
// should have an owner. This is that owner: a supervisor-maintained list per
// organisation, exactly like conditions / admission_reasons / marking_types /
// medication_routes (1700000041), which prefills the prescription form and
// supplies the sane range a rate is checked against.
//
// Fields mirror the prescription, on purpose:
//
//   dose_unit             the unit every number here is in (see 1700000058)
//   dose_rate             the usual rate per kilogram
//   rate_min / rate_max   the range outside which the form warns
//   concentration_per_ml  the stock strength
//   route                 default route of administration
//   frequency_kind + interval_hours  the default schedule
//
// NO CLINICAL VALUES ARE SHIPPED. The three seeded rows are placeholders
// ("Medikament 1..3") so a supervisor opening the admin screen sees the shape of
// an entry and edits it, rather than facing an empty list — every dose-bearing
// number stays empty for the org's vet to fill. A bundled formulary would make
// this repository the source of a figure that killed a bird, and it would go
// stale; the org owns its own protocol.

const PLACEHOLDER_LABELS = ["Medikament 1", "Medikament 2", "Medikament 3"];

migrate(
  (app) => {
    const organisations = app.findCollectionByNameOrId("organisations");
    const routes = app.findCollectionByNameOrId("medication_routes");

    // Guest-safe form, per 1700000045: a self-registered account authenticates
    // but must see no org data until a supervisor grants it a real role. The
    // guest sweep in tests/test_rules.py fails loudly if this is forgotten.
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true && @request.auth.role != "guest"';
    const orgScoped = `${AUTH} && org = @request.auth.org`;
    const supervisor = `${AUTH} && @request.auth.role = "supervisor" && org = @request.auth.org`;

    const products = new Collection({
      type: "base",
      name: "medication_products",
      // Everyone in the org reads it (it prefills their prescription form);
      // only a supervisor maintains it.
      listRule: orgScoped,
      viewRule: orgScoped,
      createRule: supervisor,
      updateRule: supervisor,
      deleteRule: supervisor,
      fields: [
        { name: "label", type: "text", required: true, presentable: true, max: 200 },
        { name: "dose_unit", type: "text", required: false, max: 50 },
        { name: "dose_rate", type: "number", required: false, min: 0 },
        { name: "rate_min", type: "number", required: false, min: 0 },
        { name: "rate_max", type: "number", required: false, min: 0 },
        {
          name: "concentration_per_ml",
          type: "number",
          required: false,
          min: 0,
        },
        {
          name: "route",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: routes.id,
          cascadeDelete: false,
        },
        {
          name: "frequency_kind",
          type: "select",
          required: false,
          maxSelect: 1,
          values: ["once", "scheduled", "as_needed"],
        },
        { name: "interval_hours", type: "number", required: false, min: 1 },
        { name: "note", type: "text", required: false, max: 2000 },
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
    app.save(products);

    const saved = app.findCollectionByNameOrId("medication_products");
    for (const org of app.findAllRecords("organisations")) {
      for (const label of PLACEHOLDER_LABELS) {
        const rec = new Record(saved);
        rec.set("label", label);
        rec.set("dose_unit", "mg");
        rec.set("active", true);
        rec.set("org", org.id);
        app.save(rec);
      }
    }
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("medication_products"));
  },
);
