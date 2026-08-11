/// <reference path="../pb_data/types.d.ts" />

// An enclosure's flock-care log belongs to whoever answers for the enclosure.
//
// 1700000053 gave `journal_entries` an aviary parent and copied the stance
// `aviaries` itself had at the time: any active member reads, coordinator or
// supervisor writes. `keeper` was still close to a label then. It is not one
// any more — since 1700000077 it is write AUTHORITY over every resident, since
// 1700000085 it is who may read their patronages, and since 1700000086 it is
// who corrects the enclosure's own facts. So the aviary branch moves to the
// set every other aviary-scoped rule already names:
//
//   read  = keeper || coordinator/supervisor   (was: any active org member)
//   write = keeper || coordinator/supervisor   (was: coordinator/supervisor)
//
// It narrows on one side and widens on the other for the same reason. A flock
// journal is a care record of named birds under treatment — "wer hat wann
// gesäubert, wer hat was beobachtet" — and it was the one part of the aviary
// visible to every carer in the org whether or not they had anything to do
// with it. Meanwhile the person actually doing the cleaning could not write it
// down; that had to be relayed to a coordinator, the same gap 1700000086 closed
// for the enclosure record and federfall-ftm2 closed for the "add resident"
// FAB.
//
// Read and write are ONE set here, deliberately, so the two halves of that
// sentence cannot drift — unlike the case branch beside it, where a read share
// is a weaker grant than an edit share. There is nothing on an aviary journal
// entry that a reader may see but a writer may not add.
//
// Resolution is LIVE, through `aviary.keeper`, exactly like `sponsorships`
// resolving through `animal.current_aviary.keeper`: handing an enclosure over
// hands over its whole log, and a former keeper stops being a reader. There is
// no per-entry authorship snapshot and there should not be one — the log
// describes the enclosure, not the shift.
//
// The `case` branch is untouched, as is the XOR hook that makes exactly one of
// the two parents settable (pb_hooks/journal_entries.pb.js) and 1700000043's
// `case`/`aviary`/`org` freeze on update — which is also what makes the stored
// `aviary.keeper` lookup in the update rule safe: the relation the rule
// resolves cannot be the one the body is trying to change.
//
// Not a wire break. The tightened half is a LIST rule, and PocketBase filters a
// list rather than refusing it: an older client asking for an enclosure's
// journal it may no longer read gets an empty list in the same response shape,
// never an error, and the widened half rejects nothing that used to pass.

const AUTH =
  '@request.auth.id != "" && @request.auth.is_active = true' +
  ' && @request.auth.role != "guest"';
const SUP = '@request.auth.role = "supervisor"';
const COORD_SUP =
  '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

// 1700000043's boundary-relation freeze, as 1700000053 re-derived it.
const ISSET_GUARD =
  ' && @request.body.case:isset = false' +
  ' && @request.body.aviary:isset = false' +
  ' && @request.body.org:isset = false';

const CASE_VIEW =
  'case != "" && case.org = @request.auth.org && (case.active_carer =' +
  ' @request.auth.id || ' + COORD_SUP +
  ' || case.case_shares_via_case.shared_with ?= @request.auth.id)';
const CASE_EDIT =
  'case != "" && case.org = @request.auth.org && (case.active_carer =' +
  ' @request.auth.id || ' + SUP +
  ' || (case.case_shares_via_case.shared_with ?= @request.auth.id &&' +
  ' case.case_shares_via_case.access ?= "edit"))';

// Before: read was org-wide, write was coordinator/supervisor.
const AVIARY_VIEW_BEFORE = 'aviary != "" && aviary.org = @request.auth.org';
const AVIARY_EDIT_BEFORE =
  'aviary != "" && aviary.org = @request.auth.org && ' + COORD_SUP;
// After: one set for both.
const AVIARY_AFTER =
  'aviary != "" && aviary.org = @request.auth.org && (' + COORD_SUP +
  ' || aviary.keeper = @request.auth.id)';

function rules(aviaryView, aviaryEdit) {
  const view = AUTH + ' && ((' + CASE_VIEW + ') || (' + aviaryView + '))';
  const edit = AUTH + ' && ((' + CASE_EDIT + ') || (' + aviaryEdit + '))';
  return {
    listRule: view,
    viewRule: view,
    createRule: edit,
    updateRule: '(' + edit + ')' + ISSET_GUARD,
    deleteRule: edit,
  };
}

function apply(app, from, to) {
  const c = app.findCollectionByNameOrId("journal_entries");
  for (const name of Object.keys(from)) {
    if (String(c[name]) !== from[name]) {
      // Loud rather than silent: this migration REPLACES the rules wholesale
      // (the aviary branch cannot be edited in place), so drift would be
      // thrown away. Failing here asks whoever changed it to fold the change
      // in by hand — 1700000086's stance.
      throw new Error(
        "[1700000089] journal_entries." + name + " is not the expected " +
        "string; refusing to overwrite it:\n  found:    " + String(c[name]) +
        "\n  expected: " + from[name],
      );
    }
  }
  for (const name of Object.keys(to)) c[name] = to[name];
  app.save(c);
}

migrate(
  (app) => {
    apply(
      app,
      rules(AVIARY_VIEW_BEFORE, AVIARY_EDIT_BEFORE),
      rules(AVIARY_AFTER, AVIARY_AFTER),
    );
  },
  (app) => {
    apply(
      app,
      rules(AVIARY_AFTER, AVIARY_AFTER),
      rules(AVIARY_VIEW_BEFORE, AVIARY_EDIT_BEFORE),
    );
  },
);
