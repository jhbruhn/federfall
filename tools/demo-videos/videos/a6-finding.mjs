// A6 — Finding cases and birds. Malte (coordinator) looks across the whole
// organisation: the case browser's caseload picker, a name search, the status,
// outcome and diagnosis facets over the closed history, one colleague's
// caseload; then the animals registry, where a ring number finds Gustav and
// his record shows both of his stays.
//
// A coordinator, not a carer: a carer's "all cases" is their own plus what is
// shared with them, so the carer facet would have nothing to show.
//
// Not in this video: opening a case by barcode. The scanner is native only
// (hardware_scan_service_web.dart is an empty stream; the QR on the report
// opens through the phone's camera), so the web build cannot show it.
import { defineVideo, signIn } from '../harness/video.mjs';
import { codeLabel, PEOPLE } from '../harness/data/base.mjs';
import { BIRDS, RINGS } from '../harness/data/demo/cast.mjs';

const DIAGNOSIS = 'Trichomonadose (Gelber Knopf)';
const TAREK = PEOPLE.carer2.name;
const PIEPS = BIRDS.pieps.name;
const GUSTAV = BIRDS.gustav.name;

/** Opens one of the filter sheet's pickers (they have no label; see cases_screen.dart) and picks [entry]. */
async function pick(s, id, entry) {
  await s.click(s.id(id));
  await s.click(s.role('button', entry));
  await s.gone(s.role('button', entry));
}

async function openFilters(s) {
  // Once a facet is set, the button's name carries its count ("Filter\n1").
  await s.click(s.buttonStartingWith('casesFiltersTitle'));
  await s.waitFor(s.id('cases-filter-caseload'));
}

/** Closes the sheet the way a thumb does: a tap on the dimmed list above it. */
async function closeFilters(s) {
  await s.pointer.moveTo(s.vp.width * 0.5, 60);
  await s.hold(150);
  await s.pointer.click();
  await s.gone(s.id('cases-filter-caseload'));
}

