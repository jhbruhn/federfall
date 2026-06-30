/// <reference path="../pb_data/types.d.ts" />

// federfall-uvm — finish promoting quarantine to a timeline record: backfill
// every existing case's `quarantine_until` into a real quarantine_records row,
// then drop the now-redundant `cases.quarantine_until` column. The current
// quarantine end is read from the `case_quarantine` view going forward; no
// denormalised mirror is kept (so there is nothing to sync).

migrate(
  (app) => {
    // ── backfill cases.quarantine_until -> quarantine_records ──────────────
    const quarantine = app.findCollectionByNameOrId("quarantine_records");
    for (const c of app.findAllRecords("cases")) {
      const until = c.getString("quarantine_until");
      if (until === "") continue;
      // Skip cases that already carry a quarantine row (idempotent re-runs).
      const existing = app.findRecordsByFilter(
        "quarantine_records", "case = {:c}", "", 1, 0, { c: c.id },
      );
      if (existing.length > 0) continue;

      const rec = new Record(quarantine);
      rec.set("case", c.id);
      rec.set("quarantine_until", until);
      const setAt = c.getString("admitted_at") || c.getString("created");
      if (setAt !== "") rec.set("set_at", setAt);
      const carer = c.getString("active_carer");
      if (carer !== "") rec.set("set_by", carer);
      rec.set("org", c.getString("org"));
      app.save(rec);
    }

    // ── drop the column ────────────────────────────────────────────────────
    const cases = app.findCollectionByNameOrId("cases");
    cases.fields.removeByName("quarantine_until");
    app.save(cases);
  },
  (app) => {
    // Re-add the column (original def from 1700000004) and repopulate each case
    // from its latest quarantine row, so the field is honest again.
    const cases = app.findCollectionByNameOrId("cases");
    cases.fields.add(
      new Field({ name: "quarantine_until", type: "date", required: false }),
    );
    app.save(cases);

    for (const c of app.findAllRecords("cases")) {
      const rows = app.findRecordsByFilter(
        "quarantine_records", "case = {:c}", "-created", 1, 0, { c: c.id },
      );
      if (rows.length > 0) {
        c.set("quarantine_until", rows[0].getString("quarantine_until"));
        app.save(c);
      }
    }
  },
);
