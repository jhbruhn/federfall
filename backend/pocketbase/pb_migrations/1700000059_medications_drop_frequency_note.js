/// <reference path="../pb_data/types.d.ts" />

// federfall-6d3a.4 follow-up — retire the free-text `frequency` note.
//
// The prescription form asked how often a drug is given three times over:
// `frequency_kind` (the preset), `interval_hours` (the custom gap) and this
// free-text note. The note is the oldest of the three — 1700000014 kept it
// "for schedules a preset can't express" when the structured model arrived —
// but the custom-interval option covers exactly that case, so all it does now
// is invite a fourth, contradictory answer to the same question.
//
// Whatever anyone wrote in it is prose about the plan, so it moves to
// `instructions` (the field for prose about the plan) rather than being
// deleted, and the column goes.
//
// Nothing else reads it: the `medication_due` view selects frequency_kind and
// interval_hours only (see 1700000058), and the PDF report drops its
// `frequency` line in the same change.

migrate(
  (app) => {
    const notes = app.findRecordsByFilter(
      "medications",
      "frequency != ''",
      "",
      0,
      0,
    );
    for (const rec of notes) {
      const note = String(rec.get("frequency")).trim();
      const instructions = String(rec.get("instructions") || "").trim();
      rec.set(
        "instructions",
        instructions ? `${instructions}\n${note}` : note,
      );
      app.save(rec);
    }

    const medications = app.findCollectionByNameOrId("medications");
    medications.fields.removeByName("frequency");
    app.save(medications);
  },
  (app) => {
    // The note's text is indistinguishable from any other instruction once
    // merged, so the column comes back empty rather than guessing which line
    // used to live in it.
    const medications = app.findCollectionByNameOrId("medications");
    medications.fields.add(
      new Field({ name: "frequency", type: "text", required: false, max: 100 }),
    );
    app.save(medications);
  },
);
