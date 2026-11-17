// Turns one recorded run into an OpenScreen document and renders it.
//
// The document is OpenScreen's own editor format (schemaVersion 9), written by
// hand. Upstream declares it unstable, which is why the binary is pinned to
// v2.2.2 by checksum: a version bump means re-checking this file against a
// document that version writes itself. Two things only this format can do, and
// both are used: text pinned to the output frame (`space: "frame"`, so a zoom
// does not move it) and burned-in captions from a transcript we write from
// text (no audio, no Whisper).
//
// The cursor is not in the capture (x11grab runs with -draw_mouse 0). It is the
// sidecar `<video>.cursor.json`, written from the harness's own pointer
// samples, which OpenScreen draws with its click animation.
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { DemoError, probeVideo, requireTool, runBounded } from './util.mjs';

// The look (see README, "Look"). Colours are the app's own green family.
//
// `mask` is the footage's frame (see frameArt): the wallpaper with a hole
// where the footage sits at rest, its rounded corners and its shadow, drawn
// OVER the footage for the whole clip. OpenScreen 2.2.2 clips a zoomed screen
// to its slot only in a camera block layout or in "format fill" (no bands at
// all); in this layout the zoomed footage grows past its box — at depth 3 it
// is 1.8× the box, taller than the frame — and ran under the title and the
// captions. Annotations are painted after the screen and the cursor, by
// zIndex, captions last (100000+), so the mask (zIndex 0) sits between the
// footage and the title/captions and a zoom stays inside the box. The same
// PNG is the wallpaper, so the bands match it to the pixel; OpenScreen's own
// rounding and shadow would be hidden by the mask, so the mask draws both.
export const LOOK = {
  phone: {
    aspectRatio: '9:16',
    out: { width: 1080, height: 1920 },
    padding: 70,
    wallpaper: 'linear-gradient(160deg, #1f4d3a 0%, #2f6b4f 55%, #3d7d5f 100%)',
    borderRadius: 28,
    shadowIntensity: 0,
    // OpenScreen draws the corners at ~20 px here (measured); the hole's are a
    // little rounder and 1.5 px inside, so no sliver of footage edge shows.
    mask: { radius: 24, inset: 1.5, shadow: { color: 'rgba(0,0,0,0.62)', blur: 64, y: 22 } },
    title: { y: 4, height: 6, width: 64, fontSize: 34 },
    captions: { fontSize: 28, insetY: 3, insetX: 6 },
  },
  desktop: {
    aspectRatio: '16:9',
    out: { width: 1920, height: 1080 },
    padding: 8,
    wallpaper: 'linear-gradient(160deg, #1f4d3a 0%, #2f6b4f 55%, #3d7d5f 100%)',
    borderRadius: 16,
    shadowIntensity: 0,
    mask: { radius: 14, inset: 1.5, shadow: { color: 'rgba(0,0,0,0.62)', blur: 48, y: 14 } },
    title: { y: 1.5, height: 7, width: 40, fontSize: 36 },
    captions: { fontSize: 36, insetY: 1.5, insetX: 10 },
  },
};

/**
 * Where OpenScreen puts the footage at rest, in output px: the frame scaled by
 * `1 − padding × 0.4` (the compositor's padding_scale), the source fitted
 * inside it and centred. Checked against an export: 184–896 × 269–1651 for
 * the phone look (824×1600 source).
 */
export function footageRect(look, vp) {
  const { width: W, height: H } = look.out;
  const scale = 1 - (look.padding / 100) * 0.4;
  const srcAspect = vp.width / vp.height;
  let w = W * scale;
  let h = w / srcAspect;
  if (h > H * scale) {
    h = H * scale;
    w = h * srcAspect;
  }
  return { x: (W - w) / 2, y: (H - h) / 2, width: w, height: h };
}

/**
 * The wallpaper as a PNG (Chromium's rendering of the CSS gradient) and the
 * mask over it (see LOOK): both at the output size, as data URLs, and as files
 * in [dir] for inspection.
 */
