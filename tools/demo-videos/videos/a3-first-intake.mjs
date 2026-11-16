// A3 — Your first intake. A carer with an empty case list admits a wood
// pigeon: species from the autocomplete, reason and age class, the find
// location on the map, the intake weight, a photo and the finder. The created
// case opens.
import { defineVideo, signIn } from '../harness/video.mjs';

// Past intakes by the supervisor, so the species autocomplete has something to
// offer. A carer only sees their own cases, so their list stays empty.
const SPECIES = {
  de: ['Ringeltaube', 'Stadttaube', 'Mauersegler', 'Amsel', 'Haussperling'],
  en: ['Wood pigeon', 'Feral pigeon', 'Common swift', 'Blackbird', 'House sparrow'],
};

const BIRD = {
  typed: { de: 'Ringel', en: 'Wood' },
  species: { de: 'Ringeltaube', en: 'Wood pigeon' },
  name: 'Paula',
  // A label of the seeded code list (harness/data/base.mjs), not an ARB string.
  reason: { de: 'Kollision', en: 'Collision' },
  weight: '312',
  notes: {
    de: 'Gegen eine Glasscheibe geflogen, benommen, kein Blut.',
    en: 'Flew into a window, dazed, no bleeding.',
  },
};

// The fixed answer of the stand-in geocoder (harness/lib/services.mjs).
const PLACE = { search: 'Rathausmarkt', result: 'Rathausmarkt 1,' };

const FINDER = { first: 'Erika', last: 'Sommer', phone: '0151 2345678' };

export default defineVideo({
  id: 'A3',
  slug: 'first-intake',
  title: { de: 'Der erste Fall', en: 'Your first intake' },
  viewport: 'phone',
  signInAs: 'carer',
  assets: ['pigeon.svg'],
  setup: async ({ seed, locale }) => {
    await seed.intakes('supervisor', SPECIES[locale].map((species) => ({ species })));
  },
  steps: [
    ...signIn({
      title: { de: 'Anmelden', en: 'Sign in' },
      say: {
        de: 'Melde dich mit deiner E-Mail-Adresse und deinem Passwort an.',
        en: 'Sign in with your email address and password.',
      },
    }),
    {
      name: 'start the intake',
      title: { de: (t) => t('caseNewTitle'), en: (t) => t('caseNewTitle') },
      say: {
        de: (t) => `Noch ist die Liste leer. „${t('casesEmptyAction')}“ beginnt die Aufnahme.`,
        en: (t) => `Your list is still empty. “${t('casesEmptyAction')}” starts the intake.`,
      },
      run: async (s) => {
        await s.click(s.button('casesEmptyAction'));
        await s.waitFor(s.textbox('caseFieldSpecies'));
      },
    },
    {
      name: 'species from the autocomplete',
      title: { de: 'Das Tier', en: 'The bird' },
      say: {
        de: 'Tippe die ersten Buchstaben der Art. Arten, die schon einmal da waren, schlägt die App vor.',
        en: 'Type the first letters of the species. Species you have admitted before are suggested.',
      },
      zoom: { depth: 3 },
      run: async (s) => {
        await s.focus(s.textbox('caseFieldSpecies'));
        await s.type(s.textbox('caseFieldSpecies'), s.pick(BIRD.typed), { clear: true });
        await s.hold(700);
        await s.click(s.role('button', s.pick(BIRD.species)));
      },
    },
    {
      name: 'name',
      say: {
        de: 'Ein Name ist freiwillig, hilft aber im Alltag.',
        en: 'A name is optional, but it helps day to day.',
      },
      run: async (s) => {
        await s.type(s.textbox('caseFieldName'), BIRD.name);
        await s.click(s.button('actionNext'));
        await s.waitFor(s.buttonStartingWith('caseFieldAgeClass'));
      },
    },
    {
      name: 'reason and age class',
      title: { de: 'Die Aufnahme', en: 'The admission' },
      say: {
        de: 'Wähle den Aufnahmegrund und, wenn bekannt, die Altersklasse.',
        en: 'Choose the reason for admission and, if you know it, the age class.',
      },
      zoom: { depth: 3 },
      run: async (s) => {
        await s.focus(s.role('checkbox', s.pick(BIRD.reason)));
        await s.click(s.role('checkbox', s.pick(BIRD.reason)));
        await s.click(s.buttonStartingWith('caseFieldAgeClass'));
        await s.click(s.role('menuitem', s.t('ageClassAdult')));
        await s.waitFor(s.button('locationPickAction'));
      },
    },
    {
      name: 'find location on the map',
      say: {
        de: 'Den Fundort suchst du auf der Karte. Die Adresse übernimmt die App.',
        en: 'Look up where the bird was found on the map. The app fills in the address.',
      },
      run: async (s) => {
        await s.click(s.button('locationPickAction'));
        await s.type(s.textbox('locationSearchHint'), PLACE.search);
        await s.press('Enter');
        await s.click(s.role('button', PLACE.result, { startsWith: true }));
        await s.hold(1200);
        await s.click(s.button('locationUseAction'));
        await s.waitFor(s.textbox('caseFieldIntakeWeight'));
      },
    },
    {
      name: 'intake weight',
      say: {
        de: 'Das Aufnahmegewicht wird gleich der erste Eintrag im Gewichtsverlauf.',
        en: 'The intake weight becomes the first entry of the weight history.',
      },
      zoom: { depth: 3 },
      run: async (s) => {
        await s.focus(s.textbox('caseFieldIntakeWeight'));
        await s.type(s.textbox('caseFieldIntakeWeight'), BIRD.weight);
      },
    },
    {
      name: 'photo',
      title: { de: 'Foto und Finder', en: 'Photo and finder' },
      say: {
        de: 'Das erste Foto wird zum Porträt des Vogels.',
        en: "The first photo becomes the bird's portrait.",
      },
      run: async (s) => {
        await s.click(s.button('actionNext'));
        await s.chooseFile(s.button('photoAddAction'), await s.asset('pigeon.svg'));
      },
    },
    {
      name: 'notes and finder',
      say: {
        de: 'Dazu kommen Notizen und die Kontaktdaten der Finderin.',
        en: "Add a few notes and the finder's contact details.",
      },
      run: async (s) => {
        await s.type(s.textbox('caseFieldIntakeNotes'), s.pick(BIRD.notes));
        await s.click(s.button('caseSectionFinder'));
        await s.type(s.textbox('finderFieldFirstName'), FINDER.first);
        await s.type(s.textbox('finderFieldLastName'), FINDER.last);
        await s.type(s.textbox('finderFieldPhone'), FINDER.phone);
      },
    },
    {
      name: 'create the case',
      title: { de: 'Der neue Fall', en: 'The new case' },
      say: {
        de: (t) => `„${t('caseCreateAction')}“ speichert alles auf einmal. Der neue Fall öffnet sich sofort.`,
        en: (t) => `“${t('caseCreateAction')}” saves everything at once. The new case opens right away.`,
      },
      minMs: 6500,
      run: async (s) => {
        await s.click(s.button('caseCreateAction'));
        await s.waitForUrl(/\/cases\/(?!new)[a-z0-9]{15}/);
        await s.expectText(BIRD.name);
        await s.expectText(s.pick(BIRD.species));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.17 });
      },
    },
  ],
});
