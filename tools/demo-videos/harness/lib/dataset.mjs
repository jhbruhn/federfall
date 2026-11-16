// Which data a video starts on, and how it gets there fast.
//
//   base  the organisation, its code lists in the run's language, one account
//         per role (seed.mjs). Nothing else — A3 needs an empty case list.
//   demo  base + the lived-in organisation of data/demo/: a year and a half of
//         cases, the showcase birds, aviaries, patronages (README, "Demo
//         dataset").
//
// Seeding the demo org takes seconds, not milliseconds, and every video and
// language starts on a fresh backend. So each dataset is seeded ONCE per run
// and language, saved by serve.sh as a template, and every later video of that
// language gets a fresh COPY of it (backend.mjs, snapshotBackend). A video's
// own setup() then runs on top of the copy, so what one video adds is never
// seen by the next.
//
// "Relative to the run day" survives the cache: a template remembers the day
// it was seeded for, and is seeded again when the run day has moved on (a run
// across midnight).
import { Api, freshBackend, snapshotBackend } from './backend.mjs';
import { Seed } from './seed.mjs';
import { DemoError } from './util.mjs';
import { Clock } from '../data/demo/clock.mjs';
import { seedDemo } from '../data/demo/index.mjs';

export const DATASETS = ['base', 'demo'];

/** `${dataset}-${locale}` → { day, state, seconds } for this process. */
const templates = new Map();

/** How long each seeding took, for the run summary: [{dataset, locale, seconds}]. */
export const seedTimings = [];

/**
 * A fresh backend holding [dataset] in [locale], and a Seed object that knows
 * its people and records. Seeds and saves the template on first use (or
 * always, with [reseed]).
 */
export async function prepareDataset({ dataset = 'base', locale, log, clock = new Clock(), reseed = false }) {
  if (!DATASETS.includes(dataset)) throw new DemoError(`unknown dataset "${dataset}" (known: ${DATASETS.join(', ')})`);
  const key = `${dataset}-${locale}`;
  const hit = templates.get(key);
  if (hit && hit.day === clock.label && !reseed) {
    await freshBackend({ log, template: key });
    return Seed.restore({ locale, log }, hit.state);
  }

  await freshBackend({ log });
  const started = Date.now();
  const seed = new Seed({ su: await Api.superuser(), locale, log });
  await seed.withoutRateLimits(async () => {
    await seed.base();
    if (dataset === 'demo') await seedDemo(seed, { clock, log });
  });
  const seconds = Math.round((Date.now() - started) / 100) / 10;
  log?.(`seeded dataset "${dataset}" (${locale}, run day ${clock.label}) in ${seconds} s`);
  seedTimings.push({ dataset, locale, day: clock.label, seconds });
  const state = seed.state();
  await snapshotBackend(key, { log });
  templates.set(key, { day: clock.label, state, seconds });
  return Seed.restore({ locale, log }, state);
}