export default defineVideo({
  id: 'A6',
  slug: 'finding',
  title: { de: 'Fälle und Vögel finden', en: 'Finding cases and birds' },
  viewport: 'phone',
  dataset: 'demo',
  signInAs: 'coordinator',
  steps: [
    ...signIn({
      say: {
        de: 'Hunderte Fälle, noch mehr Vögel: So findest du den einen, den du suchst.',
        en: 'Hundreds of cases, even more birds: this is how you find the one you need.',
      },
    }),
    {
      name: 'open the case list',
      title: { de: 'Die Fallliste', en: 'The case list' },
      say: {
        de: (t) => `„${t('casesTitle')}“ zeigt erst einmal nur deine eigenen, laufenden Fälle.`,
        en: (t) => `“${t('casesTitle')}” starts out with just your own open cases.`,
      },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navCases')));
        await s.waitFor(s.textbox('casesSearchHint'));
        await s.rest();
      },
    },
    {
      name: 'every case',
      title: { de: (t) => t('casesFiltersTitle'), en: (t) => t('casesFiltersTitle') },
      say: {
        de: (t) => `Unter „${t('casesFiltersTitle')}“ wählst du, wessen Fälle: deine, alle, oder die einer bestimmten Person.`,
        en: (t) => `Under “${t('casesFiltersTitle')}” you choose whose cases: yours, everyone's, or one person's.`,
      },
      run: async (s) => {
        await openFilters(s);
        await s.click(s.id('cases-filter-caseload'));
        await s.waitFor(s.role('button', TAREK));
        await s.hold(1500);
        await s.click(s.role('button', s.t('casesAllTitle')));
        await s.gone(s.role('button', TAREK));
        await closeFilters(s);
        // The newest open case, Kora's, heads the widened list.
        await s.waitFor(s.role('button', s.rowOf(`${BIRDS.kora.name} ·`)));
        await s.rest();
      },
    },
    {
      name: 'all open cases',
      say: {
        de: 'Jetzt stehen alle laufenden Fälle da, jeweils mit der Person, die den Vogel betreut.',
        en: 'Now every open case is listed, each with the person caring for the bird.',
      },
      run: async (s) => {
        await s.expectText(TAREK);
        await s.hold(500);
      },
    },
    {
      name: 'search by name',
      title: { de: 'Suchen', en: 'Search' },
      say: {
        de: 'Die Suche findet Fallnummern, Namen und Ringnummern, schon während du tippst.',
        en: 'Search finds case numbers, names and ring numbers, as you type.',
      },
      run: async (s) => {
        await s.type(s.textbox('casesSearchHint'), PIEPS);
        await s.waitFor(s.role('button', s.rowOf(PIEPS)));
        await s.gone(s.role('button', s.rowOf(GUSTAV)));
        await s.rest();
        await s.hold(1200);
      },
    },
    {
      name: 'clear the search',
      run: async (s) => {
        await s.type(s.textbox('casesSearchHint'), '', { clear: true });
        await s.waitFor(s.role('button', s.rowOf(GUSTAV)));
        await s.rest();
      },
    },
    {
      name: 'closed, released, a diagnosis',
      title: { de: 'Die Geschichte', en: 'The history' },
      say: {
        de: (t) => `Für die abgeschlossenen Fälle: „${t('casesActivityClosed')}“, dann Ausgang und Diagnose. Angeboten wird nur, was wirklich vorkam.`,
        en: (t) => `For closed cases: “${t('casesActivityClosed')}”, then outcome and diagnosis. Only what actually occurred is offered.`,
      },
      run: async (s) => {
        await openFilters(s);
        await s.click(s.button('casesActivityClosed'));
        await pick(s, 'cases-filter-outcome', s.t('dispositionReleased'));
        await pick(s, 'cases-filter-diagnosis', codeLabel('conditions', DIAGNOSIS, s.locale));
        await s.hold(1000);
        await closeFilters(s);
        await s.waitFor(s.role('button', s.rowOf(codeLabel('conditions', DIAGNOSIS, s.locale))).first());
        await s.rest();
      },
    },
    {
      name: 'the result',
      say: {
        de: 'Übrig bleiben die ausgewilderten Vögel mit Trichomonadose, aus diesem und dem letzten Jahr.',
        en: 'What is left: the birds with trichomonosis that were released, this year and last.',
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: "one person's cases",
      title: { de: 'Nach Person', en: 'By person' },
      say: {
        de: (t) => `Wählst du unter „${t('casesCaseloadLabel')}“ eine Person, etwa ${TAREK}, bleiben nur ihre Fälle – bei einer Übergabe oder Vertretung.`,
        en: (t) => `Pick a person under “${t('casesCaseloadLabel')}”, say ${TAREK}, and only their cases remain – for a handover or holiday cover.`,
      },
      run: async (s) => {
        await openFilters(s);
        await pick(s, 'cases-filter-caseload', TAREK);
        await closeFilters(s);
        await s.waitFor(s.role('heading', s.t('casesCarerTitle', { name: TAREK })).or(s.text(s.t('casesCarerTitle', { name: TAREK }))).first());
        await s.rest();
        await s.hold(1500);
      },
    },
    {
      name: 'reset',
      say: {
        de: (t) => `„${t('casesClearFilters')}“ führt zurück zu deinen eigenen Fällen.`,
        en: (t) => `“${t('casesClearFilters')}” takes you back to your own cases.`,
      },
      run: async (s) => {
        await openFilters(s);
        await s.click(s.button('casesClearFilters'));
        await s.gone(s.id('cases-filter-caseload'));
        await s.rest();
      },
    },
    {
      name: 'the registry',
      title: { de: (t) => t('animalsTitle'), en: (t) => t('animalsTitle') },
      say: {
        de: (t) => `Unter „${t('navAnimals')}“ steht jeder Vogel genau einmal, mit seinen Ringen und wo er gerade ist.`,
        en: (t) => `Under “${t('navAnimals')}”, every bird is listed exactly once, with its rings and where it is now.`,
      },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navAnimals')));
        await s.waitFor(s.textbox('animalsSearchHint'));
        await s.rest();
      },
    },
    {
      name: 'a ring number',
      say: {
        de: `Eine Stadttaube mit unserem Ring ${RINGS.gustav} ist gebracht worden. Die Ringnummer genügt.`,
        en: `A feral pigeon wearing our ring ${RINGS.gustav} has been brought in. The ring number is enough.`,
      },
      run: async (s) => {
        await s.type(s.textbox('animalsSearchHint'), RINGS.gustav);
        await s.waitFor(s.role('button', s.rowOf(GUSTAV, RINGS.gustav)));
        await s.rest();
        await s.hold(800);
      },
    },
    {
      name: 'his record',
      run: async (s) => {
        await s.click(s.role('button', s.rowOf(GUSTAV, RINGS.gustav)));
        await s.waitForUrl(/\/animals\/[a-z0-9]{15}/);
        await s.hold(800);
        // His cases are below his weights; the page builds them once near.
        // The case rows sit under that heading as nodes of their own, so the
        // page is taken to its end, where they are all in view.
        await s.reveal(s.role('group', s.t('animalSectionCases'), { startsWith: true }));
        await s.pointer.wheel('down', 10);
        await s.hold(500);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'both stays',
      say: {
        de: (t) => `Das ist ${GUSTAV}. Unter „${t('animalSectionCases')}“ stehen beide Aufenthalte: Er war im Frühjahr schon einmal hier.`,
        en: (t) => `That is ${GUSTAV}. Under “${t('animalSectionCases')}”, both of his stays: he was here once before, in spring.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.focus(s.role('group', s.t('animalSectionCases'), { startsWith: true }), {
          box: (b) => ({ x: b.x, y: b.y, width: b.width, height: s.vp.height - 8 - b.y }),
        });
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: 'Fälle findest du über Filter und Suche, Vögel im Tierverzeichnis – auch über die Ringnummer.',
        en: 'Find cases with filters and search, and birds in the registry – by ring number, too.',
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