export async function frameArt({ dir, look, vp }) {
  const { chromium } = requireTool('playwright-core');
  const args = process.env.FFDEMO_NO_SANDBOX === '1' ? ['--no-sandbox'] : [];
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM ?? '/usr/bin/chromium', args });
  const { width, height } = look.out;
  const hole = footageRect(look, vp);
  try {
    const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
    await page.setContent(`<body style="margin:0"><div style="width:${width}px;height:${height}px;background:${look.wallpaper}"></div></body>`);
    const wallpaper = `data:image/png;base64,${(await page.screenshot({ type: 'png' })).toString('base64')}`;
    const mask = await page.evaluate(async ({ wallpaper, width, height, hole, m }) => {
      const img = new Image();
      img.src = wallpaper;
      await img.decode();
      const c = document.createElement('canvas');
      c.width = width;
      c.height = height;
      const g = c.getContext('2d');
      g.drawImage(img, 0, 0);
      const r = [hole.x + m.inset, hole.y + m.inset, hole.width - 2 * m.inset, hole.height - 2 * m.inset];
      // The shadow of an opaque card, then the card cut out: what is left is
      // the shadow on the wallpaper around a transparent, rounded hole.
      g.save();
      g.shadowColor = m.shadow.color;
      g.shadowBlur = m.shadow.blur;
      g.shadowOffsetY = m.shadow.y;
      g.fillStyle = '#000';
      g.beginPath();
      g.roundRect(...r, m.radius);
      g.fill();
      g.restore();
      g.globalCompositeOperation = 'destination-out';
      g.beginPath();
      g.roundRect(...r, m.radius);
      g.fill();
      return c.toDataURL('image/png');
    }, { wallpaper, width, height, hole, m: look.mask });
    for (const [name, url] of [['frame-wallpaper.png', wallpaper], ['frame-mask.png', mask]]) {
      writeFileSync(path.join(dir, name), Buffer.from(url.split(',')[1], 'base64'));
    }
    return { wallpaper, mask };
  } finally {
    await browser.close();
  }
}

const FONT = 'Roboto';

/** OpenScreen's depth → magnification table (src/lib/ai-edition/timeline/zoom-scale.ts, v2.2.2). */
export const ZOOM_DEPTH_SCALES = { 1: 1.25, 2: 1.5, 3: 1.8, 4: 2.2, 5: 3.5, 6: 5.0 };

/**
 * Where a zoom aims, as OpenScreen's focus (0..1 of the source). Zoomed, the
 * box shows a window of 1/scale of the source around the focus (clamped to
 * the source, frame_geometry.rs screen_source_rect), and with the frame mask
 * nothing outside that window is seen. A target that fits is centred; one
 * wider or taller than the window (a full-width text field) is shown from its
 * start — its label, icon and the first letters — rather than its middle.
 */
export function zoomFocus(target, vp, scale) {
  const PAD = 12; // CSS px kept clear around the target's leading edge
  const axis = (start, size, extent) => {
    const win = extent / scale;
    let centre = start + size / 2;
    if (size > win - 2 * PAD) centre = start - PAD + win / 2;
    return Math.min(Math.max(centre, win / 2), extent - win / 2) / extent;
  };
  return {
    cx: +axis(target.x, target.width, vp.width).toFixed(4),
    cy: +axis(target.y, target.height, vp.height).toFixed(4),
  };
}

