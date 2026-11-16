// The demo dataset: a lived-in organisation, seeded through the real API as
// the people who would have done each thing (README, "Demo dataset").
//
// How it is built: stories.mjs (the showcase birds) and bulk.mjs (a year and a
// half of ordinary cases for the lists and statistics) do not write anything
// themselves — they SCHEDULE steps at the moment the step happened in the
// story ("Lena weighs Fiete at 07:30 three days ago"). seedDemo() then runs
// every step in that order. That is what keeps case numbers chronological
// (they are assigned at creation, per year of admission) and the audit log in
// a plausible order, even though every write happens within seconds.
import { codeLabel } from '../base.mjs';
import { DemoError } from '../../lib/util.mjs';
import { AVIARIES, DEMO_PEOPLE } from './cast.mjs';
import { attachment } from './files.mjs';
import { scheduleBulk } from './bulk.mjs';
import { scheduleStories } from './stories.mjs';
import { ORG_CONTACT, ORG_SETTINGS, PRODUCTS, SPECIES, VACCINES } from './vocab.mjs';

const enc = encodeURIComponent;

/** Rounds a calculated amount to 3 significant digits (what a carer would write down). */
export function sig(x, digits = 3) {
  if (!x) return 0;
  return Number(x.toPrecision(digits));
}

export class Ctx {
  constructor(seed, clock, log) {
    this.seed = seed;
    this.clock = clock;
    this.locale = seed.locale;
    this.log = log ?? (() => {});
    this.steps = [];
    this.ids = { aviaries: {}, animals: {}, cases: {}, medications: {}, sponsorships: {}, products: {}, quarantine: {} };
    this.weights = {}; // animal key → [{ms, g}]
    this.moves = {}; // animal key → [{aviary, ms}] in execution order
    this.caseAnimal = {}; // case key → animal key
    this.stats = { requests: 0 };
  }

  // ── Scheduling ──────────────────────────────────────────────────────────
  at(ms, label, fn) {
    if (!Number.isFinite(ms)) throw new DemoError(`seed: step "${label}" has no time`);
    this.steps.push({ ms, seq: this.steps.length, label, fn });
  }

  async run() {
    const order = [...this.steps].sort((a, b) => a.ms - b.ms || a.seq - b.seq);
    for (const st of order) {
      try {
        await st.fn();
      } catch (e) {
        throw new DemoError(`seed step "${st.label}" (${new Date(st.ms).toISOString()}): ${e.message}`);
      }
    }
  }

  // ── Small things ────────────────────────────────────────────────────────
  /** This locale's value of {de, en} (anything else is returned as is). */
  L(v) {
    if (v && typeof v === 'object' && 'de' in v && 'en' in v) return v[this.locale];
    return v;
  }

  iso(ms) { return new Date(ms).toISOString(); }
  api(role) { return this.seed.as(role); }
  user(role) { return this.seed.people[role].id; }
  get org() { return this.seed.org.id; }
  species(key) { return SPECIES[key][this.locale]; }

  code(collection, de) {
    const label = codeLabel(collection, de, this.locale);
    const id = this.codes[collection]?.[label];
    if (!id) throw new DemoError(`seed: no ${collection} row "${label}"`);
    return id;
  }

  caseId(key) {
    const id = this.ids.cases[key];
    if (!id) throw new DemoError(`seed: case "${key}" does not exist (yet)`);
    return id;
  }

  animalId(key) {
    const id = this.ids.animals[key];
    if (!id) throw new DemoError(`seed: animal "${key}" does not exist (yet)`);
    return id;
  }

  files(ids) { return ids.map((id) => attachment(id, this.locale)); }

  async create(role, collection, data, fileFields) {
    const api = await this.api(role);
    this.stats.requests++;
    const body = { org: this.org, ...data };
    if (fileFields && Object.values(fileFields).some((l) => l.length)) {
      return api.multipart('POST', `/api/collections/${collection}/records`, body, fileFields);
    }
    return api.create(collection, body);
  }

