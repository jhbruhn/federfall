/// <reference path="../pb_data/types.d.ts" />

// federfall-d1uv — users.updateRule (1700000011) pins the TARGET's current org
// (org = @request.auth.org) but never constrained the NEW org value in the
// request body. The field-guard hook (pb_hooks/main.pb.js) only blocks
// role/org/is_active/verified changes by non-supervisors, so a supervisor of
// org A could set org=B on a user in org A, planting themselves (or anyone
// they control) inside org B — OWASP A01, cross-org privilege escalation.
//
// Fix: require the request body's org (if present) to equal the caller's own
// org, on both the self-update and supervisor branches — a supervisor moving
// *themselves* would otherwise dodge the guard via the self-update clause.

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    users.updateRule =
      '@request.auth.id != "" && @request.auth.is_active = true && (@request.auth.id = id || (@request.auth.role = "supervisor" && org = @request.auth.org)) && (@request.body.org:isset = false || @request.body.org = @request.auth.org)';
    app.save(users);
  },
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    users.updateRule =
      '@request.auth.id != "" && @request.auth.is_active = true && (@request.auth.id = id || (@request.auth.role = "supervisor" && org = @request.auth.org))';
    app.save(users);
  },
);
