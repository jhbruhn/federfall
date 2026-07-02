/// <reference path="../pb_data/types.d.ts" />

// federfall-28m — scope the case_number unique index to the org.
//
// Case numbers are generated PER ORG (the cases hook computes the year max
// within `org`), but the original index from 1700000004 was globally unique.
// The first "2026-…" case of a second org would therefore collide with org
// one's and fail with an unretriable 400 — numbering only ever worked for a
// single-org deployment. Uniqueness on (org, case_number) matches what the
// generator actually guarantees.
//
// Safe on existing data: global uniqueness implies per-org uniqueness. The
// down pass restores the global index and can fail if two orgs minted the
// same number in the meantime — resolve manually before rolling back.

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const keep = [];
    for (const ix of cases.indexes) {
      if (!String(ix).includes("idx_cases_case_number")) keep.push(String(ix));
    }
    keep.push(
      "CREATE UNIQUE INDEX `idx_cases_case_number` ON `cases` (`org`, `case_number`)",
    );
    cases.indexes = keep;
    app.save(cases);
  },
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const keep = [];
    for (const ix of cases.indexes) {
      if (!String(ix).includes("idx_cases_case_number")) keep.push(String(ix));
    }
    keep.push(
      "CREATE UNIQUE INDEX `idx_cases_case_number` ON `cases` (`case_number`)",
    );
    cases.indexes = keep;
    app.save(cases);
  },
);
