// The demo dataset's names — an INTERFACE. Videos select rows by these names
// (`s.role('button', BIRDS.fiete.name, { startsWith: true })`), so import them
// from here rather than spelling them again; renaming one here renames it
// everywhere. What each bird is FOR is in the README ("Demo dataset").
//
// All people, sponsors and finders are invented; e-mail addresses use the
// reserved .example domain, phone numbers the drama block (vocab.mjs, phone()).
import { phone } from './vocab.mjs';

/** People beyond the base four (data/base.mjs, PEOPLE). Keys work as `signInAs`. */
export const DEMO_PEOPLE = {
  // Signed up through OAuth2 and is waiting for a supervisor to give them a
  // role — the awaiting-access screen (A2) and the promotion (C8).
  guest: { role: 'guest', name: 'Sven Kröger', email: 'sven.kroeger@wildvogelhilfe.example' },
};

export const AVIARIES = {
  // Kept by Lena (the carer who is also a keeper): the permanent pigeons and
  // their patronages.
  loft: { keeper: 'carer', capacity: 10,
    name: { de: 'Taubenschlag', en: 'Pigeon loft' },
    location: { de: 'Hof, hinter der Scheune', en: 'Yard, behind the barn' },
    notes: { de: 'Für Tauben, die nicht mehr ausgewildert werden können.', en: 'For pigeons that can no longer be released.' } },
  // Kept by Malte (coordinator): corvids, and birds training for release.
  outdoor: { keeper: 'coordinator', capacity: 6,
    name: { de: 'Außenvoliere', en: 'Outdoor aviary' },
    location: { de: 'Wiese am Deich', en: 'Meadow by the dyke' },
    notes: { de: 'Flugtraining vor der Auswilderung.', en: 'Flight training before release.' } },
};

/**
 * The showcase birds. `name` is what the app shows (the same in both
 * languages); `species` a key of vocab.mjs SPECIES. Who holds each bird and
 * why is the README's catalogue.
 */
export const BIRDS = {
  fiete: { name: 'Fiete', species: 'feralPigeon', sex: 'male' },
  kora: { name: 'Kora', species: 'woodPigeon', sex: 'female' },
  hedwig: { name: 'Hedwig', species: 'crow', sex: 'unknown' },
  gustav: { name: 'Gustav', species: 'feralPigeon', sex: 'male' },
  bruno: { name: 'Bruno', species: 'feralPigeon', sex: 'unknown' },
  lotte: { name: 'Lotte', species: 'feralPigeon', sex: 'unknown' },
  mats: { name: 'Mats', species: 'feralPigeon', sex: 'unknown' },
  mika: { name: 'Mika', species: 'blackbird', sex: 'male' },
  pieps: { name: 'Pieps', species: 'sparrow', sex: 'female' },
  tilda: { name: 'Tilda', species: 'feralPigeon', sex: 'female' },
  oskar: { name: 'Oskar', species: 'buzzard', sex: 'unknown' },
  momo: { name: 'Momo', species: 'blackbird', sex: 'female' },
  wilma: { name: 'Wilma', species: 'collaredDove', sex: 'unknown' },
  hinkebein: { name: 'Hinkebein', species: 'feralPigeon', sex: 'male' },
  erna: { name: 'Erna', species: 'feralPigeon', sex: 'female' },
  frieda: { name: 'Frieda', species: 'collaredDove', sex: 'female' },
  ole: { name: 'Ole', species: 'feralPigeon', sex: 'male' },
  kalle: { name: 'Kalle', species: 'crow', sex: 'male' },
  tjark: { name: 'Tjark', species: 'jackdaw', sex: 'male' },
  smilla: { name: 'Smilla', species: 'magpie', sex: 'female' },
  // The duplicate pair (C11): the same racing pigeon, entered twice.
  ringo: { name: 'Ringo', species: 'racingPigeon', sex: 'male' },
  ringoDuplicate: { name: '', species: 'racingPigeon', sex: 'unknown' },
};

/**
 * Weights (g) a video narrates, e.g. the dose a per-kg plan works out to.
 * stories.mjs records exactly these, so a caption quoting one cannot drift
 * from the screen. `latest` is the newest weighing before the run instant.
 */
export const WEIGHTS = {
  fiete: { intake: 238, latest: 292 },
  bruno: { intake: 214, latest: 226 },
  lotte: { intake: 236, latest: 243 },
  mats: { intake: 225, latest: 229 },
};

/** Codes on rings the videos search for. */
export const RINGS = {
  // Our release ring on Gustav: how he was recognised on his second admission.
  // The station rings feral pigeons only — never a wild species.
  gustav: 'EM 0412',
  // The club ring the racing pigeon ARRIVED wearing (a found marking, not ours)
  // — on BOTH duplicate records. Deliberately not a valid club-ring number
  // (letters where the club and serial digits go), so it cannot be a real
  // breeder's bird.
  ringo: 'DV-DEMO-001',
  // Fiete's temporary colour clip, since removed (B4).
  fieteClip: 'G7',
};

export const SPONSORS = {
  petersen: { name: 'Familie Petersen', address: 'Musterstraße 12', postal: '20999', city: 'Hamburg', mobile: phone(131) },
  brockmann: { name: 'Ilse Brockmann', pronouns: { de: 'sie/ihr', en: 'she/her' }, address: 'Beispielweg 4', postal: '22999', city: 'Hamburg' },
  // Organisations have names in the run's language; people do not.
  kita: { name: { de: 'Kita Möwennest, Gruppe Seesterne', en: 'Möwennest nursery, Starfish group' }, address: 'Am Musterpark 7', postal: '21999', city: 'Hamburg' },
  jansen: { name: 'Henrik Jansen', pronouns: { de: 'er/ihm', en: 'he/him' }, address: 'Musterallee 23', postal: '22999', city: 'Hamburg', mobile: phone(132) },
  lorenz: { name: 'Anke Lorenz', pronouns: { de: 'sie/ihr', en: 'she/her' }, address: 'Beispielstraße 9', postal: '25999', city: 'Pinneberg' },
  albers: { name: 'Jonas Albers', pronouns: { de: 'er/ihm', en: 'he/him' }, address: 'Musterweg 31', postal: '20999', city: 'Hamburg', mobile: phone(133) },
  schule: { name: { de: 'Grundschule am Deich, Klasse 3b', en: 'Am Deich primary school, class 3b' }, address: 'Schulweg 1', postal: '21999', city: 'Hamburg' },
};

/** Finders of the showcase birds (bulk cases have none). */
export const FINDERS = {
  kora: { first_name: 'Birte', last_name: 'Hansen', phone: phone(117), city: 'Hamburg' },
  fiete: { first_name: 'Mehmet', last_name: 'Yıldız', phone: phone(118), city: 'Hamburg' },
  hedwig: { first_name: 'Paul', last_name: 'Wendt', phone: phone(119), city: 'Hamburg' },
  gustav: { first_name: 'Carla', last_name: 'Rieger', phone: phone(120), city: 'Hamburg' },
  bruno: { first_name: 'Stefan', last_name: 'Ohm', phone: phone(121), city: 'Hamburg' },
  mika: { first_name: 'Greta', last_name: 'Lindqvist', phone: phone(122), city: 'Hamburg' },
};
