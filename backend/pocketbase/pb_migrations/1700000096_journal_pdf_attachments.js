/// <reference path="../pb_data/types.d.ts" />

// federfall-8qwo — a journal entry may carry a PDF, not only photos.
//
// The paper a case accumulates — a lab result, a transfer note, a euthanasia
// certificate, a Befund that is not tied to one vet appointment — arrives as a
// PDF, and until now could only be photographed into a journal entry. 1700000094
// already admits PDF on vet_appointments.attachments; this extends the same
// type, and ONLY that type, to journal_entries.attachments.
//
// Still an allowlist, for 1700000048's reason: files are served from the app's
// own origin, so text/html and image/svg+xml stay out. PocketBase sniffs the
// content rather than trusting the declared type, so a renamed .html does not
// get in as a .pdf. Deliberately narrower than the vet list (no Office, no ZIP,
// no DICOM): a journal note is a carer's record, not an inbox for whatever a
// practice exports.
//
// NOT cases.intake_photos and NOT animals.photo: both are pictures by
// definition, and 1700000065 promotes an intake photo to the animal's avatar.
//
// thumbs stay as 1700000049 left them; `?thumb=` on a PDF silently serves the
// original, so the client branches on the extension and never asks for one.

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("journal_entries");
    c.fields.getByName("attachments").mimeTypes = [
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/gif",
      "application/pdf",
    ];
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("journal_entries");
    c.fields.getByName("attachments").mimeTypes = [
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/gif",
    ];
    app.save(c);
  },
);
