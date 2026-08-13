/// <reference path="../pb_data/types.d.ts" />

// federfall-wmbi — how many rounds the protocol runs, on the CATALOGUE entry.
//
// 1700000090 put the give/pause rhythm on both the prescription and the
// catalogue, but left the repeat count out of the catalogue on the grounds that
// it computes an end date and an end date needs a start. That was too strict:
// "three rounds of 5 on / 2 off" is the standard course for a dewormer, i.e.
// part of the org's protocol, and re-typing it per bird is exactly the work the
// catalogue exists to remove.
//
// It lands on `medication_products` ONLY, and that asymmetry is the design:
//
//   catalogue     the count IS the fact — a protocol, stored as written
//   prescription  the DATES are the fact — start + rhythm + end
//
// A prescription still stores no count (see 1700000090): picking the entry
// pours the count into the form, the form turns it into `ended_at` against that
// bird's own start, and from then on the two dates are what the plan means. A
// stored count on the prescription could only ever contradict them.
//
// Consequence worth keeping: editing a catalogue entry's count does NOT move
// the end date of any plan already written from it. That is correct — a plan is
// a decision that was made on a day, not a live view of the protocol — and it
// is the same stance `dose_rate` already takes.

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("medication_products");
    c.fields.add(
      new Field({
        name: "cycle_repeats",
        type: "number",
        required: false,
        min: 1,
        onlyInt: true,
      }),
    );
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("medication_products");
    c.fields.removeByName("cycle_repeats");
    app.save(c);
  },
);
