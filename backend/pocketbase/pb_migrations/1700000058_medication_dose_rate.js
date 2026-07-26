/// <reference path="../pb_data/types.d.ts" />

// federfall-6d3a.2 — a prescription carries the RATE, not just a frozen amount.
//
// `medications.dose` is an absolute amount ("5.24 mg"). For a bird in rehab that
// is wrong within a week: a thin pigeon admitted at 240 g is 330 g by day ten
// and the plan silently under-doses. Storing the prescribed rate lets every dose
// re-derive from the current weight, the way `medication_due` already re-derives
// *when* the next dose falls.
//
//   dose_rate           the rate per KILOGRAM of body weight
//   concentration_per_ml the product's strength, per MILLILITRE
//
// Both are expressed in the plan's existing `dose_unit`, deliberately: a rate of
// 20 with dose_unit "mg" is 20 mg/kg, and a concentration of 15 is 15 mg/ml. One
// unit for the whole prescription removes the entire class of mg-vs-µg mismatch
// that separate `dose_rate_unit` / `concentration_unit` fields would invite — and
// it covers fluids (dose_unit "ml" → ml/kg) and biologicals (dose_unit "IU")
// without any extra vocabulary.
//
// This replaces the dormant free-text `concentration` from 1700000007, which no
// client ever wrote. Anything actually in it (set by hand in the dashboard) is
// parsed into the number where possible and otherwise appended to
// `instructions`, so no text is dropped on the floor.
//
// `medication_administrations` gains the derivation inputs of a calculated dose:
// weight_g_used and volume_ml, denormalized like drug/dose/route already are so
// "why was 0.35 ml given on the 3rd?" stays answerable even after the plan is
// deleted — which for a controlled drug is the whole point of the record.
//
// The `medication_due` VIEW must be dropped and recreated to expose the two new
// columns (the worklist rebuilds a Medication from this view to log a dose from
// there, so without them a rate-based plan would arrive rateless). Query is
// 1700000041's, plus dose_rate and concentration_per_ml passed through.

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

// The query as it stood before this migration (1700000041), for the down path.
const MEDICATION_DUE_QUERY_V41 = `
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

migrate(
  (app) => {
    // ── 1. the rate and the strength, both in the plan's dose_unit ───────────
    const medications = app.findCollectionByNameOrId("medications");
    medications.fields.add(
      new Field({ name: "dose_rate", type: "number", required: false, min: 0 }),
    );
    medications.fields.add(
      new Field({
        name: "concentration_per_ml",
        type: "number",
        required: false,
        min: 0,
      }),
    );
    app.save(medications);

    // ── 2. carry over anything in the legacy free-text concentration ─────────
    // Shapes like "1.5 mg/ml", "15mg/ml", "0,5 mg / ml". A leading number is
    // all we can trust; the rest is prose that belongs with the instructions.
    const legacy = app.findRecordsByFilter(
      "medications",
      "concentration != ''",
      "",
      0,
      0,
    );
    for (const rec of legacy) {
      const text = String(rec.get("concentration")).trim();
      const match = text.match(/^([0-9]+(?:[.,][0-9]+)?)/);
      const value = match ? parseFloat(match[1].replace(",", ".")) : NaN;
      // A parsed number is only meaningful if the text really is "per ml".
      if (!isNaN(value) && /\/\s*ml/i.test(text)) {
        rec.set("concentration_per_ml", value);
      } else {
        const note = String(rec.get("instructions") || "").trim();
        rec.set(
          "instructions",
          note ? `${note}\nKonzentration: ${text}` : `Konzentration: ${text}`,
        );
      }
      app.save(rec);
    }

    const withLegacy = app.findCollectionByNameOrId("medications");
    withLegacy.fields.removeByName("concentration");
    app.save(withLegacy);

    // ── 3. what a calculated dose was derived from ───────────────────────────
    const administrations = app.findCollectionByNameOrId(
      "medication_administrations",
    );
    administrations.fields.add(
      new Field({
        name: "weight_g_used",
        type: "number",
        required: false,
        min: 0,
      }),
    );
    administrations.fields.add(
      new Field({ name: "volume_ml", type: "number", required: false, min: 0 }),
    );
    app.save(administrations);

    // ── 4. republish the view over the new columns ───────────────────────────
    app.delete(app.findCollectionByNameOrId("medication_due"));
    saveMedicationDueView(app, MEDICATION_DUE_QUERY);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("medication_due"));

    const administrations = app.findCollectionByNameOrId(
      "medication_administrations",
    );
    administrations.fields.removeByName("weight_g_used");
    administrations.fields.removeByName("volume_ml");
    app.save(administrations);

    const medications = app.findCollectionByNameOrId("medications");
    medications.fields.add(
      new Field({
        name: "concentration",
        type: "text",
        required: false,
        max: 100,
      }),
    );
    app.save(medications);

    // Put the numeric strength back as the text it came from, so a re-run of
    // the up migration finds it again.
    const withRate = app.findRecordsByFilter(
      "medications",
      "concentration_per_ml > 0",
      "",
      0,
      0,
    );
    for (const rec of withRate) {
      const unit = String(rec.get("dose_unit") || "mg");
      rec.set("concentration", `${rec.get("concentration_per_ml")} ${unit}/ml`);
      app.save(rec);
    }

    const stripped = app.findCollectionByNameOrId("medications");
    stripped.fields.removeByName("dose_rate");
    stripped.fields.removeByName("concentration_per_ml");
    app.save(stripped);

    saveMedicationDueView(app, MEDICATION_DUE_QUERY_V41);
  },
);
