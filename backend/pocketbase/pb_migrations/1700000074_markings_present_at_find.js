/// <reference path="../pb_data/types.d.ts" />

// federfall-z9lh — a ring/marker the bird already carried when it was FOUND is
// not something we applied. `markings.type` says what the marking is
// (Finderring / Vereinsring / Mikrochip, 1700000040); provenance is orthogonal
// to that and derivable from neither: a Vereinsring is normally found-with, an
// Auswilderungsring never is.
//
// `applied_at` stays populated for such a marking (the app snapshots the case's
// find moment into it) — three readers sort or window on that date and none of
// them can see this flag: PbMarkingsRepository.forAnimal's `-applied_at`, the
// case timeline's _MarkingEvent, and case_report_rows' markings column, which
// falls back to `created` when `applied_at` is empty (1700000067). For a case
// entered after the fact that fallback lands AFTER the disposition, which would
// drop a ring the bird arrived wearing out of the annual report.
//
// Optional, so every existing row reads as false, i.e. "we applied it" — which
// is what they mean. Additive and wire-safe: an older client ignores the column.

migrate(
  (app) => {
    const markings = app.findCollectionByNameOrId("markings");
    markings.fields.add(
      new Field({ name: "present_at_find", type: "bool", required: false }),
    );
    app.save(markings);
  },
  (app) => {
    const markings = app.findCollectionByNameOrId("markings");
    markings.fields.removeByName("present_at_find");
    app.save(markings);
  },
);
