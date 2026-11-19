// One video in one language: fresh backend + dataset → setup → record → document → export.
//
// A run either ends with `<id>-<slug>.<locale>.mp4` in the output directory or
// with a failure record and NO clip under that name (an older clip of the same
// name is removed, see runner/entry.sh). There is no retry: a failure is
// reported with its cause, a screenshot and a dump of what was on screen.
import { mkdirSync, rmSync, writeFileSync, copyFileSync, appendFileSync, renameSync } from 'node:fs';
import path from 'node:path';
import { labels } from './arb.mjs';
import { BASE_URL } from './backend.mjs';
import { prepareDataset } from './dataset.mjs';
import { Session } from './session.mjs';
import { launchBrowser, logStream, Pointer, setAppClock, startCapture, startDisplay, VIEWPORTS } from './stage.mjs';
import { cursorTrack, exportClip, frameArt, LOOK, writeDocument } from './openscreen.mjs';
import { DemoError, probeVideo, sleep, withTimeout } from './util.mjs';

const ARB_DIR = process.env.FFDEMO_ARB_DIR ?? '/arb';

/**
 * The most characters a step title fits on one line of the title band (phone
 * look): "Fiete: Dosis nach Gewicht" (25) wrapped and was clipped, "Hedwig: Kur
 * beenden" (19) fit. Checked before anything is recorded.
 */
export const TITLE_MAX = 20;

export function clipName(video, locale) {
  return `${video.id}-${video.slug}.${locale}.mp4`;
}

/** Reading time for a caption: long enough to read twice at subtitle pace. */
export function readingMs(text) {
  return text ? Math.max(1800, 700 + text.length * 62) : 0;
}

/**
 * Whether the app runs on the run's clock (the default) or on the real one:
 * FFDEMO_APP_CLOCK=real, a diagnostic for comparing the two.
 */
export function appClockMode(env = process.env) {
  const v = (env.FFDEMO_APP_CLOCK ?? '').trim();
  if (v && v !== 'real' && v !== 'run') throw new DemoError(`FFDEMO_APP_CLOCK must be "run" or "real", got "${v}"`);
  return v || 'run';
}

/** Refuses a run instant the backend's real clock would contradict (data/demo/clock.mjs). */
export function requireServerAgrees(clock) {
  if (clock.serverAgrees()) return;
  throw new DemoError(`the run instant ${clock.nowLabel} is ${clock.skewHours()} h from the real clock; ` +
    'the backend keeps the real clock, so a recording needs the run day within a day of today ' +
    '(FFDEMO_RUN_DAY is for comparing seedings with `check`)');
}

