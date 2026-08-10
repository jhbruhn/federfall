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
 * Whether anybody OTHER than [auth] holds [animalId].
 *
 * Not the negation of [heldByNobody], deliberately: that one answers "is this
 * bird anyone's" for an ADMISSION, where an open case with no carer at all still
 * counts as held (an imported row, and refusing is the safe direction). This one
 * asks whether a writer would be taking a bird from somebody, so a case with
 * nobody on it takes nothing from anyone.
 *
 * An open case grants custody to its carer AND to its edit-share holders, but
 * this only has to NAME a holder, not enumerate them: a case whose carer is
 * [auth] cannot reach here (holds() answers first), so any open case left is
 * somebody else's.
 */
function heldByOthers(app, auth, animalId) {
  const id = auth ? auth.id : "";
  let animal;
  try {
    animal = app.findRecordById("animals", animalId);
  } catch (_) {
    return false;
  }
  const aviary = animal.getString("current_aviary");
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
 * Gate for a disposition write that would MOVE a bird — federfall-mpm4, then
 * federfall-q11w for the shape it settled on.
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
 * ── The predicate: one sentence per leg ─────────────────────────────────────
 *   moving the bird    the writer must HOLD it — plain [holds], no exceptions.
 *   re-opening a case  the writer must hold it, or nobody else may.
 *
 * Moving is plain custody because nothing weaker survives contact with
 * federfall-q11w. The tempting weaker form is "…or nobody else holds it once
 * this row is set aside", which would let a carer repair the placement they just
 * recorded — but a placement row IS the reason the bird is where it is, so
 * setting THAT row aside always answers "nobody holds it": for the honest repair
 * and equally for a stale carer re-pointing or withdrawing the placement that
 * houses somebody else's resident. State alone cannot separate those two (the
 * only discriminator is elapsed time), so the weaker form was tried, measured
 * against q11w, and dropped.
 *
 * What that costs is real and was accepted on purpose: once a carer has placed a
 * bird, they can no longer change WHERE it went, withdraw the placement, or
 * delete it — the bird is the enclosure's now. Handing a bird over is not
 * reversible by the person who handed it over. The repairs are the keeper's (who
 * holds the bird, and can admit it on a fresh case and place it correctly) or a
 * supervisor's.
 *
 * Re-opening keeps the weaker form because the same argument does not apply: a
 * released or deceased bird is in nobody's enclosure, so "nobody else holds it"
 * is a statement about the world rather than about the row being deleted. That is
 * what keeps the ordinary correction — "I recorded the wrong outcome, delete it"
 * — working for its carer. There is deliberately no deceased refusal here
 * (unlike [requireAdmissible]): deleting a wrong death record is exactly the act
 * that must stay possible.
 *
 * A supervisor overrides throughout ([holds]), which is what keeps archive
 * backfill — entering an old history in whatever order it is found — a supported
 * operation, and what repairs anything this refuses. A coordinator overrides
 * this gate too but rarely reaches it: `childEdit` only lets a case's own carer
 * (or a supervisor) at its dispositions in the first place.
 *
 * ── What it deliberately does NOT ask ───────────────────────────────────────
 * Whether the DESTINATION agreed. This is custody of the animal; a placement may
 * still name an enclosure the writer does not keep, even though 1700000077
 * answers "no" to the same question on the `animals.create` path. That asymmetry
 * is deliberate (federfall-ehzz): the keeper is not stuck with the bird — they
 * hold it the moment it lands, and can admit it on a fresh case and place it
 * elsewhere. Recourse after the fact rather than consent before it.
 *
 * ── Scope ───────────────────────────────────────────────────────────────────
 * Registered as the *Request variants only (see animal_custody_scope.pb.js):
 * `e.auth` lives there, and the server-side writers must stay exempt —
 * `merge_animals.pb.js` re-points a duplicate's dispositions with `tx.save()`,
 * and `intake.pb.js` writes none. Superuser is exempt for the same reason it is
 * everywhere else: it bypasses collection rules anyway.
 *
 * The app is NOT gated to match. `canWriteAnimal` (custody_providers.dart) is the
 * predicate for the moving leg and could hide the disposition sheet's aviary
 * picker behind it, but the re-opening leg needs "nobody ELSE holds it", which a
 * client cannot answer without reading cases it has no right to see. So a refusal
 * surfaces as the generic "not permitted" message, on paths a carer reaches only
 * by revisiting an outcome they can no longer change.
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
  let after;
  if (removing) {
    after = derive.prospectiveAviary(app, animalId, {
      id: disp.id,
      removed: true,
    });
  } else {
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

  // The moving leg. Compared against the STORED field rather than against a
  // second derivation, because that field is what the reconcile after this write
  // would overwrite — including for a case-less resident placed straight into an
  // enclosure (add_animal_sheet.dart), whose enclosure no disposition explains.
  if (after !== animal.getString("current_aviary")) {
    throw new ForbiddenError("This animal is in someone else's care.");
  }

  // The re-opening leg: only a delete can reach it, and only by taking away the
  // case's last disposition — `reconcileCase` then sets the case back to
  // `in_care`, and its `active_carer` holds the bird again.
  if (!removing) return;
  let siblings = [];
  try {
    siblings = app.findRecordsByFilter(
      "dispositions", "case = {:c}", "", 0, 0, { c: caseId },
    );
  } catch (_) {
    siblings = [];
  }
  for (const d of siblings) {
    if (d.id !== disp.id) return; // Another outcome keeps the case closed.
  }
  if (heldByOthers(app, auth, animalId)) {
    throw new ForbiddenError("This animal is in someone else's care.");
  }
}

module.exports = {
  holds: holds,
  heldByNobody: heldByNobody,
  requireCustody: requireCustody,
  requireAdmissible: requireAdmissible,
  requireOutcomeWrite: requireOutcomeWrite,
};
