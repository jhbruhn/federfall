/// <reference path="../pb_data/types.d.ts" />

// federfall-6d3a.3 follow-up — fill the placeholder catalogue entries with
// example VALUES, not just names.
//
// 1700000060 seeded three rows carrying nothing but a label, which shows that a
// catalogue exists but not what an entry is for. These values demonstrate the
// three shapes an entry takes:
//
//   Medikament 1  a solution dosed in mg/kg, drawn up from a 10 mg/ml stock
//   Medikament 2  the same with a twice-daily schedule and a tighter range
//   Medikament 3  dosed in ml/kg (a fluid), so there is nothing to draw up and
//                 no concentration — the field is legitimately empty
//
// The numbers are invented and deliberately round. They are NOT a protocol: the
// labels stay "Medikament n" so nothing here can be mistaken for a real
// preparation, and every row carries a note saying so. A supervisor is expected
// to edit or delete all three.
//
// Only untouched rows are filled: if a supervisor has already renamed an entry
// or put a real number in it, this migration leaves it alone rather than
// overwriting clinical data with examples.

const EXAMPLE_NOTE =
  "Beispieleintrag mit erfundenen Werten — bitte anpassen oder löschen.";

// [label, dose_unit, dose_rate, rate_min, rate_max, concentration_per_ml,
//  route label, frequency_kind, interval_hours]
const EXAMPLES = [
  ["Medikament 1", "mg", 10, 5, 20, 10, "Oral", "scheduled", 24],
  ["Medikament 2", "mg", 20, 10, 30, 15, "Subkutan", "scheduled", 12],
  ["Medikament 3", "ml", 0.5, 0.2, 1, null, "Oral", "as_needed", null],
];

migrate(
  (app) => {
    for (const [
      label,
      unit,
      rate,
      min,
      max,
      concentration,
      routeLabel,
      kind,
      interval,
    ] of EXAMPLES) {
      let rec;
      try {
        rec = app.findFirstRecordByFilter("medication_products", "label = {:l}", {
          l: label,
        });
      } catch (_) {
        continue; // Renamed or deleted by a supervisor — leave it alone.
      }

      // Untouched means: nothing but the label and the mg default was set.
      const touched =
        rec.getFloat("dose_rate") ||
        rec.getFloat("rate_min") ||
        rec.getFloat("rate_max") ||
        rec.getFloat("concentration_per_ml") ||
        rec.getString("route") ||
        rec.getString("frequency_kind") ||
        rec.getString("note");
      if (touched) continue;

      rec.set("dose_unit", unit);
      rec.set("dose_rate", rate);
      rec.set("rate_min", min);
      rec.set("rate_max", max);
      if (concentration !== null) rec.set("concentration_per_ml", concentration);
      rec.set("frequency_kind", kind);
      if (interval !== null) rec.set("interval_hours", interval);
      rec.set("note", EXAMPLE_NOTE);

      // The route is a relation into the org's own list, which a supervisor may
      // have renamed — skip it silently rather than failing the migration.
      try {
        const route = app.findFirstRecordByFilter(
          "medication_routes",
          "label = {:l} && org = {:org}",
          { l: routeLabel, org: rec.getString("org") },
        );
        rec.set("route", route.id);
      } catch (_) {
        // No matching route in this org; the entry is fine without one.
      }

      app.save(rec);
    }
  },
  (app) => {
    // Back to name-only placeholders, and only for rows still recognisable as
    // the examples this migration wrote.
    for (const [label] of EXAMPLES) {
      let rec;
      try {
        rec = app.findFirstRecordByFilter("medication_products", "label = {:l}", {
          l: label,
        });
      } catch (_) {
        continue;
      }
      if (rec.getString("note") !== EXAMPLE_NOTE) continue;
      rec.set("dose_unit", "mg");
      rec.set("dose_rate", null);
      rec.set("rate_min", null);
      rec.set("rate_max", null);
      rec.set("concentration_per_ml", null);
      rec.set("route", "");
      rec.set("frequency_kind", "");
      rec.set("interval_hours", null);
      rec.set("note", "");
      app.save(rec);
    }
  },
);
