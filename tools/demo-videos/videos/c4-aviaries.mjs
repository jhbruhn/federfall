// C4 — Aviaries. Lena's pigeon loft: who answers for an enclosure, what lives
// in it and what happened there, a new resident, and the whole loft
// vaccinated in one act.
//
//   Aviaries         every enclosure has a keeper; Lena keeps the loft
//   Bestand          the residents and their state: Hinkebein reads "in care"
//                    (Tarek treats him on a case) and still lives here — a case
//                    decides whether a bird is in care, never where it lives;
//                    the keeper holds every bird in the enclosure
//   Pflege           the flock log, and the diagnoses of birds while they lived
//                    here (the app keeps who lived here when); only the keeper,
//                    coordinators and the supervisor see the tab
//   New resident     a bird with no case goes straight into the enclosure
//   Vaccinating      "Vaccinate residents": everyone ticked, two unticked with
//                    a reason, one product from the org's own list prefills its
//                    target, one save for all — all or nothing, one entry each
//
// Lena (carer, keeper of the loft) is signed in throughout. Left out: the
// batch sheet's disabled "in someone else's care" rows. Only a keeper or a
// coordinator/supervisor is offered the sheet, and each of them holds every
// resident, so no row can be disabled (federfall-1h9z.44). The sheet also
// closes without the "N birds vaccinated" message (federfall-1h9z.45), so the
// save is proven on the new resident's record instead.
import { defineVideo, signIn } from '../harness/video.mjs';
import { AVIARIES, BIRDS } from '../harness/data/demo/cast.mjs';
import { SPECIES, VACCINES } from '../harness/data/demo/vocab.mjs';

const LOFT = AVIARIES.loft.name;
const NEWBIE = 'Krümel';
const ERNA = BIRDS.erna.name;
const FRIEDA = BIRDS.frieda.name;
const HINKEBEIN = BIRDS.hinkebein.name;
// An invented batch number in the shape the seeded ones have.
const BATCH = 'TP-2611-052';

const resident = (s, name) => s.role('button', s.rowOf(name, ' · '));
const tick = (s, name) => s.role('checkbox', s.rowOf(name));

