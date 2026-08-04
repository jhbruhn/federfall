/// <reference path="../pb_data/types.d.ts" />

// federfall-qt96.3 — Tier A of the audit log: every write that goes through the
// ordinary collection API becomes one named domain event.
//
// ── Why *Request hooks, and why after e.next() ───────────────────────────────
//
// `RecordRequestEvent` is the only event kind that carries `e.auth`,
// `e.requestInfo()` and `e.realIP()` — a model hook gets a `RecordEvent`, which
// has no authenticated caller at all, and an audit row with no actor is not
// worth writing. So the hooks below are the *Request variants.
//
// `e.next()` runs FIRST in every handler: it performs the save, and it throws
// when the save is rejected, which skips the emit entirely. No phantom events
// for writes that never happened. The accepted trade-off is the mirror image —
// the audit row lands after the domain commit and therefore cannot roll it
// back — which is why emit() swallows its own errors rather than propagating.
//
// ── Why there is no per-collection handler ───────────────────────────────────
//
// One generic body per verb, registered over every key of
// lib_audit.js's COLLECTION_ACTIONS. The body asks the record which collection
// it belongs to and looks the action up there, so auditing a new collection is
// a map entry, not a new hook. This is forced as much as chosen: a handler runs
// in an isolated JSVM context where file-level bindings — including a table
// defined ten lines above it — are out of scope. A required module keeps its
// own scope, so the lookup has to live in lib_audit.js and be re-required
// inside each handler.
//
// Cascade deletes do NOT fire request hooks, which is what keeps deleting a
// case from writing a row per timeline child: the case's own `case.deleted`
// stands for the whole subtree it took with it.
//
// NOT here: `users`, `case_shares` and auth (federfall-qt96.5), the custom
// routes intake/exam/merge_animals (qt96.4, they never fire request hooks),
// exports and cron paths (qt96.6).

const audit = require(`${__hooks}/lib_audit.js`);
const AUDITED = audit.AUDITED_COLLECTIONS;

onRecordCreateRequest((e) => {
  e.next();
  require(`${__hooks}/lib_audit.js`).emitRecordChange(e, "created");
}, ...AUDITED);

onRecordUpdateRequest((e) => {
  // Captured BEFORE the save: afterwards `original()` is the new state.
  const before = e.record.original().fieldsData();
  e.next();
  require(`${__hooks}/lib_audit.js`).emitRecordChange(e, "updated", before);
}, ...AUDITED);

onRecordDeleteRequest((e) => {
  e.next();
  require(`${__hooks}/lib_audit.js`).emitRecordChange(e, "deleted");
}, ...AUDITED);
