// Data setup, through the real API. Every video starts on a FRESH backend
// (backend.mjs → serve.sh), gets the base below, then runs its own setup().
//
// The base is what every video needs: the organisation named in the run's
// language, its code lists in that language (code lists are database rows,
// seeded German by the migrations — an English video would otherwise show
// German chips), and one account per role.
//
// Where the full demo dataset (federfall-1h9z.3) plugs in: as more helpers on
// the Seed object, called from a video's setup(). Rules for those helpers:
// go through the routes whose hooks derive state (intake, dispositions,
// placements) as the person who would do it; use the superuser only for what
// no client may write (accounts, the organisation itself).
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
  }

  /** A logged-in API client for one of the base people (`carer`, `supervisor`, …). */
  async as(role) {
    if (!this.sessions[role]) {
      const p = this.people[role];
      if (!p) throw new DemoError(`seed: no person with role "${role}"`);
      this.sessions[role] = await Api.user(p.email, PASSWORD);
    }
    return this.sessions[role];
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
    for (const [role, p] of Object.entries(PEOPLE)) {
      let user = (await this.su.list('users', `filter=${encodeURIComponent(`email="${p.email}"`)}`))[0];
      if (!user) {
        user = await this.su.create('users', {
          email: p.email, password: PASSWORD, passwordConfirm: PASSWORD, name: p.name,
          role: p.role, org: org.id, is_active: true, verified: true, emailVisibility: true,
        });
      } else {
        user = await this.su.update('users', user.id, { name: p.name, password: PASSWORD, passwordConfirm: PASSWORD });
      }
      this.people[role] = { ...p, id: user.id, password: PASSWORD };
    }
    return this;
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
