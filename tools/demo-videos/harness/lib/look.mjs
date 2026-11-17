// `look`: the demo dataset as the carer Lena sees it at the run instant —
// Today, Fiete's and Hedwig's cases — as screenshots plus a semantics dump of
// each screen (out/work/look.<locale>/). Not a video: nothing is captured or
// exported, and it is not in the video list. It exists to LOOK at the dataset
// under the run's clock while videos are written, and to diff two runs: the
// dumps hold every relative time the screens show ("Overdue by 2 h").
import { mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { labels } from './arb.mjs';
import { BASE_URL } from './backend.mjs';
import { prepareDataset } from './dataset.mjs';
import { Session } from './session.mjs';
import { launchBrowser, logStream, Pointer, setAppClock, startDisplay, VIEWPORTS } from './stage.mjs';
import { appClockMode } from './run.mjs';
import { DemoError, sleep, withTimeout } from './util.mjs';

const ARB_DIR = process.env.FFDEMO_ARB_DIR ?? '/arb';

export async function lookDemo({ locale, clock, workRoot, services }) {
  const dir = path.join(workRoot, `look.${locale}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const logFile = logStream(dir, 'run.log');
  const log = (msg) => {
    const line = `[look.${locale}] ${msg}`;
    console.log(line);
    logFile.write(`${line}\n`);
  };
  const vp = VIEWPORTS.phone;
  const t = labels(ARB_DIR, locale);
  let display;
  let browser;
  // FFDEMO_APP_CLOCK=real leaves the app on the real clock (to compare).
  const nowMs = appClockMode() === 'real' ? undefined : clock.nowMs;
  const body = async () => {
    services.setLocale(locale);
    const seed = await prepareDataset({ dataset: 'demo', locale, log, clock });
    display = await startDisplay(vp, { log: logStream(dir, 'xvfb.log') });
    browser = await launchBrowser({ display: display.display, vp, locale, url: `${BASE_URL}/`, log, nowMs });
    const { page } = browser;
    page.setDefaultTimeout(10_000);
    const pointer = new Pointer({ display: display.display, dpr: vp.dpr, clock: () => 0, start: { x: vp.width * 0.82, y: vp.height * 0.4 } });
    const s = new Session({ page, pointer, t, locale, vp, clock: () => 0, log, data: {} });
    s.workDir = dir;
    // A row's text is its aria-label; other text is a text node.
    const shown = (text) => page.locator('flt-semantics').filter({ hasText: text })
      .or(page.locator(`[aria-label*="${text}"]`)).first();
    const accessible = async () => {
      const placeholder = page.locator('flt-semantics-placeholder');
      await placeholder.waitFor({ state: 'attached', timeout: 60_000 });
      await placeholder.evaluate((el) => el.click());
    };
    // Each screen is opened by URL, i.e. a fresh page load: the app clock is
    // re-anchored to the run instant every time, so each dump reads the
    // screen at the run instant (+ the seconds it takes to load).
    const open = async (route, proof, tag) => {
      await page.goto(`${BASE_URL}${route}`);
      await accessible();
      const seen = nowMs === undefined ? { text: 'REAL' } : await setAppClock(page, nowMs);
      await s.waitFor(proof, { timeout: 30_000, what: `${route} (${tag})` });
      await sleep(1500);
      log(`${tag}: app clock reads ${seen.text}`);
      await s.dump(tag);
      // A second look further down: a Flutter list builds only what is near
      // the viewport, so the dump holds only what is on screen.
      await s.rest({ x: vp.width / 2, y: vp.height * 0.55 });
      await pointer.wheel('down', 6);
      await sleep(900);
      await s.dump(`${tag}-2`);
    };

    await accessible();
    const lena = seed.people.carer;
    await s.type(s.textbox('authEmailLabel'), lena.email, { delay: 5 });
    await s.type(s.textbox('authPasswordLabel'), lena.password, { delay: 5 });
    await s.click(s.button('authSignInAction'));
    await s.gone(s.button('authSignInAction'), { timeout: 20_000, what: 'the sign-in screen' });

    await open('/today', s.text(t('worklistGroupMeds')).first(), 'today');
    await open(`/cases/${seed.demo.cases.fiete}`, s.text('Fiete').first(), 'fiete');
    await open(`/cases/${seed.demo.cases.hedwig}`, s.text('Hedwig').first(), 'hedwig');
    // Her History: the quarantine ending today and this afternoon's appointment.
    await s.click(s.role('tab', t('caseTabHistory')));
    await sleep(1500);
    await s.dump('hedwig-history');
    await s.rest({ x: vp.width / 2, y: vp.height * 0.55 });
    await pointer.wheel('down', 6);
    await sleep(900);
    await s.dump('hedwig-history-2');

    // A record the app writes itself carries the APP's clock (administered_at)
    // while the server stamps `created` with the real one: log Hedwig's dose
    // from Today (one tap; her row is the second) and read where it lands.
    await page.goto(`${BASE_URL}/today`);
    await accessible();
    if (nowMs !== undefined) await setAppClock(page, nowMs);
    await s.waitFor(s.text(t('worklistGroupMeds')).first(), { timeout: 30_000 });
    await s.waitFor(shown('Plumadol'), { what: "Hedwig's Plumadol on Today" });
    await sleep(1000);
    await s.dump('today-before-dose');
    await s.click(page.getByRole('button', { name: t('worklistLogDose'), exact: true }).nth(1));
    await s.waitFor(shown(t('worklistDoseLogged')), { what: 'the "dose logged" note' });
    await sleep(1500);
    await s.dump('today-after-dose');
    await page.goto(`${BASE_URL}/cases/${seed.demo.cases.hedwig}`);
    await accessible();
    await s.waitFor(s.role('tab', t('caseTabHistory')), { timeout: 30_000 });
    await sleep(1000);
    await s.dump('hedwig-after-dose');
    await s.click(s.role('tab', t('caseTabHistory')));
    await sleep(1500);
    await s.dump('hedwig-history-after-dose');
    log(`screens in ${dir}`);
  };
  try {
    // Bounded: a page that hangs (a wasm trap leaves it unresponsive, and
    // page.evaluate has no timeout of its own) must fail the pass, not stall it.
    await withTimeout(body(), 5 * 60_000, `look (${locale})`);
    return { ok: true };
  } catch (e) {
    log(`FAILED: ${e instanceof DemoError ? e.message : e?.stack ?? e}`);
    if (browser) await browser.page.screenshot({ path: path.join(dir, 'failure.png') }).catch(() => {});
    return { ok: false };
  } finally {
    await browser?.context.close().catch(() => {});
    display?.stop();
    logFile.end();
  }
}
