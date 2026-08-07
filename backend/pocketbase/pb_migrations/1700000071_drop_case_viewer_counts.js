/// <reference path="../pb_data/types.d.ts" />

// federfall-45o4 — drop `case_viewer_counts` (added in 1700000070). Nothing
// reads it, and nothing should.
//
// The dashboard's status figures ship as `casesRepo.count()` per status, i.e.
// counted on `cases` itself. That is not an oversight: the view is VIEWER-
// scoped (one row per active carer / share recipient) while the dashboard is
// org-wide for coordinators and supervisors — `cases`.listRule grants them the
// whole org (1700000010_access_rules.js), and every KPI tile taps through to a
// case list with that same org-wide scope. Neither way of reading the view
// gives them the figure the tile links to:
//
//   viewer = @request.auth.id  → a coordinator's PERSONAL load shown above a
//     list of the whole org's cases; and
//   sum every row in the org   → a case shared with several people counted
//     once per viewer, and a case with no active carer at all counted zero
//     times.
//
// 1700000070's comment that the view "reproduces exactly what the dashboard
// counted" holds for a carer only. Counting on `cases` has no such split: the
// list rule scopes a count exactly as it scopes a list, so one code path is
// correct for every role.
//
// `case_carer_load` STAYS — it is read (the workload card's openByCarer) and
// answers a question `cases` cannot answer in one request: a count per carer.

migrate(
  (app) => {
    app.delete(app.findCollectionByNameOrId("case_viewer_counts"));
  },
  (app) => {
    // Verbatim from 1700000070, so a down-migration lands on the schema that
    // migration left behind. A view holds no data, so this loses nothing.
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const viewerScoped =
      `${AUTH} && org = @request.auth.org` +
      ` && (viewer = @request.auth.id || ${COORD_SUP})`;

    const viewerCounts = new Collection({
      type: "view",
      name: "case_viewer_counts",
      listRule: viewerScoped,
      viewRule: viewerScoped,
      viewQuery: `
        SELECT
          (v.viewer || ':' || v.status) AS id,
          v.org    AS org,
          v.viewer AS viewer,
          v.status AS status,
          COUNT(DISTINCT v.case_id) AS cases
        FROM (
          SELECT c.id AS case_id, c.org AS org, c.status AS status,
                 c.active_carer AS viewer
          FROM cases c
          WHERE c.active_carer != ''
          UNION ALL
          SELECT c.id AS case_id, c.org AS org, c.status AS status,
                 s.shared_with AS viewer
          FROM cases c
          JOIN case_shares s ON s."case" = c.id
          WHERE s.shared_with != ''
        ) v
        GROUP BY v.org, v.viewer, v.status
      `,
    });
    app.save(viewerCounts);
  },
);
