// C5 — Patenschaften. Hinkebein, the lame pigeon who lives in Lena's loft:
// what a patronage is, how it moves with the bird, and the coordinators'
// overview of them all.
//
//   Hinkebein's sponsors  Lena keeps the loft, so she reads both patronages:
//                    who gives how much, how often, since when
//   Ending one       „Patenschaft beenden": one tap writes today as the end;
//                    nothing is deleted (a donation receipt needs the address)
//   A new one        a new sponsor, recorded on the bird
//   The move         Lena places Hinkebein in Tarek's garden aviary: the
//                    outcome form warns that three patronages go to Tarek — a
//                    count, never a name
//   Afterwards       the card is gone for Lena; Tarek reads them as keeper, and
//                    a bird's carer never does
//   All patronages   Malte (coordinator), from the dashboard: what is given
//                    right now (no period), the archive of ended ones, the
//                    search, and a row no keeper can reach (Ole, released)
//
// Lena (carer) signs in first, Malte (coordinator) second. setup() adds Tarek's
// garden aviary (a coordinator sets up enclosures) and Tarek's handback of
// Hinkebein's case to Lena this morning. The sponsor recorded on camera is the
// German placeholder name, at a placeholder address.
//
// Left out, filed: the move warning reads its count through the patronages'
// own read rule, so the bird's carer — who may move it — gets no warning at
// all (federfall-1h9z.47); Lena records the move here. An animal record opened
// while its case page is still alive keeps the custody and patronages from
// before the move until a reload (federfall-1h9z.48), so the afterwards view is
// reached through the garden aviary, a fresh read. And the overview does not
// mark a row whose bird left aviary care (federfall-1h9z.52), so the caption
// says it.
import { defineVideo, signIn, signOut } from '../harness/video.mjs';
import { PEOPLE } from '../harness/data/base.mjs';
import { AVIARIES, BIRDS, SPONSORS } from '../harness/data/demo/cast.mjs';

const HINKEBEIN = BIRDS.hinkebein.name;
const LENA = PEOPLE.carer.name;
const TAREK = PEOPLE.carer2.name;
const MALTE = PEOPLE.coordinator.name;
// The overview's search is debounced; a surname is enough to find the row.
const ALBERS_SEARCH = 'Albers';
const LOFT = AVIARIES.loft.name;
const GARDEN = {
  name: { de: 'Gartenvoliere', en: 'Garden aviary' },
  location: { de: 'Tareks Garten', en: "Tarek's garden" },
};
// Obviously invented: the German placeholder name on a placeholder street
// (cast.mjs's sponsors live on such streets too).
const NEW_SPONSOR = { name: 'Erika Mustermann', address: 'Beispielweg 7', amount: '12' };
const CONDITION = { de: 'Atmet wieder frei, frisst gut', en: 'Breathing freely again, eating well' };

const caseRow = (s) => s.role('button', s.rowOf(`${HINKEBEIN} ·`));
const resident = (s, name) => s.role('button', s.rowOf(name, ' · '));
const sponsorRow = (s, name) => s.role('button', s.rowOf(name));
/** A filter chip on the overview, whatever role Flutter gives it. */
const chip = (s, label) => s.role('checkbox', label).or(s.role('button', label)).first();
const card = (s) => s.role('group', s.t('animalSectionSponsorships'), { startsWith: true });

