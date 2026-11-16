// The demo organisation's vocabulary: species, places, the drug catalogue,
// vaccines, vets. Everything a viewer reads comes in German (the primary
// language, written first) and English.
//
// Clinical values here are PLAUSIBLE, not prescriptive; drug and vaccine
// product names are invented (see PRODUCTS).

// ── Species ─────────────────────────────────────────────────────────────────
// weight: typical intake range in grams for a bird that needs help (a little
// under a healthy adult). months: when it turns up (1–12). share: weight of
// the species in the yearly intake of an urban rescue in northern Germany —
// feral pigeons first by a distance.
export const SPECIES = {
  feralPigeon: { de: 'Stadttaube', en: 'Feral pigeon', weight: [240, 360], share: 34, group: 'pigeon' },
  woodPigeon: { de: 'Ringeltaube', en: 'Wood pigeon', weight: [380, 520], share: 10, group: 'pigeon' },
  collaredDove: { de: 'Türkentaube', en: 'Collared dove', weight: [130, 200], share: 4, group: 'pigeon' },
  racingPigeon: { de: 'Brieftaube', en: 'Racing pigeon', weight: [330, 450], share: 3, group: 'domestic', months: [4, 5, 6, 7, 8, 9, 10] },
  swift: { de: 'Mauersegler', en: 'Common swift', weight: [32, 46], share: 7, group: 'swift', months: [6, 7, 8] },
  blackbird: { de: 'Amsel', en: 'Blackbird', weight: [70, 105], share: 8, group: 'songbird' },
  sparrow: { de: 'Haussperling', en: 'House sparrow', weight: [22, 31], share: 7, group: 'songbird' },
  greatTit: { de: 'Kohlmeise', en: 'Great tit', weight: [15, 20], share: 3, group: 'songbird' },
  blueTit: { de: 'Blaumeise', en: 'Blue tit', weight: [9, 12], share: 2, group: 'songbird' },
  robin: { de: 'Rotkehlchen', en: 'Robin', weight: [15, 21], share: 2, group: 'songbird' },
  starling: { de: 'Star', en: 'Starling', weight: [62, 85], share: 3, group: 'songbird' },
  greenfinch: { de: 'Grünfink', en: 'Greenfinch', weight: [24, 31], share: 1, group: 'songbird' },
  crow: { de: 'Rabenkrähe', en: 'Carrion crow', weight: [420, 580], share: 4, group: 'corvid' },
  magpie: { de: 'Elster', en: 'Magpie', weight: [180, 240], share: 3, group: 'corvid' },
  jackdaw: { de: 'Dohle', en: 'Jackdaw', weight: [190, 260], share: 2, group: 'corvid' },
  mallard: { de: 'Stockente', en: 'Mallard', weight: [850, 1250], share: 3, group: 'waterfowl' },
  gull: { de: 'Lachmöwe', en: 'Black-headed gull', weight: [230, 320], share: 1, group: 'waterfowl' },
  buzzard: { de: 'Mäusebussard', en: 'Common buzzard', weight: [600, 1000], share: 1, group: 'raptor' },
  kestrel: { de: 'Turmfalke', en: 'Common kestrel', weight: [150, 230], share: 1, group: 'raptor' },
  tawnyOwl: { de: 'Waldkauz', en: 'Tawny owl', weight: [380, 560], share: 0.5, group: 'raptor' },
};

