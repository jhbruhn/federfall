// The bulk: ordinary, closed cases over last year and this year up to a few
// days ago. They exist for the case browser, the registry, the statistics
// screen and the annual report — no video walks through one of them.
//
// Deterministic: each year is planned in full from a fixed seed (the year is
// part of it) and then cut at the run day, so moving the run day within a
// year only adds or removes cases at the end.
//
// Shape (an urban rescue in northern Germany, as far as a plausible picture
// goes): feral pigeons first by a distance; a spring and summer peak of
// orphaned songbirds and swifts; outcomes and lengths of stay by kind of bird;
// slightly more intakes this year than last, so the comparison says something.
import { Rng } from './rng.mjs';
import { DESTINATIONS, PLACES, RELEASE_TYPES, SPECIES, TRANSFER_TYPES, VETS } from './vocab.mjs';

const PER_YEAR = { last: 214, current: 236 };

// Share of a year's intake per month (Jan … Dec).
const MONTHS = [3.5, 3.5, 5, 8, 13, 16, 15, 11, 8, 6.5, 5.5, 5];

const REASONS = {
  pigeon: [[30, 'Geschwächt/abgemagert'], [16, 'Krankheit'], [15, 'Verletzung'], [10, 'Verheddert'], [10, 'Verwaist (Jungtier)'],
    [8, 'Kollision'], [6, 'Katzenangriff'], [3, 'Gefangen/eingeklemmt']],
  domestic: [[60, 'Geschwächt/abgemagert'], [15, 'Verletzung'], [15, 'Kollision'], [10, 'Sonstiges']],
  swift: [[45, 'Geschwächt/abgemagert'], [35, 'Verwaist (Jungtier)'], [10, 'Kollision'], [10, 'Verletzung']],
  songbird: [[35, 'Verwaist (Jungtier)'], [25, 'Katzenangriff'], [15, 'Kollision'], [15, 'Verletzung'], [10, 'Geschwächt/abgemagert']],
  corvid: [[25, 'Verwaist (Jungtier)'], [30, 'Verletzung'], [15, 'Kollision'], [15, 'Geschwächt/abgemagert'], [5, 'Krankheit'],
    [5, 'Vergiftung'], [5, 'Verheddert']],
  waterfowl: [[30, 'Verletzung'], [20, 'Verheddert'], [25, 'Verwaist (Jungtier)'], [10, 'Verölt'], [10, 'Krankheit'], [5, 'Vergiftung']],
  raptor: [[45, 'Kollision'], [30, 'Verletzung'], [20, 'Geschwächt/abgemagert'], [5, 'Vergiftung']],
};

// Diagnoses that go with a reason; `pigeonOnly` ones only for pigeons/doves.
const CONDITIONS = {
  'Katzenangriff': ['Katzenbiss', 'Weichteiltrauma', 'Gefiederschaden'],
  'Kollision': ['Kopftrauma', 'Fraktur (Knochenbruch)', 'Weichteiltrauma'],
  'Verletzung': ['Fraktur (Knochenbruch)', 'Weichteiltrauma', 'Luxation', 'Augenverletzung'],
  'Geschwächt/abgemagert': ['Abmagerung / Auszehrung', 'Endoparasiten (Wurmbefall)', 'Trichomonadose (Gelber Knopf)', 'Kokzidiose'],
  'Krankheit': ['Trichomonadose (Gelber Knopf)', 'Paramyxovirose (PMV)', 'Taubenpocken', 'Aspergillose', 'Salmonellose (Paratyphose)',
    'Kropfentzündung (Ingluvitis)', 'Ektoparasiten (Federlinge / Milben)'],
  'Verheddert': ['Fadenfuß (Haarstrangulation)', 'Weichteiltrauma'],
  'Gefangen/eingeklemmt': ['Weichteiltrauma', 'Gefiederschaden'],
  'Vergiftung': ['Vergiftung'],
  'Verölt': ['Gefiederschaden'],
  'Verwaist (Jungtier)': ['Abmagerung / Auszehrung', 'Spreizbein'],
};
const PIGEON_ONLY = new Set(['Trichomonadose (Gelber Knopf)', 'Paramyxovirose (PMV)', 'Taubenpocken', 'Fadenfuß (Haarstrangulation)',
  'Salmonellose (Paratyphose)']);

