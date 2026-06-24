/// <reference path="../pb_data/types.d.ts" />

// cr3.6 — medication_due: a read-only view computing the next due time per
// active prescription, so the carer worklist fetches due medications in ONE
// query instead of pulling every prescription + every dose per case (N+1) and
// computing next-due on the client.
//
// next_due:
//   scheduled  → last_dose + interval_hours  (or started_at if never given)
//   once       → started_at (or created) while no dose has been given, else —
//   as_needed / scheduled-without-interval → none (row carries no next_due)
// Ended prescriptions (ended_at in the past) are dropped. Dates are stored as
// UTC ("…Z"); datetime() drops the marker, so the computed branch re-appends
// 'Z' to keep the value UTC for the client.
//
// Org + active_carer scoped: it is the signed-in carer's personal worklist
// source. Drug names here are no broader than the medications collection the
// same carer can already read.

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const scoped = `${AUTH} && org = @request.auth.org && active_carer = @request.auth.id`;

    // The computed next_due lives in an inner subquery so the OUTER select is
    // all plain identifiers — PocketBase's view-column parser rejects a CASE
    // expression as a selected column, but is happy with a subquery column.
    const view = new Collection({
      type: "view",
      name: "medication_due",
      listRule: scoped,
      viewRule: scoped,
      viewQuery: `
        SELECT
          d.id             AS id,
          d.case_id        AS case_id,
          d.org            AS org,
          d.active_carer   AS active_carer,
          d.drug           AS drug,
          d.dose           AS dose,
          d.dose_unit      AS dose_unit,
          d.route          AS route,
          d.frequency_kind AS frequency_kind,
          d.interval_hours AS interval_hours,
          d.started_at     AS started_at,
          d.ended_at       AS ended_at,
          d.next_due       AS next_due
        FROM (
          SELECT
            m.id             AS id,
            m.\`case\`         AS case_id,
            m.org            AS org,
            c.active_carer   AS active_carer,
            m.drug           AS drug,
            m.dose           AS dose,
            m.dose_unit      AS dose_unit,
            m.route          AS route,
            m.frequency_kind AS frequency_kind,
            m.interval_hours AS interval_hours,
            m.started_at     AS started_at,
            m.ended_at       AS ended_at,
            CASE
              WHEN m.frequency_kind = 'scheduled' AND m.interval_hours != ''
                   AND last.last_dose != ''
                THEN datetime(last.last_dose, '+' || m.interval_hours || ' hours') || 'Z'
              WHEN m.frequency_kind = 'scheduled' AND m.interval_hours != ''
                THEN m.started_at
              WHEN m.frequency_kind = 'once' AND (last.last_dose IS NULL OR last.last_dose = '')
                THEN COALESCE(NULLIF(m.started_at, ''), m.created)
              ELSE NULL
            END AS next_due
          FROM medications m
          JOIN cases c ON c.id = m.\`case\`
          LEFT JOIN (
            SELECT medication, MAX(administered_at) AS last_dose
            FROM medication_administrations
            WHERE medication != ''
            GROUP BY medication
          ) last ON last.medication = m.id
          WHERE m.ended_at IS NULL OR m.ended_at = ''
                OR datetime(m.ended_at) > datetime('now')
        ) d
      `,
    });
    app.save(view);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("medication_due"));
  },
);
