/// <reference path="../pb_data/types.d.ts" />

// federfall-q7ks.1 — every aviary has a keeper.
//
// `aviaries.keeper` has been an optional, display-only label since 1700000008
// ("Owner / responsible person"): shown in the registry and the detail header,
// carrying no authority. The custody model (federfall-q7ks) resolves an
// aviary resident's write authority through `current_aviary.keeper`, so a
// keeperless aviary would be a bird nobody but a coordinator/supervisor could
// write about. Making the field required is what turns that label into the
// actor the model needs.
//
// ── Backfill: the org's supervisor ──────────────────────────────────────────
// A migration cannot ask who keeps an enclosure, so it picks the org's oldest
// active supervisor — deliberately a WRONG-BUT-VISIBLE answer rather than a
// silent one: the keeper shows on the aviary card and in its header, so a real
// instance surfaces it immediately and a coordinator can correct it in the form.
// Ordered by `created` so the choice is deterministic rather than
// whatever-the-index-returns.
//
// Ties are broken by id: two supervisors seeded in the same millisecond share a
// `created` value, and "whichever the index happened to return" is not an answer
// a migration should give twice differently.
//
// An org with no active supervisor leaves its aviaries keeperless: there is
// nobody to name, and failing the migration would take the whole deployment
// down over it. Such a row is then unsaveable until someone picks a keeper —
// which is the correct outcome (the form now demands one) and cannot happen on
// an instance that went through bootstrap_supervisor.pb.js.
//
// Order matters: backfill first, THEN require — the same shape 1700000020 used
// when `weights.animal` became required, because flipping the flag first would
// reject the backfill's own saves.
//
// Note PocketBase validates `required` on SAVE, not retroactively, so this does
// not rewrite history; it constrains every write from here on.

migrate(
  (app) => {
    const supervisorFor = (orgId) => {
      const found = app.findRecordsByFilter(
        "users",
        'org = {:o} && role = "supervisor" && is_active = true',
        "+created,+id",
        1,
        0,
        { o: orgId },
      );
      return found.length > 0 ? found[0].id : "";
    };

    const byOrg = {};
    for (const aviary of app.findRecordsByFilter(
      "aviaries", "keeper = ''", "", 0, 0,
    )) {
      const orgId = aviary.getString("org");
      if (!(orgId in byOrg)) byOrg[orgId] = supervisorFor(orgId);
      const keeper = byOrg[orgId];
      if (!keeper) {
        console.log(
          "[1700000076] no active supervisor in org " + orgId +
          " — aviary " + aviary.id + " stays keeperless and must be assigned " +
          "one before it can be saved again",
        );
        continue;
      }
      aviary.set("keeper", keeper);
      app.save(aviary);
    }

    const aviaries = app.findCollectionByNameOrId("aviaries");
    aviaries.fields.getByName("keeper").required = true;
    app.save(aviaries);
  },
  (app) => {
    const aviaries = app.findCollectionByNameOrId("aviaries");
    aviaries.fields.getByName("keeper").required = false;
    app.save(aviaries);
    // The backfilled keepers are deliberately NOT cleared: down-migrating the
    // constraint must not throw away an assignment someone has since corrected,
    // and an optional field holding a real keeper is valid either way.
  },
);
