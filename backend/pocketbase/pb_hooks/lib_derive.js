/// <reference path="../pb_data/types.d.ts" />

// federfall-sinp — ONE derivation of `animals.lifetime_status` /
// `current_aviary`, ordered by when a disposition SAYS it happened.
//
// Usage — `require()` INSIDE the handler, never at file level, and always with
// the `${__hooks}` absolute form (see lib_audit.js / lib_custody.js):
//
//   const derive = require(`${__hooks}/lib_derive.js`);
//   derive.reconcileAnimal(e.app, derive.reconcileCase(e.app, caseId));
//
// ── What was wrong ──────────────────────────────────────────────────────────
// Two defects, both invisible in live use and both fatal to archive work:
//
//   1. The disposition CREATE hook applied the new row's type unconditionally
//      and cleared `current_aviary` for any non-aviary type. Only the
//      after-update / after-delete paths reconciled across the animal's whole
//      history. So entering an archived `released` for a bird that is currently
//      an aviary resident flipped it to `at_large_released`, emptied
//      `current_aviary` and — via aviary_stays.pb.js reacting to that field
//      change — closed the still-running residency with a present-dated
//      `ended_at`, a false fact no UI can repair.
//   2. Where a reconcile did run, "latest" meant the most recently INSERTED
//      row: every scan compared `created`, the autodate. Backfilling a history
//      in any order but chronological therefore left the wrong final state.
//
// Since 1700000077 that is no longer only a labelling bug. `current_aviary` is
// a CUSTODY pointer: emptying it revokes the keeper's authority over a live
// resident, and only a fresh `placed_in_aviary` disposition can put it back —
// the field is isset-guarded against client writes (1700000075).
//
// ── The order ───────────────────────────────────────────────────────────────
// `COALESCE(NULLIF(disposed_at, ''), created) DESC, id DESC` — which is not a
// new opinion about ordering but the one `case_summaries` (1700000028) and
// `case_report_rows` (1700000067) have always used. The hooks were the odd ones
// out, so a bird's own record could disagree with the case browser and both
// reports about which disposition ended its story. The `id` tie-break is there
// for the same reason it is in the view: two dispositions can carry the same
// instant, and "latest" has to be one answer, not whichever row a scan met last.
//
// `disposed_at` is client-writable (finder_retention.pb.js says so out loud, and
// that is why the retention window does NOT use it), so a carer can order their
// own dispositions as they like. That is not an escalation — they can already
// record any disposition on a case they hold, which decides the same state — but
// it is the reason nothing security-relevant may key off this ordering.
//
// ── Why one module rather than four copies ──────────────────────────────────
// It had four writers: the disposition create / update / delete hooks and
// merge_animals.pb.js, three of which held their own transcription of the same
// switch statement. A required module is the one thing isolated JSVM handlers
// can share (see lib_stats.js), so it is how "latest" is made to mean one thing.
//
// STATELESS (see lib_audit.js): each pooled JSVM holds its own instance, so
// nothing here may cache a decision between calls.

/** Every disposition type, and the lifetime state it puts the bird in. */
const LIFETIME_BY_TYPE = {
  died: "deceased",
  euthanized: "deceased",
  placed_in_aviary: "in_aviary",
  // No longer in our care, presumed alive — the 4-state lifetime model folds
  // these three into "at large".
  released: "at_large_released",
  returned_to_owner: "at_large_released",
  transferred: "at_large_released",
};

/**
 * The instant a disposition says it happened, falling back to when it was
 * entered. Both are PocketBase datetimes in the same `YYYY-MM-DD HH:MM:SS.sssZ`
 * shape, so they compare lexicographically against each other and when mixed —
 * and an unset `disposed_at` is `""`, which would sort before every real date,
 * hence the fallback rather than a bare read.
 */
function instantOf(disp) {
  return disp.getString("disposed_at") || disp.getString("created");
}

/** Whether [a] beats [b] under the canonical order (see the header). */
function isLater(a, b) {
  const ia = instantOf(a);
  const ib = instantOf(b);
  if (ia !== ib) return ia > ib;
  return a.id > b.id;
}

