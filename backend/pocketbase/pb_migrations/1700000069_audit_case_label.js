/// <reference path="../pb_data/types.d.ts" />

// federfall-by7w.2 — audit_events.case_label: the case NUMBER on every
// case-scoped row.
//
// 1700000068 gave the log `case_id`, which is a 15-character PocketBase id and
// therefore unreadable. Every case-scoped line in the audit screen — and the
// whole per-case activity section — identified its case by nothing a person
// could recognise.
//
// A snapshot rather than a lookup, for the same reason `actor_label` and
// `subject_label` are snapshots: the app would have to resolve the id at read
// time, and a supervisor deletes cases (cascading through their whole
// timeline), so the resolution would fail exactly when the audit row matters
// most. The number is written once, at emit time, and never has to be fetched
// again.
//
// Additive: an older client ignores the column, an older row simply has none.
migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("audit_events");
    c.fields.add(
      new TextField({ name: "case_label", required: false, max: 64 }),
    );
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("audit_events");
    c.fields.removeByName("case_label");
    app.save(c);
  },
);
