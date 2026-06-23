/// <reference path="../pb_data/types.d.ts" />

// FED-4.6 — medication_administrations: a single dose actually given.
//
// The `medications` collection (FED-1.x) is the *prescription / plan* (drug,
// dose, route, frequency, dates, controlled, prescribing vet). This collection
// records an *administration event*: one dose given at a point in time. It may
// reference a prescription (a dose from a plan) or stand alone (an ad-hoc dose
// with no plan), so drug/dose/route are denormalized onto each event — a dose
// stays meaningful even if its plan is later removed.
//
// Visibility/edit follow the parent case, exactly like the other clinical
// child collections (same childView/childEdit rules as FED-1.11).

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const medications = app.findCollectionByNameOrId("medications");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    app.save(
      new Collection({
        type: "base",
        name: "medication_administrations",
        fields: [
          {
            name: "case",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: cases.id,
            cascadeDelete: true,
          },
          // Optional link to the prescription this dose follows.
          {
            name: "medication",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: medications.id,
            cascadeDelete: false,
          },
          // Denormalized so an ad-hoc dose (no plan) is self-contained.
          { name: "drug", type: "text", required: true, presentable: true, max: 200 },
          { name: "dose", type: "number", required: false, min: 0 },
          { name: "dose_unit", type: "text", required: false, max: 50 },
          {
            name: "route",
            type: "select",
            required: false,
            maxSelect: 1,
            values: ["oral", "subcutaneous", "intramuscular", "intravenous", "topical", "nebulized", "other"],
          },
          { name: "administered_at", type: "date", required: true },
          {
            name: "administered_by",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: users.id,
            cascadeDelete: false,
          },
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
      }),
    );

    // Access rules: visibility/edit follow the parent case (mirrors FED-1.11).
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP = '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const childView = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const childEdit = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;

    const c = app.findCollectionByNameOrId("medication_administrations");
    c.listRule = childView;
    c.viewRule = childView;
    c.createRule = childEdit;
    c.updateRule = childEdit;
    c.deleteRule = childEdit;
    app.save(c);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("medication_administrations"));
  },
);
