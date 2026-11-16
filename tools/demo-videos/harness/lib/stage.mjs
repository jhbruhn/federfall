// The "stage": an X display sized to the viewport, a headed Chromium filling
// it, the real X pointer, and the ffmpeg capture of that display.
//
// Why not Playwright's own recorder or mouse: recordVideo ignores the device
// scale factor (soft, low-bitrate VP8), and page.mouse is CDP-synthetic — it
// never moves the X pointer, so hover states would not match the cursor drawn
// into the clip. Both were measured and rejected (federfall-1h9z.1, .2).
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { createWriteStream } from 'node:fs';
import path from 'node:path';
import { DemoError, requireTool, run, sleep, startProcess, withTimeout } from './util.mjs';

export const VIEWPORTS = {
  // 412 CSS px is a common Android width; the height is set by the frame the
  // clip is placed in (see README, "Look"). DPR 2 keeps a 1.8× zoom inside
  // OpenScreen's 2× source-magnification cap at a 1080×1920 export.
  phone: { width: 412, height: 800, dpr: 2, aspect: '9:16' },
  // Untested so far (C7 is the one desktop video): 1280×720 CSS at 1.5 is a
  // 1920×1080 source, i.e. 1:1 at a 1080p 16:9 export.
  desktop: { width: 1280, height: 720, dpr: 1.5, aspect: '16:9' },
};

let nextDisplay = 90;

/** Starts Xvfb at exactly the device-pixel size of the viewport. */
export async function startDisplay(vp, { log }) {
  const display = `:${nextDisplay++}`;
  const w = Math.round(vp.width * vp.dpr);
  const h = Math.round(vp.height * vp.dpr);
  const proc = startProcess('Xvfb', [display, '-screen', '0', `${w}x${h}x24`, '-nolisten', 'tcp',
    '-ac', '-nocursor'], { log });
  for (let i = 0; i < 100; i++) {
    try {
      await run('xdpyinfo', ['-display', display]);
      return { display, w, h, proc, stop: () => proc.kill('SIGTERM') };
    } catch {
      await sleep(100);
    }
  }
  proc.kill('SIGKILL');
  throw new DemoError(`Xvfb ${display} did not start`);
}

/**
 * Launches Chromium headed on [display], in app mode (no tabs, no address bar)
 * at 0,0 with no window manager, so the X screen IS the viewport.
 */
export async function launchBrowser({ display, vp, locale, url, log }) {
  const { chromium } = requireTool('playwright-core');
  const lang = locale === 'de' ? 'de-DE' : 'en-US';
  const args = [
    `--app=${url}`, `--force-device-scale-factor=${vp.dpr}`,
    '--window-position=0,0', `--window-size=${vp.width},${vp.height}`,
    '--hide-scrollbars', '--disable-features=Translate,MediaRouter,PasswordManagerOnboarding,AutofillServerCommunication',
    '--no-first-run', '--no-default-browser-check', '--disable-infobars',
    '--password-store=basic', '--test-type', `--lang=${lang}`,
    '--disable-session-crashed-bubble',
  ];
  if (process.env.FFDEMO_NO_SANDBOX === '1') args.push('--no-sandbox');
  // Browser UI must never appear in a clip. The one that did: Chromium's
  // "Save password?" bubble after the sign-in, drawn over the app.
  const profile = mkdtempSync('/tmp/ffdemo-profile-');
  mkdirSync(path.join(profile, 'Default'), { recursive: true });
  writeFileSync(path.join(profile, 'Default', 'Preferences'), JSON.stringify({
    credentials_enable_service: false,
    credentials_enable_autosignin: false,
    profile: { password_manager_enabled: false, password_manager_leak_detection: false },
    autofill: { profile_enabled: false, credit_card_enabled: false },
    translate: { enabled: false },
  }));
  const context = await chromium.launchPersistentContext(profile, {
    executablePath: process.env.CHROMIUM ?? '/usr/bin/chromium',
    headless: false,
    viewport: null,
    locale: lang,
    timezoneId: 'Europe/Berlin',
    ignoreDefaultArgs: ['--enable-automation'],
    env: { ...process.env, DISPLAY: display, TZ: 'Europe/Berlin' },
    args,
  });
  let page = context.pages()[0];
  if (!page) page = await context.waitForEvent('page');
  page.on('pageerror', (e) => log(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error') log(`console.error: ${m.text().slice(0, 300)}`);
  });
  return { context, page };
}

