/// <reference path="../pb_data/types.d.ts" />

// federfall-49l.3 — let OAuth2 self-registration create a users record.
//
// The users createRule is supervisor-only (invite-only), but an OAuth2 sign-up
// happens with NO authenticated user, so that rule rejects the auto-created
// record ("create rule failure") and sign-in fails. PocketBase sets
// `@request.context = "oauth2"` during this flow (and the context cannot be
// forged from a normal API call), so we allow creation in that context too —
// the provisioning hook (oauth2_provisioning.pb.js) then assigns role/org and
// enforces any group gating. Anonymous direct POSTs (context "default") stay
// blocked, and supervisor invites are unchanged.

const OAUTH2 = '@request.context = "oauth2"';

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    const cur = String(users.createRule || "");
    if (!cur.includes(OAUTH2)) {
      users.createRule = OAUTH2 + " || (" + cur + ")";
      app.save(users);
    }
  },
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    const cur = String(users.createRule || "");
    const prefix = OAUTH2 + " || (";
    if (cur.startsWith(prefix) && cur.endsWith(")")) {
      users.createRule = cur.slice(prefix.length, -1);
      app.save(users);
    }
  },
);
