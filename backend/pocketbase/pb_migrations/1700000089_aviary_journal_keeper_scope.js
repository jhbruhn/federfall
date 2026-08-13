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

// A rule reduced to its ACCESS CORE: the boundary freeze stripped off, and the
// parentheses that only exist to hold it.
//
// The freeze is not access logic. It is 1700000043's "these three relations are
// immutable after create", re-derived by 1700000053 and re-derived again below,
// and it is identical on every path through this migration — so comparing it is
// comparing this file to itself. What the guard below is actually for is the
// aviary/case BRANCH, i.e. who may write at all, and that is what stays exact.
//
// This matters because at least one deployed instance reached 1700000089 with
// the freeze missing from `updateRule` (found in the wild, 2026-08-13). Nothing
// in the migration chain removes it and no hook writes rules, so it was lost
// outside the chain — a dashboard save is the only route we know of. Comparing
// whole strings turned that into a container that will not boot, on a rule this
// migration overwrites anyway. Comparing cores lets it through AND, because
// `to` always carries the freeze, RESTORES the protection on the way past: an
// instance without it can currently re-point a journal entry into another
// case, aviary or org on update, which is exactly the hole 1700000043 closed.
function core(rule) {
  let s = String(rule);
  for (const field of ["case", "aviary", "org"]) {
    s = s.split(" && @request.body." + field + ":isset = false").join("");
  }
  if (s.indexOf("(") === 0 && s.lastIndexOf(")") === s.length - 1) {
    s = s.slice(1, -1);
  }
  return s;
}

function apply(app, from, to) {
  const c = app.findCollectionByNameOrId("journal_entries");
  for (const name of Object.keys(from)) {
    if (core(c[name]) !== core(from[name])) {
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
    if (String(c[name]) !== from[name]) {
      console.log(
        "[1700000089] journal_entries." + name + " differed only in the " +
        "boundary freeze; restoring it.\n  found:    " + String(c[name]) +
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