  async update(role, collection, id, data) {
    this.stats.requests++;
    return (await this.api(role)).update(collection, id, data);
  }

  async route(role, path, body, fileFields) {
    const api = await this.api(role);
    this.stats.requests++;
    if (fileFields && Object.values(fileFields).some((l) => l.length)) return api.multipart('POST', path, body, fileFields);
    return api.post(path, body);
  }

  /** The newest recorded weight of [animalKey] at or before [ms]. */
  weightAt(animalKey, ms) {
    const list = (this.weights[animalKey] ?? []).filter((w) => w.ms <= ms);
    return list.length ? list[list.length - 1].g : null;
  }

  noteWeight(animalKey, ms, g) {
    (this.weights[animalKey] ??= []).push({ ms, g });
    this.weights[animalKey].sort((a, b) => a.ms - b.ms);
  }

  // ── Setup (before the story starts) ─────────────────────────────────────
  async init() {
    await this.seed.addPeople(DEMO_PEOPLE);
    // Vocabulary lookups, by this locale's label.
    this.codes = {};
    for (const c of ['admission_reasons', 'marking_types', 'medication_routes', 'conditions', 'microscopy_finding_types']) {
      const rows = await this.seed.su.list(c, `filter=${enc(`org="${this.org}"`)}`);
      this.codes[c] = Object.fromEntries(rows.map((r) => [r.label, r.id]));
    }
    // The org's own settings, written by its supervisor.
    await this.update('supervisor', 'organisations', this.org, {
      contact_email: ORG_CONTACT.email,
      contact_phone: ORG_CONTACT.phone,
      settings: { ...(this.seed.org.settings ?? {}), ...ORG_SETTINGS },
    });
    // The drug catalogue: the migration's placeholders out, the org's in.
    for (const row of await this.seed.su.list('medication_products', `filter=${enc(`org="${this.org}"`)}`)) {
      await (await this.api('supervisor')).remove('medication_products', row.id);
    }
    for (const [key, p] of Object.entries(PRODUCTS)) {
      const rec = await this.create('supervisor', 'medication_products', {
        label: this.L(p.label), dose_unit: p.dose_unit, dose_rate: p.dose_rate, rate_min: p.rate_min, rate_max: p.rate_max,
        concentration_per_ml: p.concentration_per_ml ?? null, route: this.code('medication_routes', p.route),
        frequency_kind: p.frequency_kind, interval_hours: p.interval_hours ?? null,
        cycle_on_days: p.cycle_on_days ?? null, cycle_off_days: p.cycle_off_days ?? null, cycle_repeats: p.cycle_repeats ?? null,
        note: this.L(p.note), active: true,
      });
      this.ids.products[key] = rec.id;
    }
    // Enclosures, set up by the coordinator.
    for (const [key, a] of Object.entries(AVIARIES)) {
      const rec = await this.create('coordinator', 'aviaries', {
        name: this.L(a.name), keeper: this.user(a.keeper), location: this.L(a.location),
        capacity: a.capacity, active: true, notes: this.L(a.notes),
      });
      this.ids.aviaries[key] = rec.id;
    }
  }

  // ── Domain helpers, each one the call the app makes ─────────────────────

