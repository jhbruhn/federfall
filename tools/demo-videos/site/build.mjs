// The demo-video site, and the CI matrix it is built from. Runs on the HOST
// (plain node, no container, no dependencies): the video definitions import
// nothing that needs the runner image.
//
//   node tools/demo-videos/site/build.mjs matrix
//       prints the video ids as a JSON array, for the workflow's matrix
//   node tools/demo-videos/site/build.mjs page <site-dir>
//       writes <site-dir>/index.html for the clips in <site-dir>/videos/
//       (named as the harness names them: <id>-<slug>.<locale>.mp4)
//
// The page lists only what is there: a video with no clip in either language
// is left out rather than shown as a gap, so a site built from a partial run
// is still a page worth opening. The order and the tiers follow the ids.
import { copyFileSync, existsSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const LOCALES = ['de', 'en'];

const TIERS = {
  A: { de: 'Erste Schritte', en: 'Getting started' },
  B: { de: 'Im Alltag', en: 'Everyday work' },
  C: { de: 'Im Detail', en: 'In depth' },
};

async function loadVideos() {
  const dir = path.join(ROOT, 'videos');
  const videos = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.mjs')).sort()) {
    videos.push((await import(pathToFileURL(path.join(dir, f)).href)).default);
  }
  // A10 after A9, not after A1.
  const key = (v) => [v.id[0], Number(v.id.slice(1))];
  return videos.sort((a, b) => {
    const [ta, na] = key(a);
    const [tb, nb] = key(b);
    return ta === tb ? na - nb : ta.localeCompare(tb);
  });
}

const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

/** Both languages' text in one element; the stylesheet shows the chosen one. */
const both = (t) => LOCALES.map((l) => `<span lang="${l}">${esc(t[l])}</span>`).join('');

function card(v, clips) {
  const players = LOCALES.map((l) => {
    const clip = clips[l];
    const body = clip
      ? `<video controls playsinline preload="metadata" src="videos/${esc(clip)}#t=0.1"></video>`
      : `<p class="missing">${l === 'de' ? 'Noch nicht auf Deutsch.' : 'Not in English yet.'}</p>`;
    return `<div class="player" lang="${l}">${body}</div>`;
  }).join('');
  return `<article class="card ${esc(v.viewport)}" id="${esc(v.id)}">
  ${players}
  <h3><span class="id">${esc(v.id)}</span> ${both(v.title)}</h3>
</article>`;
}

