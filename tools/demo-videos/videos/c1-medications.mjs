// C1 — Medications end to end. The first deep-explanation video: a carer's
// morning with the medication feature, told as one story on the demo dataset,
// with the reason for each piece in the narration.
//
//   Today          what is due, overdue in red
//   Fiete          a per-kg plan and his weight curve: why a RATE; the dose
//                  sheet derives the amount from the latest weighing; the
//                  give/pause rhythm moves the next due
//   Hedwig         a course is STOPPED, not deleted: it stays in the record and
//                  leaves Today
//   Dose round     Bruno, Lotte, Mats: one drug, three amounts, one tap
//   One course     how such a group course is written: the group switch, the
//   for three      drug catalogue, the rate preview, the cycle strip
//
// Lena (carer) is signed in throughout. The catalogue is a supervisor's admin
// screen; the video meets it where a carer does, in the prescription form's
// picker, and says who keeps it.
//
// setup() undoes this morning's Faucalin round (07:00) for the three young
// pigeons, so their round is honestly due when the video gives it: in the base
// dataset it was already given and the next one falls at 19:00, which no video
// should hand out ten hours early.
import { defineVideo, signIn } from '../harness/video.mjs';
import { BIRDS, WEIGHTS } from '../harness/data/demo/cast.mjs';
import { sig } from '../harness/data/demo/index.mjs';
import { PRODUCTS } from '../harness/data/demo/vocab.mjs';

const GROUP = ['bruno', 'lotte', 'mats'];
// Product names are invented and the same in both languages.
const NEMAKUR = PRODUCTS.dewormer.label.de;
const FAUCALIN = PRODUCTS.antiprotozoal.label.de;
const PLUMADOL = PRODUCTS.painRelief.label.de;

/** What a per-kg plan works out to for a bird of [g] grams: mg and ml, as the app rounds them. */
function doseOf(product, g) {
  const mg = sig((product.dose_rate * g) / 1000);
  return { mg, ml: sig(mg / product.concentration_per_ml) };
}
const FIETE = doseOf(PRODUCTS.dewormer, WEIGHTS.fiete.latest); // 2.92 mg, 0.292 ml
const BRUNO_ROUND = doseOf(PRODUCTS.antiprotozoal, WEIGHTS.bruno.latest); // 4.52 mg, 0.226 ml
const BRUNO_DEWORM = doseOf(PRODUCTS.dewormer, WEIGHTS.bruno.latest); // 2.26 mg, 0.226 ml

/** A number as the app writes it in [locale]: 0,292 / 0.292. */
const num = (locale, x) => (locale === 'de' ? String(x).replace('.', ',') : String(x));

