#!/usr/bin/env node
// Regenerates the placeholder attachments of the demo dataset. Run on a host
// with node, rsvg-convert and ffmpeg (an authoring step, not part of a run):
//
//   node tools/demo-videos/assets/demo-data/generate.mjs
//
// Everything here is drawn from scratch, so it is ours to publish: simple bird
// illustrations, an X-ray-like and a microscope-like picture, and short PDF
// documents in both languages that say on their face that they are fictional.
// manifest.json says where each file is used. To use a real photo instead,
// replace the file (keep its name, or change "file" in manifest.json) — no code
// change is needed. Re-running this script overwrites the generated files.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const W = 1200;
const H = 900;

// ── Birds ───────────────────────────────────────────────────────────────────
// One side-view template (the shapes of ../pigeon.svg), coloured and
// proportioned per species. Not field-guide accurate; recognisable at a glance.
const BIRDS = {
  'feral-pigeon': { bg: ['#d9e4ec', '#9fb3c4', '#5d7487'], body: ['#a3adbd', '#69768a'], breast: ['#9aa3b5', '#7d879a'],
    wing: ['#9aa5b6', '#626d80'], head: '#7d889b', neck: '#6f9a86', bars: '#2f3540', beak: '#2d2a28', eye: '#e2702a', tail: '#4f5869' },
  'feral-pigeon-2': { bg: ['#efe4d0', '#c8b48f', '#8a7451'], body: ['#a3adbd', '#69768a'], breast: ['#9aa3b5', '#7d879a'],
    wing: ['#9aa5b6', '#626d80'], head: '#7d889b', neck: '#8a6fa0', bars: '#2f3540', beak: '#2d2a28', eye: '#e2702a', tail: '#4f5869', pose: 'down' },
  'feral-pigeon-3': { bg: ['#dfeadb', '#a9c39e', '#647f5a'], body: ['#b9bfc9', '#7f8796'], breast: ['#aab1bd', '#8c94a3'],
    wing: ['#b3b9c4', '#79818f'], head: '#8e97a6', neck: '#5f9a78', bars: '#2f3540', beak: '#2d2a28', eye: '#e2702a', tail: '#59606e' },
  'wood-pigeon': { bg: ['#cfe3c4', '#8fb98a', '#4d7a52'], body: ['#a7b1c2', '#6d7889'], breast: ['#c79aa0', '#9e8a94'],
    wing: ['#8a95a6', '#5b6576'], head: '#9aa6b6', neck: '#7fa88a', patch: '#fbfbfb', beak: '#e3a23a', eye: '#f2d25a', tail: '#4f5869', scale: 1.08 },
  'collared-dove': { bg: ['#f1e6d6', '#d6c1a1', '#9c8564'], body: ['#d8c8b2', '#ad9a82'], breast: ['#e2cfc4', '#c6b1a6'],
    wing: ['#cbb89f', '#9d8a72'], head: '#d4c5b5', collar: '#1f1f1f', beak: '#2b2b2b', eye: '#b3262a', tail: '#a8957d', scale: 0.85 },
  crow: { bg: ['#dfe6ea', '#a9b7bf', '#66767f'], body: ['#2a2d33', '#121417'], breast: ['#26292e', '#15171a'],
    wing: ['#2f343c', '#0f1114'], head: '#202328', beak: '#16181b', eye: '#3a2a20', tail: '#121417', beakLen: 1.9, scale: 1.12 },
  jackdaw: { bg: ['#e4e8de', '#b4bfa6', '#728062'], body: ['#3a3e45', '#202328'], breast: ['#34383e', '#22252a'],
    wing: ['#3d424a', '#1b1e22'], head: '#2b2e33', nape: '#8f969e', beak: '#17191c', eye: '#e8eef0', tail: '#202328', beakLen: 1.2, scale: 0.95 },
  magpie: { bg: ['#e2ecf3', '#a8c1d3', '#5f7f96'], body: ['#1b1e22', '#0c0d0f'], breast: ['#f7f7f5', '#dcdcd8'],
    wing: ['#1f2a3a', '#0e1219'], wingPatch: '#f4f4f2', head: '#16181b', beak: '#121315', eye: '#2a2320', tail: '#1d3146', tailLen: 2.1, beakLen: 1.4, scale: 0.95 },
  blackbird: { bg: ['#e9efd8', '#bccb95', '#6f8445'], body: ['#2a2a2a', '#111'], breast: ['#262626', '#141414'],
    wing: ['#2d2d2d', '#101010'], head: '#1e1e1e', beak: '#f0a21b', eyeRing: '#f0b52a', eye: '#1a1a1a', tail: '#121212', beakLen: 1.2, scale: 0.78 },
  sparrow: { bg: ['#f3ead8', '#d9c499', '#9a8152'], body: ['#b3906a', '#7b5c3e'], breast: ['#cfc6b8', '#a9a092'],
    wing: ['#8e6440', '#5b3d24'], bars: '#f0ead9', head: '#8e939a', cheek: '#e9e4da', bib: '#2a2622', beak: '#2b2622', eye: '#1c1c1c',
    tail: '#6b4d33', beakLen: 0.8, scale: 0.7 },
};

