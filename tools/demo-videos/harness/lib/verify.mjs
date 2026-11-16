// Checks the demo dataset against the backend that holds it: the DERIVED
// state, not whether writes returned 200. Every assertion reads the way the
// app does — as the person who would read it, through the same routes and
// views — and states what the story says should be true.
//
//   node harness/cli.mjs check [--locale de,en]      (in the runner)
//
// Prints one line per check and a fingerprint of the dataset: two seedings
// for the same run day must print the same fingerprint.
import { createHash } from 'node:crypto';
import { Api } from './backend.mjs';
import { PASSWORD } from './seed.mjs';
import { CODE_LISTS } from '../data/base.mjs';
import { AVIARIES, BIRDS, DEMO_PEOPLE, RINGS, SPONSORS } from '../data/demo/cast.mjs';
import { PRODUCTS } from '../data/demo/vocab.mjs';
import { Clock, runDayFromEnv } from '../data/demo/clock.mjs';

const enc = encodeURIComponent;
const f = (s) => `filter=${enc(s)}`;

export async function verifyDemo(seed, { clock, log = console.log }) {
  const results = [];
  // Checks that compare with the real clock (what is due, what is running)
  // only hold when the run day IS today; an injected FFDEMO_RUN_DAY is for
  // comparing seedings, and those checks are skipped, not failed.
  const live = clock.label === new Clock(runDayFromEnv({})).label;
  if (!live) log(`run day ${clock.label} is not today: checks against the real clock are skipped`);
  const check = (name, ok, detail = '') => {
    results.push({ name, ok: !!ok, detail });
    log(`${ok ? 'ok  ' : 'FAIL'}  ${name}${!ok && detail ? `  — ${detail}` : ''}`);
  };
  const L = (v) => v[seed.locale];
  const ids = seed.demo;
  const su = seed.su;
  const lena = await seed.as('carer');
  const tarek = await seed.as('carer2');
  const malte = await seed.as('coordinator');
  const johanna = await seed.as('supervisor');
  const people = seed.people;
  const now = Date.now();
  const berlinDay = (iso) => clock.dayOffsetOf(Date.parse(iso.replace(' ', 'T')));

  // ── Showcase birds: lifetime state, enclosure, case status, carer ───────
  const animals = Object.fromEntries((await su.list('animals', f(`org="${seed.org.id}"`))).map((a) => [a.id, a]));
  const caseOf = async (key) => su.one('cases', ids.cases[key]);
  const expect = [
    // [animal, lifetime, aviary|'', case, status, carer]
    ['fiete', 'in_care', '', 'fiete', 'in_care', 'carer'],
    ['kora', 'in_care', '', 'kora', 'in_care', 'carer'],
    ['hedwig', 'in_care', '', 'hedwig', 'in_care', 'carer'],
    ['gustav', 'in_care', '', 'gustav', 'in_care', 'carer'],
    ['bruno', 'in_care', '', 'bruno', 'in_care', 'carer'],
    ['lotte', 'in_care', '', 'lotte', 'in_care', 'carer'],
    ['mats', 'in_care', '', 'mats', 'in_care', 'carer'],
    ['mika', 'in_care', '', 'mika', 'in_care', 'carer'],
    ['pieps', 'in_care', '', 'pieps', 'ready_for_release', 'carer2'],
    ['tilda', 'in_care', '', 'tilda', 'in_care', 'carer2'],
    ['hinkebein', 'in_care', 'loft', 'hinkebein', 'in_care', 'carer2'],
    ['ringoDuplicate', 'in_care', '', 'ringoDuplicate', 'in_care', 'coordinator'],
    ['oskar', 'at_large_released', '', 'oskar', 'disposed', 'coordinator'],
    ['momo', 'at_large_released', '', 'momo', 'disposed', 'carer2'],
    ['wilma', 'deceased', '', 'wilma', 'disposed', 'carer'],
    ['ole', 'at_large_released', '', 'ole', 'disposed', 'carer'],
    ['ringo', 'at_large_released', '', 'ringo0', 'disposed', 'carer2'],
    ['erna', 'in_aviary', 'loft', 'erna0', 'disposed', 'carer'],
    ['frieda', 'in_aviary', 'loft', 'frieda0', 'disposed', 'carer'],
    ['kalle', 'in_aviary', 'outdoor', 'kalle0', 'disposed', 'coordinator'],
    ['smilla', 'in_aviary', 'outdoor', 'smilla', 'disposed', 'carer2'],
  ];
  for (const [a, life, aviary, c, status, carer] of expect) {
    const animal = animals[ids.animals[a]];
    const kase = await caseOf(c);
    const want = aviary ? ids.aviaries[aviary] : '';
    check(`${a}: ${life}${aviary ? ` in ${aviary}` : ''}, case ${status}, carer ${carer}`,
      animal?.lifetime_status === life && animal?.current_aviary === want && kase.status === status && kase.active_carer === people[carer].id,
      `got ${animal?.lifetime_status} / ${animal?.current_aviary} / ${kase.status} / ${kase.active_carer}`);
  }
  {
    const t = animals[ids.animals.tjark];
    check('tjark: a case-less resident of the outdoor aviary', t?.lifetime_status === 'in_aviary' && t?.current_aviary === ids.aviaries.outdoor);
  }
  for (const [key, b] of Object.entries(BIRDS)) {
    const a = animals[ids.animals[key]];
    check(`${key}: named "${b.name}", species in ${seed.locale}`, a && a.name === b.name, `got ${a?.name} / ${a?.species}`);
  }

  // Outcomes on the showcase cases.
  const outcomeOf = async (key) => (await su.list('dispositions', f(`case="${ids.cases[key]}"`)))[0];
  const outcomes = { gustav1: 'released', momo: 'released', oskar: 'transferred', wilma: 'died', ringo0: 'returned_to_owner', ole: 'released' };
  for (const [key, type] of Object.entries(outcomes)) {
    const d = await outcomeOf(key);
    check(`${key}: outcome ${type}`, d?.type === type, `got ${d?.type}`);
  }
  check('gustav: two cases, the earlier one released', (await su.list('cases', f(`animal="${ids.animals.gustav}"`))).length === 2);

  // Residencies dated to the story, not to the seeding.
  {
    const stays = await su.list('aviary_stays', f(`animal="${ids.animals.hinkebein}"`));
    check('hinkebein: residency since day -430', stays.length === 1 && berlinDay(stays[0].started_at) === -430 && !stays[0].ended_at,
      JSON.stringify(stays.map((s) => [s.started_at, s.ended_at])));
    const ole = await su.list('aviary_stays', f(`animal="${ids.animals.ole}"`));
    check('ole: residency day -210 … -21, closed', ole.length === 1 && berlinDay(ole[0].started_at) === -210 && berlinDay(ole[0].ended_at) === -21,
      JSON.stringify(ole.map((s) => [s.started_at, s.ended_at])));
  }

  // Markings.
  {
    const gustav = await su.list('markings', f(`animal="${ids.animals.gustav}"`));
    check('gustav: wears release ring EM 0412', gustav.some((m) => m.code === RINGS.gustav && m.is_active));
    const ringo = await su.list('markings', f(`code="${RINGS.ringo}"`));
    check('duplicate pair: both records carry the club ring, found with it', ringo.length === 2 && ringo.every((m) => m.present_at_find)
      && new Set(ringo.map((m) => m.animal)).size === 2);
    const clip = await su.list('markings', f(`animal="${ids.animals.fiete}"`));
    check('fiete: colour clip removed', clip.length === 1 && !clip[0].is_active && clip[0].removed_at && clip[0].removed_reason);
  }

  {
    // The station rings feral pigeons only; any other species may carry only a
    // ring it was FOUND with.
    const feral = (await import('../data/demo/vocab.mjs')).SPECIES.feralPigeon[seed.locale];
    const all = await su.list('markings', f(`org="${seed.org.id}"`));
    const bad = all.filter((m) => !m.present_at_find && animals[m.animal]?.species !== feral);
    check('markings: station-applied only on feral pigeons', all.length > 0 && bad.length === 0,
      bad.map((m) => `${animals[m.animal]?.species} ${m.code}`).join(', '));
  }

  // Handover and shares (C2).
  {
    const mikaShares = await su.list('case_shares', f(`case="${ids.cases.mika}"`));
    check('mika: Tarek kept read access after the handover', mikaShares.some((s) => s.shared_with === people.carer2.id && s.access === 'read'));
    const hinkShares = await su.list('case_shares', f(`case="${ids.cases.hinkebein}"`));
    check('hinkebein: Lena kept read access after handing the case to Tarek', hinkShares.some((s) => s.shared_with === people.carer.id && s.access === 'read'));
    const fieteShares = await su.list('case_shares', f(`case="${ids.cases.fiete}"`));
    check('fiete: shared with Tarek for editing', fieteShares.some((s) => s.shared_with === people.carer2.id && s.access === 'edit'));
  }

  // ── Today, as Lena ──────────────────────────────────────────────────────
  if (live) {
    const due = await lena.list('medication_due');
    const myCases = new Set((await lena.list('cases', f(`active_carer="${people.carer.id}" && status!="disposed"`))).map((c) => c.id));
    const soon = due.filter((r) => myCases.has(r.case_id) && r.next_due && Date.parse(r.next_due.replace(' ', 'T')) < now + 24 * 3_600_000);
    const drugs = soon.map((r) => r.drug);
    const roundDrug = L(PRODUCTS.antiprotozoal.label);
    check('Today (Lena): doses due within 24 h on at least 5 plans', soon.length >= 5, drugs.join(', '));
    check('Today (Lena): a dose round — one drug due on three birds', drugs.filter((x) => x === roundDrug).length === 3, drugs.join(', '));
    const deworm = due.find((r) => r.id === ids.medications.fieteDeworm);
    check('Fiete: the deworming course is on a giving day', deworm?.next_due && Date.parse(deworm.next_due.replace(' ', 'T')) < now + 24 * 3_600_000,
      JSON.stringify(deworm));
    const vets = await lena.list('vet_appointments', f('attended_at="" && cancelled_at=""'));
    const mine = vets.filter((v) => myCases.has(v.case));
    check('Today (Lena): a vet appointment today', mine.some((v) => berlinDay(v.starts_at) === 0), mine.map((v) => v.starts_at).join(', '));
    check('Today (Lena): an upcoming appointment with attachments', mine.some((v) => berlinDay(v.starts_at) > 0 && v.attachments.length > 0));
    const fu = (await lena.list('follow_ups', f('done_at=""'))).filter((x) => myCases.has(x.case));
    check('Today (Lena): follow-ups due', fu.filter((x) => berlinDay(x.due_at) <= 0).length >= 2, fu.map((x) => x.due_at).join(', '));
    const q = await lena.list('case_quarantine');
    const ending = q.filter((r) => myCases.has(r.id) && berlinDay(r.quarantine_until) === 0);
    check('Today (Lena): a quarantine ends today', ending.some((r) => r.id === ids.cases.hedwig), q.map((r) => r.quarantine_until).join(', '));
    const kora = q.find((r) => r.id === ids.cases.kora);
    check('Kora: quarantine started this morning, runs 14 days', kora && berlinDay(kora.set_at) === 0 && berlinDay(kora.quarantine_until) === 14);
  }
  if (live) {
    const due = await tarek.list('medication_due');
    check('Today (Tarek): his own dose due', due.some((r) => r.id === ids.medications.hinkebeinAntifungal && r.next_due));
  }

  // ── Statistics: current year AND the same period a year earlier ─────────
  {
    const y = clock.year;
    const s = await malte.get(`/api/federfall/stats?year=${y}`);
    const prev = s.series?.previous;
    check(`stats ${y}: intakes this year`, s.totals?.intakes > 12, JSON.stringify(s.totals));
    check(`stats ${y}: compared with ${y - 1}`, prev && prev.year === y - 1 && prev.points.some((p) => (p.count ?? p.value ?? 0) > 0), JSON.stringify(prev)?.slice(0, 200));
    const types = s.outcomes.map((o) => o.type);
    check('stats: released, died, transferred and euthanised all present', ['released', 'died', 'transferred', 'euthanized'].every((t) => types.includes(t)), types.join(', '));
    check('stats: species and diagnoses broken down', s.species.length >= 10 && s.conditions.length >= 8, `${s.species.length} species, ${s.conditions.length} diagnoses`);
    check('stats: both years selectable', s.intakeYears.includes(y) && s.intakeYears.includes(y - 1), s.intakeYears.join(', '));
    const m = clock.runDay.mo;
    const sm = await malte.get(`/api/federfall/stats?year=${y}&month=${m}`);
    check(`stats ${y}-${m}: this month compared with the same month last year`, sm.series?.previous?.points?.length > 0, JSON.stringify(sm.totals));
    const sp = s.sponsorships;
    if (live) {
      check('patronage totals: 7 on record, 6 running', sp.total === 7 && sp.active === 6, JSON.stringify(sp));
      // 15 €/month + 30 €/quarter + 120 €/year + 20 €/month + 5 €/month.
      check('patronage totals: 60,00 € a month, 50,00 € one-off', sp.monthlyCents === 6000 && sp.oneTimeCents === 5000, JSON.stringify(sp));
    }
    const loc = await malte.list('case_report_rows', f('city!=""'));
    const all = await malte.list('case_report_rows');
    check('intake map: find locations on nearly every case', loc.length >= all.length - 5, `${loc.length} of ${all.length}`);
  }

  // ── Who reads what ──────────────────────────────────────────────────────
  {
    const guest = await Api.user(DEMO_PEOPLE.guest.email, PASSWORD);
    const gc = await guest.get('/api/collections/cases/records?perPage=1').then((r) => r.totalItems, () => 0);
    const ga = await guest.get('/api/collections/animals/records?perPage=1').then((r) => r.totalItems, () => 0);
    check('guest: walled off (no cases, no animals)', gc === 0 && ga === 0, `${gc} cases, ${ga} animals`);
    const g = await su.one('users', people.guest.id);
    check('guest: is a pending guest (role guest, active)', g.role === 'guest' && g.is_active, `${g.role} ${g.is_active}`);

    const sees = async (api, collection, id) => api.one(collection, id).then(() => true, () => false);
    check('Tarek cannot open Lena\'s case (Kora)', !(await sees(tarek, 'cases', ids.cases.kora)));
    check('Tarek still reads Mika (read share), Lena reads Hinkebein\'s case', await sees(tarek, 'cases', ids.cases.mika) && await sees(lena, 'cases', ids.cases.hinkebein));
    const write = async (api, caseKey, animal) => api.create('weights', { org: seed.org.id, case: ids.cases[caseKey], animal: ids.animals[animal], weight_g: 100, measured_at: new Date().toISOString() })
      .then(() => true, () => false);
    check('Tarek cannot write on Mika any more (read-only after the handover)', !(await write(tarek, 'mika', 'mika')));
    check('Lena cannot write on Tarek\'s Tilda', !(await write(lena, 'tilda', 'tilda')));

    const spons = async (api) => (await api.list('sponsorships')).map((s) => s.id);
    const all = await spons(malte);
    check('coordinator reads every patronage (7)', all.length === 7, `${all.length}`);
    const lenaSees = await spons(lena);
    const lenaWant = [ids.sponsorships.petersen, ids.sponsorships.brockmann, ids.sponsorships.kita, ids.sponsorships.lorenz];
    check('Lena (keeper of the loft) reads exactly the loft\'s patronages', lenaSees.length === 4 && lenaWant.every((x) => lenaSees.includes(x)), `${lenaSees.length}`);
    const tarekSees = await spons(tarek);
    check('Tarek (Hinkebein\'s carer) reads no patronage', tarekSees.length === 0, `${tarekSees.length}`);
    check('Ole\'s patronage (bird released) is out of every keeper\'s reach', !lenaSees.includes(ids.sponsorships.albers));
  }

  // ── Vocabulary in both languages ────────────────────────────────────────
  for (const [collection, labels] of Object.entries(CODE_LISTS)) {
    const rows = await su.list(collection, f(`org="${seed.org.id}"`));
    const want = new Set(labels.map((l) => l[seed.locale]));
    const bad = rows.filter((r) => !want.has(r.label)).map((r) => r.label);
    check(`${collection}: every row in ${seed.locale}, every entry has de + en`, bad.length === 0 && labels.every((l) => l.de && l.en), bad.join(', '));
  }
  {
    const rows = await su.list('medication_products', f(`org="${seed.org.id}"`));
    const want = Object.values(PRODUCTS).map((p) => L(p.label)).sort();
    check(`drug catalogue in ${seed.locale}`, JSON.stringify(rows.map((r) => r.label).sort()) === JSON.stringify(want), rows.map((r) => r.label).join(', '));
    const avs = await su.list('aviaries', f(`org="${seed.org.id}"`));
    check(`aviaries named in ${seed.locale}`, Object.values(AVIARIES).every((a) => avs.some((x) => x.name === L(a.name))));
    const vacc = await su.list('vaccine_labels');
    check('vaccine vocabulary: two products, each with its target', vacc.length === 2 && vacc.every((v) => v.target));
  }

  // ── Volume and the audit log ────────────────────────────────────────────
  {
    const cases = await su.get(`/api/collections/cases/records?perPage=1&${f(`org="${seed.org.id}"`)}`);
    const open = await su.get(`/api/collections/cases/records?perPage=1&${f(`org="${seed.org.id}" && status!="disposed"`)}`);
    check('cases: last year and this year', cases.totalItems > 220, `${cases.totalItems} cases, ${open.totalItems} open`);
    check('open caseload is the showcase only', open.totalItems === 12, `${open.totalItems}`);
    const audit = await su.list('audit_events', f(`org="${seed.org.id}"`));
    const byKind = {};
    for (const a of audit) byKind[a.actor_kind] = (byKind[a.actor_kind] ?? 0) + 1;
    const byActor = {};
    for (const a of audit) byActor[a.actor_label] = (byActor[a.actor_label] ?? 0) + 1;
    check('audit log: the team did the work, not the superuser', (byKind.user ?? 0) > 10 * (byKind.superuser ?? 0) && Object.keys(byActor).length >= 4,
      `${JSON.stringify(byKind)} ${JSON.stringify(byActor)}`);
  }

  // ── Fingerprint ─────────────────────────────────────────────────────────
  const fingerprint = await fingerprintOf(su, seed);
  log(`fingerprint ${fingerprint}`);
  const failed = results.filter((r) => !r.ok);
  log(`${results.length - failed.length}/${results.length} checks passed`);
  return { results, failed, fingerprint };
}