/** The real X pointer. Moves are eased and sampled for the cursor track. */
export class Pointer {
  constructor({ display, dpr, clock, start }) {
    this.display = display;
    this.dpr = dpr;
    this.clock = clock;
    this.samples = [];
    this.at = start;
  }

  async xdo(...args) {
    await run('xdotool', args.map(String), { env: { ...process.env, DISPLAY: this.display } });
  }

  sample(x, y, interactionType = 'move') {
    this.samples.push({ timeMs: this.clock(), x, y, interactionType });
  }

  async moveTo(x, y, { durationMs } = {}) {
    const from = this.at;
    const dist = Math.hypot(x - from.x, y - from.y);
    // Slow enough to follow, never sluggish: ~350–800 ms depending on distance.
    const ms = durationMs ?? Math.min(800, Math.max(350, dist * 1.6));
    const steps = Math.max(8, Math.round(ms / 16));
    const t0 = Date.now();
    for (let i = 1; i <= steps; i++) {
      const t = i / steps;
      const e = t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2; // easeInOutCubic
      const px = from.x + (x - from.x) * e;
      const py = from.y + (y - from.y) * e;
      await this.xdo('mousemove', Math.round(px * this.dpr), Math.round(py * this.dpr));
      this.sample(px, py);
      const due = t0 + (ms * i) / steps;
      const wait = due - Date.now();
      if (wait > 0) await sleep(wait);
    }
    this.at = { x, y };
  }

  async click() {
    const { x, y } = this.at;
    this.sample(x, y, 'click');
    await this.xdo('mousedown', 1);
    await sleep(70);
    await this.xdo('mouseup', 1);
    this.sample(x, y, 'mouseup');
  }

  async wheel(direction, clicks = 1) {
    for (let i = 0; i < clicks; i++) {
      await this.xdo('click', direction === 'down' ? 5 : 4);
      await sleep(40);
    }
  }
}

/** ffmpeg x11grab of the whole display, H.264, 30 fps, cursor not drawn. */
export function startCapture({ display, w, h, file, log }) {
  const proc = startProcess('ffmpeg', ['-y', '-hide_banner', '-nostats', '-loglevel', 'info',
    '-f', 'x11grab', '-draw_mouse', '0', '-framerate', '30', '-video_size', `${w}x${h}`,
    '-i', `${display}.0`, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '16',
    '-pix_fmt', 'yuv420p', file], { log });
  // x11grab stamps frames with the wall clock, and ffmpeg prints the first
  // one as the input's "start:" (seconds since the epoch). That instant is
  // t=0 of the capture, on the same clock as Date.now().
  let stderr = '';
  const started = new Promise((resolve) => {
    proc.stderr.on('data', (d) => {
      stderr += d;
      const m = /start: (\d+\.\d+)/.exec(stderr);
      if (m) resolve(Math.round(Number(m[1]) * 1000));
    });
  });
  let exited = false;
  const done = new Promise((r) => proc.on('exit', (code) => { exited = true; r(code); }));
  return {
    proc,
    /** Epoch ms of the capture's first frame. */
    firstFrame: () => withTimeout(started, 10_000, 'ffmpeg to grab its first frame'),
    async stop() {
      if (!exited) proc.stdin.write('q');
      const code = await withTimeout(done, 20_000, 'ffmpeg to finish the capture').catch((e) => {
        proc.kill('SIGKILL');
        throw e;
      });
      if (code !== 0 || !existsSync(file)) throw new DemoError(`ffmpeg capture failed (exit ${code})`);
    },
    kill: () => { if (!exited) proc.kill('SIGKILL'); },
  };
}

/**
 * Renders an SVG from assets/ to a JPEG (what a phone camera would hand the
 * picker) in a separate headless browser, so nothing appears on the stage.
 */
export async function renderAsset(svgFile, outFile, { width = 1200, height = 900 } = {}) {
  const { chromium } = requireTool('playwright-core');
  const args = process.env.FFDEMO_NO_SANDBOX === '1' ? ['--no-sandbox'] : [];
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM ?? '/usr/bin/chromium', args });
  try {
    const page = await browser.newPage({ viewport: { width, height } });
    await page.goto(`file://${svgFile}`);
    await page.screenshot({ path: outFile, type: 'jpeg', quality: 88 });
  } finally {
    await browser.close();
  }
  return outFile;
}

export function logStream(dir, name) {
  return createWriteStream(path.join(dir, name), { flags: 'a' });
}