  /**
   * POST /api/federfall/intake as [role]. [o.animal] re-admits an existing
   * bird (by animal key); otherwise a new animal [o.animalKey] is created.
   */
  async intake(role, caseKey, o) {
    const p = o.place;
    const body = {
      ...(o.animal ? { animal: this.animalId(o.animal) } : { species: this.species(o.species), name: o.name || undefined }),
      case: {
        admission_reasons: (o.reasons ?? []).map((r) => this.code('admission_reasons', r)),
        age_class: o.age, admitted_at: this.iso(o.ms), found_at: this.iso(o.foundMs ?? o.ms - 3_600_000),
        ...(p ? { find_location: p.name, city: p.city, region: p.region, find_geo: { lat: o.lat ?? p.lat, lon: o.lon ?? p.lon } } : {}),
        intake_notes: this.L(o.notes) ?? '',
      },
      ...(o.weight ? { weight_g: o.weight } : {}),
      ...(o.finder ? { finder: o.finder } : {}),
      ...(o.quarantineDays ? { quarantine_days: o.quarantineDays } : {}),
    };
    const res = await this.route(role, '/api/federfall/intake', body, { intake_photos: this.files(o.photos ?? []) });
    const animalKey = o.animal ?? o.animalKey ?? caseKey;
    this.ids.cases[caseKey] = res.id;
    this.ids.animals[animalKey] = res.animal;
    this.caseAnimal[caseKey] = animalKey;
    if (o.weight) this.noteWeight(animalKey, o.ms, o.weight);
    // The sex is not part of the intake wizard; the carer sets it on the bird.
    if (o.sex && o.sex !== 'unknown' && !o.animal) await this.update(role, 'animals', res.animal, { sex: o.sex });
    return res;
  }

  async weigh(role, caseKey, ms, g, notes) {
    const animalKey = this.caseAnimal[caseKey];
    await this.create(role, 'weights', {
      animal: this.animalId(animalKey), case: this.caseId(caseKey), measured_at: this.iso(ms), weight_g: g,
      notes: this.L(notes) ?? '', author: this.user(role),
    });
    this.noteWeight(animalKey, ms, g);
  }

  /** A weight with no case — a keeper weighing a resident. */
  async weighAnimal(role, animalKey, ms, g) {
    await this.create(role, 'weights', {
      animal: this.animalId(animalKey), measured_at: this.iso(ms), weight_g: g, notes: '', author: this.user(role),
    });
    this.noteWeight(animalKey, ms, g);
  }

  async dispose(role, caseKey, ms, type, o = {}) {
    const rel = o.release;
    const rec = await this.create(role, 'dispositions', {
      case: this.caseId(caseKey), type, disposed_at: this.iso(ms), reason: this.L(o.reason) ?? '',
      performed_by: this.user(role), vet_signed_off: !!o.vetSignedOff, vet: o.vet ?? '',
      release_location: rel ? rel.name + (rel.city !== 'Hamburg' ? `, ${rel.city}` : '') : '',
      release_geo: rel ? { lat: o.lat ?? rel.lat, lon: o.lon ?? rel.lon } : { lat: 0, lon: 0 },
      release_type: this.L(o.releaseType) ?? '',
      transfer_type: this.L(o.transferType) ?? '', transfer_destination: this.L(o.destination) ?? '',
      aviary: o.aviary ? this.ids.aviaries[o.aviary] : '',
    });
    const animalKey = this.caseAnimal[caseKey];
    if (type === 'placed_in_aviary') this.noteMove(animalKey, o.aviary, ms);
    else if (o.leavesAviary) this.noteMove(animalKey, null, ms);
    return rec;
  }

  noteMove(animalKey, aviaryKey, ms) {
    (this.moves[animalKey] ??= []).push({ aviary: aviaryKey ? this.ids.aviaries[aviaryKey] : null, ms });
  }

  async condition(role, caseKey, de, o = {}) {
    return this.create(role, 'case_conditions', {
      case: this.caseId(caseKey), condition: this.code('conditions', de), certainty: o.certainty ?? 'confirmed',
      onset_date: this.iso(o.onset), resolved_date: o.resolved ? this.iso(o.resolved) : '', notes: this.L(o.notes) ?? '',
    });
  }

  async journal(role, target, ms, text, files = []) {
    return this.create(role, 'journal_entries', {
      ...(target.aviary ? { aviary: this.ids.aviaries[target.aviary] } : { case: this.caseId(target.case) }),
      entry_at: this.iso(ms), text: this.L(text), author: this.user(role),
    }, { attachments: this.files(files) });
  }

