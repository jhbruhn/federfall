/// <reference path="../pb_data/types.d.ts" />

// federfall-q7ks.5 — "who holds this bird", for the routes that bypass rules.
//
// Usage — `require()` INSIDE the handler, never at file level, and always with
// the `${__hooks}` absolute form (see lib_audit.js / lib_auth.js):
//
//   const custody = require(`${__hooks}/lib_custody.js`);
//   custody.requireAdmissible(tx, e.auth, animalId);
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

  const aviaryId = animal.getString("current_aviary");
  if (aviaryId) {
    try {
      const aviary = app.findRecordById("aviaries", aviaryId);
      if (aviary.getString("keeper") === auth.id) return true;
    } catch (_) {
      // A dangling enclosure grants nothing rather than throwing.
    }
  }

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
  for (const caseRec of casesOf(app, animalId)) {
    if (isOpen(caseRec)) return false;
  }
  return true;
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

module.exports = {
  holds: holds,
  heldByNobody: heldByNobody,
  requireCustody: requireCustody,
  requireAdmissible: requireAdmissible,
};
