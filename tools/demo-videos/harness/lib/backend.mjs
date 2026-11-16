// The backend as the harness sees it: a fresh PocketBase per video (see
// backend/serve.sh for the other half of the reset handshake) and a small REST
// client for seeding through the real API.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { DemoError, sleep } from './util.mjs';

const CTL = process.env.FFDEMO_CTL ?? '/ffdemo/ctl';
export const BASE_URL = process.env.FFDEMO_BASE_URL ?? 'http://localhost:8090';

function generation() {
  try {
    return Number(readFileSync(`${CTL}/generation`, 'utf8').trim()) || 0;
  } catch {
    return 0;
  }
}

async function healthy() {
  try {
    const r = await fetch(`${BASE_URL}/api/health`);
    return r.ok;
  } catch {
    return false;
  }
}

/**
 * Waits for the backend to come up, then asks it for a fresh data dir and
 * waits for that. The runner never trusts compose to have ordered anything:
 * podman-compose 1.5.0 ignores depends_on conditions.
 */
export async function freshBackend({ timeoutMs = 180_000, log }) {
  const deadline = Date.now() + timeoutMs;
  while (!(existsSync(`${CTL}/generation`) && (await healthy()))) {
    if (Date.now() > deadline) {
      throw new DemoError(`backend did not come up within ${timeoutMs / 1000} s ` +
        `(no ${CTL}/generation or ${BASE_URL}/api/health not answering)`);
    }
    await sleep(500);
  }
  const before = generation();
  writeFileSync(`${CTL}/reset`, String(before));
  while (!(generation() > before && (await healthy()))) {
    if (Date.now() > deadline) {
      throw new DemoError(`backend did not restart with a fresh data dir within ${timeoutMs / 1000} s`);
    }
    await sleep(200);
  }
  log?.(`backend generation ${generation()} (fresh)`);
}

/** A thin PocketBase REST client. `token` is a user's or the superuser's. */
export class Api {
  constructor(token = null) {
    this.token = token;
  }

  async request(method, path, body, { raw = false } = {}) {
    const headers = this.token ? { Authorization: this.token } : {};
    let payload;
    if (body instanceof FormData) {
      payload = body;
    } else if (body !== undefined) {
      headers['content-type'] = 'application/json';
      payload = JSON.stringify(body);
    }
    const r = await fetch(BASE_URL + path, { method, headers, body: payload });
    const text = await r.text();
    if (!r.ok) {
      throw new DemoError(`seed: ${method} ${path} -> ${r.status} ${text.slice(0, 400)}`);
    }
    return raw ? text : text ? JSON.parse(text) : null;
  }

  get(path) { return this.request('GET', path); }
  post(path, body) { return this.request('POST', path, body); }
  patch(path, body) { return this.request('PATCH', path, body); }

  async list(collection, query = '') {
    const out = [];
    for (let page = 1; ; page++) {
      const r = await this.get(`/api/collections/${collection}/records?perPage=200&page=${page}${query ? `&${query}` : ''}`);
      out.push(...r.items);
      if (page >= r.totalPages) return out;
    }
  }

  create(collection, data) { return this.post(`/api/collections/${collection}/records`, data); }
  update(collection, id, data) { return this.patch(`/api/collections/${collection}/records/${id}`, data); }

  static async superuser() {
    const r = await new Api().post('/api/collections/_superusers/auth-with-password', {
      identity: process.env.FFDEMO_SUPERUSER_EMAIL,
      password: process.env.FFDEMO_SUPERUSER_PASSWORD,
    });
    return new Api(r.token);
  }

  static async user(email, password) {
    const r = await new Api().post('/api/collections/users/auth-with-password',
      { identity: email, password });
    return new Api(r.token);
  }
}
