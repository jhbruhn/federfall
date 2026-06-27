/// <reference path="../pb_data/types.d.ts" />

// FED-8.1 — add a `pii_purged` marker to finders. The retention job
// (pb_hooks/finder_retention.pb.js) sets it true once a finder's identifying PII
// has been anonymised, so the job is idempotent (it only ever looks at
// pii_purged = false) and the state is auditable. Defaults to false.

migrate(
  (app) => {
    const finders = app.findCollectionByNameOrId("finders");
    finders.fields.add(new BoolField({ name: "pii_purged" }));
    app.save(finders);
  },
  (app) => {
    const finders = app.findCollectionByNameOrId("finders");
    finders.fields.removeByName("pii_purged");
    app.save(finders);
  },
);