/** Splits narration into caption cues of at most ~[max] characters, at sentence breaks first. */
export function cueTexts(text, max = 84) {
  const sentences = text.match(/[^.!?…]+[.!?…]*["“”„«»]?\s*/g)?.map((s) => s.trim()).filter(Boolean) ?? [text];
  const cues = [];
  for (const s of sentences) {
    if (s.length <= max) {
      cues.push(s);
      continue;
    }
    // A long sentence: break at the last comma/space before the limit.
    let rest = s;
    while (rest.length > max) {
      let cut = rest.lastIndexOf(', ', max);
      cut = cut > max * 0.4 ? cut + 1 : rest.lastIndexOf(' ', max);
      if (cut <= 0) cut = max;
      cues.push(rest.slice(0, cut).trim());
      rest = rest.slice(cut).trim();
    }
    if (rest) cues.push(rest);
  }
  return cues;
}

/** Captions as a transcript: one run of words per cue, cues separated by a pause. */
function transcriptFor(steps, locale, assetId) {
  const GAP = 0.32; // > OpenScreen's 0.24 s line-break gap: each cue is its own line
  const words = [];
  const segments = [];
  for (const step of steps) {
    const say = step.say?.[locale];
    if (!say) continue;
    const start = step.startMs / 1000 + 0.15;
    const end = step.endMs / 1000 - 0.1;
    const cues = cueTexts(say);
    const total = cues.reduce((n, c) => n + c.length, 0);
    const span = end - start - GAP * (cues.length - 1);
    let t = start;
    for (const cue of cues) {
      const cueDur = (span * cue.length) / total;
      const ws = cue.split(/\s+/);
      const chars = ws.reduce((n, w) => n + w.length, 0);
      let wt = t;
      const ids = [];
      for (const w of ws) {
        const d = (cueDur * w.length) / chars;
        const n = words.length + 1;
        words.push({ id: `word_${n}`, segmentId: `seg_${segments.length + 1}`,
          startSec: +wt.toFixed(3), endSec: +(wt + d).toFixed(3), text: w });
        ids.push(`word_${n}`);
        wt += d;
      }
      segments.push({ id: `seg_${segments.length + 1}`, kind: 'speech', startSec: +t.toFixed(3),
        endSec: +(t + cueDur).toFixed(3), text: cue, wordIds: ids });
      t += cueDur + GAP;
    }
  }
  return { assetId, language: locale, segments, words };
}

export function writeDocument({ dir, video, locale, vpName, vp, steps, intro, captureFile, meta, cursor, art }) {
  const look = LOOK[vpName];
  const assetId = 'asset_main';
  const clipId = 'clip_main';
  const durationSec = meta.durationMs / 1000;
  const s = (ms) => Math.round(ms) / 1000;
  const anchored = (o, startMs, endMs) => ({
    ...o, clipId, sourceStartSec: s(startMs), sourceEndSec: s(endMs),
    startMs: Math.round(startMs), endMs: Math.round(endMs),
  });
  const textStyle = (fontSize, extra = {}) => ({
    color: '#ffffff', backgroundColor: 'transparent', fontSize, fontFamily: FONT,
    fontWeight: 'bold', fontStyle: 'normal', textDecoration: 'none', textAlign: 'center',
    textAnimation: 'fade', ...extra,
  });

  // On-screen text: the video title over the first seconds, then each step's
  // `title` until the next one. Pinned to the frame, in the band above the app.
  const titles = [];
  const titleSpans = [];
  if (intro) titleSpans.push({ text: intro.text, startMs: intro.startMs, endMs: intro.endMs });
  const titled = steps.filter((st) => st.title?.[locale]);
  titled.forEach((st, i) => {
    const next = titled[i + 1];
    titleSpans.push({ text: st.title[locale], startMs: Math.max(st.startMs, intro?.endMs ?? 0),
      endMs: next ? next.startMs : meta.durationMs - 100 });
  });
  titleSpans.forEach((t, i) => {
    if (t.endMs - t.startMs < 300) return;
    titles.push(anchored({
      id: `title_${i + 1}`, type: 'text', content: t.text, textContent: t.text, space: 'frame',
      position: { x: (100 - look.title.width) / 2, y: look.title.y },
      size: { width: look.title.width, height: look.title.height },
      // A plate behind the text: a zoom enlarges the footage into this band,
      // and white on the app's white app bar would vanish.
      style: textStyle(look.title.fontSize, { backgroundColor: 'rgba(16,38,28,0.85)' }), zIndex: 1,
    }, t.startMs, t.endMs));
  });

  // The footage's frame, over the footage for the whole clip (see LOOK):
  // what keeps a zoom inside the box. Below the titles, below the captions.
  const frame = anchored({
    id: 'frame_mask', type: 'image', content: '', imageContent: art.mask, space: 'frame',
    position: { x: 0, y: 0 }, size: { width: 100, height: 100 },
    style: textStyle(look.title.fontSize, { textAnimation: 'none' }), zIndex: 0,
  }, 0, meta.durationMs);

  // Zooms: from the step's start to its end, aimed at the step's focus (an
  // explicit s.focus(), else the last thing the step clicked or typed into).
  const zooms = [];
  for (const st of steps) {
    if (!st.zoom) continue;
    const target = st.focus?.box ?? st.events.at(-1)?.box;
    if (!target) throw new DemoError(`step ${st.index + 1} asks for a zoom but touched nothing to aim at`);
    const depth = st.zoom.depth ?? 3;
    const { cx, cy } = zoomFocus(target, vp, ZOOM_DEPTH_SCALES[depth]);
    zooms.push(anchored({ id: `zoom_${zooms.length + 1}`, depth,
      focus: { cx: +cx.toFixed(4), cy: +cy.toFixed(4) }, focusMode: 'manual', source: 'manual' },
    st.startMs, st.endMs));
  }

  const transcript = transcriptFor(steps, locale, assetId);
  const doc = {
    schemaVersion: 9,
    project: { id: `ffdemo_${video.id}_${locale}`, title: video.title[locale],
      createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-01T00:00:00.000Z', primaryAssetId: assetId },
    assets: [{ id: assetId, kind: 'video', label: path.basename(captureFile), originalPath: captureFile,
      cameraTrack: null, durationSec, video: { codec: 'unknown', fps: 0, width: meta.width, height: meta.height } }],
    transcript,
    transcripts: [transcript],
    timeline: {
      clips: [{ id: clipId, assetId, sourceStartSec: 0, timelineStartSec: 0, timelineEndSec: durationSec,
        sourceEndSec: durationSec, wordRefs: [], origin: 'system', reason: 'ffdemo' }],
      gaps: [], trimRanges: [], muteRanges: [], speedRanges: [], captionRanges: [],
    },
    annotations: [frame, ...titles],
    zoomRanges: zooms,
    audioTracks: [],
    legacyEditor: {
      aspectRatio: look.aspectRatio, padding: look.padding, wallpaper: art.wallpaper,
      borderRadius: look.borderRadius, shadowIntensity: look.shadowIntensity,
      captions: { enabled: true, language: null, captionLane: 'recording', fontSize: look.captions.fontSize,
        fontFamily: FONT, fontWeight: 'bold', color: '#ffffff', backgroundEnabled: true,
        backgroundColor: '#10261c', backgroundOpacity: 0.82, anchorV: 'bottom', insetY: look.captions.insetY,
        anchorH: 'center', insetX: look.captions.insetX, minWordsPerLine: 1, maxWordsPerLine: 40 },
    },
    shaderEffectRanges: [],
  };
  const docFile = path.join(dir, 'project.openscreen');
  writeFileSync(docFile, JSON.stringify(doc, null, 2));
  writeFileSync(`${captureFile}.cursor.json`, JSON.stringify(cursor));
  return docFile;
}

/** Cursor sidecar from pointer samples (CSS px, capture clock). */
export function cursorTrack(samples, vp) {
  return {
    version: 2, provider: 'none', assets: [],
    samples: samples.map((p) => ({ timeMs: Math.max(0, Math.round(p.timeMs)),
      cx: +(p.x / vp.width).toFixed(5), cy: +(p.y / vp.height).toFixed(5), visible: true,
      interactionType: p.interactionType })),
  };
}

export async function exportClip({ docFile, outFile, durationMs, display, log }) {
  const args = ['export', docFile, '-o', outFile, '--json'];
  if (process.env.FFDEMO_NO_SANDBOX === '1') args.push('--no-sandbox');
  // A hang guard, not a pace: ~50 s for a 60 s clip measured, once 347 s on a busy host.
  const budget = 120_000 + durationMs * 8;
  await runBounded('openscreen', args, budget, { log, env: { ...process.env, DISPLAY: display } });
  const meta = await probeVideo(outFile);
  if (meta.durationMs < durationMs * 0.9) {
    throw new DemoError(`export is ${meta.durationMs} ms long, the capture ${durationMs} ms`);
  }
  return meta;
}
