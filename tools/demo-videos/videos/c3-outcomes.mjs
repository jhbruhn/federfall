// C3 — Outcomes and the bird's state. Tarek's morning: an outcome that landed
// on the wrong case is corrected by deleting it, the right one is recorded,
// and the animals registry shows what each kind of outcome makes of a bird.
//
//   A mistake        Tilda is missing from Tarek's cases: this morning he
//                    recorded "released" on her case instead of Pieps's
//                    (setup()); the registry calls her "no longer in our care"
//   Deleting it      a case's status follows its outcome, so it cannot just be
//                    set back to "in care" — re-opening means deleting the
//                    outcome; the confirmation says what that does
//   Releasing        Pieps's release, recorded from "Status & completion"
//   Death, transfer  Oskar (transferred yesterday) and Wilma (died) in the
//                    registry: what each outcome makes of the bird; a death is
//                    final for a carer
//   Back again       Gustav: released in spring, admitted again four days ago —
//                    the latest event counts, so he reads "in care"
//
// Tarek (carer2) is signed in throughout. Oskar is Malte's and Wilma and
// Gustav are Lena's: Tarek sees their animal records (read org-wide), not
// their cases.
import { defineVideo, signIn } from '../harness/video.mjs';
import { BIRDS } from '../harness/data/demo/cast.mjs';
import { place, RELEASE_TYPES } from '../harness/data/demo/vocab.mjs';

const TILDA = BIRDS.tilda.name;
const PIEPS = BIRDS.pieps.name;
const OSKAR = BIRDS.oskar.name;
const WILMA = BIRDS.wilma.name;
const GUSTAV = BIRDS.gustav.name;
// Where Pieps was found, and where she goes back to (her follow-up says so).
const PIEPS_PLACE = place('Alma-Wartenberg-Platz');
const REASON = { de: 'Schwanzfedern nachgewachsen, fliegt sicher', en: 'Tail feathers grown back, flying well' };

/**
 * The registry's search field. Its name is empty once it holds text, and then
 * two inputs sit on it (semantics' and the editor's); a click on either
 * focuses the same field. The case list's, kept alive behind its tab, is hidden.
 */
const search = (s) => s.page.getByRole('textbox').locator('visible=true').first();

async function findInRegistry(s, name) {
  await s.type(search(s), name, { clear: true });
  await s.waitFor(s.role('button', s.rowOf(name)));
  await s.rest();
}

