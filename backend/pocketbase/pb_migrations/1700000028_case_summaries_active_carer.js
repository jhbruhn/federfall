/// <reference path="../pb_data/types.d.ts" />

// federfall-127 — extend the case_summaries view (FED-7.6) with `active_carer`:
// the user currently responsible for the case. Lets the animal-lifetime and
// "other/prior cases" lists name the carer beside each case, the same way the
// main cases list and case detail header already do.
//
// active_carer is identity-layer info (a relation to a staff `users` record),
// not clinical data — consistent with the view's existing stance of exposing
// non-clinical summary columns org-wide (number, status, dates). Privacy stays
// enforced at the CASE level: the stub remains non-tappable and clinical data
// is still gated by the `cases`/child-collection rules. Org-wide read rule
// unchanged.

const VIEW_WITH_CARER = `
  SELECT
    cases.id            AS id,
    cases.animal        AS animal,
    cases.org           AS org,
    cases.case_number   AS case_number,
    cases.status        AS status,
    cases.admitted_at   AS admitted_at,
    cases.found_at      AS found_at,
    cases.created       AS created,
    cases.active_carer  AS active_carer,
    (
      SELECT COALESCE(d.disposed_at, d.created)
      FROM dispositions d
      WHERE d."case" = cases.id
      ORDER BY COALESCE(d.disposed_at, d.created) DESC
      LIMIT 1
    ) AS ended_at
  FROM cases
`;

const VIEW_WITH_ENDED = `
  SELECT
    cases.id            AS id,
    cases.animal        AS animal,
    cases.org           AS org,
    cases.case_number   AS case_number,
    cases.status        AS status,
    cases.admitted_at   AS admitted_at,
    cases.found_at      AS found_at,
    cases.created       AS created,
    (
      SELECT COALESCE(d.disposed_at, d.created)
      FROM dispositions d
      WHERE d."case" = cases.id
      ORDER BY COALESCE(d.disposed_at, d.created) DESC
      LIMIT 1
    ) AS ended_at
  FROM cases
`;

migrate(
  (app) => {
    const view = app.findCollectionByNameOrId("case_summaries");
    view.viewQuery = VIEW_WITH_CARER;
    app.save(view);
  },
  (app) => {
    const view = app.findCollectionByNameOrId("case_summaries");
    view.viewQuery = VIEW_WITH_ENDED;
    app.save(view);
  },
);
