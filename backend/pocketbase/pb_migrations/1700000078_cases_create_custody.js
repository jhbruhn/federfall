/// <reference path="../pb_data/types.d.ts" />

// federfall-q7ks.4 — opening a case on an existing bird follows custody.
//
// `cases.create` was "any active member, naming themselves as active_carer", so
// a stranger could open a case on another keeper's aviary resident — or on a
// bird recorded as dead. Both are answered here, on the two facts a rule can
// actually check about the INCOMING animal.
//
// On CREATE, PocketBase resolves plain field references against the SUBMITTED
// record, so `animal.current_aviary.keeper` reads the aviary the named bird
// actually lives in. (On UPDATE it would read the stored row — the trap behind
// 1700000043, federfall-ti77 and 1700000075. `cases.animal` is not
// isset-guarded, so re-pointing an existing case at another bird stays possible
// and is tracked on federfall-piu5; that is a different hole from this one.)
//
// ── This rule is deliberately the COARSER half ──────────────────────────────
// The model says a bird already in someone's acute care is not a stranger's to
// admit. That cannot be written as a rule: it needs "the animal has NO open
// case", a negative existential, and PocketBase's `?!=` means "any of them
// differs" rather than "none of them matches" — so
// `animal.cases_via_animal.status ?!= "in_care"` is true for a bird with one
// open case and one closed one, i.e. exactly backwards.
//
// So the authoritative gate is `pb_hooks/lib_custody.js`'s requireAdmissible(),
// called from intake.pb.js, and this rule is the backstop for what it can
// express. That division is sound rather than merely convenient: the app creates
// cases ONLY through `POST /api/federfall/intake`
// (cases_repository.dart:434) — a direct `cases.create` has no client path — and
// a route bypasses collection rules anyway, so the hook is where the check has
// to live regardless of how expressive the rule is.
//
// `lifetime_status` is trustworthy in this one direction: it lags toward the
// PAST (federfall-sinp — the derivation orders dispositions by `created`, not
// `disposed_at`, and intake's re-identification branch deliberately leaves it
// alone), so it can read stale-alive but never falsely deceased. A rule that
// refuses on "deceased" therefore cannot refuse a living bird.

const COORD_SUP =
  '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

const SUFFIX =
  " && (" +
  COORD_SUP +
  " || animal.current_aviary = ''" +
  " || animal.current_aviary.keeper = @request.auth.id)" +
  " && (" +
  COORD_SUP +
  ' || animal.lifetime_status != "deceased")';

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("cases");
    c.createRule = "(" + String(c.createRule) + ")" + SUFFIX;
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("cases");
    const rule = String(c.createRule);
    if (!rule.endsWith(SUFFIX)) return;
    let orig = rule.slice(0, rule.length - SUFFIX.length);
    if (orig.startsWith("(") && orig.endsWith(")")) {
      orig = orig.slice(1, -1);
    }
    c.createRule = orig;
    app.save(c);
  },
);