/** A hash over what the dataset SAYS (no ids, no autodates): same run day, same hash. */
export async function fingerprintOf(su, seed) {
  const h = createHash('sha256');
  const org = `org="${seed.org.id}"`;
  const take = async (collection, fields, sort, filter = org) => {
    const rows = await su.list(collection, `${f(filter)}&sort=${sort}`);
    for (const r of rows) h.update(`${collection}|${fields.map((k) => JSON.stringify(r[k] ?? null)).join('|')}\n`);
    return rows.length;
  };
  const counts = {
    cases: await take('cases', ['case_number', 'admitted_at', 'status', 'age_class', 'find_location', 'intake_weight_g'], 'case_number'),
    animals: await take('animals', ['name', 'species', 'sex', 'lifetime_status'], 'species,name,lifetime_status'),
    dispositions: await take('dispositions', ['type', 'disposed_at', 'reason'], 'disposed_at,type', `case.org="${seed.org.id}"`),
    weights: await take('weights', ['measured_at', 'weight_g'], 'measured_at,weight_g'),
    administrations: await take('medication_administrations', ['administered_at', 'drug', 'dose'], 'administered_at,drug,dose'),
    sponsorships: await take('sponsorships', ['sponsor_name', 'amount_cents', 'interval', 'started_at', 'ended_at'], 'sponsor_name'),
    journal: await take('journal_entries', ['entry_at', 'text'], 'entry_at,text'),
  };
  h.update(JSON.stringify(counts));
  // The same dataset design in both languages: case numbers, dates, states
  // and outcomes must match between a de and an en seeding of the same day.
  const s = createHash('sha256');
  for (const r of await su.list('case_report_rows', `${f(org)}&sort=case_number`)) {
    s.update(`${r.case_number}|${r.admitted_at}|${r.status}|${r.outcome}|${r.ended_at}|${r.city}\n`);
  }
  return `${h.digest('hex').slice(0, 16)} structure ${s.digest('hex').slice(0, 16)} ${JSON.stringify(counts)}`;
}