export default defineVideo({
  id: 'C3',
  slug: 'outcomes',
  title: { de: 'Ausgang und Status', en: 'Outcomes and state' },
  viewport: 'phone',
  dataset: 'demo',
  signInAs: 'carer2',
  // The mistake the video corrects: Pieps's release, recorded on Tilda's case
  // at 08:30 this morning — by Tarek, who may delete it again.
  setup: async ({ seed, locale }) => {
    const tarek = await seed.as('carer2');
    await tarek.create('dispositions', {
      case: seed.demo.cases.tilda, org: seed.org.id, type: 'released',
      disposed_at: new Date(Date.parse(seed.demo.now) - 70 * 60_000).toISOString(),
      reason: REASON[locale], performed_by: seed.people.carer2.id, vet_signed_off: false, vet: '',
      release_location: PIEPS_PLACE.name, release_geo: { lat: PIEPS_PLACE.lat, lon: PIEPS_PLACE.lon },
      release_type: RELEASE_TYPES.soft[locale], transfer_type: '', transfer_destination: '', aviary: '',
    });
    return {};
  },
  steps: [
    ...signIn({
      say: {
        de: 'Jeder Fall endet mit einem Ausgang: ausgewildert, abgegeben oder verstorben. Was das aus dem Vogel macht – und wie du einen falschen Ausgang korrigierst.',
        en: 'Every case ends with an outcome: released, transferred or died. What that makes of the bird – and how to correct a wrong one.',
      },
    }),

    // ── A mistake ────────────────────────────────────────────────────────
    {
      name: "Tarek's cases",
      title: { de: 'Ein Fehler', en: 'A mistake' },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navCases')));
        await s.waitFor(s.role('button', s.rowOf(`${PIEPS} ·`)));
        await s.rest();
      },
    },
    {
      name: 'Tilda is missing',
      say: {
        de: (t) => `In Tareks Fällen fehlt Tilda. Heute früh hat er bei ihr versehentlich „${t('dispositionReleased')}“ eingetragen – gemeint war Pieps.`,
        en: (t) => `Tilda is missing from Tarek's cases. This morning he recorded “${t('dispositionReleased')}” on her case by mistake – he meant Pieps.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.gone(s.role('button', s.rowOf(`${TILDA} ·`)));
        const pieps = await s.box(s.role('button', s.rowOf(`${PIEPS} ·`)));
        await s.focus(s.role('button', s.rowOf(`${BIRDS.hinkebein.name} ·`)), {
          box: (b) => ({ ...b, height: pieps.y + pieps.height - b.y }),
        });
      },
    },
    {
      name: 'find Tilda',
      run: async (s) => {
        await s.click(s.role('tab', s.t('navAnimals')));
        await findInRegistry(s, TILDA);
      },
    },
    {
      name: 'no longer in our care',
      say: {
        de: (t) => `Der Ausgang hat ihren Fall abgeschlossen. Und Tilda selbst gilt jetzt als „${t('lifetimeStatusAtLargeReleased')}“ – dabei sitzt sie in Quarantäne.`,
        en: (t) => `The outcome closed her case. And Tilda herself now reads “${t('lifetimeStatusAtLargeReleased')}” – while she is actually in quarantine.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(TILDA, s.t('lifetimeStatusAtLargeReleased'))));
      },
    },
    {
      name: 'open her case',
      run: async (s) => {
        await s.click(s.role('button', s.rowOf(TILDA)));
        const row = s.role('button', s.rowOf(s.t('caseStatusDisposed')));
        await s.reveal(row);
        await s.click(row);
        await s.click(s.role('tab', s.t('caseTabHistory')));
        await s.waitFor(s.button('dispositionEditTitle'));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'the outcome',
      title: { de: 'Ausgang löschen', en: 'Deleting it' },
      say: {
        de: (t) => `Im Verlauf steht der Ausgang. Den Fall einfach wieder auf „${t('caseStatusInCare')}“ stellen geht nicht: Der Status folgt immer dem Ausgang.`,
        en: (t) => `The outcome is in the history. Simply setting the case back to “${t('caseStatusInCare')}” is not possible: the status always follows the outcome.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('group', s.rowOf(s.t('dispositionReleased'))));
      },
    },
    {
      name: 'open it',
      run: async (s) => {
        await s.click(s.button('dispositionEditTitle'));
        await s.click(s.button('dispositionDeleteAction'));
        await s.expectText(s.t('dispositionDeleteConfirm'));
        await s.rest({ x: s.vp.width * 0.5, y: s.vp.height * 0.75 });
      },
    },
    {
      name: 'what deleting does',
      say: {
        de: 'Wieder öffnen heißt: den falschen Ausgang löschen. Dann ist der Fall wieder offen, und Tilda bekommt ihren Status zurück.',
        en: 'Re-opening means deleting the wrong outcome. The case is open again, and Tilda gets her state back.',
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: 'delete',
      run: async (s) => {
        // The dialog's confirm button carries the same label as the sheet's.
        await s.click(s.page.getByRole('alertdialog').getByRole('button', { name: s.t('dispositionDeleteAction'), exact: true }));
        await s.waitFor(s.role('checkbox', s.t('caseStatusInCare')), { timeout: 15_000 });
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'open again',
      say: {
        de: (t) => `Tildas Fall steht wieder auf „${t('caseStatusInCare')}“. Jetzt bekommt Pieps den richtigen Eintrag.`,
        en: (t) => `Tilda's case is back to “${t('caseStatusInCare')}”. Now Pieps gets the right entry.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.buttonStartingWith('caseOpenAnimal'), {
          box: (b) => ({ x: 16, y: b.y - 8, width: 380, height: 130 }),
        });
      },
    },

    // ── The right outcome, on Pieps ──────────────────────────────────────
    {
      name: 'open Pieps',
      title: { de: 'Auswildern', en: 'Releasing' },
      run: async (s) => {
        await s.click(s.button('actionBack'));
        await s.gone(s.role('tab', s.t('caseTabHistory')));
        await s.click(s.role('tab', s.t('navCases')));
        await s.click(s.role('button', s.rowOf(`${PIEPS} ·`)));
        await s.reveal(s.button('timelineRecordOutcome'));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'ready for release',
      say: {
        de: (t) => `Pieps, ein Haussperling, ist „${t('caseStatusReadyForRelease')}“. Unter „${t('caseLifecycleTitle')}“ trägt Tarek jetzt den richtigen Ausgang ein.`,
        en: (t) => `Pieps, a house sparrow, is “${t('caseStatusReadyForRelease')}”. Under “${t('caseLifecycleTitle')}”, Tarek now records the right outcome.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.button('timelineRecordOutcome'), {
          box: (b) => ({ x: b.x, y: b.y - 110, width: b.width, height: b.height + 118 }),
        });
      },
    },
    {
      name: 'the outcome form',
      run: async (s) => {
        await s.click(s.button('timelineRecordOutcome'));
        await s.waitFor(s.textbox('dispositionFieldReleaseLocation'));
        await s.type(s.textbox('dispositionFieldReleaseLocation'), PIEPS_PLACE.name);
        await s.type(s.textbox('dispositionFieldReleaseType'), s.pick(RELEASE_TYPES.soft));
        await s.type(s.textbox('dispositionFieldReason'), s.pick(REASON));
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'where and how',
      say: {
        de: (t) => `„${t('dispositionReleased')}“ ist schon gewählt. Dazu wo und wie: Pieps fliegt dort, wo sie gefunden wurde.`,
        en: (t) => `“${t('dispositionReleased')}” is already chosen. Then where and how: Pieps goes back to where she was found.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        const type = await s.box(s.role('button', s.rowOf(s.t('dispositionFieldType'), s.t('dispositionReleased'))));
        await s.focus(s.textbox('dispositionFieldReleaseType'), {
          box: (b) => ({ x: type.x, y: type.y, width: type.width, height: b.y + b.height - type.y }),
        });
      },
    },
    {
      name: 'save the release',
      run: async (s) => {
        await s.click(s.button('dispositionSaveAction'));
        await s.waitFor(s.role('checkbox', s.t('caseStatusDisposed')), { timeout: 15_000 });
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'closed',
      say: {
        de: (t) => `Der Fall ist „${t('caseStatusDisposed')}“. Auswildern, Abgeben und die Rückgabe an den Halter heißen für den Vogel: „${t('lifetimeStatusAtLargeReleased')}“.`,
        en: (t) => `The case is “${t('caseStatusDisposed')}”. Released, transferred or returned to its owner all mean the same for the bird: “${t('lifetimeStatusAtLargeReleased')}”.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.buttonStartingWith('caseOpenAnimal'), {
          box: (b) => ({ x: 16, y: b.y - 8, width: 380, height: 130 }),
        });
      },
    },

    // ── Death and transfer ───────────────────────────────────────────────
    {
      name: 'find Oskar',
      title: { de: 'Abgabe und Tod', en: 'Transfer and death' },
      run: async (s) => {
        await s.click(s.button('actionBack'));
        await s.gone(s.role('tab', s.t('caseTabHistory')));
        await s.click(s.role('tab', s.t('navAnimals')));
        await findInRegistry(s, OSKAR);
      },
    },
    {
      name: 'transferred',
      say: {
        de: (t) => `Oskar, ein Mäusebussard, ging gestern an eine Greifvogelstation. Auch er ist jetzt „${t('lifetimeStatusAtLargeReleased')}“.`,
        en: (t) => `Oskar, a buzzard, went to a raptor centre yesterday. He too now reads “${t('lifetimeStatusAtLargeReleased')}”.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(OSKAR, s.t('lifetimeStatusAtLargeReleased'))));
      },
    },
    {
      name: 'find Wilma',
      run: async (s) => { await findInRegistry(s, WILMA); },
    },
    {
      name: 'died',
      say: {
        de: (t) => `Wilma ist in ihrer ersten Nacht gestorben: „${t('lifetimeStatusDeceased')}“. Das ist endgültig – einen neuen Fall legt dann nur die Koordination oder Leitung an, denn dann war der Eintrag falsch.`,
        en: (t) => `Wilma died during her first night: “${t('lifetimeStatusDeceased')}”. That is final – only a coordinator or supervisor can open a new case then, because it means the record was wrong.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(WILMA, s.t('lifetimeStatusDeceased'))));
      },
    },

    // ── Back again ───────────────────────────────────────────────────────
    {
      name: 'find Gustav',
      title: { de: 'Wieder da', en: 'Back again' },
      run: async (s) => {
        await findInRegistry(s, GUSTAV);
        await s.click(s.role('button', s.rowOf(GUSTAV)));
        await s.waitFor(s.role('checkbox', s.t('lifetimeStatusInCare')));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.6 });
      },
    },
    {
      name: 'in care again',
      say: {
        de: (t) => `Gustav, eine Stadttaube, gilt als „${t('lifetimeStatusInCare')}“ – dabei wurde er im Frühjahr ausgewildert.`,
        en: (t) => `Gustav, a feral pigeon, reads “${t('lifetimeStatusInCare')}” – yet he was released in the spring.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('checkbox', s.t('lifetimeStatusInCare')), {
          box: (b) => ({ x: 16, y: b.y - 72, width: 380, height: 120 }),
        });
      },
    },
    {
      name: 'to his cases',
      run: async (s) => {
        // His cases are Lena's: rows without access merge into the card.
        await s.reveal(s.role('group', s.t('animalSectionCases'), { startsWith: true }));
        // reveal() stops once the card's box touches the screen; bring all of it up.
        await s.pointer.wheel('down', 8);
        await s.hold(500);
        await s.expectText(s.t('caseStatusDisposed'));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'the latest event counts',
      say: {
        de: 'Vor vier Tagen kam er mit einer Bisswunde zurück: sein zweiter Fall. Es zählt immer das jüngste Ereignis – und die neue Aufnahme ist jünger als die Auswilderung.',
        en: 'Four days ago he came back with a bite wound: his second case. The latest event always counts – and the new admission is later than the release.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('group', s.t('animalSectionCases'), { startsWith: true }));
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: 'Der Ausgang beendet den Fall und bestimmt, was der Vogel jetzt ist. Es zählt das jüngste Ereignis. Und ein falscher Ausgang wird gelöscht, nicht überschrieben.',
        en: 'The outcome ends the case and decides what the bird is now. The latest event counts. And a wrong outcome is deleted, not overwritten.',
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
