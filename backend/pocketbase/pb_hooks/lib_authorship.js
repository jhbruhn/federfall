/// <reference path="../pb_data/types.d.ts" />

// federfall's authorship VOCABULARY. The stamping itself is zugvogel's
// (zv_authorship.js): which collection names its actor in which field is
// domain knowledge, and no two products share it.
//
// federfall-vfry — these relations were ordinary client-writable fields, so a
// client could name somebody else as the author of a record. The shared helper
// overwrites whatever arrived rather than validating it: a mismatch is not a
// validation error to report, it is a value with no standing.

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
  vaccinations: "author",
  vet_appointments: "created_by",
  weights: "author",
};

// Only the map and the tag list. There is deliberately no `stampActor`
// delegate here: authorship.pb.js hands ACTOR_FIELDS to zv_guards.js, which
// calls the shared stamper itself, so a wrapper would be a second way to do
// the same thing — and the one nothing calls is the one that rots.
module.exports = {
  ACTOR_FIELDS: ACTOR_FIELDS,
  /** The tag list for the hooks — every collection that has an actor field. */
  COLLECTIONS: Object.keys(ACTOR_FIELDS),
};