  /** A prescription on [caseKey] from catalogue entry [product], as the sheet writes it. */
  async prescribe(role, caseKey, medKey, product, o) {
    const p = PRODUCTS[product];
    const rec = await this.create(role, 'medications', this.planOf(p, o, caseKey));
    this.ids.medications[medKey] = rec.id;
    this.meds ??= {};
    this.meds[medKey] = { product, caseKey, role };
    return rec;
  }

  planOf(p, o, caseKey) {
    return {
      ...(caseKey ? { case: this.caseId(caseKey) } : {}),
      drug: this.L(p.label), dose: null, dose_unit: p.dose_unit, dose_rate: p.dose_rate,
      concentration_per_ml: p.concentration_per_ml ?? null, frequency_kind: p.frequency_kind,
      interval_hours: p.interval_hours ?? null, cycle_on_days: p.cycle_on_days ?? null, cycle_off_days: p.cycle_off_days ?? null,
      route: this.code('medication_routes', p.route), started_at: this.iso(o.start), ended_at: o.end ? this.iso(o.end) : '',
      is_controlled: false,
      // What the product is for leads the instructions, so a viewer reading a
      // prescription learns it without the catalogue ("Wurmkur – …").
      instructions: [this.L(p.note), this.L(o.instructions)].filter(Boolean).join(' – '), prescribed_by: o.prescribedBy ?? '',
    };
  }

  /** The amount a per-kg plan gives a bird of its latest weight: {dose, weight_g_used, volume_ml}. */
  doseFor(medKey, ms) {
    const m = this.meds[medKey];
    const p = PRODUCTS[m.product];
    const g = this.weightAt(this.caseAnimal[m.caseKey], ms);
    const dose = sig((p.dose_rate * g) / 1000);
    return { dose, weight_g_used: g, volume_ml: p.concentration_per_ml ? sig(dose / p.concentration_per_ml) : null };
  }

  /** One dose logged on the administration sheet. */
  async give(role, medKey, ms, notes) {
    const m = this.meds[medKey];
    const p = PRODUCTS[m.product];
    const d = this.doseFor(medKey, ms);
    return this.create(role, 'medication_administrations', {
      case: this.caseId(m.caseKey), medication: this.ids.medications[medKey], drug: this.L(p.label),
      dose: d.dose, dose_unit: p.dose_unit, weight_g_used: d.weight_g_used, volume_ml: d.volume_ml,
      route: this.code('medication_routes', p.route), administered_at: this.iso(ms), notes: this.L(notes) ?? '',
      administered_by: this.user(role),
    });
  }

  /** A dose round over a group: POST /api/federfall/administer-batch. */
  async round(role, medKeys, ms) {
    return this.route(role, '/api/federfall/administer-batch', {
      doses: medKeys.map((k) => ({ medication: this.ids.medications[k], ...this.doseFor(k, ms) })),
      administration: { administered_at: this.iso(ms) },
    });
  }

  async exam(role, caseKey, ms, exam, findings = []) {
    return this.route(role, '/api/federfall/exam', {
      case: this.caseId(caseKey), animal: this.animalId(this.caseAnimal[caseKey]),
      exam: { ...exam, examined_at: this.iso(ms), notes: this.L(exam.notes) ?? '' },
      findings: findings.map((f) => ({ system: f[0], status: f[1], note: this.L(f[2]) ?? '' })),
    });
  }

  async microscopy(role, caseKey, ms, sample, findings = [], files = []) {
    return this.route(role, '/api/federfall/microscopy', {
      case: this.caseId(caseKey),
      sample: { ...sample, examined_at: this.iso(ms), notes: this.L(sample.notes) ?? '', no_findings: findings.length === 0 },
      findings: findings.map(([de, severity]) => ({ finding_type: this.code('microscopy_finding_types', de), severity })),
    }, { attachments: this.files(files) });
  }

