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
// record any disposition on a case they hold, which decides the same state.
//
// This file used to end that paragraph with "which is the reason nothing
// security-relevant may key off this ordering", written in the same line that
// made 1700000077 key off `current_aviary` — i.e. off exactly this output. The
// sentence was wrong, not the code, so it is gone (federfall-j163). What is true:
//
//   * an ORDER a client picks does decide a custody pointer, so the dates it can
//     pick are bounded — `disposition_dates.pb.js` refuses a `disposed_at` more
//     than a day in the future, because a disposition is a thing that HAPPENED
//     and a future one could otherwise pin a bird's derived state indefinitely;
//   * within the past, ordering stays the writer's to state, and it has to be:
//     backfilling an archive is entering old events in whatever order they are
//     found. Dating a placement just-past therefore still makes it the bird's
//     latest event — what is bounded is WHO may do that, not the ordering
//     (federfall-mpm4): `disposition_custody.pb.js` asks THIS module what a
//     pending write would derive ([prospectiveAviary]) and refuses one that
//     would move a bird its writer does not hold.
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

/**
 * The instant a case says the bird came in — the same shape and the same
 * fallback as [instantOf], so an admission and a disposition compare directly.
 */
function admissionOf(caseRec) {
  return caseRec.getString("admitted_at") || caseRec.getString("created");
}

/**
 * The latest admission among [animalId]'s still-OPEN cases, or `""` when it has
 * none.
 *
 * "Open" is the explicit status set the case browser calls active
 * (federfall-jt5u) and 1700000077's custody rule names verbatim — spelled out
 * rather than `!= "disposed"` so the three cannot drift. `""` is in it because a
 * row imported through the Admin UI can carry no status at all, and such a case
 * is open.
 */
function latestAdmission(app, animalId) {
  if (!animalId) return "";
  let cases = [];
  try {
    cases = app.findRecordsByFilter(
      "cases",
      'animal = {:a} && (status = "in_care" || status = "ready_for_release"' +
        ' || status = "")',
      "", 0, 0, { a: animalId },
    );
  } catch (_) {
    return "";
  }
  let latest = "";
  for (const c of cases) {
    const at = admissionOf(c);
    if (at > latest) latest = at;
  }
  return latest;
}

/** Whether [a] beats [b] under the canonical order (see the header). */
function isLater(a, b) {
  if (a.instant !== b.instant) return a.instant > b.instant;
  return a.id > b.id;
}

/**
 * Every disposition of [animalId], reduced to the four things the order and the
 * derivation actually read: `{ id, case, instant, type, aviary }`.
 *
 * Plain objects rather than records because [prospectiveAviary] weighs a row
 * that has not been written yet against them, and a pending row is not a stored
 * record: its `created` is still empty, and on a create its id is not in the
 * table at all.
 */
function dispositionEvents(app, animalId) {
  const events = [];
  if (!animalId) return events;
  let cases = [];
  try {
    cases = app.findRecordsByFilter(
      "cases", "animal = {:a}", "", 0, 0, { a: animalId },
    );
  } catch (_) {
    return events;
  }
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
      events.push({
        id: d.id,
        case: c.id,
        instant: instantOf(d),
        type: d.getString("type"),
        aviary: d.getString("aviary"),
      });
    }
  }
  return events;
}

/** The latest of [events] under the canonical order, or null when there is none. */
function latestOf(events) {
  let latest = null;
  for (const ev of events) {
    if (!latest || isLater(ev, latest)) latest = ev;
  }
  return latest;
}

/** The enclosure an event implies — only a placement puts a bird in one. */
function aviaryOf(event) {
  if (!event) return "";
  return event.type === "placed_in_aviary" ? event.aviary : "";
}

/**
 * The disposition that decides [animalId]'s state — the latest across ALL of
 * its cases, not just one — as a [dispositionEvents] entry, or null when it has
 * none anywhere.
 *
 * Scanned in JS rather than sorted by the server because the order is a
 * COALESCE, which `findRecordsByFilter`'s sort argument cannot express.
 */
function latestDisposition(app, animalId) {
  return latestOf(dispositionEvents(app, animalId));
}

