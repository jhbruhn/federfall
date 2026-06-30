/// <reference path="../pb_data/types.d.ts" />

// federfall-7k9 — promote medication routes from a fixed inline select on both
// `medications` and `medication_administrations` to a supervisor-managed,
// org-scoped code list (mirroring conditions / admission_reasons / marking
// types). Each record references one route via the `route` relation.
//
// `route` is optional (nullable) on both collections, so there is no required
// constraint to restore. The `medication_due` VIEW selects `medications.route`,
// so it is dropped before the field swap and recreated afterwards (its query is
// unchanged from 1700000024 — it just passes the stored value through, now an
// id instead of a wire).
//
// NB: MedicationFrequencyKind stays a fixed enum — it drives reminder
// scheduling logic; only `route` is free vocabulary.

// [wire, German label] — the select values paired with the labels the UI used
// to resolve via ARB (route*). Order = display order.
const SEED_ROUTES = [
  ["oral", "Oral"],
  ["subcutaneous", "Subkutan"],
  ["intramuscular", "Intramuskulär"],
  ["intravenous", "Intravenös"],
  ["topical", "Topisch"],
  ["nebulized", "Inhalativ"],
  ["other", "Sonstige"],
];

// Collections carrying a medication `route` select field.
const ROUTE_COLLECTIONS = ["medications", "medication_administrations"];

// The medication_due view query (verbatim from 1700000024) — recreated after
// the field swap so it keeps reading the (now relation) `route` column.
const MEDICATION_DUE_QUERY = `
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

function saveMedicationDueView(app) {
  const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
  const scoped = `${AUTH} && org = @request.auth.org && active_carer = @request.auth.id`;
  const view = new Collection({
    type: "view",
    name: "medication_due",
    listRule: scoped,
    viewRule: scoped,
    viewQuery: MEDICATION_DUE_QUERY,
  });
  app.save(view);
}

migrate(
  (app) => {
    const organisations = app.findCollectionByNameOrId("organisations");

    // ── 1. medication_routes code list ──────────────────────────────────────
    const routes = new Collection({
      type: "base",
      name: "medication_routes",
      listRule:
        '@request.auth.id != "" && @request.auth.is_active = true && org = @request.auth.org',
      viewRule:
        '@request.auth.id != "" && @request.auth.is_active = true && org = @request.auth.org',
      createRule:
        '@request.auth.id != "" && @request.auth.is_active = true && @request.auth.role = "supervisor" && org = @request.auth.org',
      updateRule:
        '@request.auth.id != "" && @request.auth.is_active = true && @request.auth.role = "supervisor" && org = @request.auth.org',
      deleteRule:
        '@request.auth.id != "" && @request.auth.is_active = true && @request.auth.role = "supervisor" && org = @request.auth.org',
      fields: [
        { name: "label", type: "text", required: true, presentable: true, max: 200 },
        { name: "active", type: "bool", required: false },
        {
          name: "org",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: organisations.id,
          cascadeDelete: false,
        },
        { name: "created", type: "autodate", onCreate: true, onUpdate: false },
        { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
      ],
    });
    app.save(routes);

    // ── 2. seed the 7 routes per org, keyed wire -> record id per org ────────
    const wireToId = {};
    for (const org of app.findAllRecords("organisations")) {
      const perOrg = {};
      for (const [wire, label] of SEED_ROUTES) {
        const rec = new Record(routes);
        rec.set("label", label);
        rec.set("active", true);
        rec.set("org", org.id);
        app.save(rec);
        perOrg[wire] = rec.id;
      }
      wireToId[org.id] = perOrg;
    }

    // ── 3. drop the view that reads medications.route ───────────────────────
    app.delete(app.findCollectionByNameOrId("medication_due"));

    // ── 4. swap select -> relation on each collection + backfill ────────────
    for (const name of ROUTE_COLLECTIONS) {
      const mapped = {};
      for (const r of app.findAllRecords(name)) {
        const perOrg = wireToId[r.getString("org")];
        const wire = r.getString("route");
        if (perOrg && wire !== "" && perOrg[wire]) mapped[r.id] = perOrg[wire];
      }

      const coll = app.findCollectionByNameOrId(name);
      coll.fields.removeByName("route");
      app.save(coll);
      coll.fields.add(
        new Field({
          name: "route",
          type: "relation",
          required: false,
          maxSelect: 1,
          collectionId: routes.id,
          cascadeDelete: false,
        }),
      );
      app.save(coll);

      for (const r of app.findAllRecords(name)) {
        const id = mapped[r.id];
        if (!id) continue;
        r.set("route", id);
        app.save(r);
      }
    }

    // ── 5. recreate the view ────────────────────────────────────────────────
    saveMedicationDueView(app);
  },
  (app) => {
    // Reverse: relation ids -> wire (label per org), swap relation back to the
    // original select, drop the view first / recreate after, drop the list.
    const labelToWire = {};
    for (const [wire, label] of SEED_ROUTES) labelToWire[label] = wire;

    app.delete(app.findCollectionByNameOrId("medication_due"));

    for (const name of ROUTE_COLLECTIONS) {
      const mapped = {};
      for (const r of app.findAllRecords(name)) {
        const id = r.getString("route");
        if (id === "") continue;
        try {
          const rt = app.findRecordById("medication_routes", id);
          const wire = labelToWire[rt.getString("label")];
          if (wire) mapped[r.id] = wire;
        } catch (_) {
          // record gone — skip
        }
      }

      const coll = app.findCollectionByNameOrId(name);
      coll.fields.removeByName("route");
      app.save(coll);
      coll.fields.add(
        new Field({
          name: "route",
          type: "select",
          required: false,
          maxSelect: 1,
          values: SEED_ROUTES.map(([wire]) => wire),
        }),
      );
      app.save(coll);

      for (const r of app.findAllRecords(name)) {
        const wire = mapped[r.id];
        if (!wire) continue;
        r.set("route", wire);
        app.save(r);
      }
    }

    saveMedicationDueView(app);
    app.delete(app.findCollectionByNameOrId("medication_routes"));
  },
);
