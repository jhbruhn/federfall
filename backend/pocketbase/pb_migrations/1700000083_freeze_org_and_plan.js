/// <reference path="../pb_data/types.d.ts" />

// federfall-<sweep> — the two decisions the relation sweep forced.
//
// Enumerating every relation field on every client-writable collection (see
// test_rules.py's `[relation guards]`) turned up two rows with no answer to
// "what authorises the new target". Both get the cheapest correct one: nothing
// legitimate changes them after create, so they are frozen.
//
// ── 1. `org`, on the seven collections that still had it writable ───────────
// A tenant boundary, and the one relation that is NEVER legitimately changed:
// no record moves between organisations, in the app or anywhere else. 1700000043
// froze it on twelve collections and 1700000075 added the identity layer, but
// the vocabulary/code-list collections plus `aviaries` and `finders` were left
// out — so a supervisor could PATCH one of their rows into ANOTHER org.
//
// `finders` is the one that matters: those rows are the PII
// finder_retention.pb.js exists to scrub, and a re-point moves them out of the
// reach of the org that is responsible for them and into an org that never
// collected them.
//
// Rules cannot catch this themselves, which is why it needs a guard rather than
// a check: every update rule already says `org = @request.auth.org`, but on
// UPDATE that resolves against the STORED record (1700000043's finding), so it
// authorises the org the row is leaving.
//
// ── 2. `medication_administrations.medication` ──────────────────────────────
// A dose's link to the plan it was given under. `case` has been frozen since
// 1700000043, but `medication` was not, so a dose could be pointed at a
// medication plan belonging to a DIFFERENT case — the shape federfall-piu5 closed
// for `weights.case` / `markings.applied_in_case`, third instance. Minor next to
// those (the leak is a drug name expanded onto a case the reader can already
// see), and closed the same way because it costs nothing:
// `administration_sheet.dart:145-153` sends `medication` in its CREATE branch
// only. Attaching a dose to a plan after the fact is not an operation the app
// offers; deleting and re-logging it is.

const ORG_FREEZE = [
  "admission_reasons",
  "aviaries",
  "conditions",
  "finders",
  "marking_types",
  "medication_products",
  "medication_routes",
];

const SUFFIXES = { medication_administrations: "medication" };
for (const name of ORG_FREEZE) SUFFIXES[name] = "org";

migrate(
  (app) => {
    for (const name of Object.keys(SUFFIXES)) {
      const c = app.findCollectionByNameOrId(name);
      const suffix =
        " && @request.body." + SUFFIXES[name] + ":isset = false";
      const rule = String(c.updateRule);
      // Idempotent: a rule that already carries the guard is left alone.
      if (rule.indexOf(suffix.trim()) !== -1) continue;
      c.updateRule = "(" + rule + ")" + suffix;
      app.save(c);
    }
  },
  (app) => {
    for (const name of Object.keys(SUFFIXES)) {
      const c = app.findCollectionByNameOrId(name);
      const suffix =
        " && @request.body." + SUFFIXES[name] + ":isset = false";
      const rule = String(c.updateRule);
      if (!rule.endsWith(suffix)) continue;
      c.updateRule = rule.slice(1, rule.length - suffix.length - 1);
      app.save(c);
    }
  },
);