export async function recordOne({ video, locale, workRoot, outRoot, services, noExport, clock: runClock }) {
  const name = clipName(video, locale);
  const dir = path.join(workRoot, `${video.id}.${locale}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const logFile = logStream(dir, 'run.log');
  const started = Date.now();
  const log = (msg) => {
    const line = `[${video.id}.${locale} +${((Date.now() - started) / 1000).toFixed(1)}s] ${msg}`;
    console.log(line);
    logFile.write(`${line}\n`);
  };
  const result = { video: video.id, locale, clip: name, status: 'failed', error: null, timings: {}, appClock: null };
  const mark = (k) => { result.timings[k] = Math.round((Date.now() - started) / 100) / 10; };

  const vpName = video.viewport ?? 'phone';
  const vp = VIEWPORTS[vpName];
  const t = labels(ARB_DIR, locale);
  let display;
  let exportDisplay;
  let browser;
  let capture;
  let page;
  let aborted = false;

  const cleanup = async () => {
    // A failed run keeps a playable capture (ffmpeg finishes the file on
    // "q"; a kill leaves it without its index): it is what shows how a frozen
    // page got there. stop() is bounded and kills on its own timeout.
    await capture?.stop().catch(() => capture?.kill());
    // Bounded: a page whose renderer is stuck (federfall-1h9z.38) can leave
    // close() waiting forever.
    await withTimeout(browser?.context.close() ?? Promise.resolve(), 15_000, 'closing the browser').catch(() => {});
    display?.stop();
    exportDisplay?.stop();
  };

  const body = async () => {
    services.setLocale(locale);
    const realClock = appClockMode() === 'real';
    if (!realClock) requireServerAgrees(runClock);
    log(`app clock: ${realClock ? 'REAL (FFDEMO_APP_CLOCK=real)' : `${runClock.nowLabel} at the first frame, ${runClock.skewHours()} h from the real clock`}`);
    // Titles are checked before anything is seeded or recorded.
    video.steps.forEach((def, i) => {
      const title = typeof def.title?.[locale] === 'function' ? def.title[locale](t) : def.title?.[locale];
      if (title && title.length > TITLE_MAX) {
        throw new DemoError(`step ${i + 1} "${def.name ?? ''}": title "${title}" is ${title.length} characters; the band holds ${TITLE_MAX} on one line`);
      }
    });
    const seed = await prepareDataset({ dataset: video.dataset, locale, log, clock: runClock });
    const data = (await video.setup?.({ seed, locale })) ?? {};
    const person = seed.people[video.signInAs];
    if (!person) throw new DemoError(`signInAs "${video.signInAs}" is not a seeded person`);
    mark('seeded');

    display = await startDisplay(vp, { log: logStream(dir, 'xvfb.log') });
    browser = await launchBrowser({ display: display.display, vp, locale, url: `${BASE_URL}/`, log,
      nowMs: realClock ? undefined : runClock.nowMs });
    page = browser.page;
    page.setDefaultTimeout(10_000);
    // Flutter web paints to a canvas; the semantics tree that Playwright reads
    // is built only once the engine's off-screen "Enable accessibility"
    // placeholder is activated. Playwright's click() refuses it (outside the
    // viewport), a DOM click works. It changes nothing that is drawn.
    const placeholder = page.locator('flt-semantics-placeholder');
    await placeholder.waitFor({ state: 'attached', timeout: 60_000 }).catch((e) => {
      throw new DemoError(`the app did not start: no semantics placeholder (${e.message.split('\n')[0]})`);
    });
    await placeholder.evaluate((el) => el.click());

    const pointer = new Pointer({ display: display.display, dpr: vp.dpr, clock: () => 0,
      start: { x: vp.width * 0.82, y: vp.height * 0.4 } });
    const s = new Session({ page, pointer, t, locale, vp, clock: () => 0, log, data: { ...data, person, seed } });
    s.workDir = dir;
    // Rendered now, not on camera.
    for (const a of video.assets ?? []) await s.asset(a);
    await s.waitFor(s.textbox('authEmailLabel'), { timeout: 60_000, what: 'the sign-in screen' });
    await pointer.xdo('mousemove', Math.round(pointer.at.x * vp.dpr), Math.round(pointer.at.y * vp.dpr));
    // Let the first frame settle (fonts, the logo) before the clip starts.
    await sleep(800);
    mark('app-ready');

    const captureFile = path.join(dir, 'capture.mp4');
    capture = startCapture({ ...display, file: captureFile, log: logStream(dir, 'ffmpeg.log') });
    const firstFrameMs = await capture.firstFrame();
    // Every video starts at the same app moment, however long the run (and
    // this video's setup) has taken so far.
    if (!realClock) {
      const seen = await setAppClock(page, runClock.nowMs);
      result.appClock = new Date(seen.now).toISOString();
      log(`app clock set: the page reads ${seen.text}`);
    }
    const t0 = Date.now();
    const clock = () => Date.now() - t0;
    pointer.clock = clock;
    s.clock = clock;
    pointer.sample(pointer.at.x, pointer.at.y);

    const introText = video.title[locale];
    const introMs = video.introMs ?? 2200;
    await sleep(introMs);
    const steps = [];
    for (const [i, def] of video.steps.entries()) {
      const label = def.name ?? `step ${i + 1}`;
      // Narration may name a UI label: `(t) => `… ${t('caseCreateAction')} …``.
      const text = (v) => (typeof v === 'function' ? v(t) : v);
      const rec = { index: i, name: label, zoom: def.zoom ?? null,
        title: def.title ? { [locale]: text(def.title[locale]) } : undefined,
        say: def.say ? { [locale]: text(def.say[locale]) } : undefined,
        startMs: clock(), endMs: 0, events: [], focus: null };
      s.step = rec;
      log(`step ${i + 1}/${video.steps.length}: ${label}`);
      try {
        await withTimeout(Promise.resolve(def.run?.(s)), def.timeoutMs ?? 30_000, `step ${i + 1} "${label}"`);
      } catch (e) {
        throw new DemoError(`step ${i + 1} "${label}": ${e.message}`);
      }
      const busy = clock() - rec.startMs;
      const minMs = Math.max(readingMs(rec.say?.[locale]), def.minMs ?? 0);
      await sleep(Math.max(def.hold ?? 700, minMs - busy));
      rec.endMs = clock();
      steps.push(rec);
    }
    await sleep(video.outroMs ?? 1200);
    const tEnd = clock();
    await capture.stop();
    capture = null;
    mark('captured');

    // Align the harness clock with the capture: script time 0 is t0, capture
    // time 0 is ffmpeg's first frame, both on the wall clock. (Aligning on the
    // common END instead, as federfall-1h9z.2 did, was measured ~350 ms late in some
    // runs: ffmpeg's stop latency varies.)
    const meta = await probeVideo(captureFile);
    const offset = t0 - firstFrameMs;
    const tail = meta.durationMs - tEnd - offset;
    log(`capture ${meta.width}x${meta.height}, ${meta.durationMs} ms; clock offset ${offset} ms; stop latency ${tail} ms`);
    if (offset < 0 || offset > 3000 || tail < -200) {
      throw new DemoError(`capture and script clocks disagree (offset ${offset} ms, tail ${tail} ms)`);
    }
    for (const st of steps) {
      st.startMs += offset;
      st.endMs += offset;
      for (const ev of st.events) ev.timeMs += offset;
      if (st.focus) st.focus.timeMs += offset;
    }
    for (const p of pointer.samples) p.timeMs += offset;
    const intro = { text: introText, startMs: offset + 150, endMs: offset + introMs + 600 };
    writeFileSync(path.join(dir, 'timeline.json'), JSON.stringify({ intro, steps }, null, 2));

    const docFile = writeDocument({
      dir, video, locale, vpName, vp, steps, captureFile, meta, intro,
      cursor: cursorTrack(pointer.samples, vp), art: await frameArt({ dir, look: LOOK[vpName], vp }),
    });
    await browser.context.close();
    browser = null;
    display.stop();
    display = null;
    if (noExport) result.status = 'captured';
    else exportArgs = { docFile, durationMs: meta.durationMs };
  };

  // The export runs outside the whole-run budget: that budget is for a hung
  // app, and exportClip has its own hang guard, scaled to the clip's length.
  // On a slow host (a hosted CI runner) the export alone outlasted 8 min.
  let exportArgs = null;
  const exportAndPublish = async () => {
    if (!exportArgs) return;
    const { docFile, durationMs } = exportArgs;
    exportDisplay = await startDisplay({ width: 640, height: 480, dpr: 1 }, { log: logStream(dir, 'xvfb-export.log') });
    const exported = path.join(dir, 'export.mp4');
    const out = await exportClip({ docFile, outFile: exported, durationMs,
      display: exportDisplay.display, log: logStream(dir, 'openscreen.log') });
    mark('exported');
    log(`exported ${out.width}x${out.height}, ${out.durationMs} ms`);
    if (aborted) return;
    mkdirSync(outRoot, { recursive: true });
    copyFileSync(exported, path.join(outRoot, `.${name}.tmp`));
    renameSync(path.join(outRoot, `.${name}.tmp`), path.join(outRoot, name));
    result.status = 'passed';
  };

  const budgetMs = video.maxMs ?? 8 * 60_000;
  try {
    await withTimeout(body(), budgetMs, `the whole run (${budgetMs / 1000} s)`);
    await exportAndPublish();
  } catch (e) {
    aborted = true;
    result.error = e instanceof DemoError ? e.message : String(e?.stack ?? e);
    log(`FAILED: ${result.error}`);
    if (page) {
      await page.screenshot({ path: path.join(dir, 'failure.png'), timeout: 5000 }).catch(() => {});
      // Bounded like everything else: page.evaluate has no timeout of its
      // own, and on a frozen page (a renderer stuck at 100 % CPU, seen in C1)
      // it never returns — that kept a recorder alive for half an hour.
      const dump = await withTimeout(page.evaluate(() => [...document.querySelectorAll('flt-semantics, flt-semantics-host input, flt-semantics-host textarea')]
        .filter((e) => e.getAttribute('role') || e.getAttribute('aria-label') || e.childElementCount === 0)
        .map((e) => {
          const r = e.getBoundingClientRect();
          const name = e.getAttribute('aria-label') ?? (e.textContent ?? '').trim().slice(0, 60);
          const id = e.getAttribute('flt-semantics-identifier');
          return `${e.getAttribute('role') ?? '-'} "${name}"${id ? ` #${id}` : ''} @${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}`;
        }).join('\n')), 10_000, 'the failure dump').catch((dumpError) => {
        // A page that is already closed (a failure in the export, after
        // capture) rejects at once: that is not a freeze.
        if (!(dumpError instanceof DemoError)) return `(no dump: ${dumpError?.message ?? dumpError})`;
        // Say so in the verdict: a frozen app is a different bug from a
        // missing label, and the screenshot alone looks like a wrong screen.
        result.error += ' — and the page then stopped answering (frozen renderer, see federfall-1h9z.38)';
        log('the page did not answer the failure dump within 10 s: frozen');
        return '(no dump: the page did not answer within 10 s)';
      });
      writeFileSync(path.join(dir, 'failure-semantics.txt'), `${page.url()}\n${dump}\n`);
    }
    mkdirSync(outRoot, { recursive: true });
    appendFileSync(path.join(outRoot, '.unpublish'), `${name}\n`);
  } finally {
    await cleanup();
    mark('total');
    writeFileSync(path.join(dir, 'result.json'), JSON.stringify(result, null, 2));
    logFile.end();
  }
  return result;
}

/**
 * Re-renders an earlier capture with the current look and document code,
 * without driving the app again: `export <ID>`. For tuning the look; a script
 * change needs a new recording.
 */
export async function reexportOne({ video, locale, workRoot, outRoot }) {
  const { readFileSync } = await import('node:fs');
  const dir = path.join(workRoot, `${video.id}.${locale}`);
  const name = clipName(video, locale);
  const vpName = video.viewport ?? 'phone';
  const vp = VIEWPORTS[vpName];
  const captureFile = path.join(dir, 'capture.mp4');
  const { intro, steps } = JSON.parse(readFileSync(path.join(dir, 'timeline.json'), 'utf8'));
  const cursor = JSON.parse(readFileSync(`${captureFile}.cursor.json`, 'utf8'));
  const meta = await probeVideo(captureFile);
  const art = await frameArt({ dir, look: LOOK[vpName], vp });
  const docFile = writeDocument({ dir, video, locale, vpName, vp, steps, captureFile, meta, intro, cursor, art });
  const display = await startDisplay({ width: 640, height: 480, dpr: 1 }, { log: logStream(dir, 'xvfb-export.log') });
  try {
    const exported = path.join(dir, 'export.mp4');
    await exportClip({ docFile, outFile: exported, durationMs: meta.durationMs, display: display.display,
      log: logStream(dir, 'openscreen.log') });
    mkdirSync(outRoot, { recursive: true });
    copyFileSync(exported, path.join(outRoot, name));
  } finally {
    display.stop();
  }
  return { video: video.id, locale, clip: name, status: 'passed', error: null, timings: {} };
}
