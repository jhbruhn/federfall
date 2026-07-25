/// <reference path="../pb_data/types.d.ts" />

// federfall-4agw.1 — an egg record's `animal` must live in the record's own org.
//
// This hook is a deliberate deviation from the epic's "no hooks" note, added
// because the rule tests caught a real cross-org write: `animal` is
// intentionally MUTABLE (reassignment is a plain PATCH of that field, exempt
// from 1700000043's :isset guards), and PocketBase cannot express "the org of
// the record this field now points at". Plain field references in an UPDATE rule
// are evaluated against the STORED record — that is 1700000043's whole finding —
// so `animal.org = @request.auth.org` in the update rule would check the OLD
// animal and let the body re-point the row at any foreign-org bird. The row
// would stay unreadable to that org (list/view are still `org =
// @request.auth.org`), but it would hang off their animal and be destroyed by
// its cascade delete.
//
// Same stance and same phrasing as the referenced-record checks in
// intake.pb.js / exam.pb.js / main.pb.js: validate the relation server-side
// where a rule can't. Enforced on create as well as update so the invariant
// holds for every writer, including hook-internal `app.save()` calls.
//
// JSVM gotcha: each callback runs in an isolated context, so the check is
// written out in both rather than shared via a file-level helper.

onRecordCreate((e) => {
  const animalId = e.record.getString("animal");
  let animal;
  try {
    animal = e.app.findRecordById("animals", animalId);
  } catch (_) {
    throw new BadRequestError("Unknown animal.");
  }
  if (animal.getString("org") !== e.record.getString("org")) {
    throw new BadRequestError("Animal belongs to another organisation.");
  }
  e.next();
}, "egg_records");

onRecordUpdate((e) => {
  const animalId = e.record.getString("animal");
  let animal;
  try {
    animal = e.app.findRecordById("animals", animalId);
  } catch (_) {
    throw new BadRequestError("Unknown animal.");
  }
  if (animal.getString("org") !== e.record.getString("org")) {
    throw new BadRequestError("Animal belongs to another organisation.");
  }
  e.next();
}, "egg_records");
