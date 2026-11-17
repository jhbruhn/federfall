// The run's ONE definition of "now", and the demo dataset's calendar.
//
// A run has a fixed instant: the run day (today in Europe/Berlin — the org's
// zone and the containers' TZ — unless FFDEMO_RUN_DAY=YYYY-MM-DD names another)
// at a fixed time of day (FFDEMO_TIME=HH:MM, default DEFAULT_TIME_OF_DAY). It is
// computed once per process and used by all three parties:
//
//   the seeder   every date in the demo dataset is relative to the run day
//                ("admitted twelve days ago", "the next dose is due at 19:00"),
//                and nothing is written later than the run instant;
//   the browser  the app's clock starts at the run instant when each video's
//                capture starts and runs forward at normal speed from there
//                (stage.mjs, installAppClock) — so "overdue by 2 h" reads the
//                same whenever the run happens;
//   the checks   verify.mjs computes what the app will show AT the run instant.
//
// The backend keeps the REAL clock. A few things it decides against its own
// now (a plan is listed while `ended_at > now`, a disposition may be dated at
// most a day ahead, `created`), so the run instant must stay within
// SERVER_SKEW_MS of the real time to record — `serverAgrees()`. Every time of
// day with the run day = today is within it; FFDEMO_RUN_DAY far away is for
// comparing seedings with `check` (the server-dependent checks are skipped).
import { DemoError } from '../../lib/util.mjs';

const ZONE = 'Europe/Berlin';
const DAY_MS = 86_400_000;

/**
 * The app's time of day when a video starts. The dataset's dues sit on the
 * hour (doses, rechecks) or the half hour (appointments), and the app rounds
 * "in/overdue by n h" UP to the hour — so at hh:40 every such label holds
 * until the next full hour: 20 minutes of app time a video can rely on.
 */
export const DEFAULT_TIME_OF_DAY = '09:40';

/** How far the run instant may be from the real clock for a recording (see above). */
export const SERVER_SKEW_MS = 20 * 3_600_000;

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

export function timeOfDayFromEnv(env = process.env) {
  const raw = (env.FFDEMO_TIME ?? '').trim() || DEFAULT_TIME_OF_DAY;
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(raw);
  if (!m) throw new DemoError(`FFDEMO_TIME must be HH:MM (24 h), got "${raw}"`);
  return raw;
}

export const ymdString = ({ y, mo, d }) =>
  `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

/**
 * The run's clock. `nowMs` is the run instant (the run day at the time of
 * day); `at(-12, '08:30')` is the ISO instant of 08:30 Berlin time twelve days
 * before the run day. Both UTC, as the app writes them.
 */
export class Clock {
  constructor(runDay = runDayFromEnv(), timeOfDay = timeOfDayFromEnv()) {
    this.runDay = runDay;
    this.year = runDay.y;
    this.label = ymdString(runDay);
    this.timeOfDay = timeOfDay;
    /** The run instant: what the app's clock reads when a video starts. */
    this.nowMs = this.ms(0, timeOfDay);
    this.nowLabel = `${this.label} ${timeOfDay} (${ZONE})`;
  }

  /** Hours the run instant is ahead of the real clock (negative: behind). */
  skewHours(real = Date.now()) {
    return Math.round((this.nowMs - real) / 360_000) / 10;
  }

  /** Whether the backend's real clock is close enough to the run instant to record (see top). */
  serverAgrees(real = Date.now()) {
    return Math.abs(this.nowMs - real) <= SERVER_SKEW_MS;
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

/**
 * The app's own "in n h / overdue by n h" wording for [dueMs] at [nowMs]
 * (relativeDueLabel in apps/federfall/lib/features/worklist/worklist_labels.dart:
 * whole minutes, rounded UP to the hour; whole days beyond 24 h), in a
 * language-free form: "in 3 h", "overdue 2 h", "in 3 d".
 */
export function relativeDue(dueMs, nowMs) {
  const ahead = dueMs > nowMs;
  const diff = Math.abs(dueMs - nowMs);
  const minutes = Math.floor(diff / 60_000);
  const label = diff < DAY_MS ? `${Math.ceil(minutes / 60)} h` : `${Math.floor(diff / DAY_MS)} d`;
  return ahead ? `in ${label}` : `overdue ${label}`;
}

export const iso = (ms) => new Date(ms).toISOString();
export { DAY_MS };
