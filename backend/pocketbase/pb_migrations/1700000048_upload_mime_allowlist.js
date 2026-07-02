/// <reference path="../pb_data/types.d.ts" />

// federfall-8a5 — MIME allowlist for cases.intake_photos and
// journal_entries.attachments.
//
// Both fields set maxSelect/maxSize but no mimeTypes, so PocketBase accepted
// arbitrary content — including text/html and image/svg+xml. The fields are
// Protected (1700000027) but served from the same origin as the SPA/Admin UI:
// any org member could upload evil.svg/.html and anyone opening the file URL
// (any same-org member can mint a file token) would execute script in the
// Federfall origin — stored XSS / token theft. intake_photos is also reachable
// via POST /api/federfall/intake.
//
// The app only ever uploads image-picker output, so the allowlist matches the
// one animals.photo has had since 1700000017. Existing files are not
// re-validated (PocketBase checks on upload only) — acceptable, since the
// exposure window predates any real deployment.
migrate(
  (app) => {
    const allowed = ["image/jpeg", "image/png", "image/webp", "image/gif"];
    const targets = [
      ["cases", "intake_photos"],
      ["journal_entries", "attachments"],
    ];
    for (const [collection, fieldName] of targets) {
      const c = app.findCollectionByNameOrId(collection);
      c.fields.getByName(fieldName).mimeTypes = allowed;
      app.save(c);
    }
  },
  (app) => {
    const targets = [
      ["cases", "intake_photos"],
      ["journal_entries", "attachments"],
    ];
    for (const [collection, fieldName] of targets) {
      const c = app.findCollectionByNameOrId(collection);
      c.fields.getByName(fieldName).mimeTypes = [];
      app.save(c);
    }
  },
);