function page(videos, clipsByVideo) {
  const version = process.env.FFDEMO_SITE_VERSION;
  const commit = process.env.GITHUB_SHA?.slice(0, 7);
  const built = new Date().toISOString().slice(0, 10);
  const sections = Object.entries(TIERS)
    .map(([tier, name]) => {
      const cards = videos
        .filter((v) => v.id.startsWith(tier) && clipsByVideo.has(v.id))
        .map((v) => card(v, clipsByVideo.get(v.id)));
      return cards.length ? `<section><h2>${both(name)}</h2><div class="grid">${cards.join('\n')}</div></section>` : '';
    })
    .join('\n');
  const stamp = [version && `v${esc(version)}`, commit && esc(commit), built].filter(Boolean).join(' · ');

  return `<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Federfall — Videos</title>
<link rel="icon" href="favicon.png">
<style>
:root {
  --bg: #f6f8f6; --surface: #ffffff; --text: #17201d; --muted: #56635e;
  --accent: #356859; --line: #d6dfdb;
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #0f1513; --surface: #18211e; --text: #e3ebe7; --muted: #9aaba4;
          --accent: #8fd1bc; --line: #2b3733; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
       font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
header, main, footer { max-width: 1200px; margin: 0 auto; padding: 0 16px; }
header { display: flex; align-items: center; gap: 12px; padding-top: 32px; flex-wrap: wrap; }
header img { width: 40px; height: 40px; border-radius: 10px; }
h1 { font-size: 1.6rem; margin: 0; flex: 1; }
.intro { color: var(--muted); max-width: 60ch; margin: 8px 0 0; }
nav button { font: inherit; padding: 6px 14px; border: 1px solid var(--line); background: var(--surface);
             color: var(--text); cursor: pointer; }
nav button:first-child { border-radius: 999px 0 0 999px; }
nav button:last-child { border-radius: 0 999px 999px 0; border-left: 0; }
nav button[aria-pressed="true"] { background: var(--accent); border-color: var(--accent); color: var(--bg); }
h2 { font-size: 1.2rem; margin: 40px 0 16px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
.grid { display: grid; gap: 24px; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); }
.card { background: var(--surface); border: 1px solid var(--line); border-radius: 14px; padding: 12px;
        display: flex; flex-direction: column; gap: 10px; align-self: start; }
.card.desktop { grid-column: span 2; }
@media (max-width: 560px) { .card.desktop { grid-column: auto; } }
video { width: 100%; display: block; border-radius: 8px; background: #000; }
.phone video { aspect-ratio: 9 / 16; }
.desktop video { aspect-ratio: 16 / 9; }
h3 { font-size: 1rem; margin: 0; font-weight: 600; }
.id { color: var(--muted); font-weight: 500; font-variant-numeric: tabular-nums; margin-right: 4px; }
.missing { color: var(--muted); margin: 0; padding: 24px 0; text-align: center; }
footer { color: var(--muted); font-size: .85rem; padding-top: 40px; padding-bottom: 32px; }
html[data-lang="de"] [lang="en"]:not(html), html[data-lang="en"] [lang="de"]:not(html) { display: none; }
</style>
</head>
<body>
<header>
  <img src="favicon.png" alt="">
  <h1>${both({ de: 'Federfall in Videos', en: 'Federfall in videos' })}</h1>
  <nav aria-label="Sprache / Language">
    <button type="button" data-set-lang="de">Deutsch</button><button type="button" data-set-lang="en">English</button>
  </nav>
</header>
<main>
  <p class="intro">${both({
    de: 'So funktioniert Federfall.',
    en: 'How Federfall works.',
  })}</p>
${sections}
</main>
<footer>${stamp}</footer>
<script>
(() => {
  const root = document.documentElement;
  let lang = 'de';
  try { lang = localStorage.getItem('lang') || ''; } catch (e) { lang = ''; }
  if (lang !== 'de' && lang !== 'en') lang = /^de\\b/i.test(navigator.language || '') ? 'de' : 'en';
  const set = (l) => {
    root.dataset.lang = l;
    root.lang = l;
    for (const b of document.querySelectorAll('[data-set-lang]')) b.setAttribute('aria-pressed', String(b.dataset.setLang === l));
    // A clip playing in the language just hidden would keep talking to nobody.
    for (const v of document.querySelectorAll('video')) if (!v.offsetParent) v.pause();
    try { localStorage.setItem('lang', l); } catch (e) { /* private window */ }
  };
  for (const b of document.querySelectorAll('[data-set-lang]')) b.addEventListener('click', () => set(b.dataset.setLang));
  set(lang);
})();
</script>
</body>
</html>
`;
}

const [cmd, siteDir] = process.argv.slice(2);
const videos = await loadVideos();

if (cmd === 'matrix') {
  console.log(JSON.stringify(videos.map((v) => v.id)));
} else if (cmd === 'page' && siteDir) {
  const clipDir = path.join(siteDir, 'videos');
  const present = new Set(existsSync(clipDir) ? readdirSync(clipDir) : []);
  const clipsByVideo = new Map();
  for (const v of videos) {
    const clips = {};
    for (const l of LOCALES) {
      const name = `${v.id}-${v.slug}.${l}.mp4`;
      if (present.has(name)) clips[l] = name;
    }
    if (Object.keys(clips).length) clipsByVideo.set(v.id, clips);
  }
  writeFileSync(path.join(siteDir, 'index.html'), page(videos, clipsByVideo));
  copyFileSync(path.join(ROOT, '../../apps/federfall/web/favicon.png'), path.join(siteDir, 'favicon.png'));
  console.log(`${siteDir}/index.html: ${clipsByVideo.size} of ${videos.length} videos`);
} else {
  console.error('usage: build.mjs matrix | build.mjs page <site-dir>');
  process.exit(2);
}