function birdSvg(p) {
  const s = p.scale ?? 1;
  const beakLen = 50 * (p.beakLen ?? 1);
  const tailLen = p.tailLen ?? 1;
  const headY = p.pose === 'down' ? 340 : 300;
  const tailX = 330 - 180 * tailLen;
  const extras = [];
  if (p.bars) extras.push(`<path d="M470 520 C 520 512, 580 516, 630 530" stroke="${p.bars}" stroke-width="12" fill="none" stroke-linecap="round" opacity="0.85"/>
    <path d="M455 552 C 510 548, 570 552, 620 564" stroke="${p.bars}" stroke-width="12" fill="none" stroke-linecap="round" opacity="0.85"/>`);
  if (p.wingPatch) extras.push(`<path d="M420 500 C 480 470, 560 470, 620 500 C 560 530, 480 535, 420 520 Z" fill="${p.wingPatch}"/>`);
  const neck = [];
  if (p.neck) neck.push(`<path d="M745 ${headY + 80} C 760 ${headY + 65}, 790 ${headY + 62}, 810 ${headY + 72}" stroke="${p.neck}" stroke-width="22" fill="none" stroke-linecap="round" opacity="0.85"/>`);
  if (p.patch) neck.push(`<ellipse cx="770" cy="${headY + 102}" rx="30" ry="18" fill="${p.patch}" transform="rotate(-25 770 ${headY + 102})"/>`);
  if (p.collar) neck.push(`<path d="M748 ${headY + 70} C 765 ${headY + 58}, 795 ${headY + 56}, 815 ${headY + 66}" stroke="${p.collar}" stroke-width="12" fill="none" stroke-linecap="round"/>`);
  if (p.nape) neck.push(`<path d="M770 ${headY - 40} C 740 ${headY}, 735 ${headY + 60}, 750 ${headY + 110}" stroke="${p.nape}" stroke-width="40" fill="none" stroke-linecap="round" opacity="0.9"/>`);
  const face = [];
  if (p.cheek) face.push(`<ellipse cx="840" cy="${headY + 22}" rx="36" ry="24" fill="${p.cheek}"/>`);
  if (p.bib) face.push(`<path d="M850 ${headY + 45} C 870 ${headY + 70}, 860 ${headY + 110}, 830 ${headY + 130} C 815 ${headY + 100}, 820 ${headY + 70}, 850 ${headY + 45} Z" fill="${p.bib}"/>`);
  if (p.eyeRing) face.push(`<circle cx="850" cy="${headY - 8}" r="17" fill="${p.eyeRing}"/>`);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
  <defs>
    <radialGradient id="bg" cx="35%" cy="30%" r="90%">
      <stop offset="0" stop-color="${p.bg[0]}"/><stop offset="0.55" stop-color="${p.bg[1]}"/><stop offset="1" stop-color="${p.bg[2]}"/>
    </radialGradient>
    <radialGradient id="body" cx="40%" cy="35%" r="75%"><stop offset="0" stop-color="${p.body[0]}"/><stop offset="1" stop-color="${p.body[1]}"/></radialGradient>
    <linearGradient id="breast" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${p.breast[0]}"/><stop offset="1" stop-color="${p.breast[1]}"/></linearGradient>
    <linearGradient id="wing" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${p.wing[0]}"/><stop offset="1" stop-color="${p.wing[1]}"/></linearGradient>
    <filter id="soft"><feGaussianBlur stdDeviation="18"/></filter>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#bg)"/>
  <g filter="url(#soft)" opacity="0.5">
    <circle cx="160" cy="140" r="90" fill="#ffffff"/><circle cx="1040" cy="210" r="120" fill="${p.bg[0]}"/>
    <circle cx="960" cy="760" r="140" fill="${p.bg[2]}"/><circle cx="260" cy="760" r="110" fill="${p.bg[1]}"/>
  </g>
  <path d="M40 720 C 300 690, 620 700, 1180 640" stroke="#5a4130" stroke-width="34" fill="none" stroke-linecap="round"/>
  <path d="M760 690 C 820 640, 880 620, 960 610" stroke="#5a4130" stroke-width="16" fill="none" stroke-linecap="round"/>
  <g transform="translate(600 560) scale(${s}) translate(-600 -560)">
    <path d="M340 560 L ${tailX} 650 L ${tailX + 20} 690 L 360 620 Z" fill="${p.tail}"/>
    <ellipse cx="560" cy="520" rx="270" ry="170" fill="url(#body)"/>
    <ellipse cx="690" cy="520" rx="150" ry="140" fill="url(#breast)"/>
    <path d="M360 470 C 470 400, 640 410, 700 480 C 640 600, 470 640, 340 590 Z" fill="url(#wing)"/>
    ${extras.join('\n    ')}
    <path d="M700 420 C 720 ${headY + 30}, 760 ${headY - 20}, 810 ${headY - 30} C 870 ${headY - 38}, 900 ${headY + 10}, 890 ${headY + 60} C 880 ${headY + 110}, 830 ${headY + 140}, 790 470 Z" fill="${p.head}"/>
    ${neck.join('\n    ')}
    <circle cx="830" cy="${headY}" r="62" fill="${p.head}"/>
    ${face.join('\n    ')}
    <circle cx="850" cy="${headY - 8}" r="13" fill="${p.eye}"/>
    <circle cx="852" cy="${headY - 8}" r="7" fill="#1d1d1d"/>
    <circle cx="848" cy="${headY - 11}" r="3" fill="#ffffff" opacity="0.8"/>
    <path d="M885 ${headY - 2} L ${885 + beakLen} ${headY + 12} L 886 ${headY + 22} Z" fill="${p.beak}"/>
    <path d="M520 680 L 510 712 M560 682 L 572 712" stroke="#c9736b" stroke-width="12" stroke-linecap="round"/>
  </g>
</svg>`;
}

// ── Clinical pictures ───────────────────────────────────────────────────────
function xraySvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
  <defs><radialGradient id="g" cx="50%" cy="50%" r="70%"><stop offset="0" stop-color="#2b3036"/><stop offset="1" stop-color="#07090b"/></radialGradient>
  <filter id="b"><feGaussianBlur stdDeviation="6"/></filter></defs>
  <rect width="${W}" height="${H}" fill="url(#g)"/>
  <g filter="url(#b)" fill="none" stroke-linecap="round">
    <ellipse cx="600" cy="470" rx="250" ry="150" fill="#3b434b" opacity="0.7"/>
    <path d="M420 420 C 300 330, 220 300, 120 290" stroke="#c9d2d8" stroke-width="22"/>
    <path d="M420 440 C 330 380, 250 370, 150 380" stroke="#aeb8bf" stroke-width="16"/>
    <path d="M140 300 L 60 250" stroke="#d6dde2" stroke-width="14"/>
    <path d="M520 360 C 600 340, 680 345, 760 370" stroke="#cfd7dc" stroke-width="18"/>
    <path d="M560 600 L 545 720 M640 600 L 655 720" stroke="#c3ccd2" stroke-width="16"/>
    <path d="M760 380 C 820 300, 860 260, 900 250" stroke="#d9e0e4" stroke-width="20"/>
    <circle cx="930" cy="245" r="55" stroke="#bfc8ce" stroke-width="10"/>
  </g>
  <path d="M262 318 L 300 352" stroke="#e8eef2" stroke-width="5" opacity="0.9"/>
  <circle cx="281" cy="335" r="40" fill="none" stroke="#f2c14e" stroke-width="5" stroke-dasharray="14 10"/>
  <path d="M1080 48 L 1080 100 L 1112 100" stroke="#d7dde1" stroke-width="9" fill="none"/>
</svg>`;
}

