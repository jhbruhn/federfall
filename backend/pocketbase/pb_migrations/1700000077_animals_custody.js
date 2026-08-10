/// <reference path="../pb_data/types.d.ts" />

// federfall-q7ks.2 — writing about a bird requires holding it.
//
// Until now `animals` was org-wide writable (5yg.4's "identity layer"): any
// active member could rename, re-species or re-photograph any bird in the org,
// including one in another carer's acute care, while being unable to open the
// case that bird's data belongs to. Reads stay org-wide — re-identification
// depends on seeing every bird — but writing now follows CUSTODY, and custody
// is not a role: it is who currently holds the animal.
//
//   in care    the active carer of a non-disposed case, plus anyone that case
//              is shared with at `edit`
//   in aviary  the enclosure's keeper (required since 1700000076)
//   at large / deceased   nobody; a coordinator or supervisor has to act, or a
//              new case has to be opened (which makes the opener the carer)
//
// Coordinator/supervisor is a blanket override throughout.
//
// ── Why the rule keys on the CAUSE, not on lifetime_status ──────────────────
// `lifetime_status` looks like the custody state and is not: it is derived from
// the last DISPOSITION and deliberately lags. intake.pb.js sets `in_care` only
// when it creates a BRAND-NEW animal; the re-identification branch skips it on
// purpose (federfall-sinp — the derivation orders dispositions by `created`,
// not `disposed_at`, so writing a lifetime state there would clobber an aviary
// residency when archived cases are backfilled). A re-admitted bird therefore
// still reads `at_large_released`, and a resident under treatment still reads
// `in_aviary`. Keying on it would hand a bird in someone's kitchen to the
// aviary keeper. The open case and the aviary relation are both live, so the
// rule reads those instead.
//
// ── Why no denormalized `custodian` column ──────────────────────────────────
// The traversal self-heals: a handoff changes `active_carer` and custody
// follows in the same write, and re-assigning an aviary's keeper re-points
// every resident at once. A derived column would need a writer in each of
// those places, and this schema has already paid that bill once
// (`current_aviary` had five writers before 1700000052 centralised it).
//
// ── The back-relation clauses genuinely correlate (verified, 0.39.8) ─────────
// Two `?=` conditions on the same back-relation path bind to the SAME joined
// row, including the two-hop `cases_via_animal.case_shares_via_case.*` chain:
// an edit-share on a DISPOSED case is refused even while the same animal has
// somebody else's OPEN case. 1700000010's `case_shares` note found the same on
// 0.39.4. It is NOT a general property — cases_repository.dart:301 documents a
// forward-then-back path (`animal.markings_via_animal`) with non-`?` operators
// where a second clause is satisfied independently — so this is pinned by
// test_rules.py's [custody: animals] block rather than assumed. If a PocketBase
// upgrade changes it, that block fails loudly and the fix is a denormalized
// column, not a widened rule.
//
// The isset guards from 1700000075 are load-bearing here rather than merely
// hygienic: without them anyone could PATCH `current_aviary` and hand
// themselves the keeper branch.

const AUTH =
  '@request.auth.id != "" && @request.auth.is_active = true' +
  ' && @request.auth.role != "guest"';
const COORD_SUP =
  '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

// The same status set the case browser calls "active" (federfall-jt5u): named
// rather than negated, so the two answers cannot drift. `""` is included for
// parity — the case-create hook defaults to `in_care`, but a row imported
// through the Admin UI can carry no status at all, and such a case is open.
const ACTIVE =
  '(cases_via_animal.status ?= "in_care"' +
  ' || cases_via_animal.status ?= "ready_for_release"' +
  ' || cases_via_animal.status ?= "")';

const CUSTODY =
  "(" +
  COORD_SUP +
  " || current_aviary.keeper = @request.auth.id" +
  " || (cases_via_animal.active_carer ?= @request.auth.id && " +
  ACTIVE +
  ")" +
  " || (cases_via_animal.case_shares_via_case.shared_with ?= @request.auth.id" +
  ' && cases_via_animal.case_shares_via_case.access ?= "edit" && ' +
  ACTIVE +
  ")" +
  ")";

const GUARDS =
  " && @request.body.org:isset = false" +
  " && @request.body.current_aviary:isset = false" +
  " && @request.body.lifetime_status:isset = false";

// What 1700000010 + 1700000075 left in place, restored verbatim on the way down.
const PRE_CUSTODY_UPDATE =
  "(" + AUTH + " && org = @request.auth.org)" + GUARDS;
const PRE_CUSTODY_CREATE = AUTH + " && org = @request.auth.org";

migrate(
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");

    animals.updateRule =
      "(" + AUTH + " && org = @request.auth.org && " + CUSTODY + ")" + GUARDS;

    // Create: the only client path is the aviary's "add resident" sheet, which
    // always names an enclosure. Placing a bird into one is the keeper's call
    // (or a coordinator's) — the UI already assumed exactly this, gating its
    // FAB behind canManageAviaries while the server let anyone through
    // (federfall-ftm2, superseded here). A bird created into NO aviary stays
    // open to any member: intake writes those server-side through
    // intake.pb.js, which bypasses rules anyway.
    //
    // On CREATE, PocketBase resolves plain field references against the
    // SUBMITTED record, so `current_aviary.keeper` reads the incoming aviary —
    // the opposite of the UPDATE behaviour this schema keeps tripping over, and
    // the reason it can be expressed as a rule at all. `current_aviary = ""`
    // rather than an isset guard, so a client that explicitly sends an empty
    // relation is treated as "no enclosure" instead of being refused.
    animals.createRule =
      AUTH +
      " && org = @request.auth.org" +
      " && (current_aviary = ''" +
      " || " +
      COORD_SUP +
      " || current_aviary.keeper = @request.auth.id)";

    app.save(animals);
  },
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");
    animals.updateRule = PRE_CUSTODY_UPDATE;
    animals.createRule = PRE_CUSTODY_CREATE;
    app.save(animals);
  },
);
