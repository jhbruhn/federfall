/// <reference path="../pb_data/types.d.ts" />

// UX Phase C / blp.1 — trim the case status lifecycle to three states.
//
// Decision: in_care -> ready_for_release -> disposed. The intermediate
// in_treatment / rehab states were never set by any hook and added noise;
// treatment progress lives in the case timeline, not the status field.
// ready_for_release is a manual flag a carer sets; disposed is set by the
// disposition hook. No existing data uses the dropped values (hooks only ever
// set in_care / disposed), so this is a safe narrowing.
migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const field = cases.fields.getByName("status");
    field.values = ["in_care", "ready_for_release", "disposed"];
    app.save(cases);
  },
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const field = cases.fields.getByName("status");
    field.values = [
      "in_care",
      "in_treatment",
      "rehab",
      "ready_for_release",
      "disposed",
    ];
    app.save(cases);
  },
);
