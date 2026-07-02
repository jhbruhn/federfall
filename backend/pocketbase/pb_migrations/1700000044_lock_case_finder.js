/// <reference path="../pb_data/types.d.ts" />

// federfall-zod / federfall-9hy — cases.finder is written exclusively by the
// atomic intake route (pb_hooks/intake.pb.js), never directly by clients.
//
// Extends the 1700000043 pattern to the finder relation, on CREATE as well as
// UPDATE: without this, any active member could link an ARBITRARY existing
// finder to their own case by id (finder ids are enumerable) and thereby grant
// themselves read access to that finder's PII through the finders view rule —
// including the update-side re-point that 1700000043 deliberately left open.
// Unlinking/re-linking a finder is a coordinator/supervisor task via the
// Admin UI (superusers bypass rules).

const GUARD = " && @request.body.finder:isset = false";

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("cases");
    c.createRule = "(" + String(c.createRule) + ")" + GUARD;
    c.updateRule = "(" + String(c.updateRule) + ")" + GUARD;
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("cases");
    const strip = (rule) => {
      const s = String(rule);
      if (!s.endsWith(GUARD)) return s;
      let orig = s.slice(0, s.length - GUARD.length);
      if (orig.startsWith("(") && orig.endsWith(")")) {
        orig = orig.slice(1, -1);
      }
      return orig;
    };
    c.createRule = strip(c.createRule);
    c.updateRule = strip(c.updateRule);
    app.save(c);
  },
);
