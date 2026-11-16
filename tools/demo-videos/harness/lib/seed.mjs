// Data setup, through the real API. Every video starts on a FRESH backend
// (backend.mjs → serve.sh), gets a dataset (lib/dataset.mjs: "base" or the
// lived-in "demo" org), then runs its own setup().
//
// The base is what every video needs: the organisation named in the run's
// language, its code lists in that language (code lists are database rows,
// seeded German by the migrations — an English video would otherwise show
// German chips), and one account per role. The demo dataset (data/demo/) is
// seeded on top of it by the same Seed object.
//
// Rules for anything that seeds: go through the routes whose hooks derive
// state (intake, dispositions, placements, the batch routes) as the person who
// would do it; use the superuser only for what no client may write (accounts,
// the organisation itself). The README's "Demo dataset" section lists the
// places the demo dataset departs from that, and why.
import { Api } from './backend.mjs';
import { DemoError } from './util.mjs';
import { CODE_LISTS, ORG_NAME, PEOPLE } from '../data/base.mjs';

export const PASSWORD = 'demo-video-1';

export class Seed {
  constructor({ su, locale, log }) {
    this.su = su;
    this.locale = locale;
    this.log = log;
    this.people = {};
    this.sessions = {};
    /** What the demo dataset seeded (record ids by cast name), or null. */
    this.demo = null;
  }

  /** A logged-in API client for one of the seeded people (`carer`, `supervisor`, …). */
  async as(role) {
    if (!this.sessions[role]) {
      const p = this.people[role];
      if (!p) throw new DemoError(`seed: no person with role "${role}"`);
      this.sessions[role] = await Api.user(p.email, PASSWORD);
    }
    return this.sessions[role];
  }

  /**
   * Everything a later video needs to carry on from this seeding: ids, and the
   * session tokens (valid for 30 days, and still valid in every COPY of the
   * data dir — reusing them is what keeps a video's setup from signing in
   * again, which the backend's `*:auth` budget of 2 per 3 s would refuse).
   */
  state() {
    return JSON.parse(JSON.stringify({
      org: this.org,
      people: this.people,
      tokens: Object.fromEntries(Object.entries(this.sessions).map(([k, v]) => [k, v.token])),
      suToken: this.su.token,
      demo: this.demo,
    }));
  }

  static restore({ locale, log }, state) {
    const seed = new Seed({ su: new Api(state.suToken), locale, log });
    seed.org = state.org;
    seed.people = state.people;
    seed.sessions = Object.fromEntries(Object.entries(state.tokens).map(([k, t]) => [k, new Api(t)]));
    seed.demo = state.demo;
    return seed;
  }

  /**
   * Runs [fn] with the backend's request budgets raised, then puts back exactly
   * the rules it found. A seeding is hundreds of writes in seconds, far past
   * `*:create` (20 per 5 s) and `/api/` (300 per 10 s); the backend's own rule
   * suite raises them the same way (tests/test_rules.py, "[rate limiting]").
   * The recorded app then runs under the real budgets again.
   */
  async withoutRateLimits(fn) {
    const settings = await this.su.get('/api/settings');
    const original = settings.rateLimits;
    const raised = { ...original, rules: original.rules.map((r) => ({ ...r, maxRequests: 1_000_000 })) };
    await this.su.patch('/api/settings', { rateLimits: raised });
    try {
      return await fn();
    } finally {
      await this.su.patch('/api/settings', { rateLimits: original });
    }
  }

  async base() {
    const org = (await this.su.list('organisations'))[0];
    if (!org) throw new DemoError('seed: the fresh backend has no organisation');
    this.org = await this.su.update('organisations', org.id, { name: ORG_NAME[this.locale] });

    // Code lists: rename the migration's German rows to this locale's labels.
    for (const [collection, labels] of Object.entries(CODE_LISTS)) {
      const rows = await this.su.list(collection, `filter=${encodeURIComponent(`org="${org.id}"`)}`);
      for (const row of rows) {
        const entry = labels.find((l) => l.de === row.label);
        if (!entry) throw new DemoError(`seed: ${collection} row "${row.label}" has no translation in data/base.mjs`);
        if (entry[this.locale] !== row.label) {
          await this.su.update(collection, row.id, { label: entry[this.locale] });
        }
      }
    }

    // People. The supervisor already exists (bootstrapped from the env by the
    // backend's own hook); the others are created here.
    await this.addPeople(PEOPLE);
    return this;
  }

  /** Creates (or resets) accounts as the superuser: {key: {role, name, email, …}}. */
  async addPeople(people) {
    for (const [key, p] of Object.entries(people)) {
      const { role, name, email, ...extra } = p;
      let user = (await this.su.list('users', `filter=${encodeURIComponent(`email="${email}"`)}`))[0];
      if (!user) {
        user = await this.su.create('users', {
          email, password: PASSWORD, passwordConfirm: PASSWORD, name,
          role, org: this.org.id, is_active: true, verified: true, emailVisibility: true, ...extra,
        });
      } else {
        user = await this.su.update('users', user.id, { name, password: PASSWORD, passwordConfirm: PASSWORD, ...extra });
      }
      this.people[key] = { ...p, id: user.id, password: PASSWORD };
    }
  }

  /** The active admission reasons, by label, in this locale. */
  async admissionReasons() {
    const rows = await this.su.list('admission_reasons', `filter=${encodeURIComponent(`org="${this.org.id}"`)}`);
    return Object.fromEntries(rows.map((r) => [r.label, r.id]));
  }

  /**
   * Past intakes by [role] through POST /api/federfall/intake — the real
   * route, so every hook that derives state runs. A carer only ever sees their
   * own cases, so intakes by the supervisor leave a carer's list empty while
   * still filling the org-wide vocabularies (species autocomplete).
   */
  async intakes(role, intakes) {
    const api = await this.as(role);
    const reasons = await this.admissionReasons();
    const out = [];
    for (const it of intakes) {
      const ids = (it.reasons ?? []).map((label) => {
        if (!reasons[label]) throw new DemoError(`seed: no admission reason "${label}"`);
        return reasons[label];
      });
      out.push(await api.post('/api/federfall/intake', {
        species: it.species, name: it.name,
        case: { admission_reasons: ids, ...(it.case ?? {}) },
        ...(it.weight_g ? { weight_g: it.weight_g } : {}),
      }));
    }
    return out;
  }
}
