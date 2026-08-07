/// <reference path="../pb_data/types.d.ts" />

// federfall-s0wk — the dashboard's figures as counts, so it stops pulling the
// whole `cases` and `animals` collections to a handset on every open (the load
// pattern federfall-80tc removed from the CSV export and federfall-nmwi from
// the statistics screen).
//
// Two views, because they answer two different questions that cannot be
// derived from one another by summing:
//
//   case_viewer_counts — "how many cases may I SEE, by status", one row per
//     (viewer, status). A viewer is the active carer OR anyone the case is
//     shared with, so this reproduces exactly what the dashboard counted when
//     it aggregated `casesRepo.list()` client-side. COUNT(DISTINCT) matters:
//     a case that is both mine and shared with me must count once.
//
//   case_carer_load — "how many OPEN cases is each member the active carer
//     of", one row per carer. Open means "not disposed", the same intent as
//     the guard on deleting a member in main.pb.js — though that guard is
//     written as a PocketBase filter and this is SQL. The two do agree:
//     federfall-jt5u doubted the filter's != and a live probe cleared it. What
//     the two spellings really differ on is NULL, hence the guard below.
//
// ── Why the rules do the scoping ────────────────────────────────────────────
// A view's list rule runs per caller, so "which counts may I read" is enforced
// by the same mechanism as every collection — nothing here re-implements
// own/shared/org-wide in JS. That is deliberate: a hook route mirroring the
// access rules is exactly where federfall-75sy's bug came from.
//
// A carer reads only their own viewer row. Coordinators and supervisors read
// every row in their org, because they already read org-wide — that is also
// what makes the workload card work for them and not for a carer, matching the
// `canViewReports` gate the card already carries.
//
// ── What is deliberately NOT here ───────────────────────────────────────────
// "Intakes this year" is absent on purpose. A view computes its columns in
// SQL, i.e. in UTC, and the year boundary belongs to the CALLER — a bird
// admitted at 00:30 on New Year's Day in UTC+1 is a this-year intake for the
// carer and a last-year one for the database. That is the exact defect
// federfall-s0wk's first half fixed on the client, and grouping by month only
// makes it rarer, not correct. The figure therefore stays where the caller's
// offset is known (see `?tzOffsetMinutes=` on the reporting routes).
//
// Read-only by nature (view collections). Predicates use the guest-safe form
// (1700000045; test_rules.py's guest sweep catches an omission).

migrate(
  (app) => {
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

    // Own row always; every row in the org for the roles that read org-wide.
    const viewerScoped =
      `${AUTH} && org = @request.auth.org` +
      ` && (viewer = @request.auth.id || ${COORD_SUP})`;
    const orgWideOnly = `${AUTH} && ${COORD_SUP} && org = @request.auth.org`;

    // One row per (viewer, status). The id concatenates them because a view
    // needs a stable unique key and neither column is unique alone.
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

    // Open = not disposed, the same definition main.pb.js's delete guard uses.
    const carerLoad = new Collection({
      type: "view",
      name: "case_carer_load",
      listRule: orgWideOnly,
      viewRule: orgWideOnly,
      viewQuery: `
        SELECT
          -- Composite, like the other view: a member who carries cases in two
          -- orgs has a row per org, and a view's id must be unique across the
          -- whole result or PocketBase collapses the collision.
          (c.org || ':' || c.active_carer) AS id,
          c.active_carer AS carer,
          c.org          AS org,
          COUNT(c.id)    AS open_cases
        FROM cases c
        -- Open = not disposed. The NULL guard keeps a case with no status at
        -- all counted as open, since it plainly has not been disposed; a bare
        -- != would evaluate to NULL for that row and drop it.
        -- (No backticks in this comment: it sits inside a JS template literal
        -- and one would end the string.)
        WHERE c.active_carer != ''
          AND (c.status IS NULL OR c.status != 'disposed')
        GROUP BY c.org, c.active_carer
      `,
    });
    app.save(carerLoad);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("case_carer_load"));
    app.delete(app.findCollectionByNameOrId("case_viewer_counts"));
  },
);
