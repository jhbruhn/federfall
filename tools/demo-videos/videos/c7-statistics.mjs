// C7 — Statistics and the annual report, at DESKTOP size (the one video that
// is). Malte, the coordinator, reads the station's year at his desk.
//
//   Statistics       coordinators and the supervisor; every case of the
//                    station, counted by when it was admitted
//   Rates            a rate is a share of the cases that ENDED, never of the
//                    intakes: the tile says of how many, and a bird still in
//                    care counts once its case ends
//   The comparison   the series against the same period a year earlier
//   A month          days instead of months; still compared with the same
//                    month last year, because the season decides the work
//   A dash, not 0 %  December has not begun: nothing has ended, so no rate
//   Behind a number  a breakdown row opens exactly its cases
//   The intake map   every find location, a pin opens the case
//   The report       the export sheet takes the same period with the same
//                    control; the server builds the report from the same
//                    cases. The PDF is shown opened in the browser.
//
// The export itself is not tapped: on this browser (Chromium on Linux, no Web
// Share) the share step fails in the wasm build and the sheet says "something
// went wrong" (federfall-1h9z.46). What the PDF button would hand over is
// fetched from the same report route, for the same period, as the same
// person, and opened in the browser window — so what is shown is the real
// report, not a mock-up.
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { defineVideo, signIn } from '../harness/video.mjs';
import { BASE_URL } from '../harness/lib/backend.mjs';

const MONTHS = {
  november: { de: 'November', en: 'November' },
  december: { de: 'Dezember', en: 'December' },
};

/** A semantics node with no node inside it whose text holds [text]: one KPI tile. */
const leaf = (s, text) => s.page.locator('flt-semantics:not(:has(flt-semantics))').filter({ hasText: text });
const intakesTile = (s) => s.role('button', s.rowOf(s.t('statsIntakes')));
const rateTile = (s) => leaf(s, s.t('statsReleaseRate'));
const chart = (s) => s.id('statistics-intake-chart');
const monthPicker = (s, label) => s.role('button', label);

/** Picks [month] (a MONTHS entry, or the whole year) from the period's month dropdown. */
async function pickMonth(s, from, to) {
  await s.click(monthPicker(s, from));
  await s.click(s.role('menuitem', to));
  await s.waitFor(monthPicker(s, to));
}

/** Scrolls the statistics page with the wheel over its middle. */
async function scroll(s, direction, clicks) {
  await s.pointer.moveTo(s.vp.width * 0.5, s.vp.height * 0.55);
  await s.pointer.wheel(direction, clicks);
  await s.hold(500);
}