/**
 * The `current_aviary` [animalId] would end up with if its dispositions were
 * changed by [change] — a write that has not happened yet.
 *
 * [change] is `{ id, instant, type, aviary }` for a row being created or
 * updated (the stored row with that id, if any, is replaced by it), or
 * `{ id, removed: true }` for one being deleted. `null` asks the question about
 * the history as it stands.
 *
 * The caller supplies `instant` rather than letting this read `disposed_at`,
 * because a pending create has no `created` to fall back on yet: the fallback
 * has to be the clock, and that belongs to the writer, not here.
 *
 * No fallback enclosure, unlike [deriveState]: an animal with no disposition
 * left ends up with none, which is exactly what the disposition create / update
 * / delete hooks ask for (they call `reconcileAnimal` without one). This is
 * therefore the aviary the NEXT reconcile would write — which is what makes it
 * answerable BEFORE the write, and the reason
 * `disposition_custody.pb.js` can gate on it.
 */
function prospectiveAviary(app, animalId, change) {
  const events = [];
  for (const ev of dispositionEvents(app, animalId)) {
    if (change && ev.id === change.id) continue;
    events.push(ev);
  }
  if (change && !change.removed) {
    events.push({
      id: change.id,
      case: change.case || "",
      instant: change.instant,
      type: change.type,
      aviary: change.aviary,
    });
  }
  return aviaryOf(latestOf(events));
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
 *
 * ── An open case is an event too (federfall-8f1m) ───────────────────────────
 * A disposition describes a PAST episode; an open case describes now. Derived
 * from dispositions alone, a re-admitted bird kept reading `at_large_released`
 * and a resident under treatment `in_aviary` for the whole of its new stay,
 * because "has an open case" is not a disposition. So the LATEST EVENT decides
 * across both kinds: an admission later than every disposition means `in_care`.
 *
 * Later, not merely present. "Any open case wins" would be the same bug in the
 * other direction — one case somebody forgot to close would pin a bird to
 * `in_care` forever, and no disposition could ever repair it (which is exactly
 * the shape of `[hooks: dispositions]`'s c3: a stale open case alongside a
 * placement entered afterwards, where `in_aviary` is the true answer). Ties go
 * to the open case: a same-instant admission and disposition is a same-day
 * re-admission, and the failure mode of the other choice is the bug being fixed.
 *
 * Two things deliberately do NOT follow:
 *
 *   * `current_aviary`. A resident under treatment is still that enclosure's
 *     bird, and since 1700000077 the field is a CUSTODY pointer — emptying it on
 *     admission would revoke the keeper's authority over a live resident, the
 *     same failure federfall-sinp fixed. So `lifetime_status = in_care` WITH
 *     `current_aviary` set is a legitimate, reachable pair.
 *   * the direction lib_custody.js depends on. `requireAdmissible` reads
 *     `lifetime_status` for one thing only — refusing to admit a bird recorded
 *     deceased — on the stated grounds that it can read stale-alive but never
 *     falsely deceased. This override only ever produces `in_care`, so it can
 *     make a state stale-alive and never the reverse.
 */
function deriveState(app, animalId, fallbackAviary) {
  const latest = latestDisposition(app, animalId);
  const aviary = latest ? aviaryOf(latest) : (fallbackAviary || "");
  let lifetime;
  if (latest) {
    lifetime = LIFETIME_BY_TYPE[latest.type] || "in_care";
  } else {
    lifetime = aviary ? "in_aviary" : "in_care";
  }
  if (lifetime !== "in_care") {
    const admitted = latestAdmission(app, animalId);
    if (admitted && admitted >= (latest ? latest.instant : "")) {
      lifetime = "in_care";
    }
  }
  return { lifetime: lifetime, aviary: aviary };
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
 * Re-derives [animalId] after a CASE event — an admission, a status change, a
 * deleted case (main.pb.js section 2c).
 *
 * The animal's own `current_aviary` is the fallback here, and that is the whole
 * difference from [reconcileAnimal]: a case never decides WHERE a bird lives.
 * For a case-less resident (add_animal_sheet.dart puts a bird straight into an
 * enclosure — no case, therefore no disposition to re-derive the enclosure from)
 * the plain default would answer `aviary: ""` and evict it, closing a running
 * residency and taking its keeper's write access with it. Opening a case on a
 * resident must leave the enclosure exactly as it was.
 */
function reconcileAnimalFromCase(app, animalId) {
  if (!animalId) return false;
  let animal;
  try {
    animal = app.findRecordById("animals", animalId);
  } catch (_) {
    return false;
  }
  return reconcileAnimal(app, animalId, animal.getString("current_aviary"));
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
  admissionOf: admissionOf,
  latestAdmission: latestAdmission,
  latestDisposition: latestDisposition,
  prospectiveAviary: prospectiveAviary,
  deriveState: deriveState,
  reconcileAnimal: reconcileAnimal,
  reconcileAnimalFromCase: reconcileAnimalFromCase,
  reconcileCase: reconcileCase,
};
