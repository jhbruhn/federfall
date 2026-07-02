/// <reference path="../pb_data/types.d.ts" />

// federfall-621 — make access-boundary relations immutable after create.
//
// PocketBase evaluates plain field references in UPDATE rules against the
// STORED record, so a rule like `case.active_carer = @request.auth.id` grants
// the update based on the OLD parent while the request body may re-point
// `case` at ANY other record. Concretely: a carer creates a share on their own
// case, then PATCHes the share's `case` to a private foreign case — granting
// themselves (or an accomplice via `shared_with`) read/edit on it. The same
// root cause lets an edit-share holder re-point a child record (journal entry,
// medication, …) into a foreign case's timeline.
//
// Fix: append `@request.body.<field>:isset = false` guards to every update
// rule whose grant traverses that relation, plus `org` (the scope everything
// hangs on). The app only ever sends these fields on CREATE, so nothing
// legitimate breaks — "re-pointing" is delete + recreate by design.
// `case_shares.access` intentionally stays mutable (changing a share's level
// is a legitimate update).
//
// weights / animals / markings are deliberately absent: they are org-wide
// writable identity-layer collections (5yg.4), so a re-point grants nothing
// the writer doesn't already have (weights rules are revisited on
// federfall-p5n).

const GUARDS = [
  ["case_shares", ["case", "shared_with", "org"]],
  ["cases", ["org"]],
  ["case_conditions", ["case", "org"]],
  ["medications", ["case", "org"]],
  ["journal_entries", ["case", "org"]],
  ["placements", ["case", "org"]],
  ["dispositions", ["case", "org"]],
  ["medication_administrations", ["case", "org"]],
  ["follow_ups", ["case", "org"]],
  ["exams", ["case", "org"]],
  ["quarantine_records", ["case", "org"]],
  ["exam_findings", ["exam", "org"]],
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
