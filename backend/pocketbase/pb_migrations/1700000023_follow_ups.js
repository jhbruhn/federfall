/// <reference path="../pb_data/types.d.ts" />

// cr3.4 — follow_ups: one-off, future-dated rechecks on a case ("recheck the
// wound Thursday", "vet visit next week"). A clinical timeline record like the
// others, and the worklist's "follow-up due" source. Recurring cadence stays
// medications' job; this is a single dated reminder with an optional note and a
// done stamp.
//
// Case-scoped access mirrors the other child collections (FED-1.11): viewable
// by the case's carer / coordinators+supervisors / shared users; editable by
// the carer / supervisor / edit-shared users. Self-contained migration.

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    app.save(
      new Collection({
        type: "base",
        name: "follow_ups",
        fields: [
          {
            name: "case",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: cases.id,
            cascadeDelete: true,
          },
          { name: "due_at", type: "date", required: true },
          { name: "note", type: "text", required: false, max: 2000 },
          { name: "done_at", type: "date", required: false },
          {
            name: "created_by",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: users.id,
          },
          {
            name: "org",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: organisations.id,
          },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
          {
            name: "updated",
            type: "autodate",
            onCreate: true,
            onUpdate: true,
          },
        ],
      }),
    );

    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const childView = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const childEdit = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;

    const c = app.findCollectionByNameOrId("follow_ups");
    c.listRule = childView;
    c.viewRule = childView;
    c.createRule = childEdit;
    c.updateRule = childEdit;
    c.deleteRule = childEdit;
    app.save(c);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("follow_ups"));
  },
);
