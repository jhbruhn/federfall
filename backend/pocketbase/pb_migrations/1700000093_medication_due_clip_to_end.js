/// <reference path="../pb_data/types.d.ts" />

// federfall-082v — a dose is never due after the plan has ended.
//
// The view keeps a plan while `ended_at > now`, but next_due was computed
// entirely independently of `ended_at`, so the two could disagree and the row
// would sit in the worklist carrying a due instant beyond its own end. Two ways
// in, and the fix has to cover both:
//
//   - a CYCLE plan (1700000090) whose `ended_at` falls inside a pause: the
//     candidate lands in the pause and is pushed forward to the first instant of
//     the next cycle, which is past the end. The prescription form's repeats
//     calculator always lands the end on the last giving day, so reaching this
//     takes a hand-picked date — but nothing stops one.
//   - a plain interval plan: `last dose + interval_hours` simply overshoots a
//     near-future `ended_at`.
//
// Clipped HERE rather than on the device, because there are two independent
// readers and the view is the one place both take next-due from — the stated
// reason the cycle stayed derivable in SQL at all. `worklist.dart` filters only
// on its window and `reminder_plan.dart` checks nothing but `isAfter(now)`, so
// the item showed and a local notification could fire for a dose the plan no
// longer prescribes. Both already skip a null next-due, so no client change is
// needed and an older client is fixed by the server alone.
//
// The clip only ever turns a due instant into NULL — the row itself stays, which
// is the honest reading: the plan has not ended yet, there is simply nothing
// further due under it.
//
// `>` and not `>=`: a dose due at the exact instant the plan ends is still
// prescribed by it. That is also how the row's own survival is decided in the
// WHERE below (`ended_at > now`).
//
// ── why this adds a nesting level rather than one clause ─────────────────────
//
// PocketBase parses the OUTERMOST SELECT of a view query to infer its fields,
// and that parser only accepts plain `alias.column AS name` there — a CASE in
// the outer projection is rejected outright ("invalid identifier parts", and
// then `fields: cannot be blank` and both rules failing on an unknown `org`).
// That is the real reason 1700000090 looks the way it does: every computation
// lives one level down under a pass-through outer SELECT. So the clip gets its
// own level (`d`) between the derivation and the pass-through (`e`), instead of
// being repeated inside each arm of the inner CASE.
//
// Timezones need no thought: both sides are PocketBase UTC strings and
// `datetime()` normalises the trailing `Z`, exactly as the WHERE clause has
// always done. And every column of this view is inferred as `json` (nothing
// computed traces back to a real collection field — see the federfall-dk0c note
// in CLAUDE.md), so one more expression changes no type.

// Levels `q` and below: 1700000090's derivation, verbatim and untouched.
const CORE = `
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
          ) q`;

// The new level: the same columns through, with next_due clipped to the plan's
// own end. Wrapped by the pass-through outer SELECT below, which is the only
// shape PocketBase's field parser accepts.
const QUERY_CLIPPED = `
        SELECT
          e.id             AS id,
          e.case_id        AS case_id,
          e.org            AS org,
          e.active_carer   AS active_carer,
          e.drug           AS drug,
          e.dose           AS dose,
          e.dose_unit      AS dose_unit,
          e.dose_rate      AS dose_rate,
          e.concentration_per_ml AS concentration_per_ml,
          e.route          AS route,
          e.frequency_kind AS frequency_kind,
          e.interval_hours AS interval_hours,
          e.cycle_on_days  AS cycle_on_days,
          e.cycle_off_days AS cycle_off_days,
          e.started_at     AS started_at,
          e.ended_at       AS ended_at,
          e.next_due       AS next_due
        FROM (
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
            CASE
              WHEN d.next_due IS NOT NULL
                   AND d.ended_at IS NOT NULL AND d.ended_at != ''
                   AND datetime(d.next_due) > datetime(d.ended_at)
                THEN NULL
              ELSE d.next_due
            END AS next_due
          FROM (
${CORE}
          ) d
        ) e
      `;

// 1700000090's query, for the down path: the same CORE under a pass-through
// outer SELECT, with no clip level in between.
const QUERY_V90 = `
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
${CORE}
        ) d
      `;

function saveMedicationDueView(app, query) {
  // The guest-safe predicate, NOT the bare one 1700000090 copied. Re-creating
  // this view is precisely how it lost the guest wall three times over
  // (federfall-3dy9 / 1700000092): a delete+save resets the rules to whatever
  // is written here, so the clause has to be written here. test_rules.py's
  // schema sweep fails if a future migration forgets it again.
  const AUTH =
    '@request.auth.id != "" && @request.auth.is_active = true' +
    ' && @request.auth.role != "guest"';
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

migrate(
  (app) => {
    app.delete(app.findCollectionByNameOrId("medication_due"));
    saveMedicationDueView(app, QUERY_CLIPPED);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("medication_due"));
    saveMedicationDueView(app, QUERY_V90);
  },
);
