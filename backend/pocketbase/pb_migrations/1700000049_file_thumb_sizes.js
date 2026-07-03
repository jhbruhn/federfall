/// <reference path="../pb_data/types.d.ts" />

// Thumb-size whitelist for the photo file fields.
//
// PocketBase only generates a `?thumb=WxH` variant when that size is listed in
// the field's `thumbs` option; for any other size it silently serves the
// ORIGINAL file. None of the photo fields ever configured `thumbs`, so every
// `thumb=200x200` request the app makes (case intake photos, journal
// attachments, animal avatars) returned the full-size original — megabytes per
// tile, and a non-square image that the client's fixed decode size then
// distorted into a square.
//
// 200x200 is the one size the app requests (center-crop, matching the square
// 96px tiles / round avatars). Thumbs are generated lazily on first request,
// so existing files are covered too.
migrate(
  (app) => {
    const targets = [
      ["cases", "intake_photos"],
      ["journal_entries", "attachments"],
      ["animals", "photo"],
    ];
    for (const [collection, fieldName] of targets) {
      const c = app.findCollectionByNameOrId(collection);
      c.fields.getByName(fieldName).thumbs = ["200x200"];
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
      c.fields.getByName(fieldName).thumbs = [];
      app.save(c);
    }
  },
);
