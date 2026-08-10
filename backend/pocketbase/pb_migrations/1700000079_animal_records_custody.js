/// <reference path="../pb_data/types.d.ts" />

// federfall-q7ks.3 — weights, markings and egg_records follow custody too.
//
// 5yg.4 made these org-wide writable and roles.dart said so out loud:
// "Recording and editing stay open to the whole org like the rest of the
// identity layer." That is now false by decision — recording a weight or a ring
// on a bird you do not hold, an aviary resident above all, is somebody else's
// business. READS stay org-wide, unchanged: re-identification depends on seeing
// every bird's markings and weight series, and 1700000010 is explicit that
// privacy is enforced at the CASE level, not here.
//
// The predicate is 1700000077's, reached one hop further through `animal.`.
// That hop needed proving: cases_repository.dart:301 documents a
// forward-then-back path (`animal.markings_via_animal`) where a second clause on
// the same back-relation is satisfied INDEPENDENTLY, which would make this rule
// grant a former carer access whenever the bird also carried somebody else's
// open case. Probed against 0.39.8 with the exact rule below: it correlates, and
// the trap case (a former carer of a closed case on a bird that also has another
// carer's open one) is refused. The difference from the documented failure looks
// to be the operator — `?=` any-of correlates, the `=`/`~` all-of forms in that
// comment do not — so this is pinned by test_rules.py rather than assumed.
//
// DELETE keeps whatever was already narrower: custody is a floor, not a
// widening. weights and egg_records stay author-or-supervisor (1700000047 /
// 1700000056) AND now also require custody — once a bird has left your care its
// history is not yours to erase; a supervisor still can. `markings.delete` was
// already supervisor-only (1700000010) and a supervisor always holds every
// bird, so it is left exactly as it was.
//
// NOT closed here: federfall-piu5's create-side half. Custody stops a stranger
// writing rows on a bird they never held, but a carer who holds a bird through
// their OWN open case can still attach a weight to a DIFFERENT, older case of
// that same bird — one belonging to another carer, which they cannot read. That
// needs a constraint on the incoming `case` / `applied_in_case` and its own test
// matrix, so it stays on piu5 rather than being smuggled in here.

const AUTH =
  '@request.auth.id != "" && @request.auth.is_active = true' +
  ' && @request.auth.role != "guest"';
const COORD_SUP =
  '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
const ORG_SCOPED = AUTH + " && org = @request.auth.org";

const ACTIVE =
  '(animal.cases_via_animal.status ?= "in_care"' +
  ' || animal.cases_via_animal.status ?= "ready_for_release"' +
  ' || animal.cases_via_animal.status ?= "")';

const CUSTODY =
  "(" +
  COORD_SUP +
  " || animal.current_aviary.keeper = @request.auth.id" +
  " || (animal.cases_via_animal.active_carer ?= @request.auth.id && " +
  ACTIVE +
  ")" +
  " || (animal.cases_via_animal.case_shares_via_case.shared_with" +
  " ?= @request.auth.id" +
  ' && animal.cases_via_animal.case_shares_via_case.access ?= "edit" && ' +
  ACTIVE +
  ")" +
  ")";

const AUTHOR_OR_SUP =
  '(@request.auth.role = "supervisor" || author = @request.auth.id)';

// Verbatim pre-custody rules, so the down pass restores exactly what
// 1700000010 / 1700000020 / 1700000047 / 1700000056 / 1700000075 had left.
const BEFORE = {
  weights: {
    create: ORG_SCOPED,
    update: "(" + ORG_SCOPED + ") && @request.body.org:isset = false",
    delete: ORG_SCOPED + " && " + AUTHOR_OR_SUP,
  },
  markings: {
    create: ORG_SCOPED,
    update: "(" + ORG_SCOPED + ") && @request.body.org:isset = false",
    delete: null, // untouched by this migration
  },
  egg_records: {
    create: ORG_SCOPED,
    update: ORG_SCOPED + " && @request.body.org:isset = false",
    delete: ORG_SCOPED + " && " + AUTHOR_OR_SUP,
  },
};

const AFTER = {
  weights: {
    create: ORG_SCOPED + " && " + CUSTODY,
    update:
      "(" + ORG_SCOPED + " && " + CUSTODY + ") && @request.body.org:isset = false",
    delete: ORG_SCOPED + " && " + AUTHOR_OR_SUP + " && " + CUSTODY,
  },
  markings: {
    create: ORG_SCOPED + " && " + CUSTODY,
    update:
      "(" + ORG_SCOPED + " && " + CUSTODY + ") && @request.body.org:isset = false",
    delete: null,
  },
  egg_records: {
    create: ORG_SCOPED + " && " + CUSTODY,
    update:
      ORG_SCOPED + " && " + CUSTODY + " && @request.body.org:isset = false",
    delete: ORG_SCOPED + " && " + AUTHOR_OR_SUP + " && " + CUSTODY,
  },
};

const apply = (app, table) => {
  for (const name of ["weights", "markings", "egg_records"]) {
    const c = app.findCollectionByNameOrId(name);
    const r = table[name];
    c.createRule = r.create;
    c.updateRule = r.update;
    if (r.delete !== null) c.deleteRule = r.delete;
    app.save(c);
  }
};

migrate(
  (app) => {
    apply(app, AFTER);
  },
  (app) => {
    apply(app, BEFORE);
  },
);
