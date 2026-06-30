/// <reference path="../pb_data/types.d.ts" />

// federfall-uvm — case_quarantine: a read-only view giving the CURRENT
// quarantine end per case (the latest quarantine_records row), so the carer
// worklist and the dashboard fetch quarantine state in ONE query instead of
// reading a denormalised `cases.quarantine_until` mirror (dropped in the next
// migration) or scanning every record per case. Same approach as the
// `medication_due` and `case_activity` views.
//
// "Current" = the most recently recorded row (MAX(created)) for the case:
// extending quarantine adds a newer row, lifting it early edits/adds a row with
// an earlier end — either way the newest row wins.
//
// Views emit no realtime events, so the worklist watches the base collection
// (`quarantine_records`) and re-evaluates on its 1-minute ticker for the
// clock-driven "quarantine ending" transition.
//
// Org-scoped read for any active member — consistent with case_summaries
// exposing status/dates org-wide (a quarantine end date is no more sensitive
// than the case status already is); the full quarantine_records rows stay
// case-scoped.

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const orgScoped = `${AUTH} && org = @request.auth.org`;

    const view = new Collection({
      type: "view",
      name: "case_quarantine",
      listRule: orgScoped,
      viewRule: orgScoped,
      // The view id IS the case id, so one row per case. The latest row is
      // picked by joining quarantine_records to its own per-case MAX(created).
      viewQuery: `
        SELECT
          c.id           AS id,
          c.org          AS org,
          latest.quarantine_until AS quarantine_until,
          latest.set_at  AS set_at
        FROM cases c
        JOIN (
          SELECT
            q.\`case\`           AS case_id,
            q.quarantine_until AS quarantine_until,
            q.set_at           AS set_at
          FROM quarantine_records q
          JOIN (
            SELECT \`case\` AS case_id, MAX(created) AS max_created
            FROM quarantine_records
            GROUP BY \`case\`
          ) m ON m.case_id = q.\`case\` AND m.max_created = q.created
        ) latest ON latest.case_id = c.id
      `,
    });
    app.save(view);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("case_quarantine"));
  },
);
