/// <reference path="../pb_data/types.d.ts" />

// ctw.7 — animals.photo: an optional, dedicated portrait for the animal,
// separate from any case's intake photos. Shown as the round avatar in the
// detail header; when unset the header falls back to the most recent case's
// admission photo.
//
// Single image file. Inherits the animals collection access rules (org-wide
// readable identity layer, FED-1.11) — no new rule needed; the file URL is
// unprotected like the existing case intake photos.

migrate(
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");
    animals.fields.add(
      new Field({
        name: "photo",
        type: "file",
        required: false,
        maxSelect: 1,
        maxSize: 10485760,
        mimeTypes: ["image/jpeg", "image/png", "image/webp", "image/gif"],
      }),
    );
    app.save(animals);
  },
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");
    animals.fields.removeByName("photo");
    app.save(animals);
  },
);
