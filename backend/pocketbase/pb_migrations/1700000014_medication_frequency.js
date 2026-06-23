/// <reference path="../pb_data/types.d.ts" />

// Semantic medication frequency (follow-up to FED-4.6). Replaces the meaning of
// the free-text `frequency` with a structured, reminder-ready model:
//
//   frequency_kind ∈ once | scheduled | as_needed
//   interval_hours  : the gap between doses when kind = scheduled
//                     (24=q24h/daily, 12=q12h/BID, 8=q8h/TID, 6=q6h/QID, 48=EOD …)
//
// A reminder is then simply: next due = last administration + interval_hours.
// The existing free-text `frequency` column is kept as an optional note for
// schedules a preset can't express.

migrate(
  (app) => {
    const c = app.findCollectionByNameOrId("medications");
    c.fields.add(
      new Field({
        name: "frequency_kind",
        type: "select",
        required: false,
        maxSelect: 1,
        values: ["once", "scheduled", "as_needed"],
      }),
    );
    c.fields.add(
      new Field({
        name: "interval_hours",
        type: "number",
        required: false,
        min: 1,
      }),
    );
    app.save(c);
  },
  (app) => {
    const c = app.findCollectionByNameOrId("medications");
    c.fields.removeByName("frequency_kind");
    c.fields.removeByName("interval_hours");
    app.save(c);
  },
);
