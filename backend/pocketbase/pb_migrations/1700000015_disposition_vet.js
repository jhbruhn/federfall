/// <reference path="../pb_data/types.d.ts" />

// FED-4.11 — add a free-text `vet` to dispositions: the external vet who
// performed the procedure (esp. euthanasia). Vets don't log in (referral data
// only), so this is a name, mirroring medications.prescribed_by — distinct from
// `performed_by`, which is the staff member who recorded the outcome.

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("dispositions");
    c.fields.add(
      new Field({
        name: "vet",
        type: "text",
        required: false,
        max: 200,
      }),
    );
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("dispositions");
    c.fields.removeByName("vet");
    app.save(c);
  },
);
