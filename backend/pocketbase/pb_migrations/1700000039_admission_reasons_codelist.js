/// <reference path="../pb_data/types.d.ts" />

// federfall-l12 — promote reasons-for-admission from a fixed inline select on
// `cases` to a supervisor-managed, org-scoped code list (mirroring `conditions`).
// Supervisors can add/rename/deactivate reasons at runtime; new + existing cases
// reference them via the multi-relation `cases.admission_reasons`.
//
// Migration shape:
//   1. create the `admission_reasons` collection (+ org-scoped access rules);
//   2. seed the previous 12 reasons (German labels) PER ORG, keeping a per-org
//      wire->record-id map;
//   3. add the `admission_reasons` relation field to `cases`;
//   4. backfill each case from its old `reasons_for_admission` wire values;
//   5. drop the old `reasons_for_admission` select field.
//
// `label` is a single user-language name (German UI), like `conditions.label` —
// these are user-authored data, not i18n'd app chrome.

// [wire, German label] — the exact strings the inline select stored, paired with
// the labels the UI used to resolve via ARB (caseReason*). Order = display order.
const SEED_REASONS = [
  ["injury", "Verletzung"],
  ["illness", "Krankheit"],
  ["orphaned", "Verwaist (Jungtier)"],
  ["trauma", "Trauma"],
  ["poisoning", "Vergiftung"],
  ["trapped", "Gefangen/eingeklemmt"],
  ["cat_attack", "Katzenangriff"],
  ["collision", "Kollision"],
  ["oiled", "Verölt"],
  ["entangled", "Verheddert"],
  ["weak_emaciated", "Geschwächt/abgemagert"],
  ["other", "Sonstiges"],
];

migrate(
  (app) => {
    const organisations = app.findCollectionByNameOrId("organisations");

    // ── 1. admission_reasons code list ──────────────────────────────────────
    const reasons = new Collection({
      type: "base",
      name: "admission_reasons",
      // read by all org members, managed by supervisors (same as `conditions`;
      // mirrors the AUTH / SUP helpers in 1700000010_access_rules.js).
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
    app.save(reasons);

    // ── 2. seed the 12 reasons per org, keyed wire -> record id per org ──────
    // wireToId[orgId][wire] = admission_reasons record id
    const wireToId = {};
    for (const org of app.findAllRecords("organisations")) {
      const perOrg = {};
      for (const [wire, label] of SEED_REASONS) {
        const rec = new Record(reasons);
        rec.set("label", label);
        rec.set("active", true);
        rec.set("org", org.id);
        app.save(rec);
        perOrg[wire] = rec.id;
      }
      wireToId[org.id] = perOrg;
    }

    // ── 3. add the multi-relation field to cases ────────────────────────────
    const cases = app.findCollectionByNameOrId("cases");
    cases.fields.add(
      new Field({
        name: "admission_reasons",
        type: "relation",
        required: false,
        maxSelect: 99,
        collectionId: reasons.id,
        cascadeDelete: false,
      }),
    );
    app.save(cases);

    // ── 4. backfill each case from its old wire values ──────────────────────
    for (const c of app.findAllRecords("cases")) {
      const old = c.get("reasons_for_admission");
      if (!old || old.length === 0) continue;
      const perOrg = wireToId[c.getString("org")];
      if (!perOrg) continue; // case in an org we didn't seed — leave empty
      const ids = [];
      for (const wire of old) {
        if (perOrg[wire]) ids.push(perOrg[wire]);
      }
      c.set("admission_reasons", ids);
      app.save(c);
    }

    // ── 5. drop the old select field ────────────────────────────────────────
    cases.fields.removeByName("reasons_for_admission");
    app.save(cases);
  },
  (app) => {
    // Reverse: re-add the original inline select, backfill from the relation
    // (label -> wire per org), drop the relation field + the collection.
    const cases = app.findCollectionByNameOrId("cases");
    cases.fields.add(
      new Field({
        name: "reasons_for_admission",
        type: "select",
        required: false,
        maxSelect: 12,
        values: SEED_REASONS.map(([wire]) => wire),
      }),
    );
    app.save(cases);

    // label -> wire (labels are unique within the seed set).
    const labelToWire = {};
    for (const [wire, label] of SEED_REASONS) labelToWire[label] = wire;

    for (const c of app.findAllRecords("cases")) {
      const ids = c.get("admission_reasons");
      if (!ids || ids.length === 0) continue;
      const wires = [];
      for (const id of ids) {
        try {
          const r = app.findRecordById("admission_reasons", id);
          const wire = labelToWire[r.getString("label")];
          if (wire) wires.push(wire);
        } catch (_) {
          // record gone — skip
        }
      }
      c.set("reasons_for_admission", wires);
      app.save(c);
    }

    cases.fields.removeByName("admission_reasons");
    app.save(cases);

    app.delete(app.findCollectionByNameOrId("admission_reasons"));
  },
);
