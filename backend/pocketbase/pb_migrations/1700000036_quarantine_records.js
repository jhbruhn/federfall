/// <reference path="../pb_data/types.d.ts" />

// federfall-uvm — quarantine_records: quarantine promoted from a single
// `cases.quarantine_until` field to a timeline record kind (like weights /
// conditions / dispositions). Each row is one quarantine period: when it was
// imposed (`set_at`) and when it ends (`quarantine_until`), with an optional
// reason. Extending or lifting quarantine adds/edits a row; the *current* end
// per case is the latest row, exposed read-only by the `case_quarantine` view
// (next migration). A default 14-day row is created on case intake by the
// cases hook in main.pb.js.
//
// Visibility/edit follow the parent case, exactly like the other case child
// collections (the access-rule clauses are copied from FED-1.11 since this
// collection is created after that migration ran).

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const COORD_SUP = '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const SUP = '@request.auth.role = "supervisor"';
    const childView = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const childEdit = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;

    const cases = app.findCollectionByNameOrId("cases");
    const organisations = app.findCollectionByNameOrId("organisations");
    const users = app.findCollectionByNameOrId("users");

    const quarantine = new Collection({
      type: "base",
      name: "quarantine_records",
      listRule: childView,
      viewRule: childView,
      createRule: childEdit,
      updateRule: childEdit,
      deleteRule: childEdit,
      fields: [
        {
          name: "case",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: cases.id,
          cascadeDelete: true,
        },
        // When the quarantine was imposed (timeline ordering key; the default
        // intake row backdates this to admission).
        { name: "set_at", type: "date", required: false },
        // When the quarantine ends.
        { name: "quarantine_until", type: "date", required: true },
        { name: "reason", type: "text", required: false, max: 2000 },
        {
          name: "set_by",
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
    app.save(quarantine);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("quarantine_records"));
  },
);
