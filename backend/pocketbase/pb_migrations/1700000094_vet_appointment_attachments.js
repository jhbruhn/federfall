/// <reference path="../pb_data/types.d.ts" />

// federfall-hw63 — attachments on a vet appointment: the X-ray the practice
// handed over, a photo of the wound they dressed, and — most often — the
// written Befund, which arrives as a PDF by e-mail rather than as a picture.
//
// That last case is why this is the first file field here that is NOT
// image-only. It is still an ALLOWLIST rather than "anything": the reason
// 1700000048 exists has not gone away. Files are served from the app's own
// origin, so an uploaded text/html or image/svg+xml is a stored-XSS vehicle
// for anyone who opens its URL. What is admitted is what a vet practice
// actually sends — images (HEIC because that is what an iPhone photographs in,
// TIFF/BMP because that is what X-ray software exports), PDF, DICOM, Office and
// OpenDocument files, plain text/CSV, and ZIP (a DICOM series, and the type
// content sniffing falls back to for an Office file it does not recognise).
// PocketBase sniffs the content rather than trusting the declared type, so a
// renamed .html does not get in as a .pdf.
//
// Born correct, as 1700000087 spelled out: protected + allowlist + thumbs
// INLINE, because 1700000027 / 1700000048 / 1700000049 carry hardcoded target
// lists and a field created without their treatment never gets it.
//
// NB thumbs are generated for IMAGES ONLY — `?thumb=` on a PDF silently serves
// the ORIGINAL (the 1700000049 finding), so the client branches on the file
// type and draws an icon for anything that is not a picture.
//
// 50 MB follows microscopy (1700000073): a scanned multi-page report or a DICOM
// export is far larger than a phone photo, and DEPLOYMENT.md already tells
// operators to raise the reverse proxy's body limit for exactly that reason.
//
// No rule change: the appointment's existing case-scoped rules (1700000064 +
// 1700000072's frozen `case`/`org`) are the file's access rules too, and the
// file token only serves it to someone who can read the record.

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("vet_appointments");
    c.fields.add(
      new Field({
        name: "attachments",
        type: "file",
        required: false,
        maxSelect: 10,
        maxSize: 52428800,
        mimeTypes: [
          "image/jpeg",
          "image/png",
          "image/webp",
          "image/gif",
          "image/heic",
          "image/heif",
          "image/tiff",
          "image/bmp",
          "application/pdf",
          "application/dicom",
          "application/msword",
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "application/vnd.ms-excel",
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          "application/vnd.oasis.opendocument.text",
          "application/vnd.oasis.opendocument.spreadsheet",
          "text/plain",
          "text/csv",
          "application/zip",
        ],
        thumbs: ["200x200"],
        protected: true,
      }),
    );
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("vet_appointments");
    c.fields.removeByName("attachments");
    app.save(c);
  },
);
