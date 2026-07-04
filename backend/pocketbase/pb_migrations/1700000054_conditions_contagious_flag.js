/// <reference path="../pb_data/types.d.ts" />

// federfall-d5co follow-up — conditions gets an `is_contagious` flag
// alongside `is_notifiable`: distinct concepts (a notifiable disease must be
// reported to the authorities; a contagious one risks spreading to other
// flock residents — e.g. Trichomonadose is contagious among pigeons but is
// NOT a reportable disease in Germany, see 1700000012). The aviary flock
// timeline (federfall-d5co.3) highlights it so a coordinator spots a
// diagnosis that matters for the whole enclosure, not just the one bird.
//
// Backfills the launch org's seeded list (1700000012) for the diseases that
// plausibly spread bird-to-bird in a shared aviary (direct contact / shared
// food-water / fecal-oral route); trauma, toxicity and environmental
// (fungal) causes are deliberately left false. This is a starting default,
// not a clinical guarantee — supervisors can adjust per-org afterwards via
// the conditions code-list admin screen.

const ORG_ID = "org00000default";

const CONTAGIOUS_LABELS = [
  "Trichomonadose (Gelber Knopf)",
  "Paramyxovirose (PMV)",
  "Ornithose / Chlamydiose",
  "Salmonellose (Paratyphose)",
  "Kokzidiose",
  "Endoparasiten (Wurmbefall)",
  "Ektoparasiten (Federlinge / Milben)",
  "Taubenpocken",
];

migrate(
  (app) => {
    const conditions = app.findCollectionByNameOrId("conditions");
    conditions.fields.add(
      new Field({ name: "is_contagious", type: "bool", required: false }),
    );
    app.save(conditions);

    for (const label of CONTAGIOUS_LABELS) {
      try {
        const rec = app.findFirstRecordByFilter(
          "conditions",
          "org = {:org} && label = {:label}",
          { org: ORG_ID, label },
        );
        rec.set("is_contagious", true);
        app.save(rec);
      } catch (_) {
        // Seed row not present (renamed/deleted by a supervisor) — skip.
      }
    }
  },
  (app) => {
    const conditions = app.findCollectionByNameOrId("conditions");
    conditions.fields.removeByName("is_contagious");
    app.save(conditions);
  },
);