export default defineVideo({
  id: 'C5',
  slug: 'sponsorships',
  title: { de: 'Patenschaften', en: 'Patronages' },
  viewport: 'phone',
  dataset: 'demo',
  signInAs: 'carer',
  // ~3:45 of capture plus its export does not fit the default 8 minutes.
  maxMs: 12 * 60_000,
  setup: async ({ seed, locale }) => {
    // Tarek's garden aviary, set up by the coordinator (only coordinators and
    // the supervisor create enclosures) with Tarek as its keeper.
    const malte = await seed.as('coordinator');
    await malte.create('aviaries', {
      org: seed.org.id, name: GARDEN.name[locale], keeper: seed.people.carer2.id,
      location: GARDEN.location[locale], capacity: 4, active: true, notes: '',
    });
    // Hinkebein is well again: this morning Tarek handed his case back to
    // Lena (a placement naming her — the route the app takes), so she may
    // record the move on camera.
    const tarek = await seed.as('carer2');
    await tarek.create('placements', {
      org: seed.org.id, case: seed.demo.cases.hinkebein,
      moved_in_at: new Date(Date.parse(seed.demo.now) - 50 * 60_000).toISOString(),
      carer: seed.people.carer.id, from_user: seed.people.carer2.id, to_user: seed.people.carer.id,
      enclosure: '', condition_at_handoff: CONDITION[locale], comments: '',
    });
    return {};
  },
  steps: [
    ...signIn({
      say: {
        de: 'Manche Vögel haben Paten, die für sie spenden. Was eine Patenschaft ist, wie sie dem Vogel folgt – und wo die Koordination alle findet.',
        en: 'Some birds have sponsors who give money for them. What a patronage is, how it follows the bird – and where coordinators find them all.',
      },
    }),

    // ── The keeper ───────────────────────────────────────────────────────
    {
      name: "Lena's loft",
      title: { de: 'Hinkebeins Paten', en: "Hinkebein's sponsors" },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navAviaries')));
        await s.click(s.role('button', s.rowOf(s.pick(LOFT))));
        await s.click(resident(s, HINKEBEIN));
        await s.reveal(sponsorRow(s, SPONSORS.petersen.name));
        await s.pointer.wheel('down', 2);
        await s.hold(400);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'what a patronage is',
      say: {
        de: 'Eine Patenschaft hält fest, wer für einen Vogel spendet: wie viel, wie oft, seit wann. Hinkebein hat zwei Paten.',
        en: 'A patronage records who gives money for a bird: how much, how often, since when. Hinkebein has two sponsors.',
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.expectText(SPONSORS.brockmann.name);
        await s.focus(card(s));
      },
    },
    {
      name: 'why the keeper sees them',
      say: {
        de: 'Lena sieht sie, weil sie den Taubenschlag betreut, in dem Hinkebein lebt.',
        en: 'Lena sees them because she keeps the pigeon loft Hinkebein lives in.',
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.expectText(SPONSORS.brockmann.name);
        await s.focus(card(s));
      },
    },

    // ── Ending one ───────────────────────────────────────────────────────
    {
      name: 'open the Petersens',
      title: { de: 'Beenden', en: 'Ending one' },
      run: async (s) => {
        await s.click(sponsorRow(s, SPONSORS.petersen.name));
        await s.waitFor(s.button('sponsorshipEndNowAction'));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'the whole record',
      say: {
        de: (t) => `Familie Petersen zieht weg. Lena tippt auf „${t('sponsorshipEndNowAction')}“.`,
        en: (t) => `The Petersens are moving away. Lena taps “${t('sponsorshipEndNowAction')}”.`,
      },
      run: async (s) => {
        await s.hold(1800);
        await s.click(s.button('sponsorshipEndNowAction'));
        await s.waitFor(s.button('sponsorshipEndNowConfirmAction'));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'nothing is deleted',
      say: {
        de: 'Als Ende steht dann heute. Gelöscht wird nichts: Eine Spendenquittung braucht Name und Adresse auch später.',
        en: 'Today becomes the end date. Nothing is deleted: a donation receipt still needs the name and address later.',
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: 'end it',
      run: async (s) => {
        await s.click(s.button('sponsorshipEndNowConfirmAction'));
        await s.waitFor(s.role('checkbox', s.t('sponsorshipStatusEnded')), { timeout: 15_000 });
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'ended',
      say: {
        de: (t) => `Ein Tipp, fertig: „${t('sponsorshipStatusEnded')}“. War es ein Versehen, entfernst du das Ende unter „${t('sponsorshipEditTitle')}“ wieder.`,
        en: (t) => `One tap, done: “${t('sponsorshipStatusEnded')}”. If it was a mistake, remove the end date again under “${t('sponsorshipEditTitle')}”.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('checkbox', s.t('sponsorshipStatusEnded')), {
          box: (b) => ({ x: 24, y: b.y - 4, width: b.x + b.width - 24, height: 150 }),
        });
      },
    },

    // ── A new one ────────────────────────────────────────────────────────
    {
      name: 'add one',
      title: { de: 'Neue Patenschaft', en: 'A new patronage' },
      say: {
        de: (t) => `Dafür meldet sich Erika Mustermann: Sie übernimmt Hinkebein für 12 € im Monat. „${t('sponsorshipNewTitle')}“.`,
        en: (t) => `Then Erika Mustermann gets in touch: she takes Hinkebein on for €12 a month. “${t('sponsorshipNewTitle')}”.`,
      },
      run: async (s) => {
        await s.press('Escape');
        await s.gone(s.role('checkbox', s.t('sponsorshipStatusEnded')));
        await s.click(s.button('sponsorshipNewTitle'));
        await s.waitFor(s.textbox('sponsorshipFieldName'));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.08 });
      },
    },
    {
      name: 'fill it in',
      run: async (s) => {
        await s.type(s.textbox('sponsorshipFieldName'), NEW_SPONSOR.name);
        await s.type(s.textbox('sponsorshipFieldAddress'), NEW_SPONSOR.address);
        await s.type(s.textbox('sponsorshipFieldAmount'), NEW_SPONSOR.amount);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.08 });
      },
    },
    {
      name: 'on the patronage itself',
      say: {
        de: (t) => `„${t('sponsorshipIntervalMonthly')}“ und Beginn heute sind vorgegeben. Die Adresse steht in der Patenschaft selbst – in keinem Adressbuch für alle.`,
        en: (t) => `“${t('sponsorshipIntervalMonthly')}” and today's start are filled in. The address lives in the patronage itself – not in an address book for everyone.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const interval = await s.box(s.buttonStartingWith('sponsorshipFieldInterval'));
        await s.focus(s.textbox('sponsorshipFieldAmount'), {
          box: (b) => ({ x: b.x, y: b.y, width: b.width, height: interval.y + interval.height + 64 - b.y }),
        });
      },
    },
    {
      name: 'save it',
      run: async (s) => {
        await s.click(s.button('actionSave'));
        await s.gone(s.textbox('sponsorshipFieldName'), { timeout: 15_000 });
        await s.waitFor(sponsorRow(s, NEW_SPONSOR.name));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'three now',
      say: {
        de: 'Jetzt stehen drei auf der Karte – die beendete bleibt dabei.',
        en: 'The card now lists three – the ended one stays on it.',
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.expectText(s.t('sponsorshipIntervalMonthly'));
        await s.focus(card(s));
      },
    },
    // ── The move ─────────────────────────────────────────────────────────
    {
      name: 'his case',
      title: { de: 'Der Umzug', en: 'The move' },
      run: async (s) => {
        await s.click(s.button('actionBack'));
        await s.click(s.role('tab', s.t('navCases')));
        await s.click(caseRow(s));
        await s.waitFor(s.role('tab', s.t('caseTabHistory')));
        await s.rest({ x: s.vp.width * 0.5, y: s.vp.height * 0.62 });
        await s.reveal(s.button('timelineRecordOutcome'));
        // reveal() stops at the screen's edge; bring the card up to the middle.
        await s.pointer.wheel('down', 3);
        await s.hold(400);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'to the garden aviary',
      say: {
        de: (t) => `Hinkebein ist gesund, Tarek hat ihn Lena zurückgegeben. Er zieht in Tareks ruhige Gartenvoliere: Lena schließt seinen Fall mit „${t('dispositionPlacedInAviary')}“ ab.`,
        en: (t) => `Hinkebein is well, and Tarek has handed him back to Lena. He moves into Tarek's quiet garden aviary: Lena closes his case with “${t('dispositionPlacedInAviary')}”.`,
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
        await s.click(s.role('button', s.rowOf(s.t('dispositionFieldType'), s.t('dispositionReleased'))));
        await s.click(s.role('menuitem', s.t('dispositionPlacedInAviary')));
        await s.click(s.buttonStartingWith('dispositionFieldAviary'));
        await s.click(s.role('menuitem', s.pick(GARDEN.name)));
        await s.expectText(s.t('sponsorshipTransferWarning', { count: 3, keeper: TAREK }));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'the warning',
      say: {
        de: 'Patenschaften folgen dem Vogel. Deshalb warnt die App: Drei wechseln zu Tarek. Sie nennt eine Zahl – nie einen Namen.',
        en: 'Patronages follow the bird. So the app warns: three go to Tarek. It gives a number – never a name.',
      },
      run: async (s) => {
        const save = await s.box(s.button('dispositionSaveAction'));
        await s.focus(s.buttonStartingWith('dispositionFieldAviary'), {
          box: (b) => ({ x: b.x, y: b.y, width: b.width, height: save.y - 8 - b.y }),
        });
      },
    },
    {
      name: 'save the move',
      run: async (s) => {
        await s.click(s.button('dispositionSaveAction'));
        await s.waitFor(s.role('checkbox', s.t('caseStatusDisposed')), { timeout: 15_000 });
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.2 });
      },
    },

    // ── Afterwards ───────────────────────────────────────────────────────
    {
      name: 'the garden aviary',
      title: { de: 'Danach', en: 'Afterwards' },
      run: async (s) => {
        await s.click(s.button('actionBack'));
        await s.click(s.role('tab', s.t('navAviaries')));
        await s.click(s.role('button', s.rowOf(s.pick(GARDEN.name))));
        await s.waitFor(resident(s, HINKEBEIN));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.75 });
      },
    },
    {
      name: 'his record, for Lena',
      run: async (s) => {
        await s.click(resident(s, HINKEBEIN));
        await s.reveal(s.role('group', s.t('animalSectionCases'), { startsWith: true }));
        // reveal() stops once the card touches the screen; bring it up.
        await s.pointer.wheel('down', 3);
        await s.hold(400);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'gone for Lena',
      say: {
        de: 'Hinkebein lebt jetzt in der Gartenvoliere: Seine Paten sieht Tarek als Betreuer, Lena nicht mehr. Wer einen Vogel nur pflegt, sieht sie nie.',
        en: "Hinkebein now lives in the garden aviary: Tarek sees his sponsors as its keeper, Lena no longer does. Someone who only treats a bird never sees them.",
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.gone(card(s));
        // Without a write control, the markings card has no node of its own:
        // aim from the exams card above it down into the cases card.
        const cases = await s.box(s.role('group', s.t('animalSectionCases'), { startsWith: true }));
        await s.focus(s.buttonStartingWith('animalSectionExams'), {
          box: (b) => ({ x: b.x, y: b.y, width: b.width, height: Math.min(cases.y + 80, s.vp.height) - b.y }),
        });
      },
    },
    // ── The overview ─────────────────────────────────────────────────────
    {
      name: 'leave for the overview',
      run: async (s) => {
        // The account menu is on a top-level screen only.
        await s.click(s.button('actionBack'));
        await s.hold(600);
        if (!(await s.button('accountTooltip').isVisible())) await s.click(s.button('actionBack'));
        await s.waitFor(s.button('accountTooltip'));
      },
    },
    ...signOut({
      title: { de: 'Alle Patenschaften', en: 'All patronages' },
      say: {
        de: 'Alle Patenschaften auf einen Blick hat die Koordination. Malte meldet sich an.',
        en: 'Coordinators see every patronage at a glance. Malte signs in.',
      },
    }),
    ...signIn({ as: 'coordinator' }),
    {
      name: 'from the dashboard',
      run: async (s) => {
        // Signing in returns to the profile, now Malte's.
        await s.expectText(MALTE);
        await s.click(s.button('actionBack'));
        await s.click(s.role('tab', s.t('navDashboard')));
        // The patronage teaser is the dashboard's last card, below the bottom
        // bar's edge: reveal() stops once a sliver of it touches the screen, so
        // wheel it up to the middle and let it be seen before the click.
        const teaser = s.role('button', s.t('sponsorshipsOverviewTitle'), { startsWith: true });
        await s.rest({ x: s.vp.width * 0.5, y: s.vp.height * 0.5 });
        await s.reveal(teaser);
        await s.pointer.wheel('down', 4);
        await s.hold(900);
        await s.click(teaser);
        await s.waitFor(s.textbox('sponsorshipsSearchHint'), { timeout: 15_000 });
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.6 });
      },
    },
    {
      name: 'what is given right now',
      say: {
        de: 'Oben steht, was gerade gegeben wird: laufende Patenschaften, pro Monat und einmalig. Das ist der Stand jetzt, an keinen Berichtszeitraum gebunden.',
        en: 'At the top is what is being given right now: running patronages, per month and one-off. It is the state as of now, tied to no reporting period.',
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.expectText(s.t('sponsorshipsTotalsNote'));
        const search = await s.box(s.textbox('sponsorshipsSearchHint'));
        await s.focus(s.textbox('sponsorshipsSearchHint'), {
          box: (b) => ({ x: b.x, y: 64, width: b.width, height: search.y - 64 }),
        });
      },
    },
    {
      name: 'the ended ones',
      run: async (s) => {
        await s.click(chip(s, s.t('sponsorshipStatusEnded')));
        await s.waitFor(s.role('button', s.rowOf(SPONSORS.petersen.name)));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.6 });
      },
    },
    {
      name: 'an archive',
      say: {
        de: (t) => `Unter „${t('sponsorshipStatusEnded')}“ liegt das Archiv – heute dazugekommen: Familie Petersen. Für eine Spendenquittung braucht ihr es noch.`,
        en: (t) => `“${t('sponsorshipStatusEnded')}” is the archive – the Petersens joined it today. You still need it for a donation receipt.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(SPONSORS.petersen.name)));
      },
    },
    {
      name: 'search',
      run: async (s) => {
        await s.click(chip(s, s.t('sponsorshipsFilterAll')));
        await s.type(s.textbox('sponsorshipsSearchHint'), ALBERS_SEARCH);
        await s.waitFor(s.role('button', s.rowOf(SPONSORS.albers.name, BIRDS.ole.name)), { timeout: 15_000 });
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.6 });
      },
    },
    {
      name: 'out of every keeper\'s reach',
      say: {
        de: 'Die Suche findet Paten und Orte. Jonas Albers spendet für Ole – doch Ole wurde ausgewildert. Keine Betreuung sieht diese Patenschaft mehr: nur hier.',
        en: 'The search finds sponsors and towns. Jonas Albers gives for Ole – but Ole was released. No keeper sees this patronage any more: only here.',
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(SPONSORS.albers.name, BIRDS.ole.name)));
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: 'Patenschaften sieht, wer die Voliere betreut. Zieht der Vogel um, gehen sie mit; beenden heißt: ein Datum. Und die Koordination sieht sie alle.',
        en: "Patronages are seen by the aviary's keeper. When the bird moves, they go with it; ending one is a date. And coordinators see them all.",
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
