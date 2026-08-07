/// <reference path="../pb_data/types.d.ts" />

// federfall-d5co.1 — aviary_stays: an append-only residency ledger for
// `animals.current_aviary`, maintained by centralizing on the `animals`
// collection instead of patching each of the five places current_aviary is
// written (dispositions create/update/delete reconcile in main.pb.js,
// merge_animals.pb.js, and add_animal_sheet.dart's case-less resident
// create). Every one of those writers ends in a saved `animals` record, so
// hooking `animals` covers all of them here, in one place.
//
// "Current residency" = the latest row per animal with `ended_at` unset
// (mirrors how `active_carer` is derived from the latest Placement). No
// recursion risk: these hooks only ever write `aviary_stays` rows, never
// re-save the animal that triggered them.
//
// NOTE: each hook callback runs in its own isolated JSVM — see main.pb.js's
// header note; nothing here is shared with other files.

onRecordAfterCreateSuccess((e) => {
  const animal = e.record;
  const aviary = animal.getString("current_aviary");
  if (aviary) {
    const stay = new Record(e.app.findCollectionByNameOrId("aviary_stays"));
    stay.set("animal", animal.id);
    stay.set("aviary", aviary);
    stay.set("started_at", new Date().toISOString());
    stay.set("org", animal.getString("org"));
    e.app.save(stay);
  }
  e.next();
}, "animals");

onRecordAfterUpdateSuccess((e) => {
  const animal = e.record;
  const before = animal.original().getString("current_aviary");
  const after = animal.getString("current_aviary");

  if (before !== after) {
    const now = new Date().toISOString();

    // Close every row that is still open and is not the one `after` already
    // calls for. The invariant this enforces is "at most one open stay, and it
    // names current_aviary" — stated over ALL open rows rather than just
    // closing the latest one, because two can exist:
    //
    //   * a merge re-points the duplicate's ledger onto the survivor
    //     (merge_animals.pb.js, federfall-0ua6) — it closes what it moves, but
    //     the invariant should not depend on a caller remembering to;
    //   * a writer that saves the same animal twice in one transaction gets
    //     this callback twice for ONE transition, since the after-success
    //     hooks are deferred to the commit and each re-reads the same record
    //     object against the same stale `original()`. Skipping an already-open
    //     row for `after` makes the second run a no-op instead of a second
    //     residency in the enclosure the bird is already in.
    let alreadyOpen = false;
    for (const stay of e.app.findRecordsByFilter(
      "aviary_stays", "animal = {:a} && ended_at = ''", "-started_at", 0, 0,
      { a: animal.id },
    )) {
      if (after && !alreadyOpen && stay.getString("aviary") === after) {
        alreadyOpen = true;
        continue;
      }
      stay.set("ended_at", now);
      e.app.save(stay);
    }

    if (after && !alreadyOpen) {
      const stay = new Record(e.app.findCollectionByNameOrId("aviary_stays"));
      stay.set("animal", animal.id);
      stay.set("aviary", after);
      stay.set("started_at", now);
      stay.set("org", animal.getString("org"));
      e.app.save(stay);
    }
  }

  e.next();
}, "animals");
