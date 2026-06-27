/// <reference path="../pb_data/types.d.ts" />

// FED-8 (federfall-49l.3) — add a `guest` role and wall it off from all data.
//
// Self-registered OAuth2 users land as `guest`: they can authenticate (the users
// authRule stays `is_active = true`) so the app can show an "awaiting access"
// state, but every collection's access rule excludes them until a supervisor
// promotes them. Without this a guest would inherit the "any active member"
// grants (org-wide read + create on animals/markings/finders/cases) — a hole.
//
// The access boundary is built from a shared predicate
//   @request.auth.id != "" && @request.auth.is_active = true
// applied verbatim at the head of every app rule. We append a guest exclusion to
// that exact substring wherever it appears, so the change tracks all rules
// (incl. those set by later migrations) without re-listing them. The users
// authRule is intentionally NOT touched — guests must still be able to log in.

const BASE_AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
const GUEST_SAFE_AUTH = BASE_AUTH + ' && @request.auth.role != "guest"';

// Rules are rewritten via a handle re-fetched by name: collections returned by
// findAllCollections() are read-only snapshots whose property assignments don't
// persist, whereas findCollectionByNameOrId() yields a mutable, saveable one.
// (Dynamic bracket assignment c["listRule"] = … also no-ops; assign by name.)
function rewriteRules(app, from, to) {
  for (const snapshot of app.findAllCollections()) {
    if (!snapshot || snapshot.system) continue;
    const c = app.findCollectionByNameOrId(snapshot.name);
    let changed = false;
    // Rules come back as goja-wrapped String objects (typeof "object", not
    // "string"), so coerce with String() before matching — a `typeof ===
    // "string"` guard silently skips them all. null/undefined (no rule) is left
    // as-is; a `changed` flag avoids re-saving (and re-validating) views and
    // collections that carry no auth-predicate rule.
    const tx = (s) => {
      if (s === null || s === undefined) return s;
      const str = String(s);
      if (!str.includes(from)) return str;
      changed = true;
      return str.split(from).join(to);
    };
    c.listRule = tx(c.listRule);
    c.viewRule = tx(c.viewRule);
    c.createRule = tx(c.createRule);
    c.updateRule = tx(c.updateRule);
    c.deleteRule = tx(c.deleteRule);
    if (changed) app.save(c);
  }
}

migrate(
  (app) => {
    // 1) add the role value
    const users = app.findCollectionByNameOrId("users");
    const role = users.fields.getByName("role");
    if (!role.values.includes("guest")) {
      role.values = [...role.values, "guest"];
      app.save(users);
    }

    // 2) exclude guests from every non-system collection rule
    rewriteRules(app, BASE_AUTH, GUEST_SAFE_AUTH);
  },
  (app) => {
    rewriteRules(app, GUEST_SAFE_AUTH, BASE_AUTH);

    const users = app.findCollectionByNameOrId("users");
    const role = users.fields.getByName("role");
    role.values = role.values.filter((v) => v !== "guest");
    app.save(users);
  },
);
