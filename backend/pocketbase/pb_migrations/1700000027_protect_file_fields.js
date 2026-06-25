/// <reference path="../pb_data/types.d.ts" />

// FED-8.1 / 49l.1 — mark clinical & finder-linked image fields as Protected.
//
// PocketBase serves file fields PUBLICLY by full URL by default (the random
// filename suffix is the only guard), which bypasses the org-scoped, private-
// by-default access rules that protect the records themselves. Patient and
// finder-linked photos must not be reachable by bare URL.
//
// With `protected: true`, a file URL is only served when accompanied by a
// short-lived file token (`POST /api/files/token`, ~2min TTL) issued for an
// auth model that can read the owning record — so the same org-scoping that
// guards the records now guards their images. The client appends the token via
// `pb.files.getURL(record, name, token: ...)`.
//
// Fields protected: cases.intake_photos, journal_entries.attachments,
// animals.photo. No pure-public image asset exists today.
migrate(
  (app) => {
    const targets = [
      ["cases", "intake_photos"],
      ["journal_entries", "attachments"],
      ["animals", "photo"],
    ];
    for (const [collection, fieldName] of targets) {
      const c = app.findCollectionByNameOrId(collection);
      const field = c.fields.getByName(fieldName);
      field.protected = true;
      app.save(c);
    }
  },
  (app) => {
    const targets = [
      ["cases", "intake_photos"],
      ["journal_entries", "attachments"],
      ["animals", "photo"],
    ];
    for (const [collection, fieldName] of targets) {
      const c = app.findCollectionByNameOrId(collection);
      const field = c.fields.getByName(fieldName);
      field.protected = false;
      app.save(c);
    }
  },
);
