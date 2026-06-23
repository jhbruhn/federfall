/// <reference path="../pb_data/types.d.ts" />

// FED-1.10 — seed the German `conditions` code list for the launch org. These are
// editable by supervisors at runtime; this is just a sensible starting set for
// feral-pigeon (Stadttaube) rehab. `label` is the single user-language name (see
// FED-1.6). `is_notifiable` marks anzeige-/meldepflichtige Erkrankungen.
//
// The reasons-for-admission list is NOT seeded here — it's an inline select enum
// on the `cases` collection (FED-1.3), not a code-list collection.

const ORG_ID = "org00000default";

// [label, is_notifiable]
const CONDITIONS = [
  ["Trichomonadose (Gelber Knopf)", false],
  ["Paramyxovirose (PMV)", false], // not notifiable for pigeons in Germany
  ["Ornithose / Chlamydiose", true], // anzeigepflichtige Tierseuche (Psittakose)
  ["Salmonellose (Paratyphose)", false],
  ["Kokzidiose", false],
  ["Endoparasiten (Wurmbefall)", false],
  ["Ektoparasiten (Federlinge / Milben)", false],
  ["Taubenpocken", false],
  ["Aspergillose", false],
  ["Kropfentzündung (Ingluvitis)", false],
  ["Fadenfuß (Haarstrangulation)", false],
  ["Spreizbein", false],
  ["Fraktur (Knochenbruch)", false],
  ["Luxation", false],
  ["Weichteiltrauma", false],
  ["Kopftrauma", false],
  ["Augenverletzung", false],
  ["Gefiederschaden", false],
  ["Katzenbiss", false],
  ["MBD (Metabolische Knochenerkrankung)", false],
  ["Abmagerung / Auszehrung", false],
  ["Vergiftung", false],
];

migrate(
  (app) => {
    const conditions = app.findCollectionByNameOrId("conditions");
    for (const [label, notifiable] of CONDITIONS) {
      const rec = new Record(conditions);
      rec.set("label", label);
      rec.set("is_notifiable", notifiable);
      rec.set("active", true);
      rec.set("org", ORG_ID);
      app.save(rec);
    }
  },
  (app) => {
    for (const [label] of CONDITIONS) {
      try {
        const rec = app.findFirstRecordByFilter("conditions", "org = {:org} && label = {:label}", {
          org: ORG_ID,
          label: label,
        });
        if (rec) app.delete(rec);
      } catch (_) {
        // already gone — ignore
      }
    }
  },
);
