// Entry point inside the runner container.
//
//   record <ID…|all> [--locale de,en] [--no-export]
//   export <ID…|all> [--locale de,en]   re-render the last capture (look tuning)
//   list
//
// Writes, under /work/out (handed to the mounted output directory by
// runner/entry.sh): the clips, `work/<id>.<locale>/` with every intermediate
// file, and `last-run.json`. The exit status is 0 only when every requested
// clip was produced — and the same verdict is in last-run.json, for engines
// whose compose wrapper does not pass the exit status through.
import { readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { recordOne, reexportOne } from './lib/run.mjs';
import { startServices } from './lib/services.mjs';

const DEMO = process.env.FFDEMO_ROOT ?? '/demo';
const WORK = process.env.FFDEMO_WORK ?? '/work';
const OUT = path.join(WORK, 'out');

async function loadVideos() {
  const dir = path.join(DEMO, 'videos');
  const files = readdirSync(dir).filter((f) => f.endsWith('.mjs')).sort();
  const videos = [];
  for (const f of files) {
    const mod = await import(pathToFileURL(path.join(dir, f)).href);
    videos.push(mod.default);
  }
  return videos;
}

function usage(msg) {
  if (msg) console.error(`error: ${msg}`);
  console.error('usage: record <ID…|all> [--locale de,en] [--no-export]\n       export <ID…|all> [--locale de,en]\n       list');
  process.exit(2);
}

const argv = process.argv.slice(2);
// `compose run --rm record A3` hands the container just "A3": a first argument
// that is not a command means `record`.
const cmd = ['record', 'export', 'list'].includes(argv[0]) ? argv.shift() : 'record';
const videos = await loadVideos();

if (cmd === 'list') {
  for (const v of videos) console.log(`${v.id.padEnd(4)} ${v.slug.padEnd(24)} ${v.viewport.padEnd(8)} ${v.title.en}`);
  process.exit(0);
}

let locales = ['de', 'en'];
let noExport = false;
const ids = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--locale') locales = (argv[++i] ?? '').split(',').filter(Boolean);
  else if (a.startsWith('--locale=')) locales = a.slice(9).split(',').filter(Boolean);
  else if (a === '--no-export') noExport = true;
  else if (a.startsWith('-')) usage(`unknown option ${a}`);
  else ids.push(a);
}
if (ids.length === 0) usage('name at least one video, or "all"');
for (const l of locales) if (!['de', 'en'].includes(l)) usage(`unknown locale "${l}"`);
const chosen = ids.includes('all') ? videos : ids.map((id) => {
  const v = videos.find((x) => x.id.toLowerCase() === id.toLowerCase());
  if (!v) usage(`no video "${id}" (known: ${videos.map((x) => x.id).join(', ')})`);
  return v;
});

mkdirSync(OUT, { recursive: true });
const services = await startServices({ cacheDir: path.join(WORK, '.cache'), log: console.log });
const results = [];
const started = new Date();
for (const video of chosen) {
  for (const locale of locales) {
    const args = { video, locale, workRoot: path.join(OUT, 'work'), outRoot: OUT, services, noExport };
    results.push(cmd === 'export' ? await reexportOne(args).catch((e) => ({ video: video.id, locale,
      clip: '', status: 'failed', error: e.message, timings: {} })) : await recordOne(args));
  }
}
const tiles = services.tileStats();
await services.close();

const ok = results.every((r) => r.status === 'passed' || (noExport && r.status === 'captured'));
const summary = { startedAt: started.toISOString(), finishedAt: new Date().toISOString(), ok, tiles, results };
writeFileSync(path.join(OUT, 'last-run.json'), JSON.stringify(summary, null, 2));
console.log('\n── result ──');
for (const r of results) {
  console.log(`${r.status === 'passed' ? 'PASS' : r.status === 'captured' ? 'CAPT' : 'FAIL'}  ${r.clip}  ${r.timings.total ?? '?'} s${r.error ? `\n      ${r.error}` : ''}`);
}
console.log(`tiles: ${tiles.hit} cached, ${tiles.fetched} fetched, ${tiles.plain} plain`);
process.exit(ok ? 0 : 1);
