/// <reference path="../pb_data/types.d.ts" />

// federfall-1hgp + federfall-7no9 — the identity layer keeps the two guards
// 1700000043 left off it.
//
// ── 1hgp: `org` is the scope everything hangs on, so it must be immutable ────
// 1700000043 made access-boundary relations immutable after create, and
// deliberately skipped `animals` / `markings` / `weights`: they are org-wide
// writable (5yg.4), so re-pointing their `animal` or `case` "grants the writer
// nothing they don't already have org-wide". That is true of those relations.
// It was never true of `org`, which rode along on the same sentence without an
// argument of its own — and PocketBase resolves a plain field reference in an
// UPDATE rule against the STORED record, so
//
//     PATCH /api/collections/animals/records/<id>  {"org": "<other org>"}
//
// passes `org = @request.auth.org` on the row's OLD org while the body moves it
// to another tenant. Verified as an ordinary carer against 0.39.8. The record
// then leaves its org and becomes writable in the target one, while its
// children keep pointing at it — and `cascadeDelete` on `animal` means a
// supervisor over there deleting that bird destroys the first org's cases,
// weights, markings and egg records. That is federfall-ti77's scenario reached
// through the other door: ti77 blocked a child naming a FOREIGN animal, not an
// animal walking into a foreign org. Reachability needs no secret either — the
// launch org id is the fixed constant `org00000default` (1700000001).
//
// `egg_records` already carries this guard (1700000056), which is why it is the
// one identity-adjacent collection that refuses the PATCH today.
//
// ── 7no9: `current_aviary` and `lifetime_status` are derived, so hook-owned ──
// Both are documented as maintained by hooks — 1700000002's header for
// `lifetime_status` ("maintained by hooks from the latest case disposition"),
// and 1700000052 / aviary_stays.pb.js treat `current_aviary` as the single
// funnel every residency writer goes through. Nothing enforced it: any active
// member could relocate any bird between enclosures with no disposition (the
// aviary_stays ledger dutifully closing one stay and opening another, recording
// a move no case history explains), declare a bird deceased, or empty an aviary.
// The audit log caught all of it; nothing prevented it.
//
// Hook writers are unaffected: `app.save()` bypasses API rules entirely, so
// main.pb.js's disposition reconcile, merge_animals.pb.js and intake.pb.js keep
// writing both fields. What this removes is the CLIENT's ability to, and the
// app never sends either on update — add_animal_sheet.dart sets them when it
// creates a resident, edit_animal_sheet.dart sends only name/species/sex. So a
// bird still leaves an aviary the one legitimate way: a disposition on a case.
//
// Not breaking (no client sends these fields on update), hence `fix:` — see
// CLAUDE.md's wire-contract rule.
//
// Same mechanics as 1700000043 / 1700000072: append the suffix, and strip
// exactly it on the way down.

const GUARDS = [
  ["animals", ["org", "current_aviary", "lifetime_status"]],
  ["markings", ["org"]],
  ["weights", ["org"]],
];

const suffixFor = (fields) =>
  fields.map((f) => ` && @request.body.${f}:isset = false`).join("");

migrate(
  (app) => {
    for (const [name, fields] of GUARDS) {
      const c = app.findCollectionByNameOrId(name);
      c.updateRule = "(" + String(c.updateRule) + ")" + suffixFor(fields);
      app.save(c);
    }
  },
  (app) => {
    for (const [name, fields] of GUARDS) {
      const c = app.findCollectionByNameOrId(name);
      const rule = String(c.updateRule);
      const suffix = suffixFor(fields);
      if (!rule.endsWith(suffix)) continue;
      let orig = rule.slice(0, rule.length - suffix.length);
      if (orig.startsWith("(") && orig.endsWith(")")) {
        orig = orig.slice(1, -1);
      }
      c.updateRule = orig;
      app.save(c);
    }
  },
);