// ── Places ──────────────────────────────────────────────────────────────────
// Public places only (parks, squares, stations) — never a private address.
// Coordinates are on land, and the jitter the bulk adds (about ±150 m) keeps
// them there. Hamburg first, then the towns around it a rescue in the
// Elbmarsch would take birds from.
export const PLACES = [
  { name: 'Planten un Blomen, St. Pauli', city: 'Hamburg', region: 'Hamburg', lat: 53.5600, lon: 9.9790, w: 6 },
  { name: 'Stadtpark, Winterhude', city: 'Hamburg', region: 'Hamburg', lat: 53.5935, lon: 10.0285, w: 6 },
  { name: 'Altonaer Volkspark, Bahrenfeld', city: 'Hamburg', region: 'Hamburg', lat: 53.5835, lon: 9.8925, w: 4 },
  { name: 'Jenischpark, Othmarschen', city: 'Hamburg', region: 'Hamburg', lat: 53.5520, lon: 9.8575, w: 3 },
  { name: 'Hauptbahnhof, St. Georg', city: 'Hamburg', region: 'Hamburg', lat: 53.5527, lon: 10.0068, w: 6 },
  { name: 'Rathausmarkt, Altstadt', city: 'Hamburg', region: 'Hamburg', lat: 53.5502, lon: 9.9928, w: 3 },
  { name: 'Inselpark, Wilhelmsburg', city: 'Hamburg', region: 'Hamburg', lat: 53.5005, lon: 10.0010, w: 4 },
  { name: 'Ohlsdorfer Friedhof, Ohlsdorf', city: 'Hamburg', region: 'Hamburg', lat: 53.6215, lon: 10.0480, w: 3 },
  { name: 'Hammer Park, Hamm', city: 'Hamburg', region: 'Hamburg', lat: 53.5560, lon: 10.0650, w: 3 },
  { name: 'Wehbers Park, Eimsbüttel', city: 'Hamburg', region: 'Hamburg', lat: 53.5718, lon: 9.9545, w: 3 },
  { name: 'Sternschanzenpark, Sternschanze', city: 'Hamburg', region: 'Hamburg', lat: 53.5645, lon: 9.9715, w: 3 },
  { name: 'Wandsbeker Gehölz, Wandsbek', city: 'Hamburg', region: 'Hamburg', lat: 53.5715, lon: 10.0760, w: 2 },
  { name: 'Niendorfer Gehege, Niendorf', city: 'Hamburg', region: 'Hamburg', lat: 53.6215, lon: 9.9405, w: 2 },
  { name: 'Lohsepark, HafenCity', city: 'Hamburg', region: 'Hamburg', lat: 53.5437, lon: 10.0055, w: 2 },
  { name: 'Alma-Wartenberg-Platz, Ottensen', city: 'Hamburg', region: 'Hamburg', lat: 53.5548, lon: 9.9302, w: 3 },
  { name: 'Hansaplatz, St. Georg', city: 'Hamburg', region: 'Hamburg', lat: 53.5552, lon: 10.0128, w: 3 },
  { name: 'Schlosspark, Bergedorf', city: 'Hamburg', region: 'Hamburg', lat: 53.4880, lon: 10.2150, w: 2 },
  { name: 'Harburger Rathausplatz, Harburg', city: 'Hamburg', region: 'Hamburg', lat: 53.4606, lon: 9.9832, w: 2 },
  { name: 'Marktplatz, Blankenese', city: 'Hamburg', region: 'Hamburg', lat: 53.5602, lon: 9.8052, w: 1 },
  { name: 'Museum der Arbeit, Barmbek', city: 'Hamburg', region: 'Hamburg', lat: 53.5822, lon: 10.0460, w: 2 },
  { name: 'Drosteipark', city: 'Pinneberg', region: 'Schleswig-Holstein', lat: 53.6585, lon: 9.7985, w: 2 },
  { name: 'Stadtpark', city: 'Norderstedt', region: 'Schleswig-Holstein', lat: 53.7075, lon: 10.0045, w: 2 },
  { name: 'Schlosspark', city: 'Ahrensburg', region: 'Schleswig-Holstein', lat: 53.6748, lon: 10.2395, w: 1 },
  { name: 'Rathausplatz', city: 'Wedel', region: 'Schleswig-Holstein', lat: 53.5805, lon: 9.7045, w: 1 },
  { name: 'Altstadt', city: 'Buxtehude', region: 'Niedersachsen', lat: 53.4772, lon: 9.6995, w: 1 },
  { name: 'Schlossgarten', city: 'Reinbek', region: 'Schleswig-Holstein', lat: 53.5108, lon: 10.2485, w: 1 },
  { name: 'Marktplatz', city: 'Winsen (Luhe)', region: 'Niedersachsen', lat: 53.3585, lon: 10.2105, w: 1 },
];

/** A place by the start of its name — the showcase birds name theirs. */
export function place(name) {
  const p = PLACES.find((x) => x.name.startsWith(name));
  if (!p) throw new Error(`no place "${name}" in vocab.mjs`);
  return p;
}

