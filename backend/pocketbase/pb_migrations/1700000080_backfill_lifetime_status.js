/// <reference path="../pb_data/types.d.ts" />

// federfall-sinp — give every bird that never got a lifetime state one.
//
// `animals.lifetime_status` is derived, and until intake.pb.js started setting
// `in_care` on the brand-new-animal branch nothing wrote it before the FIRST
// disposition. So rows from before that fix read `""`, which the registry and
// the animal header render as no status chip at all — a bird with no answer to
// "where is this one now", indistinguishable from a bird whose state simply
// hasn't been decided.
//
// Two shapes, because "no status" means two different things:
//
//   * housed (`current_aviary` set) -> `in_aviary`. This is the case-less
//     resident (add_animal_sheet.dart puts a bird straight into an enclosure, no
//     case and therefore no disposition), whose residency lives only on the
//     animal record. `in_care` would be wrong AND, since 1700000077, misleading
//     about custody — the keeper holds it through exactly that relation.
//   * everything else with no disposition anywhere -> `in_care`, the same
//     default lib_derive.js reconciles to.
//
// Rows that DO have a disposition are left alone: the create hook has always set
// a lifetime state for every one of the six types, so an empty status there would
// mean something this migration cannot guess.
//
// Raw SQL rather than a record loop: this touches every animal in every org, and
// a `save()` per row would fire the aviary_stays hook — which, for the housed
// branch, would open a SECOND residency for a bird already in its enclosure
// (`current_aviary` is not changing here, but the hook keys on a field diff and
// the ledger has no business seeing a status backfill at all).

migrate(
  (app) => {
    const noDisposition = `
      id NOT IN (
        SELECT c.animal FROM cases c
        JOIN dispositions d ON d."case" = c.id
        WHERE c.animal IS NOT NULL AND c.animal != ''
      )
    `;
    app
      .db()
      .newQuery(`
        UPDATE animals SET lifetime_status = 'in_aviary'
        WHERE (lifetime_status IS NULL OR lifetime_status = '')
          AND current_aviary IS NOT NULL AND current_aviary != ''
          AND ${noDisposition}
      `)
      .execute();
    app
      .db()
      .newQuery(`
        UPDATE animals SET lifetime_status = 'in_care'
        WHERE (lifetime_status IS NULL OR lifetime_status = '')
          AND (current_aviary IS NULL OR current_aviary = '')
          AND ${noDisposition}
      `)
      .execute();
  },
  // Deliberately irreversible. Down would have to blank a status again, and it
  // cannot tell the rows this migration filled from the ones the app has written
  // since — so it would destroy real data to undo a repair.
  (app) => {},
);
