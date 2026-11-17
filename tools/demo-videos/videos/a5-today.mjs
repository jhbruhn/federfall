// A5 — Today. Lena's worklist at 09:40: what is due for her birds, grouped by
// kind, most urgent first, and how most of it is finished from the row itself
// — a whole dose round, a quarantine note acknowledged, a recheck ticked off,
// one dose. Vet appointments are shown, not stamped: Hedwig's is this
// afternoon.
//
// setup() undoes this morning's Faucalin round (07:00) for the three young
// pigeons, as C1 does, so their round is honestly due when the video gives
// it (README, "Pitfalls met in C1").
//
// The order is forced by the undo snackbar. With the semantics tree on (the
// harness needs it to find things) Flutter keeps a snackbar that has an
// action on screen until something replaces it, and a click on a row beneath
// it does not reach the row. So the bottom-most row, the quarantine note, is
// finished first, while no snackbar is up; the recheck is clicked with the
// list scrolled to its end, which lifts it clear; the dose row is at the top.
//
// Not in this video: the "no activity for N days" note on a quiet case. It
// lives on the case list and reads the server's `updated` stamps, which are
// all the moment of seeding (README, "What data cannot fix"), so no case of
// the demo dataset can show it.
import { defineVideo, signIn } from '../harness/video.mjs';
import { BIRDS } from '../harness/data/demo/cast.mjs';
import { PRODUCTS } from '../harness/data/demo/vocab.mjs';

const GROUP = ['bruno', 'lotte', 'mats'];
const NEMAKUR = PRODUCTS.dewormer.label.de;
const FAUCALIN = PRODUCTS.antiprotozoal.label.de;
const FIETE = BIRDS.fiete.name;
const HEDWIG = BIRDS.hedwig.name;
// Fiete's recheck for today (stories.mjs).
const RECHECK = { de: 'Kot für die Kontrolluntersuchung sammeln', en: 'Collect droppings for the re-test' };

/**
 * The [key] button (a row's own verb, by its tooltip) inside the worklist row
 * [row]. The verb is a sibling of the row's node in the semantics tree, not a
 * child, so it is told apart from the other rows' by where it sits.
 */
async function verbOf(s, row, key) {
  const r = await s.reveal(row);
  const all = s.button(key);
  const n = await all.count();
  for (let i = 0; i < n; i++) {
    const b = await all.nth(i).boundingBox();
    if (b && b.y >= r.y - 1 && b.y + b.height <= r.y + r.height + 1) return all.nth(i);
  }
  throw new Error(`no "${s.t(key)}" button in the row ${row}`);
}

/** Scrolls the list to its end (rows at the bottom rise above the snackbar). */
async function toEnd(s) {
  await s.pointer.moveTo(s.vp.width / 2, s.vp.height * 0.5);
  await s.pointer.wheel('down', 12);
  await s.hold(400);
}