export default defineVideo({
  id: 'C4',
  slug: 'aviaries',
  title: { de: 'Volieren', en: 'Aviaries' },
  viewport: 'phone',
  dataset: 'demo',
  signInAs: 'carer',
  steps: [
    ...signIn({
      say: {
        de: 'Manche Vögel bleiben für immer. Wie Volieren in Federfall funktionieren – am Beispiel von Lenas Taubenschlag.',
        en: "Some birds stay for good. How aviaries work in Federfall – using Lena's pigeon loft as the example.",
      },
    }),

    // ── The keeper ───────────────────────────────────────────────────────
    {
      name: 'the aviaries',
      title: { de: (t) => t('navAviaries'), en: (t) => t('navAviaries') },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navAviaries')));
        await s.waitFor(s.role('button', s.rowOf(s.pick(LOFT))));
        await s.rest();
      },
    },
    {
      name: 'every enclosure has a keeper',
      say: {
        de: 'Jede Voliere hat eine Person, die sie betreut. Den Taubenschlag betreut Lena, die Außenvoliere Malte.',
        en: 'Every aviary has one keeper. Lena keeps the pigeon loft, Malte the outdoor aviary.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const loft = await s.box(s.role('button', s.rowOf(s.pick(LOFT))));
        await s.focus(s.role('button', s.rowOf(s.pick(AVIARIES.outdoor.name))), {
          box: (b) => ({ ...b, height: loft.y + loft.height - b.y }),
        });
      },
    },

    // ── Bestand ──────────────────────────────────────────────────────────
    {
      name: 'open the loft',
      title: { de: (t) => t('aviaryTabBestand'), en: (t) => t('aviaryTabBestand') },
      run: async (s) => {
        await s.click(s.role('button', s.rowOf(s.pick(LOFT))));
        await s.waitFor(resident(s, HINKEBEIN));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.75 });
      },
    },
    {
      name: 'the residents',
      say: {
        de: (t) => `„${t('aviaryTabBestand')}“ zeigt, wer hier lebt: drei von zehn Plätzen. Erna und Frieda sind „${t('lifetimeStatusInAviary')}“.`,
        en: (t) => `“${t('aviaryTabBestand')}” shows who lives here: three of ten places. Erna and Frieda are “${t('lifetimeStatusInAviary')}”.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.expectText(s.t('aviaryOccupancyOfCapacity', { count: 3, capacity: AVIARIES.loft.capacity }));
        const last = await s.box(resident(s, HINKEBEIN));
        await s.focus(s.role('group', s.rowOf(s.pick(LOFT))), {
          box: (b) => ({ ...b, height: last.y + last.height - b.y }),
        });
      },
    },
    {
      name: 'Hinkebein is in care',
      say: {
        de: (t) => `Hinkebein ist krank und „${t('lifetimeStatusInCare')}“ – Tarek behandelt ihn. Er wohnt trotzdem hier: Ein Fall entscheidet, ob ein Vogel in Pflege ist, nie, wo er lebt.`,
        en: (t) => `Hinkebein is ill and “${t('lifetimeStatusInCare')}” – Tarek is treating him. He still lives here: a case decides whether a bird is in care, never where it lives.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(HINKEBEIN, s.t('lifetimeStatusInCare'))));
      },
    },
    {
      name: 'the keeper holds them all',
      say: {
        de: 'Als Betreuerin hält Lena jeden Vogel im Schlag und darf über ihn schreiben. Ist ein Vogel einmal hier eingezogen, sagen nur sie, die Koordination oder die Leitung, wohin er als Nächstes geht.',
        en: 'As keeper, Lena holds every bird in the loft and may write about it. Once a bird has moved in, only she, a coordinator or the supervisor can say where it goes next.',
      },
      run: async (s) => { await s.hold(300); },
    },

    // ── Pflege ───────────────────────────────────────────────────────────
    {
      name: 'the flock log',
      title: { de: (t) => t('aviaryTabPflege'), en: (t) => t('aviaryTabPflege') },
      run: async (s) => {
        await s.click(s.role('tab', s.t('aviaryTabPflege')));
        await s.waitFor(s.button('aviaryConditionOpenCase'));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.75 });
      },
    },
    {
      name: 'what happened here',
      say: {
        de: (t) => `„${t('aviaryTabPflege')}“ ist das Tagebuch des Schlags: Putzen, Umbauten, Beobachtungen an der ganzen Gruppe.`,
        en: (t) => `“${t('aviaryTabPflege')}” is the loft's own log: cleaning, changes, what the whole group is doing.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.focus(s.role('tablist'), {
          box: (b) => ({ x: 16, y: b.y + b.height + 8, width: 380, height: 250 }),
        });
      },
    },
    {
      name: 'diagnoses while they lived here',
      say: {
        de: 'Dazwischen stehen Diagnosen der Bewohner – aber nur aus der Zeit, in der sie hier lebten. Die App merkt sich, wer wann eingezogen und ausgezogen ist.',
        en: 'In between are diagnoses of residents – but only from the time they lived here. The app remembers who moved in and out, and when.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('group', s.rowOf(HINKEBEIN)).filter({ has: s.button('aviaryConditionOpenCase') }));
      },
    },
    {
      name: 'who sees it',
      say: {
        de: 'Diesen Reiter sehen nur Lena, die Koordination und die Leitung. Den Bestand sieht dagegen jeder – sonst ließe sich ein Vogel, der wiederkommt, nicht erkennen.',
        en: 'Only Lena, the coordinators and the supervisor see this tab. The residents, though, are visible to everyone – otherwise a bird that comes back could not be recognised.',
      },
      run: async (s) => { await s.hold(300); },
    },

    // ── A new resident ───────────────────────────────────────────────────
    {
      name: 'add a resident',
      title: { de: 'Neuer Bewohner', en: 'A new resident' },
      say: {
        de: (t) => `Ein neuer Vogel ohne Fall, etwa eine abgegebene, zahme Taube, zieht direkt ein: „${t('aviaryAddResident')}“.`,
        en: (t) => `A new bird without a case, such as a tame pigeon someone hands in, moves straight in: “${t('aviaryAddResident')}”.`,
      },
      run: async (s) => {
        await s.click(s.role('tab', s.t('aviaryTabBestand')));
        await s.click(s.button('aviaryAddResident'));
        await s.waitFor(s.textbox('caseFieldName'));
        await s.type(s.textbox('caseFieldSpecies'), s.pick(SPECIES.feralPigeon));
        await s.click(s.role('button', s.pick(SPECIES.feralPigeon)));
        await s.type(s.textbox('caseFieldName'), NEWBIE);
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.45 });
      },
    },
    {
      name: 'save the resident',
      run: async (s) => {
        await s.click(s.button('actionSave'));
        await s.waitFor(resident(s, NEWBIE), { timeout: 15_000 });
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.75 });
      },
    },
    {
      name: 'moved in today',
      say: {
        de: (t) => `${NEWBIE} steht im Bestand, „${t('lifetimeStatusInAviary')}“. Ihr Aufenthalt hier beginnt heute.`,
        en: (t) => `${NEWBIE} is among the residents, “${t('lifetimeStatusInAviary')}”. Its residency here starts today.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(resident(s, NEWBIE));
      },
    },

    // ── Vaccinating the loft ─────────────────────────────────────────────
    {
      name: 'open the batch sheet',
      title: { de: (t) => t('vaccinationBatchTitle'), en: (t) => t('vaccinationBatchTitle') },
      say: {
        de: (t) => `Geimpft wird der ganze Schlag auf einmal: „${t('vaccinationBatchAction')}“.`,
        en: (t) => `The whole loft is vaccinated in one go: “${t('vaccinationBatchAction')}”.`,
      },
      run: async (s) => {
        await s.click(s.button('vaccinationBatchAction'));
        await s.waitFor(tick(s, NEWBIE));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.55 });
      },
    },
    {
      name: 'everyone ticked',
      say: {
        de: 'Alle Bewohner sind schon angehakt. Erna hat ihre Pockenimpfung im Frühjahr bekommen, Hinkebein ist krank – Lena nimmt beide heraus.',
        en: 'Every resident is ticked already. Erna had her pox shot in the spring, and Hinkebein is ill – so Lena takes both out.',
      },
      zoom: { depth: 1 },
      run: async (s) => {
        const last = await s.box(tick(s, HINKEBEIN));
        await s.focus(tick(s, ERNA), { box: (b) => ({ ...b, height: last.y + last.height - b.y }) });
        await s.hold(2500);
        await s.click(tick(s, ERNA));
        await s.click(tick(s, HINKEBEIN));
      },
    },
    {
      name: 'pick the vaccine',
      run: async (s) => {
        await s.type(s.textbox('vaccinationFieldVaccine'), 'Sentinova');
        await s.click(s.role('button', s.pick(VACCINES.pox.vaccine)));
        // A field's value is in neither the semantics tree nor the DOM (the
        // canvas draws it): the stills show the target filled in.
        await s.hold(800);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: "from the org's own list",
      say: {
        de: 'Der Impfstoff kommt aus dem, was ihr schon einmal eingetragen habt. Wogegen er schützt, füllt die App gleich mit aus.',
        en: 'The vaccine comes from what your team has entered before. The app fills in what it protects against as well.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const target = await s.box(s.textbox('vaccinationFieldTarget'));
        await s.focus(s.textbox('vaccinationFieldVaccine'), {
          box: (b) => ({ ...b, height: target.y + target.height - b.y }),
        });
      },
    },
    {
      name: 'the batch number',
      say: {
        de: 'Die Chargennummer steht auf der Ampulle. Gibt es je einen Rückruf, findest du damit jeden Vogel, der sie bekommen hat.',
        en: 'The batch number is on the vial. Should there ever be a recall, it finds every bird that had it.',
      },
      run: async (s) => {
        await s.type(s.textbox('vaccinationFieldBatch'), BATCH);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'save for two',
      run: async (s) => {
        await s.click(s.button('vaccinationBatchSaveAction', { count: 2 }));
        await s.gone(s.button('vaccinationBatchSaveAction', { count: 2 }), { timeout: 15_000 });
        await s.waitFor(resident(s, NEWBIE));
        await s.rest({ x: s.vp.width * 0.7, y: s.vp.height * 0.4 });
      },
    },
    {
      name: 'one act',
      say: {
        de: 'Ein Tipp, zwei Vögel geimpft. Gespeichert wird alles oder nichts – ein halb eingetragener Bestand sähe sonst aus wie Absicht.',
        en: 'One tap, two birds vaccinated. It saves everything or nothing – otherwise a half-recorded flock would look intentional.',
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: 'open the new resident',
      run: async (s) => {
        await s.click(resident(s, NEWBIE));
        const card = s.role('group', s.t('animalSectionVaccinations'), { startsWith: true });
        await s.reveal(card);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'one entry each',
      say: {
        de: 'Trotzdem bekommt jeder Vogel seinen eigenen Eintrag in der Tierakte. Zieht er um, nimmt er seine Impfungen mit.',
        en: 'Each bird still gets an entry of its own in its animal record. If it moves, its vaccinations go with it.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.expectText(BATCH);
        await s.focus(s.role('group', s.t('animalSectionVaccinations'), { startsWith: true }));
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: 'Eine Voliere hat eine Betreuung, die jeden Vogel darin hält. Der Bestand zeigt, wer hier lebt, die Pflege, was hier geschah – und geimpft wird der Schlag in einem Schritt.',
        en: 'An aviary has one keeper, who holds every bird in it. The residents tab shows who lives there, the care tab what happened there – and the whole loft is vaccinated in one step.',
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
