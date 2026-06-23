/// <reference path="../pb_data/types.d.ts" />

// blp.3 — extend the case_summaries view (FED-7.6) with `ended_at`: the date a
// case was closed, i.e. the latest disposition's disposed_at (falling back to
// the disposition's created time). Lets the "other cases" lists show a case's
// start–end span. Still no clinical fields; org-wide read rule unchanged.

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

const VIEW_ORIGINAL = `
  SELECT
    cases.id            AS id,
    cases.animal        AS animal,
    cases.org           AS org,
    cases.case_number   AS case_number,
    cases.status        AS status,
    cases.admitted_at   AS admitted_at,
    cases.found_at      AS found_at,
    cases.created       AS created
  FROM cases
`;

migrate(
  (app) => {
    const view = app.findCollectionByNameOrId("case_summaries");
    view.viewQuery = VIEW_WITH_ENDED;
    app.save(view);
  },
  (app) => {
    const view = app.findCollectionByNameOrId("case_summaries");
    view.viewQuery = VIEW_ORIGINAL;
    app.save(view);
  },
);
