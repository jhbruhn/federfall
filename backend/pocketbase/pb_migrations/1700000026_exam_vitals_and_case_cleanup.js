/// <reference path="../pb_data/types.d.ts" />

// blp.6 — reconcile the case's clinical fields with the relational exam/weights
// model:
//   1. add temperature + mucous-membrane vitals to `exams` (typed, optional);
//   2. backfill each case's `intake_weight_g` into a real `weights` entry so the
//      intake baseline reaches the trend chart (intake stops writing the
//      case-only column at the app layer);
//   3. drop the 14 dead `cases.exam_*` columns — they were the original flat
//      FED-4.8 exam, never read or written by any UI, now superseded by
//      exams/exam_findings (empty, so no backfill needed).
//
// `intake_weight_g` itself is kept (back-compat for old rows) but goes unused;
// a later migration can drop it once nothing reads it.

migrate(
  (app) => {
    // ── 1. new exam vitals ────────────────────────────────────────────────
    const exams = app.findCollectionByNameOrId("exams");
    exams.fields.add(
      new Field({ name: "temperature", type: "number", required: false }),
    );
    exams.fields.add(
      new Field({
        name: "mm_color",
        type: "select",
        required: false,
        maxSelect: 1,
        values: ["pink", "pale", "cyanotic", "icteric", "injected"],
      }),
    );
    exams.fields.add(
      new Field({
        name: "mm_texture",
        type: "select",
        required: false,
        maxSelect: 1,
        values: ["moist", "tacky", "dry"],
      }),
    );
    app.save(exams);

    // ── 2. backfill intake_weight_g -> weights ────────────────────────────
    const weights = app.findCollectionByNameOrId("weights");
    for (const c of app.findAllRecords("cases")) {
      const w = c.getFloat("intake_weight_g");
      const animal = c.getString("animal");
      if (w > 0 && animal !== "") {
        const rec = new Record(weights);
        rec.set("animal", animal);
        rec.set("case", c.id);
        rec.set("weight_g", w);
        const measured = c.getString("admitted_at") || c.getString("created");
        if (measured !== "") rec.set("measured_at", measured);
        const carer = c.getString("active_carer");
        if (carer !== "") rec.set("author", carer);
        rec.set("org", c.getString("org"));
        app.save(rec);
      }
    }

    // ── 3. drop the dead cases.exam_* columns ─────────────────────────────
    const cases = app.findCollectionByNameOrId("cases");
    for (const name of [
      "exam_bcs",
      "exam_dehydration",
      "exam_attitude",
      "exam_temperature",
      "exam_mm_color",
      "exam_mm_texture",
      "exam_head",
      "exam_cns",
      "exam_cardiopulmonary",
      "exam_gi",
      "exam_musculoskeletal",
      "exam_integument",
      "exam_forelimb",
      "exam_hindlimb",
    ]) {
      cases.fields.removeByName(name);
    }
    app.save(cases);
  },
  (app) => {
    // Re-add the dead exam_* columns (original defs from 1700000004). The
    // backfilled weights are left in place — data backfills aren't reversed.
    const cases = app.findCollectionByNameOrId("cases");
    const textField = (name, max) =>
      new Field({ name, type: "text", required: false, max });
    cases.fields.add(
      new Field({ name: "exam_bcs", type: "number", required: false, min: 0, max: 9 }),
    );
    cases.fields.add(textField("exam_dehydration", 100));
    cases.fields.add(textField("exam_attitude", 200));
    cases.fields.add(
      new Field({ name: "exam_temperature", type: "number", required: false }),
    );
    cases.fields.add(textField("exam_mm_color", 100));
    cases.fields.add(textField("exam_mm_texture", 100));
    cases.fields.add(textField("exam_head", 1000));
    cases.fields.add(textField("exam_cns", 1000));
    cases.fields.add(textField("exam_cardiopulmonary", 1000));
    cases.fields.add(textField("exam_gi", 1000));
    cases.fields.add(textField("exam_musculoskeletal", 1000));
    cases.fields.add(textField("exam_integument", 1000));
    cases.fields.add(textField("exam_forelimb", 1000));
    cases.fields.add(textField("exam_hindlimb", 1000));
    app.save(cases);

    const exams = app.findCollectionByNameOrId("exams");
    exams.fields.removeByName("temperature");
    exams.fields.removeByName("mm_color");
    exams.fields.removeByName("mm_texture");
    app.save(exams);
  },
);