const OUTCOMES = {
  pigeon: [[52, 'released'], [20, 'died'], [13, 'euthanized'], [2, 'transferred']],
  domestic: [[50, 'returned_to_owner'], [30, 'released'], [12, 'died'], [8, 'euthanized']],
  swift: [[55, 'released'], [20, 'died'], [5, 'euthanized'], [20, 'transferred']],
  songbird: [[55, 'released'], [27, 'died'], [12, 'euthanized'], [3, 'transferred']],
  corvid: [[60, 'released'], [15, 'died'], [15, 'euthanized'], [5, 'transferred']],
  waterfowl: [[45, 'released'], [15, 'died'], [15, 'euthanized'], [25, 'transferred']],
  raptor: [[20, 'released'], [10, 'died'], [15, 'euthanized'], [55, 'transferred']],
};

// Days from admission to the outcome.
const STAY = {
  released: { pigeon: [10, 45], domestic: [2, 10], swift: [7, 30], songbird: [12, 38], corvid: [18, 55], waterfowl: [7, 35], raptor: [14, 45] },
  died: [0, 4], euthanized: [0, 2], transferred: [0, 3], returned_to_owner: [1, 7],
};

const REASON_TEXT = {
  released: [{ de: 'Gesund, fliegt sicher', en: 'Healthy, flying well' }, { de: 'Gut genährt, voll befiedert', en: 'Well fed, fully feathered' },
    { de: 'Selbstständig und futterfest', en: 'Independent and feeding well' }],
  died: [{ de: 'In der Nacht verstorben', en: 'Died overnight' }, { de: 'Kurz nach der Aufnahme verstorben', en: 'Died shortly after admission' },
    { de: 'Trotz Behandlung verstorben', en: 'Died despite treatment' }],
  euthanized: [{ de: 'Verletzung nicht behandelbar', en: 'Injury beyond treatment' },
    { de: 'Keine Aussicht auf Auswilderung, starke Schmerzen', en: 'No prospect of release, in severe pain' }],
  transferred: [{ de: 'Zur Fachstation', en: 'To a specialist centre' }],
  returned_to_owner: [{ de: 'Halter über den Ring ermittelt', en: 'Owner traced via the ring' }],
};

// Rescues name their birds; the registry sorts by name, so unnamed birds would
// open it with a page of bare species. A long list keeps repeats rare.
const NAMES = ['Anton', 'Bella', 'Carlo', 'Dora', 'Emil', 'Flocke', 'Gretel', 'Hannes', 'Ida', 'Jette', 'Kuno', 'Lenny', 'Mira', 'Nele',
  'Otto', 'Polly', 'Rosi', 'Sammy', 'Toni', 'Udo', 'Willi', 'Zora', 'Bobby', 'Charly', 'Elli', 'Fritz', 'Henni', 'Ilse', 'Jupp',
  'Kiki', 'Lilo', 'Moritz', 'Nala', 'Olli', 'Paule', 'Rudi', 'Susi', 'Theo', 'Wanda', 'Krümel', 'Fussel', 'Hummel', 'Piet',
  'Hein', 'Knut', 'Meike', 'Juna', 'Finn', 'Lasse', 'Tjorven', 'Frodo', 'Bömmel', 'Wolke', 'Socke', 'Pünktchen', 'Alma', 'Benno',
  'Clara', 'Ede', 'Frieder', 'Gesa', 'Hilde', 'Inka', 'Jakob', 'Leo', 'Marta', 'Nils', 'Oda', 'Pepe', 'Quinn', 'Ronja',
  'Smudo', 'Thea', 'Ulla', 'Vito', 'Wiebke', 'Xaver', 'Yara', 'Zippo', 'Brösel', 'Cosmo', 'Dünni', 'Erbse', 'Fiffi',
  'Gonzo', 'Hops', 'Igor', 'Jojo', 'Keks', 'Lotti', 'Mocca', 'Nemo', 'Pixie', 'Quark', 'Rübe', 'Sternchen', 'Tiffy',
  'Ute', 'Vanille', 'Wuschel', 'Zimt', 'Bonnie', 'Clyde', 'Dobby', 'Eddi', 'Flitzer', 'Grummel', 'Hagen', 'Ivo', 'Janne', 'Kasimir',
  'Luna', 'Nora', 'Okka', 'Pino', 'Rieke', 'Sören', 'Tammo', 'Uwe', 'Vincent', 'Arne', 'Cord', 'Dörte',
  'Enno', 'Fenja', 'Gunnar', 'Hauke', 'Imke', 'Jördis', 'Kerrin', 'Lüder', 'Momme', 'Neele', 'Ocke', 'Pelle', 'Rasmus', 'Silke'];

