/// <reference path="../pb_data/types.d.ts" />

// federfall-8f1m — bring existing birds in line with the derivation that now
// weighs open cases against dispositions.
//
// `lifetime_status` is derived but STORED, and lib_derive.js only re-derives
// when something happens: a disposition write, a merge, or (new, main.pb.js
// section 2c) a case event. A bird admitted BEFORE this deploy therefore keeps
// whatever its last disposition said — `at_large_released` for a returning bird,
// `in_aviary` for a resident under treatment — until its next disposition, which
// for a currently open case may be weeks away and is exactly the window the bug
// is about. So the rows are corrected once, here.
//
// The condition is deriveState()'s, in SQL: an OPEN case (the same explicit
// status set 1700000077 names — never `!= 'disposed'`) whose admission is at or
// after every disposition instant across all of that animal's cases. Both sides
// use `COALESCE(NULLIF(x, ''), y)` — the ordering expression `case_summaries`
// and `case_report_rows` have always used — so this migration and the hook read
// the same history the same way.
//
// `current_aviary` is deliberately untouched: a resident under treatment is
// still its enclosure's bird, and since 1700000077 that field is a custody
// pointer (federfall-sinp emptied one and took a keeper's write access with it).
// `in_care` WITH an enclosure is the legitimate pair this line creates.
//
// Raw SQL rather than a record loop, for 1700000080's reason: a `save()` per row
// fires the aviary_stays hook, which has no business seeing a status backfill.
//
// A row still reading `''` is left alone, on the same grounds 1700000080 left it:
// an empty status on a bird that HAS a disposition means something neither
// migration can guess, and 1700000080 already gave every disposition-less bird
// an answer.
//
// NOT covered by tests/run.sh: it applies migrations to an EMPTY data dir, so
// there is never a legacy row here to correct. What IS covered there is the
// derivation this aligns those rows with ([disposition ordering]) — the SQL is
// checked by reading, the behaviour by the suite.

migrate(
  (app) => {
    app
      .db()
      .newQuery(`
        UPDATE animals SET lifetime_status = 'in_care'
        WHERE COALESCE(lifetime_status, '') NOT IN ('', 'in_care')
          AND id IN (
            SELECT c.animal FROM cases c
            WHERE c.animal IS NOT NULL AND c.animal != ''
              AND (c.status IS NULL
                   OR c.status IN ('', 'in_care', 'ready_for_release'))
              AND COALESCE(NULLIF(c.admitted_at, ''), c.created) >= COALESCE((
                    SELECT MAX(COALESCE(NULLIF(d.disposed_at, ''), d.created))
                    FROM dispositions d
                    JOIN cases c2 ON d."case" = c2.id
                    WHERE c2.animal = c.animal
                  ), '')
          )
      `)
      .execute();
  },
  // Deliberately irreversible, like 1700000080: down would have to restore a
  // status this cannot reconstruct — the disposition it used to read is still
  // there, but so is every legitimate `in_care` written since.
  (app) => {},
);
