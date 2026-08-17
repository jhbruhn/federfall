/// <reference path="../pb_data/types.d.ts" />

// federfall-3dy9 — put the guest wall on `medication_due`, the one collection
// in the whole schema that never had it.
//
// Not a regression from any single migration. 1700000045 walled every
// collection that existed then, but `medication_due` has been CREATED three
// times since the guest role landed — 1700000024 → 1700000058 → 1700000090 —
// and each of those re-saved the view with the PRE-guest predicate copied
// verbatim:
//
//   @request.auth.id != "" && @request.auth.is_active = true
//
// so 45's pass was undone twice. Dumped from a live 0.39.8 running these
// migrations, it is the only listRule in the schema that authenticates and
// omits `&& @request.auth.role != "guest"`.
//
// What it leaked: demoting a carer to `guest` is the documented way to revoke
// access, but their old cases still carry `active_carer = <their id>`, and this
// view's rule matches on exactly that. As a guest they read no cases, no
// medications and no animals — and every still-running dose of every case they
// once held, with case_id, drug, dose, route and the whole schedule.
//
// A view's rules can be rewritten without restating its viewQuery (this is what
// 1700000045 does for case_quarantine), so this does not have to re-declare the
// query 1700000090 owns — and must not, or the two would drift.

const GUEST_CLAUSE = ' && @request.auth.role != "guest"';

// Rules are goja-wrapped String objects, so coerce with String() before
// testing/concatenating (1700000033's finding). Appending is conditional so the
// migration is idempotent and cannot double the clause.
function setGuestWall(app, name, present) {
  const c = app.findCollectionByNameOrId(name);
  if (!c) return;
  let changed = false;
  const tx = (s) => {
    if (s === null || s === undefined) return s;
    const str = String(s);
    const stripped = str.split(GUEST_CLAUSE).join("");
    const out = present ? stripped + GUEST_CLAUSE : stripped;
    if (out !== str) changed = true;
    return out;
  };
  c.listRule = tx(c.listRule);
  c.viewRule = tx(c.viewRule);
  if (changed) app.save(c);
}

migrate(
  (app) => {
    setGuestWall(app, "medication_due", true);
  },
  (app) => {
    setGuestWall(app, "medication_due", false);
  },
);
