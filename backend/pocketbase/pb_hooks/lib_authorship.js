/// <reference path="../pb_data/types.d.ts" />

// federfall-vfry — the one table of "which field on this collection names the
// person who DID the thing", read by authorship.pb.js.
//
// It is a module for the same reason lib_audit.js's registries are: a hook
// handler runs in an isolated JSVM context where file-level bindings are out of
// scope, so a map used inside two handlers AND in their tag lists would
// otherwise be written three times and drift twice.
//
// ── What belongs in here ────────────────────────────────────────────────────
// Only fields that record an ACTOR — who wrote this, who gave this dose, who
// performed this release. Those are never a choice the client gets to make:
// they are a statement about who was authenticated, and the server is the only
// party that knows the answer.
//
// Deliberately NOT here, because they name a person who is genuinely assignable
// and the caller is entitled to pick them:
//   aviaries.keeper        the member responsible for an enclosure
//   cases.active_carer     the current carer (pinned to the creator by the
//                          `cases` create rule, then moved by handoff)
//   placements.to_user     the receiving carer of a handoff — the whole point
//   placements.from_user   derived from the case's real carer in main.pb.js
//   case_shares.shared_with the colleague being granted access
//
// STATELESS (see lib_audit.js): each pooled JSVM holds its own instance, so
// nothing here may cache a decision between calls.

/** collection name → the relation field naming the actor behind the record. */
const ACTOR_FIELDS = {
  cases: "admitted_by",
  case_shares: "shared_by",
  dispositions: "performed_by",
  egg_records: "author",
  exams: "examiner",
  follow_ups: "created_by",
  journal_entries: "author",
  markings: "applied_by",
  medication_administrations: "administered_by",
  quarantine_records: "set_by",
  // NOT `vet` — that field names the external practice who gave the shot, which
  // is a fact about the world the caller is entitled to state. `author` is the
  // actor: who entered this row.
  vaccinations: "author",
  vet_appointments: "created_by",
  weights: "author",
};

module.exports = {
  ACTOR_FIELDS: ACTOR_FIELDS,
  /** The tag list for the hooks — every collection that has an actor field. */
  COLLECTIONS: Object.keys(ACTOR_FIELDS),
};
