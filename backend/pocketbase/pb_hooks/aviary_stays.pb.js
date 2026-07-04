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

    if (before) {
      const open = e.app.findRecordsByFilter(
        "aviary_stays", "animal = {:a} && ended_at = ''", "-started_at", 1, 0,
        { a: animal.id },
      );
      if (open.length > 0) {
        open[0].set("ended_at", now);
        e.app.save(open[0]);
      }
    }

    if (after) {
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
