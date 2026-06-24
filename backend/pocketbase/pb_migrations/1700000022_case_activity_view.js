/// <reference path="../pb_data/types.d.ts" />

// cr3.5 — case_activity: a read-only view exposing the last time anything
// happened on a case, so the carer worklist (UX Phase D) can surface "stale"
// active cases in ONE query instead of N+1 per-case scans.
//
// last_activity = MAX over the case's own `updated` and the `updated` of every
// child record (weights, journal, prescriptions, doses, placements, case
// conditions, dispositions, and markings applied during the case). `updated`
// (not `created`) is used so an edit counts as activity too.
//
// The view carries no clinical detail — just a timestamp keyed by case id — so
// it is org-scoped readable for any active member, mirroring case_summaries
// (FED-7.6). Privacy stays enforced at the case/child level; this leaks nothing
// a member couldn't already infer. Read-only by nature (view collection).

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const orgScoped = `${AUTH} && org = @request.auth.org`;

    const view = new Collection({
      type: "view",
      name: "case_activity",
      listRule: orgScoped,
      viewRule: orgScoped,
      viewQuery: `
        SELECT
          c.id  AS id,
          c.org AS org,
          MAX(c.updated, COALESCE(ch.last_child, c.updated)) AS last_activity
        FROM cases c
        LEFT JOIN (
          SELECT cid, MAX(updated) AS last_child FROM (
            SELECT \`case\`        AS cid, updated FROM weights WHERE \`case\` != ''
            UNION ALL SELECT \`case\`, updated FROM journal_entries
            UNION ALL SELECT \`case\`, updated FROM medications
            UNION ALL SELECT \`case\`, updated FROM medication_administrations
            UNION ALL SELECT \`case\`, updated FROM placements
            UNION ALL SELECT \`case\`, updated FROM case_conditions
            UNION ALL SELECT \`case\`, updated FROM dispositions
            UNION ALL SELECT applied_in_case, updated FROM markings
              WHERE applied_in_case != ''
          )
          GROUP BY cid
        ) ch ON ch.cid = c.id
      `,
    });
    app.save(view);
  },
  (app) => {
    const view = app.findCollectionByNameOrId("case_activity");
    app.delete(view);
  },
);