export default defineVideo({
  id: 'C1',
  slug: 'medications',
  title: { de: 'Medikamente', en: 'Medications' },
  viewport: 'phone',
  dataset: 'demo',
  signInAs: 'carer',
  setup: async ({ seed }) => {
    const lena = await seed.as('carer');
    const meds = GROUP.map((k) => seed.demo.medications[`${k}Canker`]);
    // The dose round of 07:00 today: the only administrations of these plans
    // in the last four hours before the run instant.
    const since = new Date(Date.parse(seed.demo.now) - 4 * 3600_000).toISOString().replace('T', ' ');
    const rows = await lena.list('medication_administrations', `filter=${encodeURIComponent(
      `(${meds.map((m) => `medication="${m}"`).join(' || ')}) && administered_at >= "${since}"`)}`);
    if (rows.length !== GROUP.length) {
      throw new Error(`C1 setup: expected this morning's ${GROUP.length} ${FAUCALIN} doses, found ${rows.length}`);
    }
    for (const r of rows) await lena.remove('medication_administrations', r.id);
    return {};
  },
  steps: [
    ...signIn({
      say: {
        de: 'Vom Medikamentenkatalog bis zur Sammelgabe: So arbeitest du in Federfall mit Medikamenten.',
        en: 'From the drug catalogue to the dose round: this is how you work with medication in Federfall.',
      },
    }),

    // ── Today ────────────────────────────────────────────────────────────
    {
      name: 'open Today',
      title: { de: (t) => t('todayTitle'), en: (t) => t('todayTitle') },
      say: {
        de: (t) => `Es ist 9:40 Uhr. „${t('todayTitle')}“ zeigt ganz oben, welche Medikamente fällig sind – Überfälliges in Rot.`,
        en: (t) => `It is 9:40 am. “${t('todayTitle')}” lists the medication that is due at the top – anything overdue in red.`,
      },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navDashboard')));
        await s.click(s.button('worklistSeeAll'));
        await s.waitFor(s.role('group', s.t('doseRoundHeading', { drug: FAUCALIN, count: GROUP.length })));
        await s.rest();
      },
    },
    {
      name: "Fiete's dose is overdue",
      say: {
        de: 'Fiete, eine Stadttaube, bekommt eine Wurmkur. Seine Gabe von 8 Uhr steht noch aus.',
        en: "Fiete, a feral pigeon, is on a deworming course. His 8 o'clock dose is still to be given.",
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(`· ${BIRDS.fiete.name}`, NEMAKUR, s.t('worklistOverdueHours', { hours: 2 }))));
      },
    },

    // ── Fiete: a rate, and the dose it works out to ──────────────────────
    {
      name: 'open Fiete',
      title: { de: 'Dosis nach Gewicht', en: 'Dosing by weight' },
      run: async (s) => {
        await s.click(s.role('button', s.rowOf(`· ${BIRDS.fiete.name}`, NEMAKUR)));
        await s.waitFor(s.role('group', s.t('caseSectionCurrentTreatment'), { startsWith: true }));
        await s.rest();
      },
    },
    {
      name: 'the current treatment',
      say: {
        de: (t) => `„${t('caseSectionCurrentTreatment')}“ zeigt, was er bekommt: ${NEMAKUR}, ${PRODUCTS.dewormer.dose_rate} mg pro kg, fünf Tage Gabe, zwei Tage Pause.`,
        en: (t) => `“${t('caseSectionCurrentTreatment')}” shows what he is on: ${NEMAKUR}, ${PRODUCTS.dewormer.dose_rate} mg per kg, five days on, two days off.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        // The course's lines have no node of their own (the card is one
        // merged label); they sit left of its give-dose button.
        const card = await s.box(s.role('group', s.t('caseSectionCurrentTreatment'), { startsWith: true }));
        await s.focus(s.button('medLogDose'), {
          box: (b) => ({ x: card.x + 16, y: b.y - 8, width: b.x - card.x - 16, height: card.y + card.height - b.y }),
        });
      },
    },
    {
      name: 'his weight curve',
      say: {
        de: `Er kam abgemagert mit ${WEIGHTS.fiete.intake} g. Heute wiegt er ${WEIGHTS.fiete.latest} g – fast ein Viertel mehr.`,
        en: `He came in emaciated at ${WEIGHTS.fiete.intake} g. Today he weighs ${WEIGHTS.fiete.latest} g – almost a quarter more.`,
      },
      run: async (s) => {
        // The chart has no semantics node: it is the card between the
        // treatment card and the intake card, fully on screen here. Run the
        // pointer along the curve so its tooltip reads the first weighing,
        // then the last.
        const card = await s.box(s.role('group', s.t('caseSectionCurrentTreatment'), { startsWith: true }));
        const intake = await s.box(s.role('group', s.t('caseSectionIntake'), { startsWith: true }));
        const top = card.y + card.height + 16;
        const y = top + (intake.y - 16 - top) * 0.6;
        await s.pointer.moveTo(card.x + 56, y);
        await s.hold(2400);
        await s.pointer.moveTo(card.x + card.width - 16, y, { durationMs: 2600 });
      },
    },
    {
      name: 'why a rate',
      say: {
        de: 'Eine feste Menge vom ersten Tag wäre heute zu wenig. Deshalb verordnest du eine Rate pro Kilo: Die Dosis wächst mit dem Vogel.',
        en: 'A fixed amount from day one would now be too little. So you prescribe a rate per kilo, and the dose grows with the bird.',
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: 'open the dose sheet',
      run: async (s) => {
        await s.click(s.button('medLogDose'));
        await s.waitFor(s.button('doseCalcApply'));
        await s.rest({ x: s.vp.width * 0.82, y: s.vp.height * 0.62 });
      },
    },
    {
      name: 'the dose, worked out',
      say: {
        de: `Beim Eintragen rechnet die App mit der neuesten Wägung: ${PRODUCTS.dewormer.dose_rate} mg/kg × ${WEIGHTS.fiete.latest} g = ${num('de', FIETE.mg)} mg. Bei ${PRODUCTS.dewormer.concentration_per_ml} mg pro ml sind das ${num('de', FIETE.ml)} ml.`,
        en: `To log the dose, the app uses the latest weighing: ${PRODUCTS.dewormer.dose_rate} mg/kg × ${WEIGHTS.fiete.latest} g = ${num('en', FIETE.mg)} mg. At ${PRODUCTS.dewormer.concentration_per_ml} mg per ml, that is ${num('en', FIETE.ml)} ml.`,
      },
      zoom: { depth: 3 },
      run: async (s) => {
        // The derivation ("0,292 ml" over the arithmetic) has no node of its
        // own: it is the space left of "Übernehmen", under the rate field.
        const field = await s.box(s.textbox('doseCalcRate'));
        await s.focus(s.button('doseCalcApply'), {
          box: (b) => ({ x: field.x, y: b.y - 6, width: b.x - field.x - 8, height: b.height + 12 }),
        });
        await s.expectText(`${PRODUCTS.dewormer.dose_rate} mg/kg × ${WEIGHTS.fiete.latest} g = ${num(s.locale, FIETE.mg)} mg`);
      },
    },
    {
      name: 'a stale weight is not used',
      say: {
        de: 'Darüber steht, von wann das Gewicht ist. Ist es älter als drei Tage, rechnet die App nicht selbst – dann wird erst gewogen.',
        en: "Above it: when that weight was taken. If it is more than three days old, the app won't fill in a dose – weigh the bird first.",
      },
      zoom: { depth: 3 },
      run: async (s) => {
        // doseWeightMaxAge (federfall_models, dosing.dart) is three days.
        await s.focus(s.buttonStartingWith('doseCalcTitle'));
      },
    },
    {
      name: 'save the dose',
      run: async (s) => {
        await s.click(s.button('actionSave'));
        await s.gone(s.button('doseCalcApply'));
        await s.expectText(s.t('treatmentNextDose', { relative: s.t('worklistDueInHours', { hours: 24 }) }));
        await s.rest();
      },
    },
    {
      name: 'the next dose follows the rhythm',
      say: {
        de: 'Gespeichert. Die nächste Dosis ist in 24 Stunden fällig. An Pausetagen schlägt die App keine Gabe vor.',
        en: 'Saved. The next dose is due in 24 hours. On pause days, the app proposes no dose at all.',
      },
      zoom: { depth: 1 },
      run: async (s) => {
        const card = await s.box(s.role('group', s.t('caseSectionCurrentTreatment'), { startsWith: true }));
        await s.focus(s.button('medLogDose'), {
          box: (b) => ({ x: card.x + 16, y: b.y - 8, width: b.x - card.x - 16, height: card.y + card.height - b.y }),
        });
      },
    },

    // ── Hedwig: stop, don't delete ───────────────────────────────────────
    {
      name: 'open Hedwig',
      title: { de: 'Kur beenden', en: 'Stopping a course' },
      run: async (s) => {
        await s.click(s.button('actionBack'));
        await s.gone(s.role('tab', s.t('caseTabHistory')));
        await s.click(s.role('button', s.rowOf(`${BIRDS.hedwig.name} ·`)));
        await s.waitFor(s.button('medStopAction'));
        await s.rest();
      },
    },
    {
      name: 'her pain relief',
      say: {
        de: `Hedwig, eine Rabenkrähe mit Flügelbruch, bekommt ${PLUMADOL} gegen die Schmerzen. Das Schmerzmittel wird jetzt abgesetzt.`,
        en: `Hedwig, a carrion crow with a broken wing, is on ${PLUMADOL} for pain. The pain relief is now being stopped.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        const card = await s.box(s.role('group', s.t('caseSectionCurrentTreatment'), { startsWith: true }));
        await s.focus(s.button('medStopAction'), {
          box: (b) => ({ x: card.x + 16, y: b.y - 8, width: b.x + b.width - card.x - 16, height: card.y + card.height - b.y }),
        });
      },
    },
    {
      name: 'stop, not delete',
      say: {
        de: (t) => `Statt die Verordnung zu löschen, tippst du auf „${t('medStopAction')}“. Verordnung und protokollierte Dosen bleiben erhalten.`,
        en: (t) => `Instead of deleting the prescription, you tap “${t('medStopAction')}”. The prescription and every logged dose are kept.`,
      },
      run: async (s) => {
        await s.click(s.button('medStopAction'));
        await s.waitFor(s.button('medStopConfirmAction'));
        await s.rest({ x: s.vp.width * 0.6, y: s.vp.height * 0.78 });
      },
    },
    {
      name: 'stopped',
      say: {
        de: (t) => `Ab jetzt wird ${PLUMADOL} nicht mehr als fällig vorgeschlagen, auch nicht auf „${t('todayTitle')}“. Löschen bleibt für echte Fehleinträge.`,
        en: (t) => `From now on, ${PLUMADOL} is no longer proposed as due, not even on “${t('todayTitle')}”. Deleting is for genuine mistakes only.`,
      },
      run: async (s) => {
        await s.click(s.button('medStopConfirmAction'));
        await s.gone(s.button('medStopAction'));
        // The open diagnosis keeps the card; only the course left it. (With
        // no button left in it, the card's text merges into the tab's label.)
        await s.expectText(s.t('treatmentDiagnosesHeading'));
        // Beside the header, not on the weight chart that is now where the
        // course was (a resting pointer opens the chart's tooltip).
        await s.rest({ x: s.vp.width * 0.82, y: s.vp.height * 0.2 });
      },
    },

    // ── The dose round ───────────────────────────────────────────────────
    {
      name: 'back to Today',
      title: { de: (t) => t('doseRoundTitle'), en: (t) => t('doseRoundTitle') },
      run: async (s) => {
        await s.click(s.button('actionBack'));
        // The case's own "Übersicht" tab is on screen until it has gone.
        await s.gone(s.role('tab', s.t('caseTabHistory')));
        await s.click(s.role('tab', s.t('navDashboard')));
        await s.click(s.button('worklistSeeAll'));
        await s.waitFor(s.role('group', s.t('doseRoundHeading', { drug: FAUCALIN, count: GROUP.length })));
        await s.gone(s.role('button', s.rowOf(`· ${BIRDS.hedwig.name}`, PLUMADOL)), { what: "Hedwig's stopped course on Today" });
        await s.rest();
      },
    },
    {
      name: 'one drug, three birds',
      say: {
        de: `${PLUMADOL} ist von der Liste verschwunden. Bruno, Lotte und Mats, drei junge Stadttauben, bekommen gemeinsam ${FAUCALIN} gegen Trichomonaden.`,
        en: `${PLUMADOL} has gone from the list. Bruno, Lotte and Mats, three young feral pigeons, share a course of ${FAUCALIN} against trichomonads.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        const heading = await s.box(s.role('group', s.t('doseRoundHeading', { drug: FAUCALIN, count: GROUP.length })));
        await s.focus(s.role('button', s.rowOf(`· ${BIRDS.mats.name}`)), {
          box: (b) => ({ x: heading.x, y: heading.y, width: heading.width, height: b.y + b.height - heading.y }),
        });
      },
    },
    {
      name: 'open the round',
      say: {
        de: (t) => `Ihre Morgenrunde ist noch offen. „${t('doseRoundAction')}“ öffnet sie für alle drei auf einmal.`,
        en: (t) => `Their morning round is still open. “${t('doseRoundAction')}” opens it for all three at once.`,
      },
      run: async (s) => {
        await s.hold(1200);
        await s.click(s.button('doseRoundAction'));
        await s.waitFor(s.button('doseRoundSaveAction', { count: GROUP.length }));
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.32 });
      },
    },
    {
      name: 'an amount per bird',
      say: {
        de: `Jede Zeile rechnet mit dem eigenen Gewicht: Aus ${WEIGHTS.bruno.latest} g werden ${num('de', BRUNO_ROUND.ml)} ml, bei Lotte und Mats etwas anderes.`,
        en: `Each row works from that bird's own weight: ${WEIGHTS.bruno.latest} g makes ${num('en', BRUNO_ROUND.ml)} ml, and Lotte and Mats get their own amounts.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const first = s.role('checkbox', s.rowOf(`· ${BIRDS.bruno.name}`));
        const last = await s.box(s.role('checkbox', s.rowOf(`· ${BIRDS.mats.name}`)));
        await s.expectText(s.t('doseRoundDerivedVolume', { weight: `${WEIGHTS.bruno.latest} g`, volume: num(s.locale, BRUNO_ROUND.ml) }));
        await s.focus(first, { box: (b) => ({ ...b, height: last.y + last.height - b.y }) });
      },
    },
    {
      name: 'log the round',
      say: {
        de: (t) => `„${t('doseRoundSaveAction', { count: 3 })}“ speichert alle drei in einem Schritt – ganz oder gar nicht. So fehlt nie ein Vogel.`,
        en: (t) => `“${t('doseRoundSaveAction', { count: 3 })}” saves all three in one step – all or nothing, so no bird is ever left out.`,
      },
      run: async (s) => {
        await s.click(s.button('doseRoundSaveAction', { count: GROUP.length }));
        await s.gone(s.button('doseRoundSaveAction', { count: GROUP.length }));
        await s.waitFor(s.role('button', s.rowOf(`· ${BIRDS.bruno.name}`, s.t('worklistDueInHours', { hours: 12 }))));
        await s.rest();
      },
    },

    // ── One course for three ─────────────────────────────────────────────
    {
      name: 'a new prescription for Bruno',
      title: { de: 'Eine Kur für drei', en: 'One course for three' },
      say: {
        de: 'Jetzt sollen die drei auch eine Wurmkur bekommen. Eine neue Verordnung legst du im Verlauf an.',
        en: 'Now the three are to be dewormed as well. You add a new prescription from the history.',
      },
      run: async (s) => {
        await s.click(s.role('button', s.rowOf(`· ${BIRDS.bruno.name}`, s.t('worklistDueInHours', { hours: 12 }))));
        await s.click(s.role('tab', s.t('caseTabHistory')));
        await s.click(s.button('timelineAddEntry'));
        await s.click(s.button('timelineAddPrescription'));
        await s.waitFor(s.role('switch', s.t('prescriptionBatch'), { startsWith: true }));
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.45 });
      },
    },
    {
      name: 'for the whole group',
      say: {
        de: (t) => `Ganz oben schaltest du „${t('prescriptionBatch')}“ ein.`,
        en: (t) => `At the very top, you switch on “${t('prescriptionBatch')}”.`,
      },
      run: async (s) => {
        await s.click(s.role('switch', s.t('prescriptionBatch'), { startsWith: true }));
        await s.waitFor(s.role('checkbox', s.rowOf(`· ${BIRDS.lotte.name}`)));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'tick Lotte and Mats',
      say: {
        de: 'Du hakst Lotte und Mats an. Trotzdem bekommt jeder Vogel seine eigene Verordnung.',
        en: 'You tick Lotte and Mats. Each bird still gets a prescription of its own.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const lotte = s.role('checkbox', s.rowOf(`· ${BIRDS.lotte.name}`));
        const mats = s.role('checkbox', s.rowOf(`· ${BIRDS.mats.name}`));
        const top = await s.box(s.role('switch', s.t('prescriptionBatch'), { startsWith: true }));
        await s.focus(lotte, { box: (b) => ({ x: top.x, y: top.y, width: top.width, height: b.y + b.height - top.y }) });
        await s.click(mats);
        await s.click(lotte);
      },
    },
    {
      name: 'why separate prescriptions',
      say: {
        de: 'So lässt sich jede einzeln ändern oder beenden, sobald ein Vogel anders behandelt werden muss.',
        en: 'That way each one can be changed or stopped on its own, the moment one bird needs something different.',
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: 'from the catalogue',
      say: {
        de: (t) => `Die Auswahl kommt aus dem „${t('medProductsAdminTitle')}“, den die Leitung pflegt. Ein Griff füllt Rate, Konzentration, Gabeweg und Rhythmus aus.`,
        en: (t) => `The choices come from the “${t('medProductsAdminTitle')}”, kept by your supervisors. One pick fills in rate, strength, route and rhythm.`,
      },
      run: async (s) => {
        await s.click(s.button('medProductPicker'));
        await s.waitFor(s.role('menuitem', NEMAKUR));
        await s.hold(3000);
        await s.click(s.role('menuitem', NEMAKUR));
        await s.waitFor(s.textbox('medCycleRepeats'));
        // On to what the pick filled in: rate, strength and the preview
        // under it, down to the route.
        await s.focus(s.buttonStartingWith('medRoute'));
        await s.rest();
      },
    },
    {
      name: 'the rate, previewed',
      say: {
        de: `Die Rate steht in der Verordnung, die Vorschau rechnet sie gleich für Bruno aus: ${num('de', BRUNO_DEWORM.ml)} ml. Ein Tippfehler fällt so sofort auf.`,
        en: `The rate goes into the prescription, and the preview works it out for Bruno right away: ${num('en', BRUNO_DEWORM.ml)} ml. A typo shows up at once.`,
      },
      zoom: { depth: 3 },
      run: async (s) => {
        await s.expectText(`${PRODUCTS.dewormer.dose_rate} mg/kg × ${WEIGHTS.bruno.latest} g = ${num(s.locale, BRUNO_DEWORM.mg)} mg`);
        // The preview under the strength field has no node of its own.
        await s.focus(s.textbox('doseCalcConcentration'), {
          box: (b) => ({ x: b.x, y: b.y + b.height + 2, width: b.width * 0.55, height: 46 }),
        });
      },
    },
    {
      name: 'the rhythm, drawn',
      say: {
        de: 'Auch der Rhythmus kommt aus dem Katalog: fünf Tage Gabe, zwei Pause, drei Zyklen. Der Streifen zeigt die ganze Kur, das Enddatum setzt die App.',
        en: 'The rhythm comes from the catalogue too: five days on, two off, three cycles. The strip shows the whole course, and the app sets the end date.',
      },
      run: async (s) => {
        // Bring the strip and the end date below it on screen; the strip is
        // the space between the cycles field (plus its help text) and "Beginn".
        await s.focus(s.role('group', s.t('medEnded'), { startsWith: true }));
        const cycles = await s.box(s.textbox('medCycleRepeats'));
        const start = await s.box(s.buttonStartingWith('medStarted'));
        await s.pointer.moveTo(cycles.x + 250, (cycles.y + cycles.height + start.y) / 2 + 22);
        await s.hold(2500);
        await s.pointer.moveTo(start.x + 260, start.y + start.height + 40);
      },
    },
    {
      name: 'save for three',
      say: {
        de: (t) => `„${t('prescriptionBatchSaveAction', { count: 3 })}“ legt alle drei Verordnungen in einem Schritt an.`,
        en: (t) => `“${t('prescriptionBatchSaveAction', { count: 3 })}” creates all three prescriptions in one step.`,
      },
      run: async (s) => {
        await s.click(s.button('prescriptionBatchSaveAction', { count: GROUP.length }));
        await s.gone(s.button('prescriptionBatchSaveAction', { count: GROUP.length }));
        await s.waitFor(s.role('group', s.rowOf(s.t('prescriptionEventLabel', { drug: NEMAKUR }))));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.2 });
      },
    },
    {
      name: 'the new course',
      say: {
        de: (t) => `Oben im Verlauf steht die neue Kur, mit Rate, Rhythmus und Enddatum. Auf „${t('todayTitle')}“ erscheint sie als Runde für alle drei.`,
        en: (t) => `The new course sits at the top of the history, with rate, rhythm and end date. On “${t('todayTitle')}”, it shows up as a round for all three.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.focus(s.role('group', s.rowOf(s.t('prescriptionEventLabel', { drug: NEMAKUR }))));
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: 'Eine Rate statt fester Menge, die Dosis aus dem Gewicht, Pausen im Rhythmus, beenden statt löschen – und eine Runde mit einem Tipp.',
        en: 'A rate instead of a fixed amount, the dose from the weight, pauses in the rhythm, stop instead of delete – and a whole round in one tap.',
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
