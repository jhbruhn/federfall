/// <reference path="../pb_data/types.d.ts" />

// federfall-t7ad follow-up — an enclosure's keeper may edit the enclosure.
//
// `aviaries.update` has been coordinator/supervisor since 1700000010, from a
// time when `keeper` was a display-only label. It is not one any more: since
// 1700000076 it is required, and since 1700000077 it is write AUTHORITY —
// `current_aviary.keeper` is what lets someone write about the birds living
// there, place a bird into the enclosure (1700000077's create rule) and read
// its patronages (1700000085). The keeper answers for the enclosure but could
// not correct its capacity, its location or its notes; that had to be relayed
// to a coordinator. This closes the same UI/server gap federfall-ftm2 closed
// for the "add resident" FAB, in the other direction.
//
// ── What the keeper may NOT change: who the keeper is ───────────────────────
// Reassignment stays a coordinator action, and it is the one field on this row
// that hands something over rather than describing the enclosure: naming
// somebody else grants them custody of every resident AND the sponsor PII of
// every patronage hanging off them (federfall-5s5j — inline name, address and
// mobile). A keeper giving that away is not the same act as a keeper fixing a
// capacity, so it keeps needing the role that manages enclosures.
//
// Expressed as `isset = false || = @request.auth.id` rather than a bare freeze,
// the shape 1700000051 already uses for `users.org`: the edit form sends the
// whole record including `keeper` (it is a required field), so a plain
// `@request.body.keeper:isset = false` would 404 every keeper's edit — the
// exact defect federfall-t7ad was filed for. "You may send it as long as it
// still names you" is what lets an unchanged value through while refusing a
// handover. Note the left-hand `keeper = @request.auth.id` resolves against the
// STORED record (1700000043's finding), which is what is wanted here: it asks
// who keeps the enclosure NOW, not who the body would like to.
//
// `org` stays frozen (1700000083), create stays coordinator/supervisor (making
// an enclosure is not the same as running one), delete stays supervisor.
//
// Not a wire break: a rule that accepts strictly more requests than before. No
// client is refused anything it used to be allowed.

const AUTH =
  '@request.auth.id != "" && @request.auth.is_active = true' +
  ' && @request.auth.role != "guest"';
const COORD_SUP =
  '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

// The rule as 1700000045 (guest wall) + 1700000083 (org freeze) left it — the
// exact string this migration replaces, and restores on the way down.
const BEFORE =
  "(" + AUTH + " && org = @request.auth.org && " + COORD_SUP + ")" +
  " && @request.body.org:isset = false";

const AFTER =
  "(" + AUTH + " && org = @request.auth.org" +
  " && (" + COORD_SUP + " || keeper = @request.auth.id))" +
  " && @request.body.org:isset = false" +
  " && (" + COORD_SUP +
  " || @request.body.keeper:isset = false" +
  " || @request.body.keeper = @request.auth.id)";

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("aviaries");
    if (String(c.updateRule) !== BEFORE) {
      // Loud rather than silent: this migration REPLACES the rule wholesale, so
      // a rule that has drifted would have its drift thrown away. Failing here
      // asks whoever changed it to fold the change into AFTER by hand.
      throw new Error(
        "[1700000086] aviaries.updateRule is not the expected string; " +
        "refusing to overwrite it:\n  found:    " + String(c.updateRule) +
        "\n  expected: " + BEFORE,
      );
    }
    c.updateRule = AFTER;
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("aviaries");
    if (String(c.updateRule) !== AFTER) return;
    c.updateRule = BEFORE;
    app.save(c);
  },
);
