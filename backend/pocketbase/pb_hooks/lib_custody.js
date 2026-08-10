/// <reference path="../pb_data/types.d.ts" />

// federfall-q7ks.5 — "who holds this bird", for the routes that bypass rules.
//
// Usage — `require()` INSIDE the handler, never at file level, and always with
// the `${__hooks}` absolute form (see lib_audit.js / lib_auth.js):
//
//   const custody = require(`${__hooks}/lib_custody.js`);
//   custody.requireAdmissible(tx, e.auth, animalId);
//
// It has since grown a second kind of caller: [requireOutcomeWrite], the gate
// `disposition_custody.pb.js` applies to a write that would MOVE a bird, which
// is a rule-reachable surface but not a rule-EXPRESSIBLE question — it needs the
// state the write would derive, which only lib_derive.js can answer.
//
// ── Why this exists ─────────────────────────────────────────────────────────
// 1700000077 put custody in the `animals` rules, but a custom route bypasses
// collection rules entirely — so intake, exam and merge_animals were still free
// to write about a bird nobody had handed them. That is the same hole lib_auth.js
// was created for, one level up: there the routes had to re-state WHO may act,
// here they have to re-state WHAT they may act on.
//
// ── Why the rule and this module are not identical ──────────────────────────
// The `cases` create rule can express "you hold it" but NOT "nobody holds it":
// the aviary half is a plain comparison (`animal.current_aviary = ""`), while
// "the animal has no open case" is a negative existential, and PocketBase's
// `?!=` means "any of them differs", not "none of them matches". So the rule is
// deliberately the coarser backstop (keeper + not-deceased) and THIS is the
// authoritative gate — which is sound because the app creates cases only
// through `/api/federfall/intake` (cases_repository.dart:434); a direct
// `cases.create` has no client path at all.
//
// STATELESS (see lib_audit.js): each pooled JSVM holds its own instance, so
// nothing here may cache a decision between calls.

/** Non-disposed: the status set the case browser calls active (federfall-jt5u). */
function isOpen(caseRec) {
  const status = caseRec.getString("status");
  return status === "in_care" || status === "ready_for_release" || status === "";
}

/** Every case of [animalId], newest first. */
function casesOf(app, animalId) {
  try {
    return app.findRecordsByFilter(
      "cases", "animal = {:a}", "-created", 500, 0, { a: animalId },
    );
  } catch (_) {
    return [];
  }
}

/**
 * Whether [auth] currently holds [animalId] — the same four branches
 * 1700000077 expresses as a rule, in the same order:
 *   coordinator/supervisor, the keeper of its enclosure, the active carer of an
 *   open case, an edit-share holder on one.
 */
function holds(app, auth, animalId) {
  if (!auth || !animalId) return false;
  const role = auth.getString("role");
  if (role === "coordinator" || role === "supervisor") return true;

  let animal;
  try {
    animal = app.findRecordById("animals", animalId);
  } catch (_) {
    return false;
  }

  if (keeps(app, auth, animal.getString("current_aviary"))) return true;

  for (const caseRec of casesOf(app, animalId)) {
    const status = caseRec.getString("status");
    if (!(status === "in_care" || status === "ready_for_release" ||
          status === "")) {
      continue;
    }
    if (caseRec.getString("active_carer") === auth.id) return true;
    let shares = [];
    try {
      shares = app.findRecordsByFilter(
        "case_shares",
        "case = {:c} && shared_with = {:u} && access = 'edit'",
        "", 1, 0, { c: caseRec.id, u: auth.id },
      );
    } catch (_) {
      shares = [];
    }
    if (shares.length > 0) return true;
  }
  return false;
}

/** Whether [animalId] carries any non-disposed case. */
function hasOpenCase(app, animalId) {
  for (const caseRec of casesOf(app, animalId)) {
    if (isOpen(caseRec)) return true;
  }
  return false;
}