  async marking(role, animalKey, o) {
    return this.create(role, 'markings', {
      animal: this.animalId(animalKey), ...(o.case ? { applied_in_case: this.caseId(o.case) } : {}),
      type: this.code('marking_types', o.type), code: o.code ?? '', colour: this.L(o.colour) ?? '',
      scheme_org: this.L(o.scheme) ?? '', applied_at: this.iso(o.ms), present_at_find: !!o.presentAtFind,
      applied_by: this.user(role), is_active: true,
    });
  }

  async followUp(role, caseKey, dueMs, note, doneMs) {
    return this.create(role, 'follow_ups', {
      case: this.caseId(caseKey), due_at: this.iso(dueMs), note: this.L(note),
      done_at: doneMs ? this.iso(doneMs) : '', created_by: this.user(role),
    });
  }

  async vet(role, caseKey, startsMs, o, files = []) {
    return this.create(role, 'vet_appointments', {
      case: this.caseId(caseKey), starts_at: this.iso(startsMs), vet: o.vet, reason: this.L(o.reason) ?? '',
      outcome: this.L(o.outcome) ?? '', attended_at: o.attendedMs ? this.iso(o.attendedMs) : '',
      reminder_lead_minutes: o.leadMinutes ?? null, reminder_muted: false, created_by: this.user(role),
    }, { attachments: this.files(files) });
  }

  /** Ends the case's running quarantine at [ms] (the inline "end now", backdated). */
  async endQuarantine(role, caseKey, ms) {
    const api = await this.api(role);
    const rows = await api.list('quarantine_records', `filter=${enc(`case="${this.caseId(caseKey)}"`)}&sort=-created`);
    if (!rows[0]) throw new DemoError(`seed: ${caseKey} has no quarantine to end`);
    return this.update(role, 'quarantine_records', rows[0].id, { quarantine_until: this.iso(ms) });
  }

  /** A placement with `to_user`: the handoff the hook turns into the carer change. */
  async handoff(role, caseKey, ms, toRole, o = {}) {
    return this.create(role, 'placements', {
      case: this.caseId(caseKey), moved_in_at: this.iso(ms), carer: this.user(toRole), from_user: this.user(role),
      to_user: this.user(toRole), enclosure: '', condition_at_handoff: this.L(o.condition) ?? '', comments: this.L(o.comments) ?? '',
    });
  }

  async share(role, caseKey, withRole, access) {
    return this.create(role, 'case_shares', {
      case: this.caseId(caseKey), shared_with: this.user(withRole), access, shared_by: this.user(role),
    });
  }

  async status(role, caseKey, status) {
    return this.update(role, 'cases', this.caseId(caseKey), { status });
  }

  /** A case-less resident added straight to an enclosure (the aviary's "add resident"). */
  async addResident(role, animalKey, aviaryKey, ms, o) {
    const rec = await this.create(role, 'animals', {
      species: this.species(o.species), name: o.name, sex: o.sex, current_aviary: this.ids.aviaries[aviaryKey],
      lifetime_status: 'in_aviary', notes: this.L(o.notes) ?? '',
    }, { photo: this.files(o.photos ?? []) });
    this.ids.animals[animalKey] = rec.id;
    this.noteMove(animalKey, aviaryKey, ms);
    return rec;
  }

  async sponsor(role, animalKey, key, s, o) {
    const rec = await this.create(role, 'sponsorships', {
      animal: this.animalId(animalKey), sponsor_name: this.L(s.name), sponsor_pronouns: this.L(s.pronouns) ?? '',
      address: s.address ?? '', postal_code: s.postal ?? '', city: s.city ?? '', region: s.region ?? '',
      mobile: s.mobile ?? '', amount_cents: o.cents, interval: o.interval, started_at: this.iso(o.start),
      ended_at: o.end ? this.iso(o.end) : '', notes: this.L(o.notes) ?? '',
    });
    this.ids.sponsorships[key] = rec.id;
    return rec;
  }

