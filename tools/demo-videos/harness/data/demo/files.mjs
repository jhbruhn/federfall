// The demo dataset's attachments: placeholders in assets/demo-data/, listed in
// its manifest.json (which file, which upload name per language, where used).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { DemoError } from '../../lib/util.mjs';

const DIR = fileURLToPath(new URL('../../../assets/demo-data/', import.meta.url));
let manifest;

/** One upload {name, type, bytes} for [id] in [locale]. */
export function attachment(id, locale) {
  manifest ??= JSON.parse(readFileSync(`${DIR}manifest.json`, 'utf8')).files;
  const entry = manifest[id];
  if (!entry) throw new DemoError(`seed: no attachment "${id}" in assets/demo-data/manifest.json`);
  const file = typeof entry.file === 'string' ? entry.file : entry.file[locale];
  return { name: entry.name[locale], type: entry.type, bytes: readFileSync(`${DIR}${file}`) };
}
