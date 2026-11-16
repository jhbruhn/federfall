import { createRequire } from 'node:module';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';

const execFileP = promisify(execFile);

// playwright-core lives in the image (/opt/ffdemo/node_modules), the harness on
// the /demo mount — ESM import resolution would not find it from here.
export const requireTool = createRequire(
  `${process.env.FFDEMO_NODE_MODULES ?? '/opt/ffdemo/node_modules'}/`,
);

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** A failure the run reports as its cause, verbatim — no stack trace noise. */
export class DemoError extends Error {}

/** Rejects with a DemoError naming [what] if [promise] does not settle in [ms]. */
export async function withTimeout(promise, ms, what) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new DemoError(`timed out after ${ms} ms: ${what}`)), ms);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

export async function run(cmd, args, opts = {}) {
  const { stdout } = await execFileP(cmd, args, { maxBuffer: 64 * 1024 * 1024, ...opts });
  return stdout;
}

/** Runs a command to completion; kills it and fails if it outlives [ms]. */
export function runBounded(cmd, args, ms, { log, env } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'], env: env ?? process.env });
    let tail = '';
    const keep = (d) => {
      log?.write(d);
      tail = (tail + d).slice(-4000);
    };
    child.stdout.on('data', keep);
    child.stderr.on('data', keep);
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new DemoError(`timed out after ${ms} ms: ${cmd} ${args[0] ?? ''}`));
    }, ms);
    child.on('exit', (code, signal) => {
      clearTimeout(timer);
      if (code === 0) resolve(tail);
      else reject(new DemoError(`${cmd} exited with ${code ?? signal}: ${tail.split('\n').filter(Boolean).slice(-3).join(' | ').slice(0, 600)}`));
    });
  });
}

export function startProcess(cmd, args, { log, ...opts } = {}) {
  const child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'], ...opts });
  if (log) {
    child.stdout.on('data', (d) => log.write(d));
    child.stderr.on('data', (d) => log.write(d));
  } else {
    child.stdout.resume();
    child.stderr.resume();
  }
  return child;
}

export async function probeDurationMs(file) {
  const out = await run('ffprobe', ['-v', 'error', '-show_entries', 'format=duration',
    '-of', 'csv=p=0', file]);
  const sec = Number(out.trim());
  if (!Number.isFinite(sec) || sec <= 0) throw new DemoError(`${file} has no duration`);
  return Math.round(sec * 1000);
}

export async function probeVideo(file) {
  const out = await run('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries',
    'stream=width,height,codec_name:format=duration', '-of', 'json', file]);
  const meta = JSON.parse(out);
  const s = meta.streams?.[0];
  if (!s) throw new DemoError(`${file} has no video stream`);
  return { width: s.width, height: s.height, codec: s.codec_name,
    durationMs: Math.round(Number(meta.format.duration) * 1000) };
}

export function slugify(s) {
  return s.toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}
