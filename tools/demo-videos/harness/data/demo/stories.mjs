// The showcase birds: a small cast whose histories the videos walk through.
// Every step is scheduled at the moment it happened, relative to the run day
// (day 0; -12 = twelve days ago), as the person who did it. The README's
// catalogue says what each bird is for; cast.mjs holds the names.
//
//   carer = Lena Vogt (also keeps the pigeon loft)    carer2 = Tarek Aydin
//   coordinator = Malte Riedel (keeps the outdoor aviary)    supervisor = Johanna Brandt
import { FINDERS, RINGS, SPONSORS, BIRDS, WEIGHTS } from './cast.mjs';
import { Rng } from './rng.mjs';
import { DESTINATIONS, place, PRODUCTS, RELEASE_TYPES, TRANSFER_TYPES, VETS } from './vocab.mjs';

const LENA = 'carer';
const TAREK = 'carer2';
const MALTE = 'coordinator';

export function scheduleStories(ctx) {
  const c = ctx.clock;
  const d = (day, hm) => c.ms(day, hm);
  const step = (ms, label, fn) => ctx.at(ms, label, fn);
  const bird = (key) => ({ name: BIRDS[key].name, species: BIRDS[key].species, sex: BIRDS[key].sex, animalKey: key });

  // Daily weights: [[day, 'HH:MM', grams], …]
  const weighings = (role, caseKey, list) => {
    for (const [day, hm, g] of list) step(d(day, hm), `${caseKey}: weight`, () => ctx.weigh(role, caseKey, d(day, hm), g));
  };
  // Doses of one plan: [[day, 'HH:MM', role?], …]
  const doses = (medKey, role, list) => {
    for (const [day, hm, who] of list) step(d(day, hm), `${medKey}: dose`, () => ctx.give(who ?? role, medKey, d(day, hm)));
  };

  // ════════════════════════════════════════════════════════════════════════
  // The pigeon loft (kept by Lena) and its residents
  // ════════════════════════════════════════════════════════════════════════

  // ── Erna: permanent resident, lays eggs, patronage ending in the future ──
  step(d(-520, '10:15'), 'erna: intake', () => ctx.intake(LENA, 'erna0', {
    ...bird('erna'), ms: d(-520, '10:15'), reasons: ['Verletzung'], age: 'adult', place: place('Altonaer Volkspark'),
    weight: 286, photos: ['photo-feral-pigeon-2'],
    notes: { de: 'Rechter Flügel hängt, kann nicht fliegen.', en: 'Right wing droops, unable to fly.' },
  }));
  step(d(-520, '11:00'), 'erna: fracture', () => ctx.condition(LENA, 'erna0', 'Fraktur (Knochenbruch)', {
    onset: d(-520, '10:15'), notes: { de: 'Rechter Flügel', en: 'Right wing' } }));
  step(d(-505, '18:00'), 'erna: journal', () => ctx.journal(LENA, { case: 'erna0' }, d(-505, '18:00'), {
    de: 'Der Bruch ist schief verheilt, Erna wird nicht mehr fliegen können. Sie bleibt bei uns.',
    en: 'The fracture has healed out of line; Erna will not fly again. She is staying with us.' }));
  step(d(-470, '09:00'), 'erna: into the loft', () => ctx.dispose(LENA, 'erna0', d(-470, '09:00'), 'placed_in_aviary', {
    aviary: 'loft', reason: { de: 'Nicht auswilderbar (Flügel)', en: 'Not releasable (wing)' } }));
  step(d(-455, '17:00'), 'erna: PMV primary', () => ctx.vaccinate(LENA, 'erna', 'pmv', d(-455, '17:00'), {
    series: 'primary', batch: 'PMV-2507-114', vet: VETS.deich }));

  // ── Hinkebein: resident since last year; now ill, in Tarek's care ───────
  step(d(-470, '15:30'), 'hinkebein: intake', () => ctx.intake(LENA, 'hinkebein0', {
    ...bird('hinkebein'), ms: d(-470, '15:30'), reasons: ['Verheddert', 'Geschwächt/abgemagert'], age: 'adult',
    place: place('Hauptbahnhof'), weight: 262,
    notes: { de: 'Beide Füße mit Haaren und Fäden abgeschnürt.', en: 'Both feet constricted by hair and thread.' },
  }));
  step(d(-470, '16:00'), 'hinkebein: string foot', () => ctx.condition(LENA, 'hinkebein0', 'Fadenfuß (Haarstrangulation)', {
    onset: d(-470, '15:30'), resolved: d(-445, '12:00'), notes: { de: 'Links zwei Zehen verloren', en: 'Lost two toes on the left foot' } }));
  step(d(-440, '19:00'), 'hinkebein: journal', () => ctx.journal(LENA, { case: 'hinkebein0' }, d(-440, '19:00'), {
    de: 'Der Fuß ist verheilt, aber draußen kann sich Hinkebein nicht sicher halten. Er bleibt im Taubenschlag.',
    en: "The foot has healed, but Hinkebein can't perch safely outdoors. He is staying in the pigeon loft." }));
  step(d(-430, '10:00'), 'hinkebein: into the loft', () => ctx.dispose(LENA, 'hinkebein0', d(-430, '10:00'), 'placed_in_aviary', {
    aviary: 'loft', reason: { de: 'Nicht auswilderbar (Füße)', en: 'Not releasable (feet)' } }));
  step(d(-420, '17:00'), 'hinkebein: PMV primary', () => ctx.vaccinate(LENA, 'hinkebein', 'pmv', d(-420, '17:00'), {
    series: 'primary', batch: 'PMV-2509-087', vet: VETS.deich }));
  step(d(-410, '12:00'), 'hinkebein: patronage Petersen', () => ctx.sponsor(LENA, 'hinkebein', 'petersen', SPONSORS.petersen, {
    cents: 1500, interval: 'monthly', start: d(-410, '00:00'),
    notes: { de: 'Besuchen Hinkebein gern sonntags.', en: 'Like to visit Hinkebein on Sundays.' } }));

  // ── Frieda: resident; her patronage has ENDED ───────────────────────────
  step(d(-400, '13:00'), 'frieda: intake', () => ctx.intake(LENA, 'frieda0', {
    ...bird('frieda'), ms: d(-400, '13:00'), reasons: ['Katzenangriff'], age: 'adult', place: place('Wehbers Park'),
    weight: 148, photos: ['photo-collared-dove'],
    notes: { de: 'Von einer Katze gebracht, Schwanzfedern fehlen, Flügel verletzt.', en: 'Brought in from a cat, tail feathers missing, wing injured.' },
  }));
  step(d(-400, '13:30'), 'frieda: cat bite', () => ctx.condition(LENA, 'frieda0', 'Katzenbiss', { onset: d(-400, '13:00'), resolved: d(-385, '12:00') }));
  step(d(-360, '10:00'), 'frieda: into the loft', () => ctx.dispose(LENA, 'frieda0', d(-360, '10:00'), 'placed_in_aviary', {
    aviary: 'loft', reason: { de: 'Nicht auswilderbar (fliegt zu unsicher)', en: 'Not releasable (flies too poorly)' } }));
  step(d(-330, '12:00'), 'frieda: patronage Lorenz', () => ctx.sponsor(LENA, 'frieda', 'lorenz', SPONSORS.lorenz, {
    cents: 1000, interval: 'monthly', start: d(-330, '00:00') }));
  step(d(-90, '12:00'), 'frieda: patronage ends', () => ctx.update(LENA, 'sponsorships', ctx.ids.sponsorships.lorenz, {
    ended_at: ctx.iso(d(-90, '00:00')), notes: ctx.L({ de: 'Auf Wunsch der Patin beendet.', en: "Ended at the sponsor's request." }) }));

  // ── Kalle: crow, permanent resident of the outdoor aviary (Malte) ───────
  step(d(-380, '14:00'), 'kalle: intake', () => ctx.intake(MALTE, 'kalle0', {
    ...bird('kalle'), ms: d(-380, '14:00'), reasons: ['Verletzung'], age: 'adult', place: place('Ohlsdorfer Friedhof'),
    weight: 468, photos: ['photo-crow'],
    notes: { de: 'Linke Flügelspitze fehlt, alte Verletzung.', en: 'Left wingtip missing, an old injury.' },
  }));
  step(d(-380, '14:30'), 'kalle: trauma', () => ctx.condition(MALTE, 'kalle0', 'Weichteiltrauma', { onset: d(-380, '14:00'), resolved: d(-350, '12:00') }));
  step(d(-330, '11:00'), 'kalle: into the outdoor aviary', () => ctx.dispose(MALTE, 'kalle0', d(-330, '11:00'), 'placed_in_aviary', {
    aviary: 'outdoor', reason: { de: 'Dauerhaft flugunfähig', en: 'Permanently unable to fly' } }));
  step(d(-300, '12:00'), 'kalle: patronage Jansen', () => ctx.sponsor(MALTE, 'kalle', 'jansen', SPONSORS.jansen, {
    cents: 12000, interval: 'yearly', start: d(-300, '00:00') }));

  // ── Erna's patronage, Brockmann's one-off gift for Hinkebein ────────────
  step(d(-290, '12:00'), 'erna: patronage Kita', () => ctx.sponsor(LENA, 'erna', 'kita', SPONSORS.kita, {
    cents: 3000, interval: 'quarterly', start: d(-290, '00:00'), end: d(75, '00:00'),
    notes: { de: 'Patenschaft der Kita-Gruppe, auf ein Jahr befristet. Urkunde verschickt.', en: 'Sponsored by the nursery group for one year. Certificate sent.' } }));
  step(d(-245, '12:00'), 'hinkebein: gift Brockmann', () => ctx.sponsor(LENA, 'hinkebein', 'brockmann', SPONSORS.brockmann, {
    cents: 5000, interval: 'one_time', start: d(-245, '00:00') }));

  // ── Ole: lived in the loft before release; his patronage still runs ─────
  step(d(-250, '09:40'), 'ole: intake', () => ctx.intake(LENA, 'ole0', {
    ...bird('ole'), ms: d(-250, '09:40'), reasons: ['Geschwächt/abgemagert'], age: 'immature', place: place('Hansaplatz'),
    weight: 244, notes: { de: 'Jungtaube, fliegt noch nicht richtig.', en: 'Young pigeon, not flying properly yet.' },
  }));
  step(d(-210, '10:00'), 'ole: into the loft', () => ctx.dispose(LENA, 'ole0', d(-210, '10:00'), 'placed_in_aviary', {
    aviary: 'loft', reason: { de: 'Im Schwarm aufbauen vor der Auswilderung', en: 'Building up in the flock before release' } }));

  // ── Gustav (feral pigeon), first stay: released in spring wearing our ring ─
  step(d(-214, '16:20'), 'gustav: first intake', () => ctx.intake(LENA, 'gustav1', {
    ...bird('gustav'), ms: d(-214, '16:20'), reasons: ['Kollision'], age: 'adult', place: place('Stadtpark'),
    weight: 284, finder: FINDERS.gustav, photos: ['photo-feral-pigeon-3'],
    notes: { de: 'Gegen eine Scheibe geflogen, benommen.', en: 'Flew into a window, dazed.' },
  }));
  step(d(-214, '17:00'), 'gustav: head trauma', () => ctx.condition(LENA, 'gustav1', 'Kopftrauma', { onset: d(-214, '16:20'), resolved: d(-205, '12:00') }));
  weighings(LENA, 'gustav1', [[-210, '08:00', 290], [-203, '08:00', 301], [-196, '08:00', 309], [-189, '08:00', 316]]);
  step(d(-186, '10:00'), 'gustav: release ring', () => ctx.marking(LENA, 'gustav', {
    case: 'gustav1', type: 'Auswilderungsring', code: RINGS.gustav, ms: d(-186, '10:00'),
    colour: { de: 'Aluminium', en: 'Aluminium' }, scheme: { de: 'Wildvogelhilfe Elbmarsch', en: 'Elbmarsch Wild Bird Rescue' } }));
  step(d(-185, '11:00'), 'gustav: released', () => ctx.dispose(LENA, 'gustav1', d(-185, '11:00'), 'released', {
    release: place('Stadtpark'), releaseType: RELEASE_TYPES.hard,
    reason: { de: 'Gesund, fliegt sicher', en: 'Healthy, flying well' } }));

  // ── The loft vaccinated in one act, then single shots ───────────────────
  step(d(-180, '17:00'), 'loft: PMV booster for the flock', () => ctx.vaccinateBatch(LENA, ['hinkebein', 'erna', 'frieda', 'ole'], 'pmv', d(-180, '17:00'), {
    series: 'booster', batch: 'PMV-2604-208', nextDue: d(185, '12:00'),
    notes: { de: 'Jährliche Auffrischung vor der Brutsaison.', en: 'Yearly booster before the breeding season.' } }));
  step(d(-175, '17:30'), 'erna: pox vaccine', () => ctx.vaccinate(LENA, 'erna', 'pox', d(-175, '17:30'), {
    series: 'primary', batch: 'TP-2604-031', nextDue: d(190, '12:00') }));

  // ── Ole's patronage, Tjark added to the outdoor aviary ──────────────────
  step(d(-160, '12:00'), 'ole: patronage Albers', () => ctx.sponsor(LENA, 'ole', 'albers', SPONSORS.albers, {
    cents: 2000, interval: 'monthly', start: d(-160, '00:00') }));
  step(d(-200, '15:00'), 'tjark: added as a resident', () => ctx.addResident(MALTE, 'tjark', 'outdoor', d(-200, '15:00'), {
    ...bird('tjark'), photos: ['photo-jackdaw'],
    notes: { de: 'Handaufgezogen und auf Menschen geprägt, von Privatleuten abgegeben.', en: 'Hand-reared and imprinted on people; handed in by a private keeper.' } }));
  step(d(-75, '12:00'), 'tjark: patronage school class', () => ctx.sponsor(MALTE, 'tjark', 'schule', SPONSORS.schule, {
    cents: 500, interval: 'monthly', start: d(-75, '00:00'),
    notes: { de: 'Die Klasse sammelt jeden Monat im Klassenzimmer.', en: 'The class collects in the classroom every month.' } }));

  // ── Erna's laying history (B8) ──────────────────────────────────────────
  const clutches = [[-150, 2, 'dummy_swapped'], [-118, 2, 'dummy_swapped'], [-88, 2, 'dummy_swapped'],
    [-62, 1, 'broken'], [-34, 2, 'dummy_swapped']];
  for (const [day, count, fate] of clutches) {
    step(d(day, '08:30'), 'erna: eggs', () => ctx.egg(LENA, 'erna', d(day, '08:30'), { count, fate }));
  }
  step(d(-6, '08:15'), 'erna: eggs with photo', () => ctx.egg(LENA, 'erna', d(-6, '08:15'), {
    count: 2, fate: 'dummy_swapped', notes: { de: 'Gegen Gipseier getauscht.', en: 'Swapped for dummy eggs.' } }, ['photo-eggs']));

  // ── Residents are weighed now and then by their keeper (no case) ───────
  const residentWeights = (role, key, from, to, every, lo, hi) => {
    const rng = new Rng(`weights-${key}`);
    for (let day = from; day <= to; day += every + rng.int(-4, 4)) {
      const g = rng.int(lo, hi);
      step(d(day, '09:30'), `${key}: resident weight`, () => ctx.weighAnimal(role, key, d(day, '09:30'), g));
    }
  };
  // Quarterly: enough for a curve, few enough that the vaccination and
  // patronage cards below the weights stay within reach on the animal page.
  residentWeights(LENA, 'erna', -380, -10, 90, 298, 312);
  residentWeights(LENA, 'hinkebein', -340, -14, 90, 304, 316);
  residentWeights(LENA, 'frieda', -300, -12, 90, 164, 176);
  residentWeights(LENA, 'ole', -150, -40, 55, 330, 352);
  residentWeights(MALTE, 'kalle', -280, -8, 90, 515, 545);
  residentWeights(MALTE, 'tjark', -170, -5, 80, 232, 248);
  residentWeights(MALTE, 'smilla', -9, -2, 7, 216, 224);

  // ── Flock logs ──────────────────────────────────────────────────────────
  const loftLog = [
    [-40, '18:00', { de: 'Neue Sitzbretter und zwei Nistschalen eingebaut.', en: 'Fitted new perches and two nest bowls.' }],
    [-21, '12:00', { de: 'Ole ausgewildert. Im Schlag ist es ruhiger geworden.', en: 'Ole released. The loft has got quieter.' }],
    [-10, '16:30', { de: 'Großputz, Boden neu eingestreut, Tränken desinfiziert.', en: 'Big clean: fresh litter on the floor, drinkers disinfected.' }],
    [-6, '12:00', { de: 'Hinkebein mit Atemproblemen zu Tarek. Die anderen sind unauffällig, Schlag weiter beobachten.', en: 'Hinkebein has gone to Tarek with breathing trouble. The others look fine; keeping an eye on the loft.' }],
    [-1, '18:30', { de: 'Erna brütet auf den Gipseiern und vermisst Hinkebein sichtlich.', en: 'Erna is sitting on the dummy eggs and clearly misses Hinkebein.' }],
  ];
  for (const [day, hm, text] of loftLog) step(d(day, hm), 'loft: flock log', () => ctx.journal(LENA, { aviary: 'loft' }, d(day, hm), text));
  const outdoorLog = [
    [-30, '17:00', { de: 'Netz an der Nordseite geflickt.', en: 'Patched the netting on the north side.' }],
    [-12, '11:00', { de: 'Smilla eingezogen, ab morgen Flugtraining.', en: 'Smilla moved in; flight training starts tomorrow.' }],
    [-3, '17:30', { de: 'Kalle und Tjark vertragen sich mit Smilla, keine Rangeleien.', en: 'Kalle and Tjark get on with Smilla, no squabbles.' }],
  ];
  for (const [day, hm, text] of outdoorLog) step(d(day, hm), 'outdoor: flock log', () => ctx.journal(MALTE, { aviary: 'outdoor' }, d(day, hm), text));

  // ════════════════════════════════════════════════════════════════════════
  // Ringo: the racing pigeon entered twice (C11)
  // ════════════════════════════════════════════════════════════════════════
  step(d(-500, '13:00'), 'ringo: intake', () => ctx.intake(TAREK, 'ringo0', {
    ...bird('ringo'), ms: d(-500, '13:00'), foundMs: d(-500, '11:30'), reasons: ['Geschwächt/abgemagert'], age: 'adult',
    place: place('Altonaer Volkspark'), weight: 351,
    notes: { de: 'Brieftaube mit Verbandsring, erschöpft.', en: 'Racing pigeon with a club ring, exhausted.' },
  }));
  step(d(-500, '13:20'), 'ringo: club ring (found with it)', () => ctx.marking(TAREK, 'ringo', {
    case: 'ringo0', type: 'Vereinsring', code: RINGS.ringo, ms: d(-500, '11:30'), presentAtFind: true }));
  step(d(-497, '17:00'), 'ringo: back to its owner', () => ctx.dispose(TAREK, 'ringo0', d(-497, '17:00'), 'returned_to_owner', {
    reason: { de: 'Halter über den Ring ermittelt, abgeholt', en: 'Owner traced via the ring, collected' } }));

  step(d(-8, '12:00'), 'ringo again, not recognised: intake', () => ctx.intake(MALTE, 'ringoDuplicate', {
    ...bird('ringoDuplicate'), ms: d(-8, '12:00'), foundMs: d(-8, '11:00'), reasons: ['Geschwächt/abgemagert'], age: 'adult',
    place: place('Rathausmarkt'), weight: 344,
    notes: { de: 'Brieftaube mit Ring, saß erschöpft vor dem Rathaus.', en: 'Racing pigeon with a ring, sitting exhausted outside the town hall.' },
  }));
  step(d(-8, '12:15'), 'ringo again: club ring', () => ctx.marking(MALTE, 'ringoDuplicate', {
    case: 'ringoDuplicate', type: 'Vereinsring', code: RINGS.ringo, ms: d(-8, '11:00'), presentAtFind: true }));
  weighings(MALTE, 'ringoDuplicate', [[-6, '09:00', 352], [-3, '09:00', 363], [-1, '09:00', 371]]);
  step(d(-7, '10:00'), 'ringo again: journal', () => ctx.journal(MALTE, { case: 'ringoDuplicate' }, d(-7, '10:00'), {
    de: 'Ringnummer an den Verband gemeldet, warte auf Rückmeldung des Halters.', en: 'Reported the ring number to the association; waiting to hear from the owner.' }));

  // ════════════════════════════════════════════════════════════════════════
  // Lena's open cases
  // ════════════════════════════════════════════════════════════════════════

  // ── Fiete: the full timeline (A4, B1–B7, B11, C1) ───────────────────────
  step(d(-12, '18:40'), 'fiete: intake', () => ctx.intake(LENA, 'fiete', {
    ...bird('fiete'), ms: d(-12, '18:40'), foundMs: d(-12, '17:30'), reasons: ['Geschwächt/abgemagert', 'Krankheit'], age: 'adult',
    place: place('Hauptbahnhof'), weight: WEIGHTS.fiete.intake, finder: FINDERS.fiete, photos: ['photo-feral-pigeon'],
    notes: { de: 'Saß teilnahmslos auf dem Bahnsteig, würgt, stark abgemagert.', en: 'Sitting listlessly on the platform, gagging, badly emaciated.' },
  }));
  step(d(-12, '19:00'), 'fiete: intake exam', () => ctx.exam(LENA, 'fiete', d(-12, '19:00'), {
    body_condition: 1, hydration: 'moderate', mentation: 'quiet', mm_color: 'pale', mm_texture: 'tacky',
    notes: { de: 'Brustbein scharf tastbar, Kropf leer.', en: 'Keel sharply palpable, crop empty.' },
  }, [
    ['eyes', 'normal'], ['beak_nares', 'normal'],
    ['oral', 'abnormal', { de: 'Gelbliche Beläge im Rachen', en: 'Yellowish plaques in the throat' }],
    ['integument', 'normal'], ['wings', 'normal'], ['legs_feet', 'normal'],
    ['keel', 'abnormal', { de: 'Stark hervortretend', en: 'Very prominent' }],
    ['respiratory', 'normal'],
    ['vent', 'abnormal', { de: 'Kot grünlich und dünn', en: 'Droppings greenish and loose' }],
  ]));
  step(d(-12, '19:10'), 'fiete: colour clip', () => ctx.marking(LENA, 'fiete', {
    case: 'fiete', type: 'Temporäre Markierung', code: RINGS.fieteClip, ms: d(-12, '19:10'), colour: { de: 'Grün', en: 'Green' } }));
  step(d(-12, '19:20'), 'fiete: crop swab', () => ctx.microscopy(LENA, 'fiete', d(-12, '19:20'), {
    sample_type: 'crop_swab', method: 'direct_smear', examined_by: 'in_house',
    notes: { de: 'Sehr viele bewegliche Geißeltierchen.', en: 'Large numbers of motile flagellates.' },
  }, [['Trichomonaden', 'plus_plus_plus']], ['microscopy-crop-swab']));
  step(d(-12, '19:25'), 'fiete: trichomonosis', () => ctx.condition(LENA, 'fiete', 'Trichomonadose (Gelber Knopf)', {
    onset: d(-12, '18:40'), resolved: d(-5, '09:00'), notes: { de: 'Kropfabstrich positiv', en: 'Crop swab positive' } }));
  step(d(-12, '19:28'), 'fiete: canker treatment', () => ctx.prescribe(LENA, 'fiete', 'fieteCanker', 'antiprotozoal', {
    start: d(-12, '19:30'), end: d(-7, '08:00'), prescribedBy: VETS.deich,
    instructions: { de: 'Mit etwas Wasser direkt in den Schnabel.', en: 'Straight into the beak with a little water.' } }));
  doses('fieteCanker', LENA, [[-12, '19:30'], ...[-11, -10, -9, -8].flatMap((x) => [[x, '07:30'], [x, '19:30']]), [-7, '07:30']]);
  step(d(-12, '20:15'), 'fiete: journal', () => ctx.journal(LENA, { case: 'fiete' }, d(-12, '20:15'), {
    de: 'Kropfabstrich: massenhaft Trichomonaden. Vorerst Päppelfutter per Kropfsonde, Behandlung mit Faucalin begonnen.',
    en: 'Crop swab: masses of trichomonads. Crop-feeding with rearing formula for now; started on Faucalin.' }));
  weighings(LENA, 'fiete', [[-11, '07:20', 236], [-10, '07:20', 241], [-9, '07:20', 248], [-8, '07:20', 255], [-7, '07:20', 259],
    [-6, '07:20', 266], [-5, '07:20', 271], [-4, '07:20', 277], [-3, '07:20', 280], [-2, '07:20', 286], [-1, '07:20', 289], [0, '07:20', WEIGHTS.fiete.latest]]);
  step(d(-10, '09:10'), 'fiete: journal', () => ctx.journal(LENA, { case: 'fiete' }, d(-10, '09:10'), {
    de: 'Pickt die ersten Körner selbst, Sonde nur noch abends. Kot noch grünlich.',
    en: 'Picking up his first seeds himself; crop-feeding only in the evening now. Droppings still greenish.' }));
  step(d(-10, '10:00'), 'fiete: fecal flotation', () => ctx.microscopy(LENA, 'fiete', d(-10, '10:00'), {
    sample_type: 'fecal', method: 'flotation', examined_by: 'in_house',
    notes: { de: 'Sammelkot von zwei Tagen.', en: 'Droppings pooled over two days.' },
  }, [['Spulwurmeier', 'plus_plus'], ['Haarwurmeier', 'plus']], ['microscopy-fecal']));
  step(d(-10, '10:10'), 'fiete: worms', () => ctx.condition(LENA, 'fiete', 'Endoparasiten (Wurmbefall)', {
    onset: d(-10, '10:00'), notes: { de: 'Spul- und Haarwürmer', en: 'Roundworms and capillaria' } }));
  // The give/pause rhythm: 5 days on, 2 off, three rounds (C1).
  step(d(-9, '07:55'), 'fiete: deworming course', () => ctx.prescribe(LENA, 'fiete', 'fieteDeworm', 'dewormer', {
    start: d(-9, '08:00'), end: d(10, '08:00'),
    instructions: { de: 'Morgens nüchtern geben.', en: 'Give in the morning before feeding.' } }));
  doses('fieteDeworm', LENA, [[-9, '08:00'], [-8, '08:00'], [-7, '08:00'], [-6, '08:00'], [-5, '08:00'], [-2, '08:00'], [-1, '08:00']]);
  step(d(-8, '18:30'), 'fiete: journal with photo', () => ctx.journal(LENA, { case: 'fiete' }, d(-8, '18:30'), {
    de: 'Die Beläge im Rachen sind deutlich kleiner. Foto zum Vergleich mit dem Aufnahmetag.',
    en: 'The plaques in the throat are much smaller. Photo to compare with admission day.' }, ['photo-feral-pigeon-2']));
  step(d(-7, '10:00'), 'fiete: vet check', () => ctx.vet(LENA, 'fiete', d(-7, '10:00'), {
    vet: VETS.deich, attendedMs: d(-7, '10:05'),
    reason: { de: 'Kontrolle Rachen, Kotprobe', en: 'Throat check, fecal sample' },
    outcome: { de: 'Rachen frei. Kotprobe: Spul- und Haarwürmer, Entwurmung fortsetzen.', en: 'Throat clear. Fecal test: roundworms and capillaria; continue deworming.' },
  }, ['fecal-report']));
  step(d(-6, '14:00'), 'fiete: journal with PDF', () => ctx.journal(LENA, { case: 'fiete' }, d(-6, '14:00'), {
    de: 'Der Befund der Kotprobe aus der Praxis ist da (Anhang).', en: "The practice's fecal test report is in (attached)." }, ['fecal-report']));
  step(d(-5, '09:00'), 'fiete: crop swab clear', () => ctx.microscopy(LENA, 'fiete', d(-5, '09:00'), {
    sample_type: 'crop_swab', method: 'direct_smear', examined_by: 'in_house',
    notes: { de: 'Keine Trichomonaden mehr nachweisbar.', en: 'No trichomonads detected.' } }, []));
  step(d(-5, '09:15'), 'fiete: second exam', () => ctx.exam(LENA, 'fiete', d(-5, '09:15'), {
    body_condition: 3, hydration: 'normal', mentation: 'bright', mm_color: 'pink', mm_texture: 'moist',
    notes: { de: 'Deutlich kräftiger, Brustmuskulatur baut sich auf.', en: 'Much stronger, breast muscle building up.' },
  }, [['oral', 'normal'], ['keel', 'normal'], ['vent', 'normal'], ['wings', 'normal']]));
  step(d(-2, '10:00'), 'fiete: weekend cover for Tarek', () => ctx.share(LENA, 'fiete', TAREK, 'edit'));
  step(d(-1, '10:00'), 'fiete: clip removed', async () => {
    const api = await ctx.api(LENA);
    const [clip] = await api.list('markings', `filter=${encodeURIComponent(`animal="${ctx.animalId('fiete')}" && code="${RINGS.fieteClip}"`)}`);
    return ctx.update(LENA, 'markings', clip.id, {
      is_active: false, removed_at: ctx.iso(d(-1, '10:00')),
      removed_reason: ctx.L({ de: 'Clip scheuerte am Fuß', en: 'Clip was chafing the foot' }) });
  });
  step(d(-1, '17:45'), 'fiete: journal', () => ctx.journal(LENA, { case: 'fiete' }, d(-1, '17:45'), {
    de: 'Fliegt im Zimmer schon kurze Strecken. Der Kropf leert sich über Nacht vollständig.',
    en: 'Already flying short distances indoors. The crop empties completely overnight.' }));
  step(d(-1, '18:00'), 'fiete: follow-up for today', () => ctx.followUp(LENA, 'fiete', d(0, '09:00'), {
    de: 'Kot für die Kontrolluntersuchung sammeln', en: 'Collect droppings for the re-test' }));
  step(d(-1, '18:05'), 'fiete: final check booked', () => ctx.vet(LENA, 'fiete', d(3, '10:30'), {
    vet: VETS.deich, leadMinutes: 1440,
    reason: { de: 'Abschlusskontrolle vor der Auswilderung', en: 'Final check before release' } }, ['referral']));

  // ── Kora: admitted this morning (fresh intake, quarantine just started) ──
  step(d(0, '07:40'), 'kora: intake', () => ctx.intake(LENA, 'kora', {
    ...bird('kora'), ms: d(0, '07:40'), foundMs: d(0, '07:00'), reasons: ['Verletzung'], age: 'adult', place: place('Jenischpark'),
    weight: 468, finder: FINDERS.kora, photos: ['photo-wood-pigeon'],
    notes: { de: 'Auf dem Weg am Elbhang gefunden, linker Flügel hängt leicht. Aufmerksam.', en: 'Found on the path above the Elbe, left wing droops slightly. Alert.' },
  }));

  // ── Hedwig: quarantine ends today, X-ray check this afternoon ───────────
  step(d(-14, '10:00'), 'hedwig: intake', () => ctx.intake(LENA, 'hedwig', {
    ...bird('hedwig'), ms: d(-14, '10:00'), foundMs: d(-14, '09:15'), reasons: ['Kollision', 'Verletzung'], age: 'immature',
    place: place('Museum der Arbeit'), weight: 497, finder: FINDERS.hedwig, photos: ['photo-crow'],
    notes: { de: 'Von einem Radfahrer gebracht: Zusammenstoß mit einem Bus. Linker Flügel hängt, kein offener Bruch.', en: 'Brought in by a cyclist after a collision with a bus. Left wing droops, no open fracture.' },
  }));
  step(d(-14, '10:30'), 'hedwig: intake exam', () => ctx.exam(LENA, 'hedwig', d(-14, '10:30'), {
    body_condition: 3, hydration: 'mild', mentation: 'bright', mm_color: 'pink', mm_texture: 'moist',
    notes: { de: 'Wehrt sich kräftig, sonst unauffällig.', en: 'Struggles vigorously, otherwise unremarkable.' },
  }, [['wings', 'abnormal', { de: 'Linker Flügel hängt, Knochenreiben tastbar', en: 'Left wing droops, crepitus palpable' }],
    ['eyes', 'normal'], ['legs_feet', 'normal'], ['keel', 'normal'], ['respiratory', 'normal']]));
  // Given at 10:00 every day, so at the run's 09:40 the next one is "due in
  // 1 h" — Today's something-due-soon (README, "Time of day").
  step(d(-13, '09:50'), 'hedwig: pain relief', () => ctx.prescribe(LENA, 'hedwig', 'hedwigPain', 'painRelief', {
    start: d(-13, '10:00'), end: d(1, '10:00'), prescribedBy: VETS.deich }));
  doses('hedwigPain', LENA, Array.from({ length: 13 }, (_, i) => [-13 + i, '10:00']));
  step(d(-13, '11:00'), 'hedwig: X-ray', () => ctx.vet(LENA, 'hedwig', d(-13, '11:00'), {
    vet: VETS.deich, attendedMs: d(-13, '11:05'),
    reason: { de: 'Röntgen linker Flügel', en: 'X-ray, left wing' },
    outcome: { de: 'Geschlossener Bruch, Achterverband angelegt. Röntgenkontrolle in zwei Wochen.', en: 'Closed fracture, figure-of-eight bandage applied. Follow-up X-ray in two weeks.' },
  }, ['xray-wing', 'xray-report']));
  step(d(-13, '11:30'), 'hedwig: fracture', () => ctx.condition(LENA, 'hedwig', 'Fraktur (Knochenbruch)', {
    onset: d(-14, '10:00'), notes: { de: 'Linker Flügel, geschlossen', en: 'Left wing, closed' } }));
  step(d(-13, '13:00'), 'hedwig: journal', () => ctx.journal(LENA, { case: 'hedwig' }, d(-13, '13:00'), {
    de: 'Röntgen: geschlossener Bruch. Verband angelegt, Käfigruhe.', en: 'X-ray: closed fracture. Bandaged, cage rest.' }));
  weighings(LENA, 'hedwig', [[-12, '08:30', 492], [-10, '08:30', 488], [-8, '08:30', 495], [-6, '08:30', 503], [-4, '08:30', 510], [-2, '08:30', 514], [-1, '08:30', 516]]);
  step(d(-7, '19:00'), 'hedwig: journal', () => ctx.journal(LENA, { case: 'hedwig' }, d(-7, '19:00'), {
    de: 'Verband gewechselt. Frisst gut: Insekten, eingeweichtes Hundefutter, gekochtes Ei.', en: 'Bandage changed. Eating well: insects, soaked dog food, boiled egg.' }));
  step(d(-2, '18:00'), 'hedwig: journal', () => ctx.journal(LENA, { case: 'hedwig' }, d(-2, '18:00'), {
    de: 'Sehr wach und lautstark. Hält den Flügel fast wieder gerade.', en: 'Very alert and noisy. Holding the wing almost level again.' }));
  step(d(-2, '18:10'), 'hedwig: X-ray check booked', () => ctx.vet(LENA, 'hedwig', d(0, '15:30'), {
    vet: VETS.deich, leadMinutes: 120, reason: { de: 'Röntgenkontrolle Flügel', en: 'Follow-up X-ray, wing' } }));

  // ── Gustav, second stay: recognised by his ring, 'in care' again (C3) ───
  step(d(-4, '11:15'), 'gustav: back again', () => ctx.intake(LENA, 'gustav', {
    animal: 'gustav', ms: d(-4, '11:15'), foundMs: d(-4, '10:30'), reasons: ['Katzenangriff'], age: 'adult', place: place('Stadtpark'),
    weight: 297,
    notes: { de: 'Wiederfund! Trägt unseren Ring EM 0412. Eine Katze hat ihn erwischt, Bisswunde an der Brust.', en: 'A returner! Wearing our ring EM 0412. Caught by a cat, bite wound on the chest.' },
  }));
  step(d(-4, '11:45'), 'gustav: cat bite', () => ctx.condition(LENA, 'gustav', 'Katzenbiss', { onset: d(-4, '10:30') }));
  step(d(-4, '19:55'), 'gustav: antibiotic', () => ctx.prescribe(LENA, 'gustav', 'gustavAntibiotic', 'antibiotic', {
    start: d(-4, '20:00'), end: d(3, '20:00') }));
  doses('gustavAntibiotic', LENA, [[-4, '20:00'], ...[-3, -2, -1].flatMap((x) => [[x, '08:00'], [x, '20:00']]), [0, '08:00']]);
  weighings(LENA, 'gustav', [[-3, '07:45', 295], [-2, '07:45', 300], [-1, '07:45', 304]]);
  step(d(-2, '19:00'), 'gustav: journal', () => ctx.journal(LENA, { case: 'gustav' }, d(-2, '19:00'), {
    de: 'Wunde sauber und trocken, frisst selbstständig.', en: 'Wound clean and dry, eating on his own.' }));
  step(d(-1, '19:00'), 'gustav: follow-up for today', () => ctx.followUp(LENA, 'gustav', d(0, '12:00'), {
    de: 'Bisswunde kontrollieren', en: 'Check the bite wound' }));

  // ── Bruno, Lotte, Mats: one find, one group course, one dose round ──────
  const group = ['bruno', 'lotte', 'mats'];
  const groupWeights = Object.fromEntries(group.map((k) => [k, [WEIGHTS[k].intake, { bruno: 219, lotte: 238, mats: 224 }[k], WEIGHTS[k].latest]]));
  group.forEach((key, i) => {
    step(d(-4, '14:00') + i * 300_000, `${key}: intake`, () => ctx.intake(LENA, key, {
      ...bird(key), ms: d(-4, '14:00') + i * 300_000, foundMs: d(-4, '12:00'), reasons: ['Krankheit', 'Verwaist (Jungtier)'],
      age: 'fledgling', place: place('Inselpark'), weight: groupWeights[key][0], finder: FINDERS.bruno,
      notes: { de: 'Eine von drei Jungtauben aus einem Abrissgebäude in Wilhelmsburg, alle würgen.', en: 'One of three young pigeons from a building being demolished in Wilhelmsburg; all of them are gagging.' },
    }));
    step(d(-4, '15:30'), `${key}: trichomonosis`, () => ctx.condition(LENA, key, 'Trichomonadose (Gelber Knopf)', { onset: d(-4, '14:00') }));
    weighings(LENA, key, [[-3, '06:45', groupWeights[key][1]], [-1, '06:45', groupWeights[key][2]]]);
  });
  step(d(-4, '15:00'), 'bruno: crop swab', () => ctx.microscopy(LENA, 'bruno', d(-4, '15:00'), {
    sample_type: 'crop_swab', method: 'direct_smear', examined_by: 'in_house',
    notes: { de: 'Stellvertretend für alle drei.', en: 'Taken as representative of all three.' },
  }, [['Trichomonaden', 'plus_plus']], ['microscopy-crop-swab']));
  step(d(-3, '06:55'), 'group: one course for three', async () => {
    const res = await ctx.route(LENA, '/api/federfall/prescribe-batch', {
      cases: group.map((k) => ctx.caseId(k)),
      medication: ctx.planOf(PRODUCTS.antiprotozoal, {
        start: d(-3, '07:00'), end: d(2, '07:00'),
        instructions: { de: 'Alle drei gleichzeitig behandeln.', en: 'Treat all three together.' } }),
    });
    // The route answers with the new rows; map them back by case.
    const rows = await (await ctx.api(LENA)).list('medications',
      `filter=${encodeURIComponent(group.map((k) => `case="${ctx.caseId(k)}"`).join(' || '))}`);
    ctx.meds ??= {};
    for (const key of group) {
      const row = rows.find((r) => r.case === ctx.caseId(key));
      ctx.ids.medications[`${key}Canker`] = row.id;
      ctx.meds[`${key}Canker`] = { product: 'antiprotozoal', caseKey: key, role: LENA };
    }
    return res;
  });
  for (const [day, hm] of [[-3, '07:00'], [-3, '19:00'], [-2, '07:00'], [-2, '19:00'], [-1, '07:00'], [-1, '19:00'], [0, '07:00']]) {
    step(d(day, hm), 'group: dose round', () => ctx.round(LENA, group.map((k) => `${k}Canker`), d(day, hm)));
  }
  step(d(-1, '19:10'), 'bruno: follow-up', () => ctx.followUp(LENA, 'bruno', d(1, '09:00'), {
    de: 'Kropfabstrich wiederholen', en: 'Repeat the crop swab' }));

  // ── Mika: Tarek's bird, handed to Lena for holiday cover (C2) ───────────
  step(d(-9, '16:30'), 'mika: intake', () => ctx.intake(TAREK, 'mika', {
    ...bird('mika'), ms: d(-9, '16:30'), reasons: ['Katzenangriff'], age: 'adult', place: place('Wandsbeker Gehölz'),
    weight: 84, finder: FINDERS.mika, photos: ['photo-blackbird'],
    notes: { de: 'Von einer Katze im Garten erwischt. Federverlust am Rücken, kleine Bisswunde am Flügel.', en: 'Caught by a cat in a garden. Feather loss on the back, small bite wound on the wing.' },
  }));
  step(d(-9, '17:00'), 'mika: cat bite', () => ctx.condition(TAREK, 'mika', 'Katzenbiss', { onset: d(-9, '16:00'), resolved: d(-3, '12:00') }));
  step(d(-9, '17:55'), 'mika: antibiotic', () => ctx.prescribe(TAREK, 'mika', 'mikaAntibiotic', 'antibiotic', {
    start: d(-9, '18:00'), end: d(-4, '18:00') }));
  doses('mikaAntibiotic', TAREK, [[-9, '18:00'], [-8, '06:00'], [-8, '18:00'], [-7, '06:00'], [-7, '18:00'], [-6, '06:00'],
    [-6, '18:00', LENA], [-5, '06:00', LENA], [-5, '18:00', LENA], [-4, '06:00', LENA]]);
  weighings(TAREK, 'mika', [[-8, '07:00', 83], [-7, '07:00', 85]]);
  step(d(-6, '10:00'), 'mika: handed to Lena', () => ctx.handoff(TAREK, 'mika', d(-6, '10:00'), LENA, {
    condition: { de: 'Stabil, frisst selbstständig', en: 'Stable, feeding himself' },
    comments: { de: 'Urlaubsvertretung: Lena übernimmt, solange ich weg bin.', en: 'Holiday cover: Lena takes over while I am away.' } }));
  weighings(LENA, 'mika', [[-5, '07:30', 87], [-3, '07:30', 89], [-1, '07:30', 91]]);
  step(d(-3, '19:00'), 'mika: journal', () => ctx.journal(LENA, { case: 'mika' }, d(-3, '19:00'), {
    de: 'Frisst Mehlwürmer und eingeweichte Rosinen, die Wunde ist gut verheilt.', en: 'Eating mealworms and soaked raisins; the wound has healed well.' }));

  // ── Wilma: died the night after admission (C3) ──────────────────────────
  step(d(-6, '19:30'), 'wilma: intake', () => ctx.intake(LENA, 'wilma', {
    ...bird('wilma'), ms: d(-6, '19:30'), reasons: ['Kollision'], age: 'adult', place: place('Museum der Arbeit'),
    weight: 156, photos: ['photo-collared-dove'],
    notes: { de: 'Gegen ein Fenster geflogen, kann den Kopf nicht halten.', en: 'Flew into a window, cannot hold its head up.' },
  }));
  step(d(-6, '19:50'), 'wilma: head trauma', () => ctx.condition(LENA, 'wilma', 'Kopftrauma', { onset: d(-6, '19:00') }));
  step(d(-5, '06:30'), 'wilma: died', () => ctx.dispose(LENA, 'wilma', d(-5, '06:30'), 'died', {
    reason: { de: 'In der Nacht verstorben (Schädel-Hirn-Trauma).', en: 'Died overnight (head trauma).' } }));

  // ── Ole: out of the loft and released; his patronage now has no keeper ──
  step(d(-21, '09:00'), 'ole: case for the release', () => ctx.intake(LENA, 'ole', {
    animal: 'ole', ms: d(-21, '09:00'), foundMs: d(-21, '09:00'), reasons: ['Sonstiges'], age: 'adult', weight: 352,
    notes: { de: 'Aus dem Taubenschlag, zur Auswilderung.', en: 'From the pigeon loft, for release.' },
  }));
  step(d(-21, '11:00'), 'ole: released', () => ctx.dispose(LENA, 'ole', d(-21, '11:00'), 'released', {
    release: place('Planten un Blomen'), releaseType: RELEASE_TYPES.soft, leavesAviary: true,
    reason: { de: 'Fit, fliegt im Schwarm mit', en: 'Fit, flying with the flock' } }));

  // ── Hinkebein's new case: Lena admits, Tarek treats (C5: his carer
  //    cannot see the patronage) ─────────────────────────────────────────
  step(d(-6, '08:30'), 'hinkebein: ill', () => ctx.intake(LENA, 'hinkebein', {
    animal: 'hinkebein', ms: d(-6, '08:30'), foundMs: d(-6, '08:00'), reasons: ['Krankheit'], age: 'adult', weight: 298,
    notes: { de: 'Atmet mit offenem Schnabel, sitzt aufgeplustert.', en: 'Breathing with an open beak, sitting fluffed up.' },
  }));
  step(d(-6, '11:00'), 'hinkebein: to Tarek', () => ctx.handoff(LENA, 'hinkebein', d(-6, '11:00'), TAREK, {
    condition: { de: 'Atemnot, frisst noch selbst', en: 'Laboured breathing, still eating on his own' },
    comments: { de: 'Tarek hat ein Inhaliergerät und übernimmt die Behandlung.', en: 'Tarek has a nebuliser and is taking over the treatment.' } }));
  step(d(-5, '17:30'), 'hinkebein: exam', () => ctx.exam(TAREK, 'hinkebein', d(-5, '17:30'), {
    body_condition: 3, hydration: 'normal', mentation: 'quiet', mm_color: 'pink', mm_texture: 'moist',
    notes: { de: 'Schwanzwippen bei jedem Atemzug.', en: 'Tail bobbing with every breath.' },
  }, [['respiratory', 'abnormal', { de: 'Atmung angestrengt, Schnabelatmung', en: 'Laboured, open-beak breathing' }],
    ['beak_nares', 'normal'], ['eyes', 'normal'], ['legs_feet', 'abnormal', { de: 'Alte Zehenverluste links', en: 'Old loss of toes on the left' }]]));
  step(d(-5, '17:45'), 'hinkebein: suspected aspergillosis', () => ctx.condition(TAREK, 'hinkebein', 'Aspergillose', {
    certainty: 'suspected', onset: d(-6, '08:00') }));
  step(d(-5, '17:55'), 'hinkebein: antifungal', () => ctx.prescribe(TAREK, 'hinkebein', 'hinkebeinAntifungal', 'antifungal', {
    start: d(-5, '18:00'), end: d(9, '18:00'), prescribedBy: VETS.lindenhof }));
  doses('hinkebeinAntifungal', TAREK, [[-5, '18:00'], [-4, '18:00'], [-3, '18:00'], [-2, '18:00'], [-1, '18:00']]);
  weighings(TAREK, 'hinkebein', [[-5, '17:20', 294], [-3, '08:00', 291], [-1, '08:00', 293]]);
  step(d(-2, '20:00'), 'hinkebein: journal', () => ctx.journal(TAREK, { case: 'hinkebein' }, d(-2, '20:00'), {
    de: 'Inhaliert zweimal täglich, die Atmung ist ruhiger.', en: 'Nebulised twice a day; breathing is calmer.' }));

  // ════════════════════════════════════════════════════════════════════════
  // Tarek's cases
  // ════════════════════════════════════════════════════════════════════════

  // ── Pieps: ready for release ────────────────────────────────────────────
  step(d(-24, '13:10'), 'pieps: intake', () => ctx.intake(TAREK, 'pieps', {
    ...bird('pieps'), ms: d(-24, '13:10'), reasons: ['Katzenangriff'], age: 'immature', place: place('Alma-Wartenberg-Platz'),
    weight: 24, photos: ['photo-sparrow'],
    notes: { de: 'Von einer Katze gebracht, Schwanzfedern fehlen.', en: 'Brought in from a cat, tail feathers missing.' },
  }));
  step(d(-24, '13:30'), 'pieps: feather damage', () => ctx.condition(TAREK, 'pieps', 'Gefiederschaden', { onset: d(-24, '13:00'), resolved: d(-4, '12:00') }));
  weighings(TAREK, 'pieps', [[-22, '08:00', 24.5], [-18, '08:00', 26], [-14, '08:00', 27], [-10, '08:00', 28], [-6, '08:00', 28.5], [-2, '08:00', 29]]);
  step(d(-3, '18:00'), 'pieps: journal', () => ctx.journal(TAREK, { case: 'pieps' }, d(-3, '18:00'), {
    de: 'Die Schwanzfedern sind nachgewachsen, fliegt sicher im Flugkäfig.', en: 'The tail feathers have grown back; flying confidently in the flight cage.' }));
  step(d(-1, '18:00'), 'pieps: ready for release', () => ctx.status(TAREK, 'pieps', 'ready_for_release'));
  step(d(-1, '18:05'), 'pieps: follow-up', () => ctx.followUp(TAREK, 'pieps', d(1, '10:00'), {
    de: 'Am Fundort auswildern, wenn es trocken ist', en: 'Release where she was found, on a dry day' }));

  // ── Tilda: suspected ornithosis — notifiable and contagious (B2, B5) ────
  step(d(-5, '17:00'), 'tilda: intake', () => ctx.intake(TAREK, 'tilda', {
    ...bird('tilda'), ms: d(-5, '17:00'), reasons: ['Krankheit'], age: 'adult', place: place('Hansaplatz'), weight: 276,
    quarantineDays: 21,
    notes: { de: 'Rechtes Auge verklebt, Atemgeräusche, sitzt aufgeplustert.', en: 'Right eye crusted shut, wheezing, sitting fluffed up.' },
  }));
  step(d(-5, '17:20'), 'tilda: exam', () => ctx.exam(TAREK, 'tilda', d(-5, '17:20'), {
    body_condition: 2, hydration: 'mild', mentation: 'quiet', mm_color: 'pink', mm_texture: 'moist',
    notes: { de: 'Ruhig, lässt sich gut untersuchen.', en: 'Quiet, easy to examine.' },
  }, [['eyes', 'abnormal', { de: 'Rechts Bindehautentzündung, verklebt', en: 'Right conjunctivitis, crusted' }],
    ['respiratory', 'abnormal', { de: 'Rasselnde Atemgeräusche', en: 'Rattling breath sounds' }], ['oral', 'normal'], ['keel', 'normal']]));
  step(d(-5, '17:40'), 'tilda: suspected ornithosis', () => ctx.condition(TAREK, 'tilda', 'Ornithose / Chlamydiose', {
    certainty: 'suspected', onset: d(-5, '17:00'),
    notes: { de: 'Tupferproben (Auge, Rachen, Kloake) ans Labor geschickt.', en: 'Swabs (eye, throat, cloaca) sent to the lab.' } }));
  step(d(-5, '18:00'), 'tilda: journal', () => ctx.journal(TAREK, { case: 'tilda' }, d(-5, '18:00'), {
    de: 'Wegen Ornithose-Verdacht getrennt von allen anderen Tauben untergebracht. Beim Versorgen Handschuhe und Maske.',
    en: 'Housed apart from all other pigeons on suspicion of ornithosis. Gloves and mask when handling her.' }));
  step(d(-4, '10:00'), 'tilda: vet', () => ctx.vet(TAREK, 'tilda', d(-4, '10:00'), {
    vet: VETS.lindenhof, attendedMs: d(-4, '10:10'),
    reason: { de: 'Verdacht auf Ornithose, Probenentnahme', en: 'Suspected ornithosis, sampling' },
    outcome: { de: 'Proben ans Labor. Bis zum Befund streng getrennt halten.', en: 'Samples sent to the lab. Keep strictly isolated until the result is in.' } }));
  weighings(TAREK, 'tilda', [[-4, '08:00', 272], [-2, '08:00', 275]]);
  step(d(-2, '08:10'), 'tilda: egg', () => ctx.egg(TAREK, 'tilda', d(-2, '07:30'), {
    count: 1, fate: 'removed', notes: { de: 'Ei entfernt.', en: 'Egg removed.' } }));
  step(d(-2, '09:00'), 'tilda: follow-up', () => ctx.followUp(TAREK, 'tilda', d(2, '10:00'), {
    de: 'Laborbefund Ornithose nachfragen', en: 'Chase the ornithosis lab result' }));

  // ── Momo: released three days ago (C3) ──────────────────────────────────
  step(d(-26, '15:00'), 'momo: intake', () => ctx.intake(TAREK, 'momo', {
    ...bird('momo'), ms: d(-26, '15:00'), reasons: ['Verletzung'], age: 'immature', place: place('Wehbers Park'),
    weight: 78, photos: ['photo-blackbird'],
    notes: { de: 'Kann nicht fliegen, rechter Flügel hängt.', en: "Can't fly, right wing droops." },
  }));
  step(d(-26, '15:30'), 'momo: soft-tissue trauma', () => ctx.condition(TAREK, 'momo', 'Weichteiltrauma', { onset: d(-26, '14:00'), resolved: d(-12, '12:00') }));
  weighings(TAREK, 'momo', [[-24, '08:00', 80], [-19, '08:00', 84], [-14, '08:00', 88], [-8, '08:00', 91], [-4, '08:00', 93]]);
  step(d(-3, '10:30'), 'momo: released', () => ctx.dispose(TAREK, 'momo', d(-3, '10:30'), 'released', {
    release: place('Wehbers Park'), releaseType: RELEASE_TYPES.soft,
    reason: { de: 'Fliegt sicher, gut genährt', en: 'Flying well, in good condition' } }));

  // ── Smilla: training for release in Malte's outdoor aviary ──────────────
  step(d(-30, '12:20'), 'smilla: intake', () => ctx.intake(TAREK, 'smilla', {
    ...bird('smilla'), ms: d(-30, '12:20'), reasons: ['Verletzung'], age: 'immature', place: place('Sternschanzenpark'),
    weight: 198, photos: ['photo-magpie'],
    notes: { de: 'Kann nicht auffliegen, linke Schulter geschwollen.', en: 'Cannot take off, left shoulder swollen.' },
  }));
  step(d(-30, '12:50'), 'smilla: soft-tissue trauma', () => ctx.condition(TAREK, 'smilla', 'Weichteiltrauma', { onset: d(-30, '11:00'), resolved: d(-14, '12:00') }));
  weighings(TAREK, 'smilla', [[-27, '08:00', 201], [-23, '08:00', 207], [-19, '08:00', 211], [-15, '08:00', 214]]);
  step(d(-12, '10:00'), 'smilla: into the outdoor aviary', () => ctx.dispose(TAREK, 'smilla', d(-12, '10:00'), 'placed_in_aviary', {
    aviary: 'outdoor', reason: { de: 'Flugtraining vor der Auswilderung', en: 'Flight training before release' } }));

  // ════════════════════════════════════════════════════════════════════════
  // Malte's
  // ════════════════════════════════════════════════════════════════════════

  // ── Oskar: buzzard, transferred to a raptor centre yesterday (C3) ───────
  step(d(-3, '08:50'), 'oskar: intake', () => ctx.intake(MALTE, 'oskar', {
    ...bird('oskar'), ms: d(-3, '08:50'), reasons: ['Kollision'], age: 'adult', place: place('Drosteipark'), weight: 742,
    notes: { de: 'Am Straßenrand gefunden, vermutlich angefahren. Rechter Flügel hängt.', en: 'Found by the roadside, probably hit by a car. Right wing droops.' },
  }));
  step(d(-3, '09:20'), 'oskar: suspected fracture', () => ctx.condition(MALTE, 'oskar', 'Fraktur (Knochenbruch)', {
    certainty: 'suspected', onset: d(-3, '08:00') }));
  step(d(-1, '11:00'), 'oskar: transferred', () => ctx.dispose(MALTE, 'oskar', d(-1, '11:00'), 'transferred', {
    destination: DESTINATIONS.raptors, transferType: TRANSFER_TYPES.specialist,
    reason: { de: 'Zur Versorgung an die Greifvogelstation', en: 'To the raptor centre for treatment' } }));
}