export default defineVideo({
  id: 'A5',
  slug: 'today',
  title: { de: 'Heute', en: 'Today' },
  viewport: 'phone',
  dataset: 'demo',
  signInAs: 'carer',
  setup: async ({ seed }) => {
    const lena = await seed.as('carer');
    const meds = GROUP.map((k) => seed.demo.medications[`${k}Canker`]);
    const since = new Date(Date.parse(seed.demo.now) - 4 * 3600_000).toISOString().replace('T', ' ');
    const rows = await lena.list('medication_administrations', `filter=${encodeURIComponent(
      `(${meds.map((m) => `medication="${m}"`).join(' || ')}) && administered_at >= "${since}"`)}`);
    if (rows.length !== GROUP.length) {
      throw new Error(`A5 setup: expected this morning's ${GROUP.length} ${FAUCALIN} doses, found ${rows.length}`);
    }
    for (const r of rows) await lena.remove('medication_administrations', r.id);
    return {};
  },
  steps: [
    ...signIn({
      say: {
        de: 'Was steht heute an? Federfall sammelt es für dich auf einer Liste.',
        en: 'What needs doing today? Federfall collects it for you in one list.',
      },
    }),
    {
      name: 'open Today',
      title: { de: (t) => t('todayTitle'), en: (t) => t('todayTitle') },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navDashboard')));
        await s.click(s.button('worklistSeeAll'));
        await s.waitFor(s.role('group', s.t('doseRoundHeading', { drug: FAUCALIN, count: GROUP.length })));
        await s.rest({ x: s.vp.width * 0.55, y: s.vp.height * 0.4 });
      },
    },
    {
      name: 'what the list holds',
      say: {
        de: 'Fällige Medikamente stehen oben, dann Tierarzttermine, Nachkontrollen und endende Quarantänen. Überfälliges ist rot.',
        en: 'Medication due comes first, then vet appointments, rechecks and quarantines ending. Anything overdue is red.',
      },
      run: async (s) => { await s.hold(300); },
    },

    // ── The dose round ───────────────────────────────────────────────────
    {
      name: 'the round',
      title: { de: (t) => t('doseRoundTitle'), en: (t) => t('doseRoundTitle') },
      say: {
        de: `Bruno, Lotte und Mats bekommen dasselbe Mittel, ${FAUCALIN}. Ihre Gabe von 7 Uhr steht noch aus.`,
        en: `Bruno, Lotte and Mats are on the same drug, ${FAUCALIN}. Their 7 o'clock dose is still to be given.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.expectText(s.t('worklistOverdueHours', { hours: 3 }));
        const heading = await s.box(s.role('group', s.t('doseRoundHeading', { drug: FAUCALIN, count: GROUP.length })));
        await s.focus(s.role('button', s.rowOf(`· ${BIRDS.mats.name}`)), {
          box: (b) => ({ x: heading.x, y: heading.y, width: heading.width, height: b.y + b.height - heading.y }),
        });
      },
    },
    {
      name: 'give all',
      say: {
        de: (t) => `„${t('doseRoundAction')}“ öffnet sie als eine Runde: eine Zeile pro Vogel, jede mit ihrer eigenen Menge.`,
        en: (t) => `“${t('doseRoundAction')}” opens them as one round: a row per bird, each with its own amount.`,
      },
      run: async (s) => {
        await s.click(s.button('doseRoundAction'));
        await s.waitFor(s.button('doseRoundSaveAction', { count: GROUP.length }));
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.32 });
      },
    },
    {
      name: 'save the round',
      say: {
        de: 'Ein Tipp trägt alle drei ein.',
        en: 'One tap logs all three.',
      },
      run: async (s) => {
        await s.click(s.button('doseRoundSaveAction', { count: GROUP.length }));
        await s.gone(s.button('doseRoundSaveAction', { count: GROUP.length }));
        await s.waitFor(s.role('button', s.rowOf(`· ${BIRDS.bruno.name}`, s.t('worklistDueInHours', { hours: 12 }))));
        await s.rest({ x: s.vp.width * 0.55, y: s.vp.height * 0.4 });
      },
    },

    // ── One tap each ─────────────────────────────────────────────────────
    {
      name: 'to the quarantine note',
      title: { de: 'Ein Tipp', en: 'One tap' },
      run: async (s) => {
        await toEnd(s);
        await s.waitFor(s.role('button', s.rowOf(`· ${HEDWIG}`, s.t('worklistQuarantineEndsToday'))));
        await s.rest({ x: s.vp.width * 0.6, y: s.vp.height * 0.6 });
      },
    },
    {
      name: 'a quarantine ends',
      say: {
        de: (t) => `${HEDWIG}s Quarantäne endet heute. Das ist nur ein Hinweis: „${t('worklistAcknowledge')}“ blendet ihn bis morgen aus.`,
        en: (t) => `${HEDWIG}'s quarantine ends today. That is just a note: “${t('worklistAcknowledge')}” hides it until tomorrow.`,
      },
      run: async (s) => {
        const row = s.role('button', s.rowOf(`· ${HEDWIG}`, s.t('worklistQuarantineEndsToday')));
        await s.hold(1500);
        await s.click(await verbOf(s, row, 'worklistAcknowledge'));
        await s.expectText(s.t('worklistDismissed'));
        await s.gone(row);
        await s.rest({ x: s.vp.width * 0.6, y: s.vp.height * 0.4 });
      },
    },
    {
      name: 'a recheck, done',
      say: {
        de: `${FIETE}s Kotprobe für die Kontrolle ist gesammelt. Ein Haken, und die Nachkontrolle ist erledigt.`,
        en: `${FIETE}'s droppings for the re-test are collected. One tick, and the recheck is done.`,
      },
      run: async (s) => {
        const row = s.role('button', s.rowOf(`· ${FIETE}`, s.pick(RECHECK)));
        await toEnd(s);
        await s.waitFor(row);
        await s.rest({ x: s.vp.width * 0.6, y: s.vp.height * 0.4 });
        await s.hold(1200);
        await s.click(await verbOf(s, row, 'followUpMarkDone'));
        await s.expectText(s.t('worklistFollowUpDone'));
        await s.gone(row);
        await s.rest({ x: s.vp.width * 0.6, y: s.vp.height * 0.4 });
        await s.hold(1200);
        await s.pointer.wheel('up', 12);
        await s.hold(400);
        await s.rest({ x: s.vp.width * 0.55, y: s.vp.height * 0.4 });
      },
    },
    {
      name: "Fiete's dose",
      say: {
        de: `Seine Wurmkur war um 8 Uhr fällig. Das Symbol am Rand trägt die Dosis mit einem Tipp ein.`,
        en: `His dewormer was due at 8. The icon at the end of the row logs the dose in one tap.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(`· ${FIETE}`, NEMAKUR, s.t('worklistOverdueHours', { hours: 2 }))));
      },
    },
    {
      name: 'log it',
      say: {
        de: (t) => `Die Menge rechnet die App aus seinem Gewicht von heute Morgen. Vertippt? Unten steht „${t('actionUndo')}“.`,
        en: (t) => `The app works out the amount from this morning's weight. Tapped by mistake? “${t('actionUndo')}” is right there.`,
      },
      run: async (s) => {
        const row = s.role('button', s.rowOf(`· ${FIETE}`, NEMAKUR));
        await s.click(await verbOf(s, row, 'worklistLogDose'));
        await s.expectText(s.t('worklistDoseLogged'));
        await s.waitFor(s.role('button', s.rowOf(`· ${FIETE}`, NEMAKUR, s.t('worklistDueInHours', { hours: 24 }))));
        await s.rest({ x: s.vp.width * 0.8, y: s.vp.height * 0.88 });
      },
    },

    // ── Vet appointments ─────────────────────────────────────────────────
    {
      name: 'a vet appointment',
      title: { de: (t) => t('worklistGroupAppointments'), en: (t) => t('worklistGroupAppointments') },
      say: {
        de: `${HEDWIG}s Röntgenkontrolle ist heute Nachmittag. Nach dem Besuch hakst du sie hier ab.`,
        en: `${HEDWIG}'s follow-up X-ray is this afternoon. After the visit, you tick it off here.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(`· ${HEDWIG}`, s.t('worklistDueInHours', { hours: 6 }))));
      },
    },
    {
      name: 'or cancel it',
      say: {
        de: (t) => `Fällt ein Termin aus, steht „${t('vetAppointmentCancel')}“ unter „${t('worklistMoreActions')}“.`,
        en: (t) => `If an appointment falls through, “${t('vetAppointmentCancel')}” is under “${t('worklistMoreActions')}”.`,
      },
      run: async (s) => {
        const row = s.role('button', s.rowOf(`· ${HEDWIG}`, s.t('worklistDueInHours', { hours: 6 })));
        await s.click(await verbOf(s, row, 'worklistMoreActions'));
        await s.waitFor(s.role('menuitem', s.t('vetAppointmentCancel')));
        await s.hold(1500);
        await s.press('Escape');
        await s.gone(s.role('menuitem', s.t('vetAppointmentCancel')));
        await s.rest({ x: s.vp.width * 0.55, y: s.vp.height * 0.4 });
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: (t) => `Alles, was heute ansteht, auf einer Liste – und das meiste mit einem Tipp erledigt, mit „${t('actionUndo')}“ als Netz.`,
        en: (t) => `Everything due today in one list – and most of it done in one tap, with “${t('actionUndo')}” as a safety net.`,
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
