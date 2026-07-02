/// <reference path="../pb_data/types.d.ts" />

// federfall-7ok — re-apply the guest wall to collections created AFTER the
// guest-role migration (1700000033).
//
// That migration rewrote every rule containing the shared auth predicate
//   @request.auth.id != "" && @request.auth.is_active = true
// to also exclude `role = "guest"` — but only for collections that existed at
// that point. Migrations 36–42 (quarantine_records, case_quarantine,
// admission_reasons, marking_types, medication_routes, animal_species) copied
// the pre-guest predicate verbatim, so guests could read those code lists and
// views, contradicting the "walled off from all data" invariant.
//
// This re-runs the same rewrite pass, made idempotent: rules are first
// normalised back to the base predicate and then rewritten to the guest-safe
// one, so already-walled rules come out unchanged (and are not re-saved).
// Future migrations MUST copy the guest-safe predicate (base + guest
// exclusion) — see test_rules.py's guest sweep, which catches regressions.

const BASE_AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
const GUEST_SAFE_AUTH = BASE_AUTH + ' && @request.auth.role != "guest"';

// Collections created between 1700000033 and this migration whose rules carry
// the un-walled predicate. The down pass is limited to these so it precisely
// undoes what up changed (everything else was already guest-safe before up).
const LATE_COLLECTIONS = [
  "quarantine_records",
  "case_quarantine",
  "admission_reasons",
  "marking_types",
  "medication_routes",
  "animal_species",
];

// Same mechanics as 1700000033: rules must be rewritten on a mutable handle
// re-fetched by name (findAllCollections snapshots are read-only), and rule
// values are goja-wrapped String objects, so coerce with String().
//
// `addGuestWall` — every rule is first normalised by stripping the guest
// exclusion (GUEST_SAFE → BASE); with the wall on, BASE is then rewritten
// back to GUEST_SAFE. Both directions are safe to run repeatedly. (A naive
// from→to swap can't be used symmetrically here: BASE is a substring of
// GUEST_SAFE, so replacing BASE inside an already-walled rule doubles the
// exclusion.)
function rewriteRules(app, names, addGuestWall) {
  const targets = names || app.findAllCollections().map((c) => c && c.name);
  for (const name of targets) {
    if (!name) continue;
    const c = app.findCollectionByNameOrId(name);
    if (!c || c.system) continue;
    let changed = false;
    const tx = (s) => {
      if (s === null || s === undefined) return s;
      const str = String(s);
      let out = str.split(GUEST_SAFE_AUTH).join(BASE_AUTH);
      if (addGuestWall) out = out.split(BASE_AUTH).join(GUEST_SAFE_AUTH);
      if (out !== str) changed = true;
      return out;
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
    rewriteRules(app, null, true);
  },
  (app) => {
    rewriteRules(app, LATE_COLLECTIONS, false);
  },
);
