/// <reference path="../pb_data/types.d.ts" />

// federfall-vfl7 — deleting an animal must take its cases with it.
//
// Every other relation into `animals` cascades (`markings` 1700000005, `weights`
// 1700000020, `exams` 1700000025, `aviary_stays` 1700000052, `egg_records`
// 1700000056) — `cases.animal` is the one that never did (1700000004). Since
// `animals.delete` has been supervisor-allowed since 1700000010, deleting a bird
// already left its cases behind, and every case-scoped child hangs off `case`
// rather than `animal`: journal entries, medications, administrations,
// conditions, placements, dispositions, follow-ups, shares, quarantine records,
// exams and exam findings all survived, pointing at an animal id that no longer
// resolved. That is the dangling-row case `animal_org_scope.pb.js` has to skip
// over (federfall-ti77).
//
// Flipping this one flag is enough for the whole subtree: every `case` relation
// is already `cascadeDelete: true`, so the cases go and take their children with
// them.
//
// `weights` / `markings` / `egg_records` stay OUT of a case's cascade on purpose
// — they are animal-level identity/clinical history (5yg.4, federfall-4agw), so
// deleting one treatment episode must not erase the bird's weight curve. They
// die with the animal instead, via their own `animal` cascade. `finders` are not
// cascaded either, which leaves their PII unreferenced — tracked separately as
// federfall-yw74, since the right behaviour there needs a decision.

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    cases.fields.getByName("animal").cascadeDelete = true;
    app.save(cases);
  },
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    cases.fields.getByName("animal").cascadeDelete = false;
    app.save(cases);
  },
);
