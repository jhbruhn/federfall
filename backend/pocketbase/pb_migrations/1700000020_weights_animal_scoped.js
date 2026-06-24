/// <reference path="../pb_data/types.d.ts" />

// 5yg.4 — weights become animal-scoped. A weight is a low-sensitivity
// longitudinal measurement of the ANIMAL (tracked across cases and during
// aviary residency), not strictly a per-case clinical record. So:
//   - add required `animal`; make `case` optional (set only when the weight is
//     taken during a treatment episode);
//   - the weight is owned by the animal (cascade on animal delete, not case);
//   - access follows the animal identity layer (org-wide readable + writable),
//     same stance as markings — a weight number is not case-private detail.

migrate(
  (app) => {
    const weights = app.findCollectionByNameOrId("weights");
    const animals = app.findCollectionByNameOrId("animals");

    // case: optional, and no longer cascade-deletes the weight (the weight is
    // the animal's history; deleting a case must not erase it).
    const caseField = weights.fields.getByName("case");
    caseField.required = false;
    caseField.cascadeDelete = false;

    // animal: add non-required first so existing rows pass validation.
    weights.fields.add(
      new Field({
        name: "animal",
        type: "relation",
        required: false,
        maxSelect: 1,
        collectionId: animals.id,
        cascadeDelete: true,
      }),
    );
    app.save(weights);

    // Backfill animal from each weight's parent case.
    for (const r of app.findAllRecords("weights")) {
      if (!r.getString("animal") && r.getString("case")) {
        const c = app.findRecordById("cases", r.getString("case"));
        if (c) {
          r.set("animal", c.getString("animal"));
          app.save(r);
        }
      }
    }

    // Now require animal.
    weights.fields.getByName("animal").required = true;
    app.save(weights);

    // Animal identity-layer access (org-wide), like markings.
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const orgScoped = `${AUTH} && org = @request.auth.org`;
    weights.listRule = orgScoped;
    weights.viewRule = orgScoped;
    weights.createRule = orgScoped;
    weights.updateRule = orgScoped;
    weights.deleteRule = orgScoped;
    app.save(weights);
  },
  (app) => {
    const weights = app.findCollectionByNameOrId("weights");
    weights.fields.removeByName("animal");
    const caseField = weights.fields.getByName("case");
    caseField.required = true;
    caseField.cascadeDelete = true;

    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const childView = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const childEdit = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;
    weights.listRule = childView;
    weights.viewRule = childView;
    weights.createRule = childEdit;
    weights.updateRule = childEdit;
    weights.deleteRule = childEdit;
    app.save(weights);
  },
);
