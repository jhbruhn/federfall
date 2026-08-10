/// <reference path="../pb_data/types.d.ts" />

// federfall-v9ap — a row may not be moved onto a bird its writer does not hold.
//
// 1700000079 gave `weights` / `markings` / `egg_records` a custody predicate, and
// it is reached through `animal.` — so on UPDATE it resolves against the STORED
// record (1700000043's finding) and authorises custody of the bird the row is
// moving AWAY FROM, never the one it lands on. `animal` carries no isset guard,
// so the field stayed a free relation and the whole control could be sidestepped
// in two calls: create a row on a bird you hold, then PATCH its `animal` to
// anyone else's. Confirmed against a live PocketBase; the victim then READS the
// injected row, because these collections are org-wide readable by design.
//
// 1700000043 left `animal` mutable on purpose and said why:
//
//     weights / animals / markings are deliberately absent: they are org-wide
//     writable identity-layer collections (5yg.4), so a re-point grants nothing
//     the writer doesn't already have
//
// That premise expired with 1700000079. A re-point now grants exactly what the
// writer does not have, which is the point of the custody model.
//
// ── Frozen, not checked ─────────────────────────────────────────────────────
// The same stored-record resolution that breaks the rule also stops a rule from
// fixing it, so this freezes the field instead — 1700000081's shape, for the same
// reason. It costs nothing: `weight_entry_sheet.dart:104-118`,
// `marking_sheet.dart:138` and `exam_sheet.dart` all send `animal` in their
// CREATE branch only. CREATE is already covered, because there the predicate
// resolves against the submitted record.
//
// `exams` is included: it is case-scoped rather than custody-scoped, but its
// `animal` is denormalized onto the lifetime view, and re-pointing it files an
// exam onto a bird the writer has no relationship with. 1700000043 already froze
// its `case` and `org`; this is the third of the three.
//
// ── egg_records is NOT here ─────────────────────────────────────────────────
// Re-attribution is a shipped feature: `egg_reassign_sheet.dart` moves a record
// to the bird that actually laid it, and test_rules.py pins `egg.animal IS
// mutable`. A freeze would break it, so that one gets a destination-side custody
// check in `pb_hooks/animal_custody_scope.pb.js` instead — the only form that can
// look at the INCOMING animal.
//
// Superuser writes and the hook routes are unaffected either way: a superuser
// bypasses collection rules, and `merge_animals.pb.js` re-points through
// `tx.save()`, which is not an API request at all. `[animal org scope]` drives
// its whole sweep with the superuser token, so it still exercises
// animal_org_scope.pb.js rather than passing on this guard.

const FROZEN = ["weights", "markings", "exams"];
const SUFFIX = " && @request.body.animal:isset = false";

migrate(
  (app) => {
    for (const name of FROZEN) {
      const c = app.findCollectionByNameOrId(name);
      c.updateRule = "(" + String(c.updateRule) + ")" + SUFFIX;
      app.save(c);
    }
  },
  (app) => {
    for (const name of FROZEN) {
      const c = app.findCollectionByNameOrId(name);
      const rule = String(c.updateRule);
      if (!rule.endsWith(SUFFIX)) continue;
      c.updateRule = rule.slice(1, rule.length - SUFFIX.length - 1);
      app.save(c);
    }
  },
);
