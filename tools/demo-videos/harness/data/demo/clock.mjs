// The demo dataset's calendar. Every date in it is RELATIVE to the run day, so
// the dataset never goes stale: "admitted twelve days ago", "the next dose is
// due this evening". The run day is today in Europe/Berlin (the org's zone and
// the containers' TZ) unless FFDEMO_RUN_DAY=YYYY-MM-DD names another one — which
// is what makes a run reproducible: the same run day gives the same data.
//
// Note what an injected day does NOT move: the app's own clock. Today, "due",
// "overdue" and every "x days ago" on screen are computed by the browser from
// the real time, so a run day other than the real today shows a dataset that
// lives in the past or the future. Inject a day to compare two seedings, not to
// record.
import { DemoError } from '../../lib/util.mjs';

const ZONE = 'Europe/Berlin';
const DAY_MS = 86_400_000;

const fmt = new Intl.DateTimeFormat('en-US', {
  timeZone: ZONE, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit',
});

function partsAt(ms) {
  const p = Object.fromEntries(fmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { y: +p.year, mo: +p.month, d: +p.day, h: +p.hour, mi: +p.minute, s: +p.second };
}

/** Minutes Berlin is ahead of UTC at the instant [ms]. */
function offsetMin(ms) {
  const p = partsAt(ms);
  return Math.round((Date.UTC(p.y, p.mo - 1, p.d, p.h, p.mi, p.s) - ms) / 60_000);
}

/** The UTC instant of a Berlin wall-clock time (DST-correct). */
export function berlin(y, mo, d, h = 0, mi = 0) {
  const naive = Date.UTC(y, mo - 1, d, h, mi);
  let t = naive - offsetMin(naive) * 60_000;
  const second = offsetMin(t);
  if (second !== offsetMin(naive)) t = naive - second * 60_000;
  return t;
}

/** The calendar date [days] after [ymd] ({y, mo, d}); days may be negative. */
function addDays({ y, mo, d }, days) {
  const t = new Date(Date.UTC(y, mo - 1, d) + days * DAY_MS);
  return { y: t.getUTCFullYear(), mo: t.getUTCMonth() + 1, d: t.getUTCDate() };
}

export function runDayFromEnv(env = process.env) {
  const raw = (env.FFDEMO_RUN_DAY ?? '').trim();
  if (!raw) {
    const p = partsAt(Date.now());
    return { y: p.y, mo: p.mo, d: p.d };
  }
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!m) throw new DemoError(`FFDEMO_RUN_DAY must be YYYY-MM-DD, got "${raw}"`);
  return { y: +m[1], mo: +m[2], d: +m[3] };
}

export const ymdString = ({ y, mo, d }) =>
  `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

/**
 * A clock for one seeding. `at(-12, '08:30')` is the ISO instant of 08:30
 * Berlin time twelve days before the run day; `date(-12, …)` the same as a
 * PocketBase-style value. Both are UTC, as the app writes them.
 */
export class Clock {
  constructor(runDay = runDayFromEnv()) {
    this.runDay = runDay;
    this.year = runDay.y;
    this.label = ymdString(runDay);
  }

  /** Epoch ms of [hhmm] Berlin time on the run day + [days]. */
  ms(days, hhmm = '12:00') {
    const [h, mi] = hhmm.split(':').map(Number);
    const { y, mo, d } = addDays(this.runDay, days);
    return berlin(y, mo, d, h, mi);
  }

  at(days, hhmm) { return new Date(this.ms(days, hhmm)).toISOString(); }

  /** Epoch ms of a calendar date (Berlin) in a given year. */
  calendar(y, mo, d, hhmm = '12:00') {
    const [h, mi] = hhmm.split(':').map(Number);
    return berlin(y, mo, d, h, mi);
  }

  /** Whole days from the run day to the Berlin calendar day containing [ms]. */
  dayOffsetOf(ms) {
    const p = partsAt(ms);
    return Math.round((Date.UTC(p.y, p.mo - 1, p.d) - Date.UTC(this.runDay.y, this.runDay.mo - 1, this.runDay.d)) / DAY_MS);
  }

  /** The Berlin calendar day [days] after the run day, as YYYY-MM-DD. */
  dayString(days) { return ymdString(addDays(this.runDay, days)); }
}

export const iso = (ms) => new Date(ms).toISOString();
export { DAY_MS };