// ── Drug catalogue ──────────────────────────────────────────────────────────
// Replaces the migration's three "Medikament n" placeholders. Every product
// name is INVENTED (owner's rule: no real substance or brand on screen) and
// avoids real INN stems (-cillin, -mycin, -floxacin, -azol, -idazol, …), so no
// name reads as a specific real drug. What each one is for is its `note`, the
// line the catalogue shows. Doses are clean demo values chosen so the
// arithmetic is easy to follow on video: every concentration equals the rate,
// so the volume to draw is 1 ml per kg — a 300 g pigeon gets 0.3 ml.
// `route` is the German label of the medication_routes row.
export const PRODUCTS = {
  painRelief: { label: { de: 'Plumadol', en: 'Plumadol' }, note: { de: 'Schmerzmittel', en: 'Pain relief' },
    dose_unit: 'mg', dose_rate: 2, rate_min: 1, rate_max: 4, concentration_per_ml: 2, route: 'Oral',
    frequency_kind: 'scheduled', interval_hours: 24 },
  antibiotic: { label: { de: 'Peravin', en: 'Peravin' }, note: { de: 'Antibiotikum', en: 'Antibiotic' },
    dose_unit: 'mg', dose_rate: 10, rate_min: 5, rate_max: 20, concentration_per_ml: 10, route: 'Oral',
    frequency_kind: 'scheduled', interval_hours: 12 },
  antiprotozoal: { label: { de: 'Faucalin', en: 'Faucalin' }, note: { de: 'Mittel gegen Trichomonaden', en: 'Against trichomonads' },
    dose_unit: 'mg', dose_rate: 20, rate_min: 10, rate_max: 40, concentration_per_ml: 20, route: 'Oral',
    frequency_kind: 'scheduled', interval_hours: 12 },
  antifungal: { label: { de: 'Brontalis', en: 'Brontalis' }, note: { de: 'Antimykotikum', en: 'Antifungal' },
    dose_unit: 'mg', dose_rate: 10, rate_min: 5, rate_max: 20, concentration_per_ml: 10, route: 'Oral',
    frequency_kind: 'scheduled', interval_hours: 24 },
  // The give/pause rhythm: "three rounds of 5 on / 2 off" is the standard
  // deworming course named in 1700000091.
  dewormer: { label: { de: 'Nemakur', en: 'Nemakur' }, note: { de: 'Wurmkur', en: 'Dewormer' },
    dose_unit: 'mg', dose_rate: 10, rate_min: 5, rate_max: 20, concentration_per_ml: 10, route: 'Oral',
    frequency_kind: 'scheduled', interval_hours: 24, cycle_on_days: 5, cycle_off_days: 2, cycle_repeats: 3 },
  // A kind of fluid, not a product name.
  fluids: { label: { de: 'Vollelektrolytlösung', en: 'Balanced electrolyte solution' }, note: { de: 'Flüssigkeitsersatz', en: 'Fluid replacement' },
    dose_unit: 'ml', dose_rate: 20, rate_min: 10, rate_max: 50, route: 'Subkutan', frequency_kind: 'as_needed' },
};

// ── Vaccines ────────────────────────────────────────────────────────────────
// Free text in the app; the pair (vaccine, target) is what the vaccine_labels
// view offers back, so picking a product prefills its target. Product names
// invented (as above); the targets are the real diseases.
export const VACCINES = {
  pmv: { vaccine: { de: 'Sentinova PMV', en: 'Sentinova PMV' },
    target: { de: 'Paramyxovirose (PMV-1)', en: 'Paramyxovirus (PMV-1)' }, dose: 0.2, dose_unit: 'ml', route: 'Subkutan' },
  pox: { vaccine: { de: 'Sentinova Pocken', en: 'Sentinova Pox' },
    target: { de: 'Taubenpocken', en: 'Pigeon pox' }, route: 'Sonstige' },
};

// ── People and places outside the org ───────────────────────────────────────
// Invented names. No real practice, station or person is meant.
export const VETS = {
  deich: 'Vogelpraxis am Deich',
  lindenhof: 'Kleintierpraxis Lindenhof',
};

export const DESTINATIONS = {
  raptors: { de: 'Greifvogelhilfe Heidemoor', en: 'Greifvogelhilfe Heidemoor' },
  water: { de: 'Wasservogelstation Alsterwiesen', en: 'Wasservogelstation Alsterwiesen' },
  swifts: { de: 'Mauerseglerhilfe Geestrand', en: 'Mauerseglerhilfe Geestrand' },
};

export const TRANSFER_TYPES = {
  specialist: { de: 'Fachstation', en: 'Specialist centre' },
  clinic: { de: 'Tierklinik', en: 'Veterinary clinic' },
};

export const RELEASE_TYPES = {
  hard: { de: 'Direkte Freilassung', en: 'Hard release' },
  soft: { de: 'Sanfte Auswilderung', en: 'Soft release' },
};

// ── The organisation ────────────────────────────────────────────────────────
// 040 66969 xxx is the Hamburg block the Bundesnetzagentur keeps for film and
// TV (owner checklist: confirm before publishing); .example is reserved.
export const ORG_CONTACT = { email: 'kontakt@wildvogelhilfe.example', phone: '040 66969 100' };
export const ORG_SETTINGS = { quarantineDefaultDays: 14, finderRetentionMonths: 24 };
export const phone = (n) => `040 66969 ${String(n).padStart(3, '0')}`;