/**
 * Whether [auth] is the keeper of [aviaryId].
 *
 * A dangling enclosure answers false, the same tolerance [holds] has: it grants
 * nothing rather than throwing.
 */
function keeps(app, auth, aviaryId) {
  if (!auth || !aviaryId) return false;
  try {
    return app.findRecordById("aviaries", aviaryId).getString("keeper") ===
      auth.id;
  } catch (_) {
    return false;
  }
}

/**
 * Whether anybody OTHER than [auth] would hold [animalId] if [aviary] were its
 * enclosure.
 *
 * The hypothetical enclosure is for [requireOutcomeWrite], which has to ask this
 * with the row it is judging taken back out of the bird's history. "Other than
 * [auth]" rather than "nobody" because the writer's own hold is not an obstacle
 * to their own write — and because the alternative over-refuses: a carer
 * correcting their release back into a placement would be turned away by the
 * enclosure the correction takes the bird OUT of, one they keep themselves.
 *
 * An open case grants custody to its carer AND to its edit-share holders, but
 * this only has to name a holder, not enumerate them: a case whose carer is
 * [auth] cannot reach here (holds() would have answered first), so any open case
 * left is somebody else's.
 */
function heldByOthersWith(app, auth, animalId, aviary) {
  const id = auth ? auth.id : "";
  if (aviary && !keeps(app, auth, aviary)) {
    try {
      app.findRecordById("aviaries", aviary);
      return true;
    } catch (_) {
      // A dangling enclosure holds nothing.
    }
  }
  for (const caseRec of casesOf(app, animalId)) {
    if (isOpen(caseRec) && caseRec.getString("active_carer") !== id) return true;
  }
  return false;
}

/**
 * Whether NOBODY holds [animalId]: no enclosure and no open case.
 *
 * A bird at large is anyone's to find, which is the whole point of
 * re-identification at intake — so this is what lets a stranger admit it.
 */
function heldByNobody(app, animalId) {
  let animal;
  try {
    animal = app.findRecordById("animals", animalId);
  } catch (_) {
    return false;
  }
  if (animal.getString("current_aviary")) return false;
  return !hasOpenCase(app, animalId);
}

/**
 * Gate for writing about an existing bird: hold it, or a role that overrides.
 * Throws ForbiddenError otherwise.
 */
function requireCustody(app, auth, animalId) {
  if (!holds(app, auth, animalId)) {
    throw new ForbiddenError("This animal is in someone else's care.");
  }
}

/**
 * Gate for ADMITTING an existing bird: hold it, or nobody does.
 *
 * A deceased bird is refused outright for anyone but a coordinator/supervisor —
 * a new case on one means the death record was wrong, which is a correction, not
 * an admission. `lifetime_status` is trustworthy in exactly this direction: it
 * lags toward the PAST (federfall-sinp), so it can read stale-alive but never
 * falsely deceased.
 */
function requireAdmissible(app, auth, animalId) {
  const role = auth ? auth.getString("role") : "";
  const override = role === "coordinator" || role === "supervisor";
  if (!override) {
    let animal;
    try {
      animal = app.findRecordById("animals", animalId);
    } catch (_) {
      throw new BadRequestError("Unknown animal.");
    }
    if (animal.getString("lifetime_status") === "deceased") {
      throw new ForbiddenError(
        "This animal is recorded as deceased; a supervisor has to correct that " +
        "before it can be admitted again.",
      );
    }
  }
  if (!holds(app, auth, animalId) && !heldByNobody(app, animalId)) {
    throw new ForbiddenError("This animal is in someone else's care.");
  }
}

