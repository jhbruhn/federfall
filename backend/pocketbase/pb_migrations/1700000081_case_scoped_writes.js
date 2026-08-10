/// <reference path="../pb_data/types.d.ts" />

// federfall-piu5 — a row may not be filed into a case its writer cannot read.
//
// `weights.case` and `markings.applied_in_case` were left unconstrained when
// 5yg.4 moved both collections to the identity layer (1700000020 for weights,
// 1700000010 for markings): org scope decided who could write, and nothing looked
// at WHICH case the row named. 1700000043 then exempted these two from its isset
// guards, so the field stayed freely re-pointable on update as well. The result
// was private-by-default holding for READS and not for WRITES — the exact
// "child record re-pointed into a foreign case's timeline" escalation
// 1700000043's own header describes, left open for the two collections it
// classified as identity layer.
//
// 1700000079 took the headline half: a stranger can no longer write about a bird
// they never held. What remains is narrower and still real — a carer who holds a
// bird through their OWN open case can attach a weight or a ring to a DIFFERENT,
// older case of that same bird, one belonging to another carer they cannot read,
// and it shows up in that carer's timeline, in `case_report_rows` and in the
// annual report. Custody cannot see this: the actor legitimately holds the bird.
//
// ── CREATE: the named case must be one the writer may edit ──────────────────
// The predicate is 1700000010's `childEdit` verbatim — the one every other case
// child already uses — reached through the row's own relation field. Parity
// matters more than brevity here: a weight filed into a case should obey the same
// rule as a journal entry filed into it.
//
// `<field> = ''` rather than an isset guard for the case-less path, so a client
// that explicitly sends an empty relation is treated as "no case" instead of
// being refused (1700000077 made the same choice for `current_aviary`). Case-less
// weights and markings — the aviary path — stay open to whoever holds the bird,
// which is what keeps the identity-layer stance intact.
//
// On CREATE, PocketBase resolves plain field references against the SUBMITTED
// record, so `case.active_carer` reads the INCOMING case. That is the whole
// reason this is expressible as a rule.
//
// ── UPDATE: the field is frozen, not checked ────────────────────────────────
// On UPDATE the same reference would resolve against the STORED record
// (1700000043's finding), i.e. it would authorise against the case the row is
// being moved AWAY from — worse than useless. So update gets an isset guard
// instead. That costs nothing: `weight_entry_sheet.dart` and `marking_sheet.dart`
// both put `case` / `applied_in_case` in their CREATE branch only, so no client
// path sends either on update. Re-filing a row into another case is not a
// supported operation; deleting and re-recording it is.
//
// ── cases.animal, the same hole one level up ────────────────────────────────
// `cases.animal` was never isset-guarded either, so a carer could re-point their
// OWN case onto any other bird in the org — and then a disposition on that case
// rewrites THAT bird's `lifetime_status` and `current_aviary`. Since 1700000077
// the latter is a custody pointer, so this is a way to evict another keeper's
// resident and take its write access: exactly the damage federfall-sinp caused by
// accident, available on purpose. Only the cross-org case was blocked, by
// animal_org_scope.pb.js.
//
// Nothing legitimate re-points it: `merge_animals.pb.js` does, but through
// `tx.save()`, which bypasses API rules, and the app never sends `animal` on a
// case PATCH (`new_case_screen.dart`'s only `animal` write is the intake route's
// create payload).

const AUTH =
  '@request.auth.id != "" && @request.auth.is_active = true' +
  ' && @request.auth.role != "guest"';
const SUP = '@request.auth.role = "supervisor"';

/** 1700000010's `childEdit`, reached through [field], or no case at all. */
const caseEditableOrNone = (field) =>
  "(" +
  field +
  " = ''" +
  " || (" +
  field +
  ".org = @request.auth.org" +
  " && (" +
  field +
  ".active_carer = @request.auth.id" +
  " || " +
  SUP +
  " || (" +
  field +
  ".case_shares_via_case.shared_with ?= @request.auth.id" +
  " && " +
  field +
  '.case_shares_via_case.access ?= "edit")' +
  ")))";

const TARGETS = [
  { collection: "weights", field: "case" },
  { collection: "markings", field: "applied_in_case" },
];

migrate(
  (app) => {
    for (const t of TARGETS) {
      const c = app.findCollectionByNameOrId(t.collection);
      c.createRule =
        "(" + String(c.createRule) + ") && " + caseEditableOrNone(t.field);
      c.updateRule =
        "(" +
        String(c.updateRule) +
        ") && @request.body." +
        t.field +
        ":isset = false";
      app.save(c);
    }

    const cases = app.findCollectionByNameOrId("cases");
    cases.updateRule =
      "(" + String(cases.updateRule) + ") && @request.body.animal:isset = false";
    app.save(cases);
  },
  (app) => {
    for (const t of TARGETS) {
      const c = app.findCollectionByNameOrId(t.collection);
      const createSuffix = ") && " + caseEditableOrNone(t.field);
      const updateSuffix = ") && @request.body." + t.field + ":isset = false";
      const create = String(c.createRule);
      const update = String(c.updateRule);
      if (create.endsWith(createSuffix)) {
        c.createRule = create.slice(1, create.length - createSuffix.length);
      }
      if (update.endsWith(updateSuffix)) {
        c.updateRule = update.slice(1, update.length - updateSuffix.length);
      }
      app.save(c);
    }

    const cases = app.findCollectionByNameOrId("cases");
    const suffix = ") && @request.body.animal:isset = false";
    const rule = String(cases.updateRule);
    if (rule.endsWith(suffix)) {
      cases.updateRule = rule.slice(1, rule.length - suffix.length);
      app.save(cases);
    }
  },
);