  vaccinationOf(vaccine, ms, o) {
    const v = VACCINES[vaccine];
    return {
      vaccine: this.L(v.vaccine), target: this.L(v.target), administered_at: this.iso(ms), batch: o.batch ?? '',
      dose: v.dose ?? null, dose_unit: v.dose_unit ?? '', route: v.route ? this.code('medication_routes', v.route) : '',
      series: o.series ?? '', next_due_at: o.nextDue ? this.iso(o.nextDue) : '', vet: o.vet ?? '', notes: this.L(o.notes) ?? '',
    };
  }

  async vaccinate(role, animalKey, vaccine, ms, o = {}) {
    return this.create(role, 'vaccinations', {
      animal: this.animalId(animalKey), ...this.vaccinationOf(vaccine, ms, o), author: this.user(role),
    });
  }

  /** Vaccinating a flock in one act: POST /api/federfall/vaccinate-batch. */
  async vaccinateBatch(role, animalKeys, vaccine, ms, o = {}) {
    return this.route(role, '/api/federfall/vaccinate-batch', {
      animals: animalKeys.map((k) => this.animalId(k)), vaccination: this.vaccinationOf(vaccine, ms, o),
    });
  }

  async egg(role, animalKey, ms, o, files = []) {
    return this.create(role, 'egg_records', {
      animal: this.animalId(animalKey), laid_at: this.iso(ms), count: o.count, fertility: o.fertility ?? 'unknown',
      fate: o.fate, attribution: o.attribution ?? 'confirmed', notes: this.L(o.notes) ?? '', author: this.user(role),
    }, { photos: this.files(files) });
  }

  // ── After the story ─────────────────────────────────────────────────────
  /**
   * `aviary_stays` is written by aviary_stays.pb.js with the SERVER clock, so
   * every residency would start "today". The rows have no client API at all
   * (superuser-only, unaudited by design), so the superuser dates them to the
   * moves the story made — the one write to a server-owned field this dataset
   * makes, listed in the README.
   */
  async dateResidencies() {
    for (const [animalKey, moves] of Object.entries(this.moves)) {
      const stays = await this.seed.su.list('aviary_stays',
        `filter=${enc(`animal="${this.animalId(animalKey)}"`)}&sort=created,id`);
      const arrivals = moves.filter((m) => m.aviary);
      if (stays.length !== arrivals.length) {
        throw new DemoError(`seed: ${animalKey} has ${stays.length} residencies but the story moved it in ${arrivals.length} times`);
      }
      stays.forEach((stay, i) => {
        const at = moves.indexOf(arrivals[i]);
        stay._start = arrivals[i].ms;
        stay._end = moves[at + 1]?.ms ?? null;
      });
      for (const stay of stays) {
        await this.seed.su.update('aviary_stays', stay.id, {
          started_at: this.iso(stay._start), ...(stay.ended_at ? { ended_at: this.iso(stay._end) } : {}),
        });
      }
    }
  }

  export() {
    return {
      runDay: this.clock.label,
      aviaries: this.ids.aviaries,
      animals: this.ids.animals,
      cases: this.ids.cases,
      medications: this.ids.medications,
      sponsorships: this.ids.sponsorships,
      products: this.ids.products,
    };
  }
}

/** Seeds the demo organisation on top of the base (seed.base() has run). */
export async function seedDemo(seed, { clock, log }) {
  const ctx = new Ctx(seed, clock, log);
  const t0 = Date.now();
  await ctx.init();
  scheduleStories(ctx);
  const bulk = scheduleBulk(ctx);
  log?.(`demo: ${ctx.steps.length} steps scheduled (${bulk.cases} bulk cases)`);
  await ctx.run();
  await ctx.dateResidencies();
  seed.demo = ctx.export();
  log?.(`demo: ${ctx.stats.requests} writes in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  return ctx;
}
