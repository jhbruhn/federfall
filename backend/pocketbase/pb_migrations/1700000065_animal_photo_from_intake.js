/// <reference path="../pb_data/types.d.ts" />

// federfall-v1yh — backfill `animals.photo` from the newest case intake photo.
//
// The header avatar used to resolve to `animals.photo` OR, when empty, the
// first intake photo of the newest accessible case. Those two fields have
// different access scopes (`animals.photo` is org-wide identity data,
// `cases.intake_photos` is case-scoped), so whether a bird had a visible
// portrait depended on who was looking. `intake.pb.js` now promotes the first
// intake photo to the animal at intake and the client-side fallback is gone —
// without this backfill every bird admitted BEFORE that change would lose the
// portrait the carers on its case could already see.
//
// Copies the first intake photo of each animal's newest photo-carrying case
// (`-created`, the order the client's fallback used) into `animals.photo`,
// for animals whose `photo` is empty. Never touches an animal that already
// has one.
//
// Each file is re-uploaded as an INDEPENDENT copy under a freshly generated
// name (`preserveName: false`), not a reference to the case's blob: deleting
// a case — or the whole animal timeline — must not blank the portrait, and
// PocketBase deletes files by `<collectionId>/<recordId>/` prefix.
//
// A single unreadable blob (a file removed from storage behind PocketBase's
// back) is skipped with a warning rather than aborting: a failed migration
// stops the server from starting at all, which is a far worse outcome than a
// bird keeping its placeholder.

migrate(
  (app) => {
    const fsys = app.newFilesystem();
    let promoted = 0;
    let failed = 0;
    try {
      for (const animal of app.findAllRecords("animals")) {
        if (animal.getString("photo")) continue;

        let cases = [];
        try {
          cases = app.findRecordsByFilter(
            "cases",
            "animal = {:a}",
            "-created",
            500,
            0,
            { a: animal.id },
          );
        } catch (_) {
          continue; // no cases for this animal
        }

        for (const c of cases) {
          const photos = c.get("intake_photos") || [];
          if (!photos.length) continue;
          try {
            const file = fsys.getReuploadableFile(
              c.baseFilesPath() + "/" + String(photos[0]),
              false,
            );
            animal.set("photo", file);
            app.save(animal);
            promoted++;
          } catch (err) {
            failed++;
            app
              .logger()
              .warn(
                "animal photo backfill skipped",
                "animal",
                animal.id,
                "case",
                c.id,
                "error",
                String(err),
              );
          }
          break; // newest photo-carrying case only, promoted or not
        }
      }
    } finally {
      fsys.close();
    }
    app
      .logger()
      .info("animal photo backfill", "promoted", promoted, "skipped", failed);
  },
  (app) => {
    // Not reversible: a promoted portrait is indistinguishable from one a user
    // picked, so removing them would destroy real data. `animals.photo`
    // predates this migration (1700000017) and an extra portrait breaks
    // nothing on the way down — the old client simply prefers it, which is
    // what it did for any animal that had a photo anyway.
    app.logger().info("animal photo backfill: nothing to revert");
  },
);