export default defineVideo({
  id: 'C7',
  slug: 'statistics',
  title: { de: 'Statistik und Jahresbericht', en: 'Statistics and the annual report' },
  viewport: 'desktop',
  dataset: 'demo',
  signInAs: 'coordinator',
  maxMs: 12 * 60_000,
  setup: async ({ seed, locale }) => {
    const now = new Date(Date.parse(seed.demo.now));
    const year = now.getFullYear();
    // The report the PDF button asks for: the same route, period, language,
    // time zone and person (annual_report_sheet.dart, case_report_repository).
    const coordinator = await seed.as('coordinator');
    const query = new URLSearchParams({ year: String(year), lang: locale,
      tzOffsetMinutes: String(-now.getTimezoneOffset()) });
    const r = await fetch(`${BASE_URL}/api/federfall/reports/annual?${query}`, { headers: { Authorization: coordinator.token } });
    if (!r.ok) throw new Error(`annual report: ${r.status}`);
    return { year, pdf: Buffer.from(await r.arrayBuffer()) };
  },
  steps: [
    ...signIn({
      say: {
        de: 'Wie viele Vögel kamen dieses Jahr – und wie ging es für sie aus? Die Statistik, am großen Bildschirm.',
        en: 'How many birds came in this year – and how did they fare? The statistics, on a big screen.',
      },
    }),

    // ── The year ─────────────────────────────────────────────────────────
    {
      name: 'open the statistics',
      title: { de: (t) => t('statsTitle'), en: (t) => t('statsTitle') },
      run: async (s) => {
        await s.click(s.button('statsTitle'));
        await s.waitFor(intakesTile(s), { timeout: 20_000 });
        await s.rest({ x: s.vp.width * 0.6, y: s.vp.height * 0.92 });
      },
    },
    {
      name: 'who and what',
      say: {
        de: 'Die Statistik sehen Koordination und Leitung. Sie zählt alle Fälle der Station – nicht nur die eigenen.',
        en: "The statistics are for coordinators and the supervisor. They count every case of the station – not just one's own.",
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: 'the period',
      say: {
        de: (t) => `Oben der Zeitraum: dieses Jahr, das Vorjahr oder „${t('statsExportAllTime')}“. Gezählt werden die Fälle, die darin aufgenommen wurden.`,
        en: (t) => `At the top, the period: this year, last year or “${t('statsExportAllTime')}”. What counts are the cases admitted in it.`,
      },
      run: async (s) => {
        await s.expectText(String(s.data.year));
        const b = await s.box(s.role('button', String(s.data.year - 1)));
        await s.pointer.moveTo(b.x + b.width / 2, b.y + b.height + 24);
      },
    },
    {
      name: 'rates',
      title: { de: 'Quoten', en: 'Rates' },
      say: {
        de: 'Die Auswilderungsquote ist ein Anteil an den abgeschlossenen Fällen, nicht an allen Aufnahmen. Darunter steht, an wie vielen.',
        en: 'The release rate is a share of the cases that have ended, not of all intakes. Underneath, it says of how many.',
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.rest({ x: s.vp.width * 0.6, y: s.vp.height * 0.92 });
        await s.focus(rateTile(s));
      },
    },
    {
      name: 'still in care',
      say: {
        de: (t) => `Wer noch „${t('statsInCare')}“ ist, zählt erst mit, wenn sein Fall endet. Sonst sänke die Quote mit jedem neuen Vogel.`,
        en: (t) => `A bird still “${t('statsInCare')}” only counts once its case ends. Otherwise every new bird would pull the rate down.`,
      },
      zoom: { depth: 2 },
      run: async (s) => { await s.focus(rateTile(s)); },
    },
    {
      name: 'to the series',
      run: async (s) => {
        await scroll(s, 'down', 5);
        await s.waitFor(chart(s));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.1 });
      },
    },
    {
      name: 'the comparison',
      title: { de: 'Der Vergleich', en: 'The comparison' },
      say: {
        de: (t) => `„${t('statsSectionIntakesOverTime')}“: dunkel dieses Jahr, hell das Vorjahr. Im Frühjahr und Sommer kommen die meisten Jungvögel.`,
        en: (t) => `“${t('statsSectionIntakesOverTime')}”: dark is this year, light is last year. Spring and summer bring the most young birds.`,
      },
      run: async (s) => {
        await s.expectText(String(s.data.year - 1));
        await s.focus(chart(s));
      },
    },

    // ── A month ──────────────────────────────────────────────────────────
    {
      name: 'pick November',
      title: { de: 'Ein Monat', en: 'One month' },
      run: async (s) => {
        await scroll(s, 'up', 10);
        await pickMonth(s, s.t('statsPeriodWholeYear'), s.pick(MONTHS.november));
        await scroll(s, 'down', 5);
        await s.waitFor(chart(s));
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.1 });
      },
    },
    {
      name: 'days, and the same month last year',
      say: {
        de: 'Ein Monat zeigt jeden Tag. Verglichen wird mit dem November des Vorjahrs, nicht mit dem Oktober: In einer Station bestimmt die Jahreszeit, wie viel los ist.',
        en: 'A month shows every day. It is compared with last November, not with October: in a rescue, the season decides how busy it is.',
      },
      run: async (s) => { await s.focus(chart(s)); },
    },

    // ── A dash, not 0 % ──────────────────────────────────────────────────
    {
      name: 'pick December',
      title: { de: 'Strich statt 0 %', en: 'A dash, not 0 %' },
      run: async (s) => {
        await scroll(s, 'up', 10);
        await pickMonth(s, s.pick(MONTHS.november), s.pick(MONTHS.december));
        await s.expectText(s.t('statsRateBasis', { count: 0 }));
        await s.rest({ x: s.vp.width * 0.6, y: s.vp.height * 0.92 });
      },
    },
    {
      name: 'nothing has ended',
      say: {
        de: 'Der Dezember hat noch nicht begonnen, kein Fall ist abgeschlossen. Darum steht dort ein Strich – 0 % hieße, kein Vogel kam durch.',
        en: 'December has not begun yet, so no case has ended. That is why there is a dash – 0 % would mean no bird made it.',
      },
      zoom: { depth: 2 },
      run: async (s) => { await s.focus(rateTile(s)); },
    },

    // ── Behind a number ──────────────────────────────────────────────────
    {
      name: 'back to November, to the outcomes',
      title: { de: 'Hinter der Zahl', en: 'Behind a number' },
      run: async (s) => {
        await pickMonth(s, s.pick(MONTHS.december), s.pick(MONTHS.november));
        await s.reveal(s.role('button', s.rowOf(s.t('dispositionReleased'))));
        await scroll(s, 'down', 3);
        await s.rest({ x: s.vp.width * 0.3, y: s.vp.height * 0.5 });
      },
    },
    {
      name: 'every row is a way in',
      say: {
        de: (t) => `Jede Zeile einer Aufschlüsselung führt zu ihren Fällen. Ein Tipp auf „${t('dispositionReleased')}“ …`,
        en: (t) => `Every row of a breakdown leads to its cases. A tap on “${t('dispositionReleased')}” …`,
      },
      zoom: { depth: 2 },
      run: async (s) => {
        await s.focus(s.role('button', s.rowOf(s.t('dispositionReleased'))));
      },
    },
    {
      name: 'the cases behind it',
      run: async (s) => {
        await s.click(s.role('button', s.rowOf(s.t('dispositionReleased'))));
        await s.expectText(s.t('casesAllTitle'), { timeout: 15_000 });
        await s.rest({ x: s.vp.width * 0.75, y: s.vp.height * 0.8 });
      },
    },
    {
      name: 'exactly those',
      say: {
        de: '… öffnet die Fallliste mit Zeitraum und Ausgang schon eingestellt: genau die Fälle hinter der Zahl, auch abgeschlossene, von allen Pflegestellen.',
        en: '… opens the case list with the period and outcome already set: exactly the cases behind the number, closed ones too, from every carer.',
      },
      run: async (s) => { await s.hold(600); },
    },

    // ── The intake map ───────────────────────────────────────────────────
    {
      name: 'to the map',
      title: { de: (t) => t('intakeMapTitle'), en: (t) => t('intakeMapTitle') },
      run: async (s) => {
        await s.click(s.button('statsTitle'));
        await s.waitFor(intakesTile(s), { timeout: 20_000 });
        await s.click(s.role('group', s.t('intakeMapTitle'), { startsWith: true }));
        await s.waitFor(s.button('intakeMapPeriodThisYear'), { timeout: 15_000 });
        await s.waitFor(s.id('intake-map-pin').first());
        // Tiles: let them load before the camera dwells on the map.
        await s.hold(1500);
        await s.rest({ x: s.vp.width * 0.9, y: s.vp.height * 0.12 });
      },
    },
    {
      name: 'every find',
      say: {
        de: 'Jede Nadel ist ein Fundort aus diesem Jahr. Häufungen zeigen, wo besonders viele Vögel in Not geraten.',
        en: 'Every pin is a place a bird was found this year. Clusters show where many birds get into trouble.',
      },
      run: async (s) => { await s.hold(600); },
    },
    {
      name: 'one pin',
      run: async (s) => {
        // The southernmost pin: the one furthest from the cluster in town.
        const pins = s.id('intake-map-pin');
        const ys = await pins.evaluateAll((els) => els.map((e) => e.getBoundingClientRect().y));
        const i = ys.indexOf(Math.max(...ys.filter((y) => y < 680)));
        await s.click(pins.nth(i));
        await s.waitFor(s.button('intakeMapOpenCase'));
        await s.rest({ x: s.vp.width * 0.85, y: s.vp.height * 0.3 });
      },
    },
    {
      name: 'its case',
      say: {
        de: (t) => `Ein Tipp zeigt, welcher Vogel dort gefunden wurde – und „${t('intakeMapOpenCase')}“ führt zu seinem Fall.`,
        en: (t) => `A tap shows which bird was found there – and “${t('intakeMapOpenCase')}” leads to its case.`,
      },
      run: async (s) => { await s.hold(600); },
    },

    // ── The report ───────────────────────────────────────────────────────
    {
      name: 'the export sheet',
      title: { de: 'Der Bericht', en: 'The report' },
      run: async (s) => {
        await s.press('Escape');
        await s.gone(s.button('intakeMapOpenCase'));
        await s.click(s.button('actionBack'));
        await s.click(s.button('statsExportAction'));
        await s.waitFor(s.button('statsExportPdf'));
        await s.rest({ x: s.vp.width * 0.85, y: s.vp.height * 0.4 });
      },
    },
    {
      name: 'the same period',
      say: {
        de: 'Er übernimmt den Zeitraum vom Bildschirm, mit derselben Bedienung – ein Jahr heißt in beiden dasselbe.',
        en: 'It takes the period from the screen, with the same control – a year means the same in both.',
      },
      run: async (s) => {
        await s.expectText(String(s.data.year));
        await s.hold(300);
      },
    },
    {
      name: 'built on the server',
      say: {
        de: (t) => `Gebaut wird der Bericht auf dem Server, aus denselben Fällen wie die Statistik: „${t('statsExportPdf')}“ zum Weitergeben, „${t('statsExportCsv')}“ für die Tabellenkalkulation.`,
        en: (t) => `The server builds the report from the same cases as the statistics: “${t('statsExportPdf')}” to pass on, “${t('statsExportCsv')}” for a spreadsheet.`,
      },
      run: async (s) => {
        const pdf = await s.box(s.button('statsExportPdf'));
        await s.pointer.moveTo(pdf.x + pdf.width * 0.75, pdf.y + pdf.height + 4);
        await s.hold(300);
      },
    },
    {
      name: 'the PDF',
      run: async (s) => {
        await s.press('Escape');
        await s.gone(s.button('statsExportPdf'));
        // The report the button would hand over (see the header): opened in
        // this browser window, whose PDF viewer then fills the screen.
        const file = path.join(s.workDir, `${s.t('statsExportFileName', { period: s.data.year })}.pdf`);
        writeFileSync(file, s.data.pdf);
        // Without the page thumbnails, so the page is readable at this size.
        await s.page.goto(`file://${file}#navpanes=0`);
        // The viewer is not Flutter: nothing in the semantics tree to wait for.
        await s.hold(2500);
        await s.rest({ x: s.vp.width * 0.92, y: s.vp.height * 0.6 });
      },
    },
    {
      name: 'the summary',
      say: {
        de: 'So sieht der Jahresbericht aus: vorne die Zusammenfassung mit denselben Zahlen wie auf dem Bildschirm …',
        en: 'This is the annual report: first a summary with the same figures as on screen …',
      },
      run: async (s) => { await s.hold(300); },
    },
    {
      name: 'the case list',
      say: {
        de: '… dahinter jeder Fall in einer Zeile. Genau diese Tabelle liefert auch die CSV.',
        en: '… then every case on a line of its own. The CSV holds exactly this table.',
      },
      run: async (s) => {
        // Page 2 holds the end of the summary; the case list starts on page 3,
        // ~18 wheel clicks down at the viewer's zoom (a hash change does not
        // move the viewer).
        await s.pointer.moveTo(s.vp.width * 0.5, s.vp.height * 0.5);
        await s.pointer.wheel('down', 18);
        await s.hold(800);
        await s.rest({ x: s.vp.width * 0.92, y: s.vp.height * 0.6 });
      },
    },
    {
      name: 'in short',
      title: { de: 'Kurz gesagt', en: 'In short' },
      say: {
        de: 'Statistik und Bericht zählen dieselben Fälle im selben Zeitraum. Quoten zählen nur, was abgeschlossen ist – und jede Zahl führt zu ihren Fällen.',
        en: 'The statistics and the report count the same cases over the same period. Rates count only what has ended – and every number leads to its cases.',
      },
      run: async (s) => { await s.hold(300); },
    },
  ],
});
