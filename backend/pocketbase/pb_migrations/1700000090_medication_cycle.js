/// <reference path="../pb_data/types.d.ts" />

// federfall-wmbi — a dosing RHYTHM, not just a gap between doses.
//
// `interval_hours` (1700000014) can only say "every N hours, forever until
// ended_at". A pulse regimen — five days on, two days off, repeated — is a
// perfectly ordinary antiparasitic protocol and could not be written down at
// all: the carer either wrote it into `instructions` as prose the worklist
// cannot see, or ended and re-created the plan every cycle.
//
//   cycle_on_days   consecutive days on which the interval applies
//   cycle_off_days  consecutive days of pause that follow
//
// Both set = a repeating cycle anchored at `started_at`; either unset = the
// unchanged "every N hours" behaviour. Deliberately TWO numbers and not a free
// phase list: a repeating cycle is what a rehab actually prescribes, and it is
// the most that `medication_due` can still derive in SQL — a phase list would
// have moved next-due out of this view and into a hook, i.e. out of the one
// place the worklist AND the local reminders read it from.
//
// There is no "number of cycles" column. A repeat count is a calculator for
// `ended_at` and nothing more: the record already says start, rhythm and end,
// which is complete, and a stored count would be a second thing to disagree
// with the end date. The prescription form derives the count back from the two
// dates when it divides evenly.
//
// ── how the view derives next_due ────────────────────────────────────────────
//
// The candidate is unchanged (last dose + interval_hours, else started_at). The
// cycle then only ever pushes that candidate FORWARD, out of a pause:
//
//   elapsed = whole 24-hour spans between the plan's start and the candidate
//   phase   = elapsed % (on + off)
//   phase < on  → the candidate falls on a giving day, keep it
//   otherwise   → start + (elapsed - phase + on + off) days, i.e. the first
//                 instant of the next cycle
//
// Note `elapsed` counts 24-hour spans from the start INSTANT, not calendar
// days: a cycle day therefore runs from the plan's own time of day to the same
// time next day. That is deliberate and dodges federfall-yok0 wholesale — a
// calendar-day boundary here would be a UTC midnight, so a 01:00 local dose
// would land on the previous cycle day and a pause could begin two hours early
// for readers in CEST. A view takes no timezone parameter, so the only correct
// answer is one that never asks: measured against its own anchor, the rhythm is
// the same instant sequence in every zone.
//
// `elapsed` is floored at 0 so a dose backdated before the plan's start reads
// as day 0 (a giving day) instead of a negative phase.
//
// It is counted in whole UNIX SECONDS rather than with julianday(), and that is
// not a style choice: julianday returns a double around 2.46e6, whose spacing is
// ~40 µs, so a difference that is mathematically exactly 5.0 days can land at
// 4.9999999995 and truncate to 4. Every interesting candidate here falls on a
// day boundary — a 12 h interval from an 08:00 start hits one every other dose
// — so that rounding would flip precisely the cases the cycle exists to decide.
// Integer seconds cannot.