/**
 * The disposition that decides [animalId]'s state — the latest across ALL of
 * its cases, not just one — or null when it has none anywhere.
 *
 * Scanned in JS rather than sorted by the server because the order is a
 * COALESCE, which `findRecordsByFilter`'s sort argument cannot express.
 */
function latestDisposition(app, animalId) {
  if (!animalId) return null;
  let cases = [];
  try {
    cases = app.findRecordsByFilter(
      "cases", "animal = {:a}", "", 0, 0, { a: animalId },
    );
  } catch (_) {
    return null;
  }
  let latest = null;
  for (const c of cases) {
    let disps = [];
    try {
      disps = app.findRecordsByFilter(
        "dispositions", "case = {:c}", "", 0, 0, { c: c.id },
      );
    } catch (_) {
      continue;
    }
    for (const d of disps) {
      if (!latest || isLater(d, latest)) latest = d;
    }
  }
  return latest;
}

/**
 * The state [animalId]'s history implies, as `{ lifetime, aviary }`, WITHOUT
 * saving anything.
 *
 * Separate from [reconcileAnimal] for merge_animals.pb.js, which must set these
 * fields on a survivor record it saves exactly ONCE: the after-success hooks are
 * deferred to the commit and re-read the same record object, so two saves
 * deliver two transitions off one stale `original()` — which is how one aviary
 * move opened two residencies (federfall-0ua6).
 *
 * [fallbackAviary] is consulted ONLY when the animal has no disposition
 * anywhere, and exists for exactly one caller. A merge can leave a survivor
 * whose whole merged history has no disposition while one of the two records
 * documented a CASE-LESS residency (add_animal_sheet.dart puts a bird straight
 * into an enclosure, no case and therefore no disposition), and that residency
 * lives only on the animal record — so the "in_care" default would silently
 * evict the bird. It is deliberately NOT the default: everywhere else, no
 * disposition means the reconcile is running because the last one was deleted,
 * and the enclosure it had set must go with it.
 */
function deriveState(app, animalId, fallbackAviary) {
  const latest = latestDisposition(app, animalId);
  if (!latest) {
    const housed = fallbackAviary || "";
    return housed
      ? { lifetime: "in_aviary", aviary: housed }
      : { lifetime: "in_care", aviary: "" };
  }
  const type = latest.getString("type");
  return {
    lifetime: LIFETIME_BY_TYPE[type] || "in_care",
    aviary: type === "placed_in_aviary" ? latest.getString("aviary") : "",
  };
}

/**
 * Re-derives [animalId]'s lifetime state and saves it. A no-op when the animal
 * is gone — the delete path reaches here after a cascade has already destroyed
 * it, and because that runs AFTER a successful delete, throwing would not roll
 * anything back; it would just turn a completed delete into a 400
 * (federfall-vfl7).
 */
function reconcileAnimal(app, animalId, fallbackAviary) {
  if (!animalId) return false;
  let animal;
  try {
    animal = app.findRecordById("animals", animalId);
  } catch (_) {
    return false;
  }
  const state = deriveState(app, animalId, fallbackAviary);
  animal.set("lifetime_status", state.lifetime);
  animal.set("current_aviary", state.aviary);
  app.save(animal);
  return true;
}

/**
 * Re-derives [caseId].status from whether it still carries any disposition, and
 * returns the animal to reconcile next (`""` when the case is gone).
 *
 * Order-independent, unlike the animal's state: ANY disposition closes its case,
 * because the bird has left acute care whichever one was entered last. A
 * resident that later falls ill gets a NEW case rather than reopening this one.
 */
function reconcileCase(app, caseId) {
  if (!caseId) return "";
  let caseRec;
  try {
    caseRec = app.findRecordById("cases", caseId);
  } catch (_) {
    return "";
  }
  let remaining = [];
  try {
    remaining = app.findRecordsByFilter(
      "dispositions", "case = {:c}", "", 1, 0, { c: caseId },
    );
  } catch (_) {
    remaining = [];
  }
  caseRec.set("status", remaining.length > 0 ? "disposed" : "in_care");
  app.save(caseRec);
  return caseRec.getString("animal");
}

module.exports = {
  instantOf: instantOf,
  latestDisposition: latestDisposition,
  deriveState: deriveState,
  reconcileAnimal: reconcileAnimal,
  reconcileCase: reconcileCase,
};