function microscopeSvg(kind) {
  const r = (seed) => { let x = seed; return () => (x = (x * 9301 + 49297) % 233280) / 233280; };
  const rnd = r(kind === 'swab' ? 7 : 11);
  const items = [];
  for (let i = 0; i < 70; i++) {
    const x = 250 + rnd() * 700;
    const y = 100 + rnd() * 700;
    if ((x - 600) ** 2 + (y - 450) ** 2 > 330 ** 2) continue;
    if (kind === 'swab') {
      items.push(`<ellipse cx="${x}" cy="${y}" rx="${10 + rnd() * 6}" ry="${7 + rnd() * 4}" fill="#e8c9d6" stroke="#b07b93" stroke-width="2" transform="rotate(${rnd() * 180} ${x} ${y})"/>`);
      if (i % 3 === 0) items.push(`<path d="M${x} ${y} q 12 -10 22 -4 q 10 6 20 -2" stroke="#9b5f7c" stroke-width="2" fill="none"/>`);
    } else if (i % 4 === 0) {
      items.push(`<ellipse cx="${x}" cy="${y}" rx="26" ry="16" fill="#d9c58f" stroke="#8a7440" stroke-width="3" transform="rotate(${rnd() * 180} ${x} ${y})"/>`);
    } else {
      items.push(`<circle cx="${x}" cy="${y}" r="${3 + rnd() * 5}" fill="#c9b9a0" opacity="0.7"/>`);
    }
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
  <rect width="${W}" height="${H}" fill="#0b0b0b"/>
  <defs><radialGradient id="f" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#f6f1e6"/><stop offset="0.85" stop-color="#e6ddc9"/><stop offset="1" stop-color="#b8ad96"/></radialGradient></defs>
  <circle cx="600" cy="450" r="340" fill="url(#f)"/>
  ${items.join('\n  ')}
  <circle cx="600" cy="450" r="340" fill="none" stroke="#000" stroke-width="18" opacity="0.5"/>
</svg>`;
}

function eggsSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
  <defs><radialGradient id="bg" cx="50%" cy="40%" r="80%"><stop offset="0" stop-color="#e9dcc3"/><stop offset="1" stop-color="#9b8360"/></radialGradient>
  <radialGradient id="egg" cx="35%" cy="30%" r="80%"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#d9d4c8"/></radialGradient></defs>
  <rect width="${W}" height="${H}" fill="url(#bg)"/>
  <ellipse cx="600" cy="560" rx="380" ry="190" fill="#7a5a3a"/>
  <ellipse cx="600" cy="540" rx="320" ry="150" fill="#a07a4f"/>
  <g stroke="#c9a26c" stroke-width="10" stroke-linecap="round" opacity="0.8">
    <path d="M300 520 L 900 560"/><path d="M320 580 L 880 500"/><path d="M360 470 L 840 600"/><path d="M290 550 L 910 520"/>
  </g>
  <ellipse cx="520" cy="500" rx="70" ry="95" fill="url(#egg)" transform="rotate(-18 520 500)"/>
  <ellipse cx="690" cy="510" rx="70" ry="95" fill="url(#egg)" transform="rotate(14 690 510)"/>
</svg>`;
}

// ── PDFs ────────────────────────────────────────────────────────────────────
// A minimal single-page PDF with Helvetica text in WinAnsiEncoding (so German
// umlauts work), byte offsets computed exactly.
function pdf(lines) {
  const esc = (s) => {
    let out = '';
    for (const ch of s) {
      const c = ch.codePointAt(0);
      const map = { 0x2013: 0x96, 0x2014: 0x97, 0x2019: 0x92, 0x201e: 0x84, 0x201c: 0x93, 0x20ac: 0x80 };
      const code = map[c] ?? c;
      if (ch === '(' || ch === ')' || ch === '\\') out += `\\${ch}`;
      else if (code > 126 || code < 32) out += `\\${code.toString(8).padStart(3, '0')}`;
      else out += ch;
    }
    return out;
  };
  let y = 790;
  const ops = [];
  for (const l of lines) {
    const size = l.size ?? 11;
    y = l.y ?? y - (l.gap ?? size + 7);
    ops.push(`BT /${l.bold ? 'F2' : 'F1'} ${size} Tf ${l.x ?? 56} ${y} Td (${esc(l.text)}) Tj ET`);
  }
  ops.push('0.6 0.6 0.6 RG 56 70 m 539 70 l S');
  const stream = ops.join('\n');
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>',
    `<< /Length ${Buffer.byteLength(stream, 'latin1')} >>\nstream\n${stream}\nendstream`,
  ];
  let body = '%PDF-1.4\n%\xe2\xe3\xcf\xd3\n';
  const offsets = [];
  objs.forEach((o, i) => {
    offsets.push(Buffer.byteLength(body, 'latin1'));
    body += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = Buffer.byteLength(body, 'latin1');
  body += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`;
  for (const off of offsets) body += `${String(off).padStart(10, '0')} 00000 n \n`;
  body += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(body, 'latin1');
}

const FOOT = {
  de: 'Demo-Dokument mit erfundenen Daten – erstellt für die Federfall-Demovideos.',
  en: 'Demo document with invented data – made for the Federfall demo videos.',
};

const DOCS = {
  'fecal-report': {
    de: ['Vogelpraxis am Deich', 'Befundbericht Kotuntersuchung', [
      'Patient: Stadttaube „Fiete“ (Wildvogelhilfe Elbmarsch)',
      'Material: Sammelkot, 3 Tage',
      'Methode: Flotation',
      '',
      'Befund:',
      '  Spulwurmeier (Ascaridia)  ++',
      '  Haarwurmeier (Capillaria)  +',
      '  Kokzidien-Oozysten  vereinzelt',
      '',
      'Beurteilung: Mischinfektion mit Endoparasiten.',
      'Empfehlung: Entwurmung fortsetzen, Kontrolle nach Abschluss der Kur.']],
    en: ['Vogelpraxis am Deich', 'Fecal examination report', [
      'Patient: feral pigeon "Fiete" (Elbmarsch Wild Bird Rescue)',
      'Sample: pooled droppings, 3 days',
      'Method: flotation',
      '',
      'Findings:',
      '  Roundworm eggs (Ascaridia)  ++',
      '  Capillaria eggs  +',
      '  Coccidia oocysts  occasional',
      '',
      'Assessment: mixed endoparasite infection.',
      'Recommendation: continue deworming, re-test when the course is done.']],
  },
  'xray-report': {
    de: ['Vogelpraxis am Deich', 'Röntgenbefund', [
      'Patient: Rabenkrähe „Hedwig“ (Wildvogelhilfe Elbmarsch)',
      'Aufnahmen: ventrodorsal und laterolateral',
      '',
      'Befund: geschlossene Fraktur im Bereich des linken Unterarms,',
      'gute Stellung der Fragmente, keine Gelenkbeteiligung.',
      '',
      'Versorgung: Achterverband, Käfigruhe.',
      'Kontrolle: Röntgen in etwa zwei Wochen.']],
    en: ['Vogelpraxis am Deich', 'X-ray report', [
      'Patient: carrion crow "Hedwig" (Elbmarsch Wild Bird Rescue)',
      'Views: ventrodorsal and laterolateral',
      '',
      'Findings: closed fracture of the left forearm,',
      'fragments well aligned, no joint involvement.',
      '',
      'Treatment: figure-of-eight bandage, cage rest.',
      'Follow-up: X-ray in about two weeks.']],
  },
  referral: {
    de: ['Wildvogelhilfe Elbmarsch', 'Vorstellung zur Abschlusskontrolle', [
      'An: Vogelpraxis am Deich',
      'Patient: Stadttaube „Fiete“, Aufnahme vor 12 Tagen',
      '',
      'Bisheriger Verlauf:',
      '  Trichomonadose, mit Faucalin behandelt, Abstrich negativ',
      '  Endoparasiten, Wurmkur mit Nemakur läuft',
      '  Gewicht von 238 g auf 292 g gestiegen',
      '',
      'Fragestellung: Freigabe zur Auswilderung nach Ende der Kur?']],
    en: ['Elbmarsch Wild Bird Rescue', 'Referral for a final check', [
      'To: Vogelpraxis am Deich',
      'Patient: feral pigeon "Fiete", admitted 12 days ago',
      '',
      'Progress so far:',
      '  trichomonosis, treated with Faucalin, swab negative',
      '  endoparasites, Nemakur deworming course running',
      '  weight up from 238 g to 292 g',
      '',
      'Question: clear for release once the course is finished?']],
  },
};

function docPdf(id, locale) {
  const [from, title, body] = DOCS[id][locale];
  return pdf([
    { text: from, bold: true, size: 13, gap: 0 },
    { text: title, bold: true, size: 17, gap: 40 },
    ...body.map((t, i) => ({ text: t, gap: i === 0 ? 34 : 18 })),
    { text: FOOT[locale], size: 8, y: 56 },
  ]);
}

// ── Build ───────────────────────────────────────────────────────────────────
function jpeg(svg, out, { width = 800 } = {}) {
  const tmp = mkdtempSync(path.join(tmpdir(), 'ffdemo-gen-'));
  try {
    writeFileSync(path.join(tmp, 'in.svg'), svg);
    execFileSync('rsvg-convert', ['-w', String(width), '-o', path.join(tmp, 'out.png'), path.join(tmp, 'in.svg')]);
    execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', path.join(tmp, 'out.png'), '-q:v', '4', path.join(HERE, out)]);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

for (const [name, p] of Object.entries(BIRDS)) jpeg(birdSvg(p), `photo-${name}.jpg`);
jpeg(xraySvg(), 'xray-wing.jpg');
jpeg(microscopeSvg('swab'), 'microscopy-crop-swab.jpg');
jpeg(microscopeSvg('fecal'), 'microscopy-fecal.jpg');
jpeg(eggsSvg(), 'photo-eggs.jpg');
for (const id of Object.keys(DOCS)) {
  for (const locale of ['de', 'en']) writeFileSync(path.join(HERE, `${id}.${locale}.pdf`), docPdf(id, locale));
}
console.log('generated into', HERE);