const CARERS = [[35, 'carer'], [32, 'carer2'], [18, 'coordinator'], [15, 'supervisor']];

function ageFor(rng, group, month, reason) {
  if (reason === 'Verwaist (Jungtier)') return group === 'pigeon' ? rng.weighted([[6, 'squab'], [4, 'fledgling']]) : rng.weighted([[4, 'squab'], [6, 'fledgling']]);
  const season = month >= 5 && month <= 8;
  return rng.weighted([[season ? 3 : 1, 'immature'], [6, 'adult'], [season ? 1 : 0.2, 'fledgling']]);
}

/** One year's plan: [{ms, species, …}] sorted by admission. Pure. */
function planYear(year, count, clock) {
  const rng = new Rng(`federfall-demo-bulk-${year}`);
  const plan = [];
  const total = MONTHS.reduce((a, b) => a + b, 0);
  for (let month = 1; month <= 12; month++) {
    const n = Math.round((count * MONTHS[month - 1]) / total);
    const days = new Date(Date.UTC(year, month, 0)).getUTCDate();
    for (let i = 0; i < n; i++) {
      const day = rng.int(1, days);
      const hm = `${String(rng.int(8, 19)).padStart(2, '0')}:${String(rng.int(0, 11) * 5).padStart(2, '0')}`;
      const choices = Object.entries(SPECIES).filter(([, s]) => !s.months || s.months.includes(month)).map(([k, s]) => [s.share, k]);
      const species = rng.weighted(choices);
      const group = SPECIES[species].group;
      let reasons = REASONS[group];
      if (month < 4 || month > 8) reasons = reasons.filter(([, r]) => r !== 'Verwaist (Jungtier)');
      const reason = rng.weighted(reasons);
      const second = rng.chance(0.15) ? rng.weighted(reasons) : null;
      const age = ageFor(rng, group, month, reason);
      let outcomes = OUTCOMES[group];
      if (reason === 'Verwaist (Jungtier)') outcomes = outcomes.map(([w, o]) => [o === 'released' ? w * 1.5 : w, o]);
      const outcome = rng.weighted(outcomes);
      const [lo, hi] = Array.isArray(STAY[outcome]) ? STAY[outcome] : STAY[outcome][group];
      const stayDays = rng.int(lo, hi);
      const [wLo, wHi] = SPECIES[species].weight;
      const juvenile = age === 'squab' || age === 'fledgling';
      const weight = Math.round(rng.float(wLo, wHi) * (juvenile ? rng.float(0.45, 0.8) : 1) * (wHi < 50 ? 10 : 1)) / (wHi < 50 ? 10 : 1);
      const p = rng.weighted(PLACES.map((x) => [x.w, x]));
      const conds = [];
      const pool = (CONDITIONS[reason] ?? []).filter((c) => group === 'pigeon' || !PIGEON_ONLY.has(c));
      if (pool.length && rng.chance(0.72)) conds.push(rng.pick(pool));
      if (pool.length > 1 && rng.chance(0.15)) {
        const extra = rng.pick(pool);
        if (!conds.includes(extra)) conds.push(extra);
      }
      // Ornithosis is rare and notifiable: one or two a year.
      if (group === 'pigeon' && reason === 'Krankheit' && rng.chance(0.08)) conds.push('Ornithose / Chlamydiose');
      plan.push({
        ms: clock.calendar(year, month, day, hm), species, group, reasons: second && second !== reason ? [reason, second] : [reason],
        age, outcome, stayDays, endHm: `${String(rng.int(8, 19)).padStart(2, '0')}:${String(rng.int(0, 11) * 5).padStart(2, '0')}`,
        weight, place: p, lat: p.lat + rng.float(-0.0012, 0.0012), lon: p.lon + rng.float(-0.002, 0.002),
        name: rng.pick(NAMES), carer: rng.weighted(CARERS),
        conditions: conds, confirmed: rng.chance(0.75), reasonText: rng.pick(REASON_TEXT[outcome]),
        release: rng.chance(0.6) ? p : rng.weighted(PLACES.map((x) => [x.w, x])), releaseType: rng.chance(0.7) ? 'hard' : 'soft',
        vet: rng.chance(0.5) ? VETS.deich : VETS.lindenhof,
        destination: group === 'raptor' ? 'raptors' : group === 'swift' ? 'swifts' : group === 'waterfowl' ? 'water' : 'raptors',
        sex: group === 'pigeon' && rng.chance(0.5) ? rng.pick(['male', 'female']) : 'unknown',
      });
    }
  }
  return plan.sort((a, b) => a.ms - b.ms);
}

