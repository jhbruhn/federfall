/// <reference path="../pb_data/types.d.ts" />

// FED-1.12 — widen users.updateRule to allow self-service profile edits now that
// the field-guard hook (pb_hooks/main.pb.js) blocks role/org/is_active/verified
// changes by non-supervisors. Without that guard a self-update would be a
// privilege-escalation hole, which is why FED-1.11 kept this supervisor-only.

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    users.updateRule =
      '@request.auth.id != "" && @request.auth.is_active = true && (@request.auth.id = id || (@request.auth.role = "supervisor" && org = @request.auth.org))';
    app.save(users);
  },
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    users.updateRule =
      '@request.auth.id != "" && @request.auth.is_active = true && @request.auth.role = "supervisor" && org = @request.auth.org';
    app.save(users);
  },
);