const MEDICATION_DUE_QUERY = `
        SELECT
          d.id             AS id,
          d.case_id        AS case_id,
          d.org            AS org,
          d.active_carer   AS active_carer,
          d.drug           AS drug,
          d.dose           AS dose,
          d.dose_unit      AS dose_unit,
          d.dose_rate      AS dose_rate,
          d.concentration_per_ml AS concentration_per_ml,
          d.route          AS route,
          d.frequency_kind AS frequency_kind,
          d.interval_hours AS interval_hours,
          d.cycle_on_days  AS cycle_on_days,
          d.cycle_off_days AS cycle_off_days,
          d.started_at     AS started_at,
          d.ended_at       AS ended_at,
          d.next_due       AS next_due
        FROM (
          SELECT
            q.id             AS id,
            q.case_id        AS case_id,
            q.org            AS org,
            q.active_carer   AS active_carer,
            q.drug           AS drug,
            q.dose           AS dose,
            q.dose_unit      AS dose_unit,
            q.dose_rate      AS dose_rate,
            q.concentration_per_ml AS concentration_per_ml,
            q.route          AS route,
            q.frequency_kind AS frequency_kind,
            q.interval_hours AS interval_hours,
            q.cycle_on_days  AS cycle_on_days,
            q.cycle_off_days AS cycle_off_days,
            q.started_at     AS started_at,
            q.ended_at       AS ended_at,
            CASE
              WHEN q.raw_due IS NULL THEN NULL
              WHEN q.cycle_len IS NULL THEN q.raw_due
              WHEN q.elapsed_days % q.cycle_len < q.cycle_on_days
                THEN q.raw_due
              ELSE datetime(
                     q.anchor,
                     '+' || (
                       (q.elapsed_days - (q.elapsed_days % q.cycle_len)
                        + q.cycle_len) * 24
                     ) || ' hours'
                   ) || 'Z'
            END AS next_due
          FROM (
            SELECT
              p.id             AS id,
              p.case_id        AS case_id,
              p.org            AS org,
              p.active_carer   AS active_carer,
              p.drug           AS drug,
              p.dose           AS dose,
              p.dose_unit      AS dose_unit,
              p.dose_rate      AS dose_rate,
              p.concentration_per_ml AS concentration_per_ml,
              p.route          AS route,
              p.frequency_kind AS frequency_kind,
              p.interval_hours AS interval_hours,
              p.cycle_on_days  AS cycle_on_days,
              p.cycle_off_days AS cycle_off_days,
              p.started_at     AS started_at,
              p.ended_at       AS ended_at,
              p.raw_due        AS raw_due,
              p.anchor         AS anchor,
              p.cycle_len      AS cycle_len,
              MAX(
                (CAST(strftime('%s', p.raw_due) AS INTEGER)
                 - CAST(strftime('%s', p.anchor) AS INTEGER)) / 86400,
                0
              ) AS elapsed_days
            FROM (
              SELECT
                m.id             AS id,
                m.\`case\`         AS case_id,
                m.org            AS org,
                c.active_carer   AS active_carer,
                m.drug           AS drug,
                m.dose           AS dose,
                m.dose_unit      AS dose_unit,
                m.dose_rate      AS dose_rate,
                m.concentration_per_ml AS concentration_per_ml,
                m.route          AS route,
                m.frequency_kind AS frequency_kind,
                m.interval_hours AS interval_hours,
                m.cycle_on_days  AS cycle_on_days,
                m.cycle_off_days AS cycle_off_days,
                m.started_at     AS started_at,
                m.ended_at       AS ended_at,
                COALESCE(NULLIF(m.started_at, ''), m.created) AS anchor,
                CASE
                  WHEN m.frequency_kind = 'scheduled'
                       AND m.cycle_on_days != '' AND m.cycle_off_days != ''
                       AND m.cycle_on_days > 0 AND m.cycle_off_days > 0
                    THEN m.cycle_on_days + m.cycle_off_days
                  ELSE NULL
                END AS cycle_len,
                CASE
                  WHEN m.frequency_kind = 'scheduled' AND m.interval_hours != ''
                       AND last.last_dose != ''
                    THEN datetime(last.last_dose, '+' || m.interval_hours || ' hours') || 'Z'
                  WHEN m.frequency_kind = 'scheduled' AND m.interval_hours != ''
                    THEN m.started_at
                  WHEN m.frequency_kind = 'once' AND (last.last_dose IS NULL OR last.last_dose = '')
                    THEN COALESCE(NULLIF(m.started_at, ''), m.created)
                  ELSE NULL
                END AS raw_due
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
            ) p
          ) q
        ) d
      `;

// The query as it stood before this migration (1700000058), for the down path.
const MEDICATION_DUE_QUERY_V58 = `
        SELECT
          d.id             AS id,
          d.case_id        AS case_id,
          d.org            AS org,
          d.active_carer   AS active_carer,
          d.drug           AS drug,
          d.dose           AS dose,
          d.dose_unit      AS dose_unit,
          d.dose_rate      AS dose_rate,
          d.concentration_per_ml AS concentration_per_ml,
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
            m.dose_rate      AS dose_rate,
            m.concentration_per_ml AS concentration_per_ml,
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
      `;

function saveMedicationDueView(app, query) {
  const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
  const scoped = `${AUTH} && org = @request.auth.org && active_carer = @request.auth.id`;
  app.save(
    new Collection({
      type: "view",
      name: "medication_due",
      listRule: scoped,
      viewRule: scoped,
      viewQuery: query,
    }),
  );
}

function cycleFields() {
  return [
    new Field({
      name: "cycle_on_days",
      type: "number",
      required: false,
      min: 1,
      onlyInt: true,
    }),
    new Field({
      name: "cycle_off_days",
      type: "number",
      required: false,
      min: 1,
      onlyInt: true,
    }),
  ];
}

migrate(
  (app) => {
    // The rhythm on the prescription, and the same pair on the catalogue entry
    // that prefills it — exactly how frequency_kind + interval_hours are paired
    // across the two (1700000060).
    for (const name of ["medications", "medication_products"]) {
      const c = app.findCollectionByNameOrId(name);
      for (const field of cycleFields()) c.fields.add(field);
      app.save(c);
    }

    app.delete(app.findCollectionByNameOrId("medication_due"));
    saveMedicationDueView(app, MEDICATION_DUE_QUERY);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("medication_due"));

    for (const name of ["medications", "medication_products"]) {
      const c = app.findCollectionByNameOrId(name);
      c.fields.removeByName("cycle_on_days");
      c.fields.removeByName("cycle_off_days");
      app.save(c);
    }

    saveMedicationDueView(app, MEDICATION_DUE_QUERY_V58);
  },
);
