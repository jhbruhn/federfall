// The base every video starts from. All names and addresses are fictional;
// e-mail addresses use the reserved .example domain.

export const ORG_NAME = {
  de: 'Wildvogelhilfe Elbmarsch',
  en: 'Elbmarsch Wild Bird Rescue',
};

// One account per role. The supervisor's e-mail must match
// FEDERFALL_SUPERVISOR_EMAIL in compose.yaml: the backend bootstraps that one.
export const PEOPLE = {
  supervisor: { role: 'supervisor', name: 'Johanna Brandt', email: 'leitung@wildvogelhilfe.example' },
  coordinator: { role: 'coordinator', name: 'Malte Riedel', email: 'malte@wildvogelhilfe.example' },
  carer: { role: 'carer', name: 'Lena Vogt', email: 'lena@wildvogelhilfe.example' },
  carer2: { role: 'carer', name: 'Tarek Aydin', email: 'tarek@wildvogelhilfe.example' },
};

// Code lists the migrations seed in German, keyed by the German label they
// seed: every list the app has, so no English video shows a German chip. A row
// with no entry fails the setup. The English labels follow the wire names the
// migrations pair them with (1700000039–41: `association_ring`, `nebulized`, …).
// The drug catalogue (medication_products) is not here: the migrations seed it
// with three placeholders that the demo dataset replaces outright
// (data/demo/vocab.mjs, PRODUCTS).
export const CODE_LISTS = {
  admission_reasons: [
    { de: 'Verletzung', en: 'Injury' },
    { de: 'Krankheit', en: 'Illness' },
    { de: 'Verwaist (Jungtier)', en: 'Orphaned (juvenile)' },
    { de: 'Trauma', en: 'Trauma' },
    { de: 'Vergiftung', en: 'Poisoning' },
    { de: 'Gefangen/eingeklemmt', en: 'Trapped' },
    { de: 'Katzenangriff', en: 'Cat attack' },
    { de: 'Kollision', en: 'Collision' },
    { de: 'Verölt', en: 'Oiled' },
    { de: 'Verheddert', en: 'Entangled' },
    { de: 'Geschwächt/abgemagert', en: 'Weak/emaciated' },
    { de: 'Sonstiges', en: 'Other' },
  ],
  marking_types: [
    { de: 'Finderring', en: 'Finder ring' },
    { de: 'Temporäre Markierung', en: 'Temporary marker' },
    { de: 'Auswilderungsring', en: 'Release ring' },
    { de: 'Vereinsring', en: 'Association ring' },
    { de: 'Mikrochip', en: 'Microchip' },
  ],
  medication_routes: [
    { de: 'Oral', en: 'Oral' },
    { de: 'Subkutan', en: 'Subcutaneous' },
    { de: 'Intramuskulär', en: 'Intramuscular' },
    { de: 'Intravenös', en: 'Intravenous' },
    { de: 'Topisch', en: 'Topical' },
    { de: 'Inhalativ', en: 'Nebulised' },
    { de: 'Sonstige', en: 'Other' },
  ],
  conditions: [
    { de: 'Trichomonadose (Gelber Knopf)', en: 'Trichomonosis (canker)' },
    { de: 'Paramyxovirose (PMV)', en: 'Paramyxovirus (PMV)' },
    { de: 'Ornithose / Chlamydiose', en: 'Ornithosis / chlamydiosis' },
    { de: 'Salmonellose (Paratyphose)', en: 'Salmonellosis (paratyphoid)' },
    { de: 'Kokzidiose', en: 'Coccidiosis' },
    { de: 'Endoparasiten (Wurmbefall)', en: 'Endoparasites (worms)' },
    { de: 'Ektoparasiten (Federlinge / Milben)', en: 'Ectoparasites (lice / mites)' },
    { de: 'Taubenpocken', en: 'Pigeon pox' },
    { de: 'Aspergillose', en: 'Aspergillosis' },
    { de: 'Kropfentzündung (Ingluvitis)', en: 'Crop infection (ingluvitis)' },
    { de: 'Fadenfuß (Haarstrangulation)', en: 'String foot (hair constriction)' },
    { de: 'Spreizbein', en: 'Splay leg' },
    { de: 'Fraktur (Knochenbruch)', en: 'Fracture' },
    { de: 'Luxation', en: 'Dislocation' },
    { de: 'Weichteiltrauma', en: 'Soft-tissue trauma' },
    { de: 'Kopftrauma', en: 'Head trauma' },
    { de: 'Augenverletzung', en: 'Eye injury' },
    { de: 'Gefiederschaden', en: 'Feather damage' },
    { de: 'Katzenbiss', en: 'Cat bite' },
    { de: 'MBD (Metabolische Knochenerkrankung)', en: 'MBD (metabolic bone disease)' },
    { de: 'Abmagerung / Auszehrung', en: 'Emaciation' },
    { de: 'Vergiftung', en: 'Poisoning' },
  ],
  microscopy_finding_types: [
    { de: 'Trichomonaden', en: 'Trichomonads' },
    { de: 'Hefen', en: 'Yeasts' },
    { de: 'Haarwurmeier', en: 'Capillaria eggs' },
    { de: 'Spulwurmeier', en: 'Roundworm eggs' },
    { de: 'Kokzidien-Oozysten', en: 'Coccidia oocysts' },
  ],
};

/** A code list's label in [locale], given the German label the migration seeds. */
export function codeLabel(collection, de, locale) {
  const entry = CODE_LISTS[collection]?.find((l) => l.de === de);
  if (!entry) throw new Error(`no ${collection} entry "${de}" in data/base.mjs`);
  return entry[locale];
}
