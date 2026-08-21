/// <reference path="../pb_data/types.d.ts" />

// federfall-jo1l / federfall-ti77 — a record's relations must live in its own org.
//
// Registration only. zv_guards.js wires the check, zv_org_scope.js is the check,
// and both hold the reasoning: why the SCHEMA drives it rather than a hand-kept
// list, what the exposure actually is, and the carve-outs.
//
// This file is what animal_org_scope.pb.js grew into: that hook checked `animal`
// on five collections while the same hole existed on eleven other relations, so
// the check now asks the schema which relations are org-scoped instead of being
// told.
//
// Deliberately NOT tagged with collection names — a tag list is the hand-kept
// list this replaces, and the point is that a collection added tomorrow is
// covered without anybody remembering to come back.
//
// On the MODEL events, not the *Request variants: a server-side route writes
// with `tx.save()`, which fires no request hook, and a row's org has to hold for
// those writers too.
//
// `parentOrgFallbacks` is federfall's one piece of vocabulary here: a record with
// no `org` field of its own inherits one from its `case`. Passing none was
// measured to make the check stop finding a scope and wave the write through.
//
// Written out INSIDE each handler, not hoisted to a file-level const. Each
// handler runs in its own JSVM context, so a file-level binding is not in scope
// when it runs — and this one failed loudly in the best possible way: the guard
// fires for the migrations' own writes, so a fresh instance could not apply
// migration 1700000001 at all. `ReferenceError: PARENT_ORG_FALLBACKS is not
// defined`, before any test ran.
//
// (authorship.pb.js next door DOES hoist one, and that is correct there: it is
// used in the TAG LIST, which is evaluated at registration time, not inside the
// handler body.)

onRecordCreate((e) =>
  require(`${__hooks}/zv_guards.js`).orgScope(e, true, {
    parentOrgFallbacks: [{ field: "case", collection: "cases" }],
  }),
);

onRecordUpdate((e) =>
  require(`${__hooks}/zv_guards.js`).orgScope(e, false, {
    parentOrgFallbacks: [{ field: "case", collection: "cases" }],
  }),
);