/** Schedules the bulk into [ctx]; returns {cases}. */
export function scheduleBulk(ctx) {
  const c = ctx.clock;
  const lastAdmission = c.ms(-4, '00:00');
  const lastOutcome = c.ms(-2, '20:00');
  const plans = [
    ...planYear(c.year - 1, PER_YEAR.last, c),
    ...planYear(c.year, PER_YEAR.current, c).filter((p) => p.ms < lastAdmission),
  ];
  plans.forEach((p, i) => {
    const key = `bulk${i}`;
    let end = p.ms + p.stayDays * 86_400_000;
    // Same-day outcomes still come after the admission.
    const endDay = c.dayOffsetOf(end);
    end = Math.max(c.ms(endDay, p.endHm), p.ms + 2 * 3_600_000);
    if (end > lastOutcome) end = lastOutcome;
    ctx.at(p.ms, `${key}: intake`, () => ctx.intake(p.carer, key, {
      species: p.species, name: p.name, sex: p.sex, ms: p.ms, foundMs: p.ms - 2 * 3_600_000, reasons: p.reasons, age: p.age,
      place: p.place, lat: p.lat, lon: p.lon, weight: p.weight,
    }));
    p.conditions.forEach((de, j) => {
      const at = Math.min(p.ms + (30 + j) * 60_000, end - 60_000);
      ctx.at(at, `${key}: condition`, () => ctx.condition(p.carer, key, de, {
        certainty: p.confirmed ? 'confirmed' : 'suspected', onset: p.ms,
        resolved: p.outcome === 'released' && p.confirmed ? end - 86_400_000 : null,
      }));
    });
    ctx.at(end, `${key}: outcome`, () => ctx.dispose(p.carer, key, end, p.outcome, {
      reason: p.reasonText,
      ...(p.outcome === 'released' ? { release: p.release, releaseType: RELEASE_TYPES[p.releaseType] } : {}),
      ...(p.outcome === 'transferred' ? { destination: DESTINATIONS[p.destination], transferType: TRANSFER_TYPES.specialist } : {}),
      ...(p.outcome === 'euthanized' ? { vet: p.vet, vetSignedOff: true } : {}),
    }));
  });
  return { cases: plans.length };
}
