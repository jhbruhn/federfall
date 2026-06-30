/// <reference path="../pb_data/types.d.ts" />

// federfall-28a — promote marking types from a fixed inline select on `markings`
// to a supervisor-managed, org-scoped code list (mirroring `conditions` /
// `admission_reasons`). Supervisors can add/rename/deactivate marking types at
// runtime; each marking references one via the `markings.type` relation.
//
// markings.type is single-select + required, so the field is reused in place:
//   1. create the `marking_types` collection (+ org-scoped access rules);
//   2. seed the previous 5 types (German labels) PER ORG (wire->id map);
//   3. capture each marking's old `type` wire, drop the select, re-add `type`
//      as a relation, backfill, then restore the required constraint.

// [wire, German label] — the select values paired with the labels the UI used
// to resolve via ARB (marking*). Order = display order.
const SEED_TYPES = [
  ["finder_ring", "Finderring"],
  ["temporary_marker", "Temporäre Markierung"],
  ["release_ring", "Auswilderungsring"],
  ["association_ring", "Vereinsring"],
  ["microchip", "Mikrochip"],
];

migrate(
  (app) => {
    const organisations = app.findCollectionByNameOrId("organisations");

    // ── 1. marking_types code list ──────────────────────────────────────────
    const types = new Collection({
      type: "base",
      name: "marking_types",
      // read by all org members, managed by supervisors (mirrors the AUTH / SUP
      // helpers in 1700000010_access_rules.js).
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
    app.save(types);

    // ── 2. seed the 5 types per org, keyed wire -> record id per org ─────────
    const wireToId = {};
    for (const org of app.findAllRecords("organisations")) {
      const perOrg = {};
      for (const [wire, label] of SEED_TYPES) {
        const rec = new Record(types);
        rec.set("label", label);
        rec.set("active", true);
        rec.set("org", org.id);
        app.save(rec);
        perOrg[wire] = rec.id;
      }
      wireToId[org.id] = perOrg;
    }

    // ── 3. capture old wire values, swap the field select -> relation ───────
    // markingId -> mapped relation id (resolved from the old select wire).
    const newType = {};
    for (const m of app.findAllRecords("markings")) {
      const perOrg = wireToId[m.getString("org")];
      const wire = m.getString("type");
      if (perOrg && perOrg[wire]) newType[m.id] = perOrg[wire];
    }

    const markings = app.findCollectionByNameOrId("markings");
    markings.fields.removeByName("type");
    app.save(markings);
    markings.fields.add(
      new Field({
        name: "type",
        type: "relation",
        required: false, // restored to true after backfill
        maxSelect: 1,
        collectionId: types.id,
        cascadeDelete: false,
      }),
    );
    app.save(markings);

    // ── 4. backfill, then restore the required constraint ───────────────────
    for (const m of app.findAllRecords("markings")) {
      const id = newType[m.id];
      if (!id) continue;
      m.set("type", id);
      app.save(m);
    }
    markings.fields.getByName("type").required = true;
    app.save(markings);
  },
  (app) => {
    // Reverse: capture relation ids -> wire (label per org), swap relation back
    // to the original select, backfill, drop the collection.
    const labelToWire = {};
    for (const [wire, label] of SEED_TYPES) labelToWire[label] = wire;

    const oldWire = {};
    for (const m of app.findAllRecords("markings")) {
      const id = m.getString("type");
      if (id === "") continue;
      try {
        const r = app.findRecordById("marking_types", id);
        const wire = labelToWire[r.getString("label")];
        if (wire) oldWire[m.id] = wire;
      } catch (_) {
        // record gone — skip
      }
    }

    const markings = app.findCollectionByNameOrId("markings");
    markings.fields.removeByName("type");
    app.save(markings);
    markings.fields.add(
      new Field({
        name: "type",
        type: "select",
        required: false, // restored to true after backfill
        maxSelect: 1,
        values: SEED_TYPES.map(([wire]) => wire),
      }),
    );
    app.save(markings);

    for (const m of app.findAllRecords("markings")) {
      const wire = oldWire[m.id];
      if (!wire) continue;
      m.set("type", wire);
      app.save(m);
    }
    markings.fields.getByName("type").required = true;
    app.save(markings);

    app.delete(app.findCollectionByNameOrId("marking_types"));
  },
);
