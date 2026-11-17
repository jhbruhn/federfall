// A4 — The case at a glance. Lena opens Fiete, the feral pigeon with the
// fullest record in the demo dataset, and reads his case from the top: the
// name-first header, the two tabs, the current-treatment card, the weight
// chart, the photo gallery; then the History tab and the grouped add-entry
// sheet, from which she writes one short note.
import { defineVideo, signIn } from '../harness/video.mjs';
import { BIRDS, WEIGHTS } from '../harness/data/demo/cast.mjs';
import { PRODUCTS } from '../harness/data/demo/vocab.mjs';

const FIETE = BIRDS.fiete.name;
const NEMAKUR = PRODUCTS.dewormer.label.de;
// His intake photo and the journal photo of eight days ago.
const PHOTOS = 2;
const NOTE = {
  de: 'Frisst gut, der Kot ist heute fest und dunkel.',
  en: 'Eating well; droppings firm and dark today.',
};

export default defineVideo({
  id: 'A4',
  slug: 'case-at-a-glance',
  title: { de: 'Der Fall im Überblick', en: 'The case at a glance' },
  viewport: 'phone',
  dataset: 'demo',
  signInAs: 'carer',
  steps: [
    ...signIn({
      say: {
        de: 'Ein Fall in Federfall: oben der Vogel, darunter Übersicht und Verlauf.',
        en: 'A case in Federfall: the bird at the top, an overview and a history below.',
      },
    }),
    {
      name: 'open Fiete',
      title: { de: 'Der Kopf', en: 'The header' },
      run: async (s) => {
        await s.click(s.role('tab', s.t('navCases')));
        await s.click(s.role('button', s.rowOf(`${FIETE} ·`)));
        await s.waitFor(s.role('tab', s.t('caseTabHistory')));
        await s.rest({ x: s.vp.width * 0.86, y: s.vp.height * 0.55 });
      },
    },
    {
      name: 'name first',
      say: {
        de: (t) => `Oben steht der Vogel, nicht die Fallnummer: ${FIETE}, seine Art, die Fallnummer und der Status „${t('caseStatusInCare')}“.`,
        en: (t) => `The bird comes first, not the case number: ${FIETE}, his species, the case number and the status “${t('caseStatusInCare')}”.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        // The name is a button (it opens the animal record); the avatar sits
        // left of it and the status chip below.
        const tabs = await s.box(s.role('tab', s.t('caseTabOverview')));
        await s.focus(s.role('button', s.rowOf(s.t('caseOpenAnimal'), FIETE)), {
          box: (b) => ({ x: 16, y: b.y - 8, width: s.vp.width - 32, height: tabs.y - b.y }),
        });
      },
    },
    {
      name: 'the name opens the animal record',
      say: {
        de: 'Ein Tipp auf den Namen öffnet seine Tierakte, mit allen Fällen, die er je hatte.',
        en: 'Tap the name to open his animal record, with every case he has ever had.',
      },
      zoom: { depth: 3 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(s.t('caseOpenAnimal'), FIETE)));
      },
    },
    {
      name: 'two tabs',
      say: {
        de: (t) => `Darunter zwei Reiter: „${t('caseTabOverview')}“ für den Stand von heute, „${t('caseTabHistory')}“ für alles, was passiert ist.`,
        en: (t) => `Below it, two tabs: “${t('caseTabOverview')}” for where things stand today, “${t('caseTabHistory')}” for everything that happened.`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const history = await s.box(s.role('tab', s.t('caseTabHistory')));
        await s.focus(s.role('tab', s.t('caseTabOverview')), {
          box: (b) => ({ ...b, width: history.x + history.width - b.x }),
        });
      },
    },
    {
      name: 'the current treatment',
      title: { de: (t) => t('caseTabOverview'), en: (t) => t('caseTabOverview') },
      say: {
        de: (t) => `Ganz oben „${t('caseSectionCurrentTreatment')}“: offene Diagnosen, laufende Medikamente und wann die nächste Dosis fällig ist.`,
        en: (t) => `At the top, “${t('caseSectionCurrentTreatment')}”: open diagnoses, running medication and when the next dose is due.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        await s.expectText(NEMAKUR);
        await s.focus(s.role('group', s.t('caseSectionCurrentTreatment'), { startsWith: true }));
      },
    },
    {
      name: 'the weight chart',
      say: {
        de: `Darunter der Gewichtsverlauf: von ${WEIGHTS.fiete.intake} g bei der Aufnahme auf ${WEIGHTS.fiete.latest} g heute.`,
        en: `Below it, the weight trend: from ${WEIGHTS.fiete.intake} g on admission to ${WEIGHTS.fiete.latest} g today.`,
      },
      zoom: { depth: 1 },
      run: async (s) => {
        const chart = await s.focus(s.id('case-detail-weight-chart'));
        // Along the curve, so its tooltip reads the first weighing, then the last.
        const y = chart.y + chart.height * 0.6;
        await s.pointer.moveTo(chart.x + 72, y);
        await s.hold(1500);
        await s.pointer.moveTo(chart.x + chart.width - 24, y, { durationMs: 2200 });
      },
    },
    {
      name: 'scroll to the photos',
      title: { de: (t) => t('caseSectionPhotos'), en: (t) => t('caseSectionPhotos') },
      run: async (s) => {
        // The gallery is below the fold; the list builds it once scrolled near.
        await s.reveal(s.button('photoViewLabel', { index: PHOTOS, total: PHOTOS }));
        await s.pointer.wheel('down', 2);
        await s.hold(400);
        await s.reveal(s.button('photoViewLabel', { index: PHOTOS, total: PHOTOS }));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'every photo of the case',
      say: {
        de: 'Unter den Aufnahmedaten liegen alle Fotos des Falls zusammen: das vom Aufnahmetag und die aus dem Tagebuch.',
        en: 'Below the intake details, every photo of the case in one place: the one from admission day and those from the journal.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        const last = await s.box(s.button('photoViewLabel', { index: PHOTOS, total: PHOTOS }));
        await s.focus(s.button('photoViewLabel', { index: 1, total: PHOTOS }), {
          box: (b) => ({ x: b.x, y: b.y - 40, width: last.x + last.width - b.x, height: b.height + 40 }),
        });
      },
    },
    {
      name: 'open a photo',
      say: {
        de: 'Ein Tipp zeigt das Foto groß.',
        en: 'Tap one to see it full size.',
      },
      run: async (s) => {
        await s.click(s.button('photoViewLabel', { index: PHOTOS, total: PHOTOS }));
        await s.waitFor(s.button('imagePrevious'));
        await s.hold(1800);
        // The viewer's close button is Material's own (its tooltip comes from
        // the framework, not the ARB files): the app-bar button at the
        // leading edge, level with "Share".
        const share = await s.box(s.button('imageShareAction'));
        await s.pointer.moveTo(28, share.y + share.height / 2);
        await s.hold(150);
        await s.pointer.click();
        await s.waitFor(s.role('tab', s.t('caseTabHistory')));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'open the history',
      title: { de: (t) => t('caseTabHistory'), en: (t) => t('caseTabHistory') },
      run: async (s) => {
        await s.click(s.role('tab', s.t('caseTabHistory')));
        await s.waitFor(s.button('timelineAddEntry'));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.45 });
      },
    },
    {
      name: 'one chronology',
      say: {
        de: 'Im Verlauf steht alles in einer Zeitleiste, das Neueste oben: Gewichte, Dosen, Notizen, Befunde, Termine.',
        en: 'The history holds everything in one timeline, newest first: weights, doses, notes, findings, appointments.',
      },
      run: async (s) => {
        await s.expectText(`${WEIGHTS.fiete.latest} g`);
        await s.pointer.moveTo(s.vp.width / 2, s.vp.height * 0.6);
        await s.hold(800);
        await s.pointer.wheel('down', 3);
        await s.hold(1200);
        await s.pointer.wheel('up', 3);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.45 });
      },
    },
    {
      name: 'the add-entry sheet',
      title: { de: (t) => t('timelineAddEntryTitle'), en: (t) => t('timelineAddEntryTitle') },
      say: {
        de: (t) => `„${t('timelineAddEntry')}“ öffnet die Auswahl, nach Themen geordnet: Klinisch, Medikation, Bewegung, Abschluss.`,
        en: (t) => `“${t('timelineAddEntry')}” opens the choices, grouped by topic: clinical, medication, movement, closing the case.`,
      },
      run: async (s) => {
        await s.click(s.button('timelineAddEntry'));
        await s.waitFor(s.button('timelineAddNote'));
        await s.rest({ x: s.vp.width * 0.88, y: s.vp.height * 0.55 });
        await s.hold(1500);
        await s.pointer.wheel('down', 4);
        await s.hold(1800);
      },
    },
    {
      name: 'write a note',
      say: {
        de: 'Eine Notiz ist schnell geschrieben.',
        en: 'A note takes a moment.',
      },
      run: async (s) => {
        await s.click(s.button('timelineAddNote'));
        await s.type(s.textbox('journalFieldText'), s.pick(NOTE));
      },
    },
    {
      name: 'saved at the top',
      say: {
        de: 'Gespeichert steht sie ganz oben im Verlauf, mit Uhrzeit.',
        en: 'Once saved, it sits at the top of the history, with the time.',
      },
      run: async (s) => {
        await s.click(s.button('actionSave'));
        await s.gone(s.textbox('journalFieldText'));
        await s.expectText(s.pick(NOTE));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.6 });
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: 'Oben der Vogel, in der Übersicht der Stand von heute, im Verlauf die ganze Geschichte – und jeder neue Eintrag über einen Knopf.',
        en: 'The bird at the top, today in the overview, the whole story in the history – and every new entry from one button.',
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