/**
 * Gate for a disposition write that would MOVE a bird — federfall-mpm4.
 *
 * [disp] is the pending row (`e.record`), [removing] true on the delete leg.
 * Throws ForbiddenError when the act would re-take a bird somebody else holds.
 *
 * ── What is being closed ────────────────────────────────────────────────────
 * `dispositions` create/update/delete is 1700000010's `childEdit`, and
 * `active_carer` of a DISPOSED case never expires — so the carer of a case
 * closed years ago can still write dispositions on it forever. Since 1700000077
 * that is write authority rather than a label: a `placed_in_aviary` row sets
 * `animals.current_aviary`, and `current_aviary.keeper = @request.auth.id` is a
 * custody branch on `animals` and (through 1700000079) on every animal-level
 * record collection. Dating such a row just-past makes it the bird's latest
 * event, so its writer becomes the custodian of a bird in someone else's care.
 * `disposition_dates.pb.js` bounded the FUTURE; this bounds who may write a
 * mover at all.
 *
 * ── When it fires ───────────────────────────────────────────────────────────
 * Only when the write is custody-relevant, which is two things:
 *
 *   * it would change the animal's derived `current_aviary`
 *     (`lib_derive.js`'s [prospectiveAviary] — the value the reconcile that
 *     follows this write would store), or
 *   * it is a delete that removes a case's LAST disposition, which re-opens the
 *     case (`reconcileCase`) and hands custody back to its `active_carer`. That
 *     is federfall-epkf's mechanism through a second door: `case_status.pb.js`
 *     refuses the direct `status` write, and this refuses reaching the same
 *     place by deleting the outcome that closed the case.
 *
 * Everything else about a disposition — its reason, its release location, a vet
 * name, a date that does not reorder anything — stays editable by whoever may
 * edit the case, because none of it decides who holds the bird.
 *
 * ── The predicate, and why it is not plain custody ──────────────────────────
 * Allowed when the writer holds the bird now, OR when both of these hold:
 *
 *   a. nobody ELSE holds it once this row is set aside
 *      ([heldByOthersWith] against [prospectiveAviary]'s answer without it), and
 *   b. the write does not hand the bird to the writer — the enclosure it would
 *      end up in is not one they keep.
 *
 * (a) is what keeps the correction path open, and it is the sentence
 * `requireAdmissible` already lives by — a bird nobody holds is anyone's to
 * take:
 *
 *   * A carer records `placed_in_aviary`, then notices the wrong enclosure. The
 *     placement closed their case and made the bird the enclosure's, so plain
 *     custody would refuse them their own correction and only a supervisor could
 *     repair it (the keeper cannot: `childEdit` binds a disposition to its
 *     case's carer). Without their row the bird is unheld, so they may fix it.
 *   * A carer records `died` by mistake and deletes it. Evaluated on the state
 *     as it stands, the animal reads `deceased`; there is deliberately NO
 *     deceased refusal here (unlike [requireAdmissible]), because correcting a
 *     wrong death record is exactly what this branch must allow.
 *
 * (b) is what stops (a) from handing mpm4 back. A row is the reason the bird is
 * where it is, so setting THAT row aside always answers "nobody holds it" — for
 * the honest correction above and equally for a stale carer re-pointing the
 * placement that houses somebody else's resident at their own enclosure. State
 * alone cannot separate those two, so the second condition is about the
 * DESTINATION rather than the history: whatever else a correction does, it may
 * not end with the bird in the writer's own care. That is the escalation
 * federfall-mpm4 is, and losing custody is never one.
 *
 * A supervisor overrides throughout ([holds]), which is what keeps archive
 * backfill — entering an old history in whatever order it is found — a supported
 * operation, and what repairs anything this refuses. A coordinator overrides
 * this gate too but rarely reaches it: `childEdit` only lets a case's own carer
 * (or a supervisor) at its dispositions in the first place.
 *
 * ── What it deliberately does NOT close ─────────────────────────────────────
 * By (b)'s logic the same stale carer may still EVICT another keeper's resident
 * — correcting their old placement to a release ends with the bird at large, in
 * nobody's care, so it is not an escalation and (b) does not fire. It is still
 * somebody else's flock changing under them, tracked separately (federfall-q11w)
 * because the answer trades against the same correction path: the bird's state
 * is visible in the registry, the enclosure's `aviary_stays` row closes, and
 * `lib_audit.js` records who did it.
 *
 * Nor does it ask whether the DESTINATION agreed. This is custody of the animal;
 * whether a placement may name an enclosure the writer does not keep — which
 * 1700000077 already answers "no" for the `animals.create` path — is
 * federfall-ehzz.
 *
 * ── Scope ───────────────────────────────────────────────────────────────────
 * Registered as the *Request variants only (see animal_custody_scope.pb.js):
 * `e.auth` lives there, and the server-side writers must stay exempt —
 * `merge_animals.pb.js` re-points a duplicate's dispositions with `tx.save()`,
 * and `intake.pb.js` writes none. Superuser is exempt for the same reason it is
 * everywhere else: it bypasses collection rules anyway.
 *
 * The app is NOT gated to match, and that is deliberate: the second branch above
 * depends on a counterfactual the client cannot compute without the bird's whole
 * history, and the affordance it would hide is the correction path this exists to
 * protect. A refusal here surfaces as the generic "not permitted" message on a
 * path no shipped screen can reach except by editing a stale case.
 */
