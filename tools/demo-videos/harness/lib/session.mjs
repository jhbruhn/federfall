// What a video step's `run(s)` gets: locators that resolve labels by ARB key,
// and actions that move the real pointer, visibly type, and record everything
// the clip needs (cursor track, the boxes zooms aim at) on the capture clock.
//
// Every action waits for its target with a timeout and fails the run when the
// target is missing, ambiguous (two matches) or never becomes visible. Nothing
// here retries a failed action: a flaky step is a bug to find, not to hide.
import path from 'node:path';
import { renderAsset } from './stage.mjs';
import { DemoError, sleep } from './util.mjs';

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export class Session {
  constructor({ page, pointer, t, locale, vp, clock, log, data }) {
    this.page = page;
    this.pointer = pointer;
    this.locale = locale;
    this.vp = vp;
    this.clock = clock;
    this.log = log;
    /** Whatever the video's setup() returned (the people and records it seeded). */
    this.data = data;
    this._t = t;
    this.step = null; // the step record being executed, set by the runner
    this.timeoutMs = 10_000;
  }

  // ── Labels ──────────────────────────────────────────────────────────────
  /** The app's label for an ARB key in this run's language. */
  t(key, params) { return this._t(key, params); }

  /** Picks the value for this run's language from `{de: …, en: …}`. */
  pick(byLocale) {
    const v = byLocale?.[this.locale];
    if (v === undefined) throw new DemoError(`no "${this.locale}" text in ${JSON.stringify(byLocale)}`);
    return v;
  }

  // ── Locators (Flutter's semantics tree, as the browser exposes it) ──────
  /**
   * By role and accessible name; `startsWith` for a node whose name carries
   * more (a list row). A RegExp name matches as is — for a row whose name is
   * data plus data, e.g. `s.role('button', s.rowOf(name, drug))`.
   */
  role(role, name, { startsWith = false } = {}) {
    if (name instanceof RegExp) return this.page.getByRole(role, { name });
    if (startsWith) return this.page.getByRole(role, { name: new RegExp(`^${escapeRe(name)}`) });
    return this.page.getByRole(role, { name, exact: true });
  }

  /**
   * A name pattern that contains every one of [parts], in order, anywhere
   * (each escaped). For list rows whose name is "<case no.> · <bird>\n<drug> ·
   * <when>": `s.rowOf("· Fiete", "Nemakur")` picks the bird's dose row and
   * not its appointment row, without knowing the case number.
   */
  rowOf(...parts) {
    return new RegExp(parts.map(escapeRe).join('[\\s\\S]*'));
  }

  /** A text field by the ARB key of its label. */
  textbox(key, params) { return this.role('textbox', this.t(key, params)); }

  /** A button by the ARB key of its label (or tooltip, for an icon button). */
  button(key, params) { return this.role('button', this.t(key, params)); }

  /** A button whose accessible name STARTS with the label (e.g. a dropdown, which appends its value). */
  buttonStartingWith(key, params) {
    return this.role('button', this.t(key, params), { startsWith: true });
  }

  /** A Semantics(identifier:) — only where a label cannot do it (see README). */
  id(identifier) { return this.page.locator(`[flt-semantics-identifier="${identifier}"]`); }

  /** Any semantics node whose text contains [text] (data, not a label). */
  text(text) {
    return this.page.locator('flt-semantics').filter({ hasText: text });
  }

  // ── Waiting ─────────────────────────────────────────────────────────────
  async waitFor(locator, { timeout = this.timeoutMs, what } = {}) {
    try {
      await locator.waitFor({ state: 'visible', timeout });
    } catch (e) {
      throw new DemoError(`target not found: ${what ?? describe(locator)} (${firstLine(e)})`);
    }
    return locator;
  }

  async waitForUrl(re, { timeout = 20_000 } = {}) {
    try {
      await this.page.waitForURL(re, { timeout });
    } catch (e) {
      throw new DemoError(`expected the URL to match ${re}, it is ${this.page.url()} (${firstLine(e)})`);
    }
  }

  async gone(locator, { timeout = this.timeoutMs, what } = {}) {
    try {
      await locator.waitFor({ state: 'hidden', timeout });
    } catch (e) {
      throw new DemoError(`still on screen: ${what ?? describe(locator)} (${firstLine(e)})`);
    }
  }

  /**
   * Fails unless some node on screen shows [text] (data the run created, e.g.
   * a name, or a number a caption quotes). Text that Flutter merged into a
   * card's or a row's label counts: that label is what the card shows.
   */
  async expectText(text, { timeout = this.timeoutMs } = {}) {
    const inLabel = this.page.locator(`flt-semantics[aria-label*=${JSON.stringify(text)}]`);
    await this.waitFor(this.page.locator('flt-semantics').filter({ hasText: text }).or(inLabel).first(),
      { timeout, what: `text "${text}" on screen` });
  }

  // ── Geometry ────────────────────────────────────────────────────────────
  async box(locator, what) {
    await this.waitFor(locator, { what });
    let b;
    try {
      b = await locator.boundingBox({ timeout: this.timeoutMs });
    } catch (e) {
      // Strict mode: two matches means the label is ambiguous on this screen.
      throw new DemoError(`target ambiguous or detached: ${what ?? describe(locator)} (${firstLine(e)})`);
    }
    if (!b || b.width === 0 || b.height === 0) {
      throw new DemoError(`target has no size: ${what ?? describe(locator)}`);
    }
    return b;
  }

  /** Fully on screen. Exact edges count: a bottom navigation bar ends on the viewport's last pixel. */
  inView(b) {
    return b.y >= -0.5 && b.y + b.height <= this.vp.height + 0.5;
  }

  /**
   * Scrolls with the real mouse wheel until [locator] is fully on screen. A
   * Flutter list only builds what is near the viewport, so a target that does
   * not exist yet is scrolled towards ([direction]) until it does.
   */
  async reveal(locator, { what, direction = 'down', maxWheel = 30 } = {}) {
    for (let i = 0; i <= maxWheel; i++) {
      const count = await locator.count();
      if (count > 1) {
        throw new DemoError(`target ambiguous: ${what ?? describe(locator)} matches ${count} nodes`);
      }
      let dir = direction;
      if (count === 1) {
        const b = await locator.boundingBox().catch(() => null);
        if (b && b.height > 0 && this.inView(b)) return b;
        if (b) dir = b.y < 2 ? 'up' : 'down';
      }
      if (i === maxWheel) break;
      const p = this.pointer.at;
      if (Math.abs(p.x - this.vp.width / 2) > 60 || p.y < 120 || p.y > this.vp.height - 140) {
        await this.pointer.moveTo(this.vp.width / 2, this.vp.height * 0.55);
      }
      await this.pointer.wheel(dir, 1);
      await sleep(180);
    }
    throw new DemoError(`could not scroll to: ${what ?? describe(locator)}`);
  }

  // ── Actions ─────────────────────────────────────────────────────────────
  remember(kind, b) {
    const ev = { kind, timeMs: this.clock(), box: { x: b.x, y: b.y, width: b.width, height: b.height } };
    this.step?.events.push(ev);
    return ev;
  }

  /**
   * Marks [locator] as what this step's zoom should aim at, without touching
   * it. [box] aims next to it instead: `(b) => ({ x, y, width, height })`
   * gets the node's box and returns the one to aim at — for text the
   * semantics tree merges into its card and so has no node of its own (a
   * dose derivation, one row of a card). Anchor such a box on the nearest
   * node that has a label, and check the zoom in the stills: unlike a
   * locator, a box that drifts after a layout change does not fail the run.
   */
  async focus(locator, { what, box } = {}) {
    await this.waitFor(locator, { what });
    let b = await this.reveal(locator, { what });
    if (box) b = box(b);
    if (this.step) this.step.focus = { box: b, timeMs: this.clock() };
    return b;
  }

  /** Moves the pointer onto [locator] and clicks it. */
  async click(locator, { what, settle = 250 } = {}) {
    await this.waitFor(locator, { what });
    await this.reveal(locator, { what });
    // Re-read after the pointer arrives: a scroll or an animation may have
    // moved the target while the pointer was on its way. Through the element
    // itself, not the locator: hovering an icon button opens its tooltip,
    // which changes the button's accessible name while the pointer is on it.
    let b = await this.box(locator, what);
    const el = await locator.elementHandle({ timeout: this.timeoutMs });
    await this.pointer.moveTo(b.x + b.width / 2, b.y + b.height / 2);
    b = (await el.boundingBox()) ?? b;
    const cx = b.x + b.width / 2;
    const cy = b.y + b.height / 2;
    if (Math.hypot(cx - this.pointer.at.x, cy - this.pointer.at.y) > 4) {
      await this.pointer.moveTo(cx, cy, { durationMs: 150 });
    }
    await sleep(120);
    this.remember('click', b);
    await this.pointer.click();
    await sleep(settle);
    return b;
  }

  /**
   * Clicks a text field and types into it at a readable pace. Flutter moves
   * focus to its own editing element after the click lands; a keystroke sent
   * before that is dropped (measured in federfall-1h9z.1), hence the pause.
   */
  async type(locator, text, { what, clear = false, delay = 55 } = {}) {
    await this.click(locator, { what, settle: 300 });
    if (clear) {
      await this.page.keyboard.press('Control+A');
      await this.page.keyboard.press('Backspace');
      await sleep(150);
    }
    await this.page.keyboard.type(text, { delay });
    await sleep(200);
  }

  async press(key) {
    await this.page.keyboard.press(key);
    await sleep(200);
  }

  /** Clicks [locator], expects the native file chooser, and hands it [file]. */
  async chooseFile(locator, file, { what } = {}) {
    const chooser = this.page.waitForEvent('filechooser', { timeout: this.timeoutMs });
    await this.click(locator, { what, settle: 0 });
    let fc;
    try {
      fc = await chooser;
    } catch (e) {
      throw new DemoError(`no file chooser opened after clicking ${what ?? describe(locator)} (${firstLine(e)})`);
    }
    await fc.setFiles(file);
    await sleep(400);
  }

  /** Moves the pointer somewhere neutral so it does not cover what is shown. */
  async rest({ x = this.vp.width * 0.82, y = this.vp.height * 0.4 } = {}) {
    await this.pointer.moveTo(x, y);
  }

  async hold(ms) { await sleep(ms); }

  /** A file from assets/ ready to hand to a file chooser (an .svg is rendered to .jpg first). */
  async asset(name) {
    const src = path.join(process.env.FFDEMO_ROOT ?? '/demo', 'assets', name);
    if (!name.endsWith('.svg')) return src;
    const out = path.join(this.workDir, name.replace(/\.svg$/, '.jpg'));
    const { existsSync } = await import('node:fs');
    return existsSync(out) ? out : renderAsset(src, out);
  }

  /**
   * Authoring aid: writes a screenshot and every semantics node (role, name,
   * identifier, box) to the run's work directory as dump-<tag>.{png,txt}.
   * It costs time on camera, so take it out once the script works.
   */
  async dump(tag) {
    if (!this.workDir) return;
    const { writeFileSync } = await import('node:fs');
    await this.page.screenshot({ path: `${this.workDir}/dump-${tag}.png` }).catch(() => {});
    const nodes = await this.page.evaluate(() => [...document.querySelectorAll('flt-semantics, flt-semantics-host input, flt-semantics-host textarea')]
      .map((e) => {
        const r = e.getBoundingClientRect();
        const name = e.getAttribute('aria-label') ?? (e.childElementCount === 0 ? (e.textContent ?? '').trim().slice(0, 60) : '');
        const id = e.getAttribute('flt-semantics-identifier');
        const role = e.getAttribute('role') ?? (e.tagName === 'INPUT' || e.tagName === 'TEXTAREA' ? `textbox(${e.tagName.toLowerCase()})` : null);
        if (!role && !name && !id) return null;
        return `${role ?? '-'} "${name}"${id ? ` #${id}` : ''} @${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}`;
      }).filter(Boolean).join('\n'));
    writeFileSync(`${this.workDir}/dump-${tag}.txt`, `${this.page.url()}\n${nodes}\n`);
  }
}

function firstLine(e) {
  return String(e?.message ?? e).split('\n')[0].slice(0, 200);
}

function describe(locator) {
  return String(locator).replace(/^Locator@/, '').slice(0, 160);
}
