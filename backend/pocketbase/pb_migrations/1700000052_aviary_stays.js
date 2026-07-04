/// <reference path="../pb_data/types.d.ts" />

// federfall-d5co.1 — aviary_stays: an append-only residency ledger. Today
// `current_aviary` on `animals` is a live pointer with no history, mutated in
// five places (dispositions create/update/delete reconcile in main.pb.js,
// merge_animals.pb.js, and the case-less add-animal-to-aviary create path in
// add_animal_sheet.dart) — so "what happened in this enclosure over time" is
// unrecoverable once a bird moves on. This ledger is maintained by ONE
// centralized hook on the `animals` collection (pb_hooks/aviary_stays.pb.js),
// so all five writers are covered without patching each individually: every
// current_aviary change funnels through a saved `animals` record.
//
// "Current residency" = the latest row per animal with `ended_at` unset,
// mirroring how `active_carer` is derived from the latest Placement.
//
// Access: read for any active org member (mirrors `aviaries`); writes are
// server-only (create/update/delete = null) — the hook uses `app.save()`,
// which bypasses API rules entirely, so this still lets the hook write while
// blocking direct client mutation of the ledger.

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true && @request.auth.role != "guest"';

    const organisations = app.findCollectionByNameOrId("organisations");
    const animals = app.findCollectionByNameOrId("animals");
    const aviaries = app.findCollectionByNameOrId("aviaries");

    const stays = new Collection({
      type: "base",
      name: "aviary_stays",
      listRule: `${AUTH} && org = @request.auth.org`,
      viewRule: `${AUTH} && org = @request.auth.org`,
      createRule: null,
      updateRule: null,
      deleteRule: null,
      fields: [
        {
          name: "animal",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: animals.id,
          cascadeDelete: true,
        },
        {
          name: "aviary",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: aviaries.id,
          cascadeDelete: false,
        },
        { name: "started_at", type: "date", required: false },
        // Unset = the current (open) residency.
        { name: "ended_at", type: "date", required: false },
        {
          name: "org",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: organisations.id,
          cascadeDelete: false,
        },
        { name: "created", type: "autodate", onCreate: true, onUpdate: false },
        { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
      ],
    });
    app.save(stays);

    // ── backfill: one open stay per currently-housed resident ───────────────
    // Pre-ledger history is unrecoverable — this only seeds the *present*
    // state, backdated to "now" since no earlier timestamp is known.
    const now = new Date().toISOString();
    for (const animal of app.findRecordsByFilter(
      "animals", "current_aviary != ''", "", 0, 0,
    )) {
      const rec = new Record(stays);
      rec.set("animal", animal.id);
      rec.set("aviary", animal.getString("current_aviary"));
      rec.set("started_at", now);
      rec.set("org", animal.getString("org"));
      app.save(rec);
    }
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("aviary_stays"));
  },
);
