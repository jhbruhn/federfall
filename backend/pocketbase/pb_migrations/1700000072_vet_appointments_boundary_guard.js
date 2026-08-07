/// <reference path="../pb_data/types.d.ts" />

// federfall-nbqy — vet_appointments (1700000064) shipped WITHOUT 1700000043's
// immutable-boundary suffix. PocketBase resolves plain field references in an
// UPDATE rule against the STORED record, so its update rule granted on the
// appointment's OLD case while the request body could re-point `case` (or
// `org`) at any other record: the active carer of one case — or an edit-share
// holder on it — could inject a fabricated vet appointment into another
// carer's private case, even in another organisation. Same fix, same shape as
// 1700000043: `case` and `org` become immutable after create ("re-pointing"
// is delete + recreate by design).

const FIELDS = ["case", "org"];

const suffix = FIELDS.map(
  (f) => ` && @request.body.${f}:isset = false`,
).join("");

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("vet_appointments");
    c.updateRule = "(" + String(c.updateRule) + ")" + suffix;
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("vet_appointments");
    const rule = String(c.updateRule);
    if (!rule.endsWith(suffix)) return;
    let orig = rule.slice(0, rule.length - suffix.length);
    if (orig.startsWith("(") && orig.endsWith(")")) {
      orig = orig.slice(1, -1);
    }
    c.updateRule = orig;
    app.save(c);
  },
);