function requireOutcomeWrite(app, auth, disp, removing) {
  const caseId = disp.getString("case");
  if (!caseId) return;
  let caseRec;
  try {
    caseRec = app.findRecordById("cases", caseId);
  } catch (_) {
    return; // No case to derive from; the collection rule already refused this.
  }
  const animalId = caseRec.getString("animal");
  if (!animalId) return;
  let animal;
  try {
    animal = app.findRecordById("animals", animalId);
  } catch (_) {
    return; // A dangling animal grants nothing and blocks nothing.
  }

  // The ordinary path, and the cheap one: a writer who holds the bird may move
  // it, so nothing below has to be derived at all. A coordinator or supervisor
  // answers here without a single query.
  if (holds(app, auth, animalId)) return;

  const derive = require(`${__hooks}/lib_derive.js`);
  const withoutIt = derive.prospectiveAviary(app, animalId, {
    id: disp.id,
    removed: true,
  });
  let after = withoutIt;
  if (!removing) {
    // The pending row's own instant. `disposed_at` when it carries one, else the
    // `created` it already has (an update), else the clock — which is what
    // PocketBase is about to autodate `created` to (a create). Same lexical
    // shape as a stored value, the way disposition_dates.pb.js writes it.
    const instant =
      disp.getString("disposed_at") ||
      disp.getString("created") ||
      new Date().toISOString().replace("T", " ");
    after = derive.prospectiveAviary(app, animalId, {
      id: disp.id,
      case: caseId,
      instant: instant,
      type: disp.getString("type"),
      aviary: disp.getString("aviary"),
    });
  }

  let reopensCase = false;
  if (removing) {
    let siblings = [];
    try {
      siblings = app.findRecordsByFilter(
        "dispositions", "case = {:c}", "", 0, 0, { c: caseId },
      );
    } catch (_) {
      siblings = [];
    }
    reopensCase = true;
    for (const d of siblings) {
      if (d.id !== disp.id) reopensCase = false;
    }
  }

  if (after === animal.getString("current_aviary") && !reopensCase) return;
  if (
    !heldByOthersWith(app, auth, animalId, withoutIt) &&
    !keeps(app, auth, after)
  ) {
    return;
  }
  throw new ForbiddenError("This animal is in someone else's care.");
}

module.exports = {
  holds: holds,
  keeps: keeps,
  hasOpenCase: hasOpenCase,
  heldByNobody: heldByNobody,
  heldByOthersWith: heldByOthersWith,
  requireCustody: requireCustody,
  requireAdmissible: requireAdmissible,
  requireOutcomeWrite: requireOutcomeWrite,
};
