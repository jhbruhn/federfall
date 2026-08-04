/// <reference path="../pb_data/types.d.ts" />

// federfall-qt96.2 — the audit log's emitter. Every row in `audit_events`
// (1700000068) is written from here.
//
// Usage — `require()` INSIDE the handler, never at file level, and always with
// the `${__hooks}` absolute form (a relative path fails with "Invalid module"):
//
//   onRecordUpdateRequest((e) => {
//     const audit = require(`${__hooks}/lib_audit.js`);
//     const before = e.record.original().fieldsData();
//     e.next();                       // throws ⇒ nothing is logged
//     audit.emit(e, audit.ACTIONS.WEIGHT_UPDATED, {
//       record: e.record,
//       changes: audit.diff("weights", before, e.record.fieldsData()),
//     });
//   }, "weights");
//
// This file is NOT named *.pb.js, so PocketBase does not load it as a hook —
// it is only ever reachable through that require(). Unlike a hook file, a
// required module keeps its own file-level scope, which is why ACTIONS,
// SENSITIVE and the helpers below can live out here (verified on 0.39.8).
//
// ── Three properties this module must keep ───────────────────────────────────
//
// 1. STATELESS. PocketBase pools JSVMs and each pooled VM holds its own
//    instance of this module, so a module-level counter/dedup/cache diverges
//    under concurrency — measured on 0.39.8, not assumed. Anything that must be
//    consistent has to come from the database.
// 2. EMIT NEVER THROWS. A failed audit write must not turn a successful domain
//    write into a 500; the whole body is wrapped and failures go to the logger.
//    (Consequence, accepted: emit-after-`e.next()` cannot roll a write back. A
//    log that can break the app it observes is the worse failure mode.)
// 3. NO FINDER PII, EVER. A finder is a member of the public whose contact
//    details finder_retention.pb.js scrubs on a schedule; a copy of them sitting
//    in an append-only table nothing can delete would defeat that scrub with the
//    app's own audit trail. Finder subjects carry an empty label and their
//    identity/contact fields are redacted to the FACT of a change.

// ── Action registry — the single source of truth for valid action strings ────
//
// Wire values are `domain.verb` and are FROZEN once shipped: the app maps them
// to translated sentences, and `audit_events.action` is deliberately TEXT (not
// select) so an unlisted value can never throw inside a domain transaction.
// Nothing enforces this list at write time — the coverage test does
// (federfall-qt96.7). Adding an action is additive and ships as `feat:`; an
// older client renders an unknown one from the envelope alone.
const ACTIONS = {
  // ── cases and their timeline ───────────────────────────────────────────────
  CASE_INTAKE: "case.intake",
  // A case created straight through the collection API rather than the intake
  // route — the Admin UI, an import, an older client. Distinct from
  // case.intake, which means "a bird was admitted" as one human action.
  CASE_CREATED: "case.created",
  CASE_UPDATED: "case.updated",
  CASE_DELETED: "case.deleted",
  CASE_HANDOFF: "case.handoff",
  CASE_SHARED: "case.shared",
  CASE_SHARE_REVOKED: "case.share_revoked",

  ANIMAL_CREATED: "animal.created",
  ANIMAL_UPDATED: "animal.updated",
  ANIMAL_DELETED: "animal.deleted",
  ANIMAL_MERGED: "animal.merged",

  WEIGHT_CREATED: "weight.created",
  WEIGHT_UPDATED: "weight.updated",
  WEIGHT_DELETED: "weight.deleted",

  MARKING_CREATED: "marking.created",
  MARKING_UPDATED: "marking.updated",
  MARKING_DELETED: "marking.deleted",

  CONDITION_ADDED: "condition.added",
  CONDITION_UPDATED: "condition.updated",
  CONDITION_REMOVED: "condition.removed",

  MEDICATION_PRESCRIBED: "medication.prescribed",
  MEDICATION_UPDATED: "medication.updated",
  MEDICATION_DELETED: "medication.deleted",
  ADMINISTRATION_LOGGED: "administration.logged",
  ADMINISTRATION_UPDATED: "administration.updated",
  ADMINISTRATION_DELETED: "administration.deleted",

  JOURNAL_CREATED: "journal.created",
  JOURNAL_UPDATED: "journal.updated",
  JOURNAL_DELETED: "journal.deleted",

  PLACEMENT_CREATED: "placement.created",
  PLACEMENT_UPDATED: "placement.updated",
  PLACEMENT_DELETED: "placement.deleted",

  DISPOSITION_CREATED: "disposition.created",
  DISPOSITION_UPDATED: "disposition.updated",
  DISPOSITION_DELETED: "disposition.deleted",

  EXAM_SAVED: "exam.saved",
  EXAM_DELETED: "exam.deleted",
  // The findings of an exam normally ride along inside exam.saved (the route
  // writes them in one transaction). These cover a finding edited on its own
  // through the collection API, which the rules still allow.
  EXAM_FINDING_CREATED: "exam_finding.created",
  EXAM_FINDING_UPDATED: "exam_finding.updated",
  EXAM_FINDING_DELETED: "exam_finding.deleted",

  EGG_RECORD_CREATED: "egg_record.created",
  EGG_RECORD_UPDATED: "egg_record.updated",
  EGG_RECORD_DELETED: "egg_record.deleted",

  FOLLOW_UP_CREATED: "follow_up.created",
  FOLLOW_UP_UPDATED: "follow_up.updated",
  FOLLOW_UP_DELETED: "follow_up.deleted",

  VET_APPOINTMENT_CREATED: "vet_appointment.created",
  VET_APPOINTMENT_UPDATED: "vet_appointment.updated",
  VET_APPOINTMENT_DELETED: "vet_appointment.deleted",

  QUARANTINE_SET: "quarantine.set",
  QUARANTINE_UPDATED: "quarantine.updated",
  QUARANTINE_CLEARED: "quarantine.cleared",

  // ── housing ────────────────────────────────────────────────────────────────
  AVIARY_CREATED: "aviary.created",
  AVIARY_UPDATED: "aviary.updated",
  AVIARY_DELETED: "aviary.deleted",
  // No aviary_stay.* actions: the residency ledger is derived from
  // `animals.current_aviary` by aviary_stays.pb.js and has no API of its own.
  // The human action is the animal.updated that moved the bird.

  // ── finders (ids only — never names, see the header) ───────────────────────
  FINDER_CREATED: "finder.created",
  FINDER_UPDATED: "finder.updated",
  FINDER_DELETED: "finder.deleted",
  FINDER_PII_PURGED: "finder.pii_purged",
  FINDER_ORPHAN_DELETED: "finder.orphan_deleted",

  // ── people and org administration ──────────────────────────────────────────
  USER_INVITED: "user.invited",
  USER_UPDATED: "user.updated",
  USER_ROLE_CHANGED: "user.role_changed",
  USER_DEACTIVATED: "user.deactivated",
  USER_REACTIVATED: "user.reactivated",
  USER_DELETED: "user.deleted",
  ORG_SETTINGS_UPDATED: "org.settings_updated",

  // One action for every supervisor-managed code list (conditions,
  // admission_reasons, marking_types, medication_routes, medication_products);
  // `subject_collection` says which one, so the renderer stays generic.
  CODE_LIST_CREATED: "code_list.created",
  CODE_LIST_UPDATED: "code_list.updated",
  CODE_LIST_DELETED: "code_list.deleted",

  // ── authentication and access (severity: security) ─────────────────────────
  AUTH_LOGIN: "auth.login",
  AUTH_OAUTH2_LOGIN: "auth.oauth2_login",
  AUTH_LOGIN_FAILED: "auth.login_failed",
  // No auth.login_blocked: PocketBase's rate limiter answers 429 from
  // middleware, before any hook runs, so there is nothing to observe. It would
  // also arrive unauthenticated and therefore with no org to file it under.
  AUTH_PASSWORD_RESET: "auth.password_reset",
  AUTH_PASSWORD_CHANGED: "auth.password_changed",
  AUTH_MFA_ENABLED: "auth.mfa_enabled",
  AUTH_MFA_DISABLED: "auth.mfa_disabled",

  // ── data leaving the system ────────────────────────────────────────────────
  REPORT_EXPORTED: "report.exported",
  CASE_REPORT_PRINTED: "case_report.printed",
  // gdpr.export belongs here too, but the Datenauskunft it would describe does
  // not exist yet (federfall-qocb). It ships with that feature — an action
  // nothing can emit is an unused enum value and an untranslatable string.

  // ── system paths (no human actor) ──────────────────────────────────────────
  OAUTH2_USER_PROVISIONED: "oauth2.user_provisioned",
  SUPERVISOR_BOOTSTRAPPED: "supervisor.bootstrapped",
  AUDIT_PURGED: "audit.purged",
};

const ACTION_LIST = Object.keys(ACTIONS).map((k) => ACTIONS[k]);

const SEVERITY = { INFO: "info", NOTICE: "notice", SECURITY: "security" };
const ACTOR = { USER: "user", SYSTEM: "system", CRON: "cron", SUPERUSER: "superuser" };

// What a supervisor should be able to filter for without knowing every action
// by name: "security" is who can get in and who can see what, "notice" is
// destructive or irreversible, everything else is the day's work. Set here
// rather than at each call site so the same action cannot arrive at two
// different severities depending on which emitter fired it.
const DEFAULT_SEVERITY = {
  "auth.login": SEVERITY.SECURITY,
  "auth.oauth2_login": SEVERITY.SECURITY,
  "auth.login_failed": SEVERITY.SECURITY,
  "auth.password_reset": SEVERITY.SECURITY,
  "auth.password_changed": SEVERITY.SECURITY,
  "auth.mfa_enabled": SEVERITY.SECURITY,
  "auth.mfa_disabled": SEVERITY.SECURITY,
  "user.invited": SEVERITY.SECURITY,
  "user.role_changed": SEVERITY.SECURITY,
  "user.deactivated": SEVERITY.SECURITY,
  "user.reactivated": SEVERITY.SECURITY,
  "user.deleted": SEVERITY.SECURITY,
  "user.updated": SEVERITY.NOTICE,
  "case.shared": SEVERITY.SECURITY,
  "case.share_revoked": SEVERITY.SECURITY,
  "oauth2.user_provisioned": SEVERITY.SECURITY,
  "supervisor.bootstrapped": SEVERITY.SECURITY,
  "org.settings_updated": SEVERITY.NOTICE,
  "animal.merged": SEVERITY.NOTICE,
  "animal.deleted": SEVERITY.NOTICE,
  "case.deleted": SEVERITY.NOTICE,
  "finder.pii_purged": SEVERITY.NOTICE,
  "finder.orphan_deleted": SEVERITY.NOTICE,
  "audit.purged": SEVERITY.NOTICE,
  "report.exported": SEVERITY.NOTICE,
  "case_report.printed": SEVERITY.NOTICE,
};

// ── Redaction ────────────────────────────────────────────────────────────────
//
// Emitters see raw request bodies, so this is the last place a credential or a
// finder's phone number can be stopped before it lands in a table with no
// delete path. A redacted change keeps the FACT ({field, redacted: true}) and
// drops both values: "someone changed this finder's phone number" is the useful
// part, and it is the part that is not personal data.
//
// `finders` MUST stay in step with finder_retention.pb.js's PII_FIELDS — the
// rule is that anything the GDPR scrub erases can never be in the log, while
// what the scrub deliberately keeps (the location: address/postal_code/city/
// region, non-identifying "where do birds come from" data) may be.
const SENSITIVE = {
  users: ["password", "passwordConfirm", "oldPassword", "tokenKey"],
  _superusers: ["password", "passwordConfirm", "oldPassword", "tokenKey"],
  finders: [
    "first_name",
    "last_name",
    "organisation",
    "phone",
    "alt_phone",
    "email",
    "notes",
  ],
};

// Fields that change on every write and say nothing about intent. Credentials
// are deliberately NOT here: "this account's password changed" is exactly the
// kind of thing a supervisor needs to see. SENSITIVE strips the values; leaving
// the fields out entirely would strip the signal too.
// PocketBase's own auth bookkeeping stamps (a reset mail was sent, a login
// alert went out) are internal side effects, not something a person did.
const IGNORED_FIELDS = [
  "updated",
  "created",
  "lastResetSentAt",
  "lastVerificationSentAt",
  "lastLoginAlertSentAt",
];

// Long free text (a 2000-char notes field) would bloat a row that can never be
// deleted, and `changes` has a maxSize. What matters is THAT the text changed.
const MAX_VALUE_CHARS = 500;

function isSensitive(collection, field) {
  const list = SENSITIVE[collection];
  return !!list && list.indexOf(field) !== -1;
}

function normalize(v) {
  if (v === null || v === undefined) return "";
  if (typeof v !== "object") return v;

  let json;
  try {
    json = JSON.stringify(v);
  } catch (_) {
    return String(v);
  }
  if (json === undefined) return String(v);
  // A Go value that marshals to a JSON SCALAR reaches JS as an object —
  // types.DateTime is the everyday case, and record.get() hands one back for
  // every date field. Stringifying it keeps the quotes, so the row would store
  // '"2026-06-20 07:30:00.000Z"' (unparseable as a date on the way out) and an
  // unset date would store '""' rather than being recognised as empty. Unwrap
  // it back to the plain value. Note fieldsData() does NOT do this — it yields
  // plain JS — which is why only the create/delete path hit it.
  if (json.length >= 2 && json[0] === '"' && json[json.length - 1] === '"') {
    try {
      return JSON.parse(json);
    } catch (_) {
      return json;
    }
  }
  return json;
}

function clamp(v) {
  if (typeof v === "string" && v.length > MAX_VALUE_CHARS) {
    return { value: v.slice(0, MAX_VALUE_CHARS), truncated: true };
  }
  return { value: v, truncated: false };
}

// [{field, from, to}] for a plain-object before/after pair — typically
// `record.original().fieldsData()` and `record.fieldsData()`. Sensitive fields
// collapse to {field, redacted: true}.
function diff(collection, before, after) {
  const out = [];
  const b = before || {};
  const a = after || {};
  const names = {};
  for (const k in b) names[k] = true;
  for (const k in a) names[k] = true;

  for (const field in names) {
    if (IGNORED_FIELDS.indexOf(field) !== -1) continue;
    const from = normalize(b[field]);
    const to = normalize(a[field]);
    if (String(from) === String(to)) continue;

    if (isSensitive(collection, field)) {
      out.push({ field: field, redacted: true });
      continue;
    }
    const cf = clamp(from);
    const ct = clamp(to);
    const entry = { field: field, from: cf.value, to: ct.value };
    if (cf.truncated || ct.truncated) entry.truncated = true;
    out.push(entry);
  }
  return out;
}

// ── The audited surface ──────────────────────────────────────────────────────
//
// Which collection-API write becomes which action. audit_domain.pb.js registers
// one generic request hook per verb over the keys of this map, so ADDING A
// COLLECTION HERE IS ALL IT TAKES to audit it — there is no per-collection
// handler to write. That indirection is not cosmetic: a hook handler runs in an
// isolated JSVM context where file-level bindings are out of scope, so a
// per-collection table could not be read from inside the handler at all. A
// required module can, which is why this map lives here and not there.
//
// A `null` verb means "not reachable/meaningful through the collection API" —
// e.g. a finder is never deleted by a person, only by the retention cron, which
// emits finder.orphan_deleted itself.
const COLLECTION_ACTIONS = {
  // ── the case and its timeline ──────────────────────────────────────────────
  cases: {
    created: ACTIONS.CASE_CREATED,
    updated: ACTIONS.CASE_UPDATED,
    deleted: ACTIONS.CASE_DELETED,
  },
  animals: {
    created: ACTIONS.ANIMAL_CREATED,
    updated: ACTIONS.ANIMAL_UPDATED,
    deleted: ACTIONS.ANIMAL_DELETED,
  },
  weights: {
    created: ACTIONS.WEIGHT_CREATED,
    updated: ACTIONS.WEIGHT_UPDATED,
    deleted: ACTIONS.WEIGHT_DELETED,
  },
  markings: {
    created: ACTIONS.MARKING_CREATED,
    updated: ACTIONS.MARKING_UPDATED,
    deleted: ACTIONS.MARKING_DELETED,
  },
  case_conditions: {
    created: ACTIONS.CONDITION_ADDED,
    updated: ACTIONS.CONDITION_UPDATED,
    deleted: ACTIONS.CONDITION_REMOVED,
  },
  medications: {
    created: ACTIONS.MEDICATION_PRESCRIBED,
    updated: ACTIONS.MEDICATION_UPDATED,
    deleted: ACTIONS.MEDICATION_DELETED,
  },
  medication_administrations: {
    created: ACTIONS.ADMINISTRATION_LOGGED,
    updated: ACTIONS.ADMINISTRATION_UPDATED,
    deleted: ACTIONS.ADMINISTRATION_DELETED,
  },
  journal_entries: {
    created: ACTIONS.JOURNAL_CREATED,
    updated: ACTIONS.JOURNAL_UPDATED,
    deleted: ACTIONS.JOURNAL_DELETED,
  },
  // `created` is refined to case.handoff when the placement names a to_user —
  // see refine() below.
  placements: {
    created: ACTIONS.PLACEMENT_CREATED,
    updated: ACTIONS.PLACEMENT_UPDATED,
    deleted: ACTIONS.PLACEMENT_DELETED,
  },
  dispositions: {
    created: ACTIONS.DISPOSITION_CREATED,
    updated: ACTIONS.DISPOSITION_UPDATED,
    deleted: ACTIONS.DISPOSITION_DELETED,
  },
  exams: {
    created: ACTIONS.EXAM_SAVED,
    updated: ACTIONS.EXAM_SAVED,
    deleted: ACTIONS.EXAM_DELETED,
  },
  // The exam route writes findings inside its own transaction, so these fire
  // only for a finding edited directly through the collection API.
  exam_findings: {
    created: ACTIONS.EXAM_FINDING_CREATED,
    updated: ACTIONS.EXAM_FINDING_UPDATED,
    deleted: ACTIONS.EXAM_FINDING_DELETED,
  },
  egg_records: {
    created: ACTIONS.EGG_RECORD_CREATED,
    updated: ACTIONS.EGG_RECORD_UPDATED,
    deleted: ACTIONS.EGG_RECORD_DELETED,
  },
  follow_ups: {
    created: ACTIONS.FOLLOW_UP_CREATED,
    updated: ACTIONS.FOLLOW_UP_UPDATED,
    deleted: ACTIONS.FOLLOW_UP_DELETED,
  },
  vet_appointments: {
    created: ACTIONS.VET_APPOINTMENT_CREATED,
    updated: ACTIONS.VET_APPOINTMENT_UPDATED,
    deleted: ACTIONS.VET_APPOINTMENT_DELETED,
  },
  quarantine_records: {
    created: ACTIONS.QUARANTINE_SET,
    updated: ACTIONS.QUARANTINE_UPDATED,
    deleted: ACTIONS.QUARANTINE_CLEARED,
  },

  // ── housing ────────────────────────────────────────────────────────────────
  aviaries: {
    created: ACTIONS.AVIARY_CREATED,
    updated: ACTIONS.AVIARY_UPDATED,
    deleted: ACTIONS.AVIARY_DELETED,
  },
  // NOT aviary_stays: superuser-only by rule and written exclusively by
  // aviary_stays.pb.js from `animals.current_aviary`, so the only caller a
  // request hook here could ever see is a superuser in the PocketBase
  // dashboard. Decided against (federfall-by7w.6): that event would sit beside
  // the animal.updated that caused the same move and read as a duplicate of
  // it. Moving a bird is audited as the animal.updated it is.

  // ── people and access (federfall-qt96.5) ───────────────────────────────────
  // `updated` is refined below into role_changed / deactivated / mfa_*: those
  // are the reasons anyone reads a user's history, and burying them in a
  // generic user.updated would make the log technically complete and useless.
  users: {
    created: ACTIONS.USER_INVITED,
    updated: ACTIONS.USER_UPDATED,
    deleted: ACTIONS.USER_DELETED,
  },
  // A share is who else can see a case — the closest thing this app has to a
  // permission grant. The share-on-handoff that main.pb.js creates is NOT
  // here: it saves through the model layer, so no request hook fires, and it
  // is already part of the case.handoff that caused it.
  case_shares: {
    created: ACTIONS.CASE_SHARED,
    updated: ACTIONS.CASE_SHARED,
    deleted: ACTIONS.CASE_SHARE_REVOKED,
  },

  // ── the organisation itself ────────────────────────────────────────────────
  // Create/delete are superuser-only; what a supervisor can do is change the
  // settings — retention windows, quarantine defaults, audit_log_client_info —
  // which is exactly the kind of change that should leave a trace.
  organisations: {
    created: null,
    updated: ACTIONS.ORG_SETTINGS_UPDATED,
    deleted: null,
  },

  // ── finders: ids only, never names (see the header) ────────────────────────
  finders: {
    created: ACTIONS.FINDER_CREATED,
    updated: ACTIONS.FINDER_UPDATED,
    deleted: ACTIONS.FINDER_DELETED,
  },

  // ── supervisor-managed code lists ──────────────────────────────────────────
  // One action for all of them; `subject_collection` says which list, so the
  // renderer needs one case instead of five.
  conditions: {
    created: ACTIONS.CODE_LIST_CREATED,
    updated: ACTIONS.CODE_LIST_UPDATED,
    deleted: ACTIONS.CODE_LIST_DELETED,
  },
  admission_reasons: {
    created: ACTIONS.CODE_LIST_CREATED,
    updated: ACTIONS.CODE_LIST_UPDATED,
    deleted: ACTIONS.CODE_LIST_DELETED,
  },
  marking_types: {
    created: ACTIONS.CODE_LIST_CREATED,
    updated: ACTIONS.CODE_LIST_UPDATED,
    deleted: ACTIONS.CODE_LIST_DELETED,
  },
  medication_routes: {
    created: ACTIONS.CODE_LIST_CREATED,
    updated: ACTIONS.CODE_LIST_UPDATED,
    deleted: ACTIONS.CODE_LIST_DELETED,
  },
  medication_products: {
    created: ACTIONS.CODE_LIST_CREATED,
    updated: ACTIONS.CODE_LIST_UPDATED,
    deleted: ACTIONS.CODE_LIST_DELETED,
  },
};

// What a row of each collection is CALLED, for `subject_label`. First non-empty
// field wins.
//
// A label must be NEUTRAL — a name, a number, a code, or a string a user typed
// into a code list. Never a translated phrase: the log is read in German and in
// English, and a label is stored verbatim, so a German word written here would
// be frozen in the row forever. Anything enum-shaped (a disposition type, an
// exam finding's body system) therefore has no label at all and travels as a
// wire value in `changes`/`detail`, where the app translates it.
//
// Absent means the envelope carries no label, which the design requires the app
// to survive anyway. Two collections are absent ON PURPOSE, not by oversight:
//
//   finders          — additionally forced to "" in emit(). A member of the
//                      public is never named in this table.
//   journal_entries  — a journal entry is free clinical text its author can
//                      edit or delete. Copying it into an append-only table
//                      would quietly make it permanent, and it is the one
//                      field most likely to mention a person in passing. The
//                      row says who wrote a note on which case; the note stays
//                      where it can still be corrected.
const LABEL_FIELDS = {
  cases: ["case_number"],
  animals: ["name", "species"],
  aviaries: ["name"],
  users: ["name", "email"],
  markings: ["code"],
  medications: ["drug"],
  // The drug is denormalized onto the administration, so no lookup is needed.
  medication_administrations: ["drug"],
  vet_appointments: ["vet"],
  organisations: ["name"],
  conditions: ["label"],
  admission_reasons: ["label"],
  marking_types: ["label"],
  medication_routes: ["label"],
  medication_products: ["name", "label"],
};

// Labels that have to be READ FROM ANOTHER RECORD: `{field: collection}`, tried
// in order after LABEL_FIELDS comes up empty, and labelled by that record's own
// LABEL_FIELDS entry.
//
// These are relations into user-managed code lists and rosters, where the id is
// meaningless in a log and the target can be renamed or deleted later — so the
// label has to be snapshotted at emit time like every other label here. It
// costs one indexed read per emit, on write paths that already do several.
const LABEL_RELATIONS = {
  case_conditions: { condition: "conditions" },
  case_shares: { shared_with: "users" },
  // Where the bird went, or who took it on.
  placements: { to_user: "users", aviary: "aviaries" },
  // Only reached when a marking carries no code of its own (an unnumbered
  // marking still says what KIND it was).
  markings: { type: "marking_types" },
  // A journal entry is dual-parent (case XOR aviary, 1700000053). The
  // case-scoped one is named by its case number; the AVIARY-scoped one belongs
  // to no case and would otherwise say nothing whatsoever — caught by the
  // uninformative-event check in test_rules.py. Naming the aviary is not
  // naming the text, so nothing about the entry's prose is recorded.
  journal_entries: { aviary: "aviaries" },
};

// Values that are a measurement rather than a name. Kept out of LABEL_FIELDS
// because they need a unit to mean anything, and the unit must be neutral.
const LABEL_QUANTITIES = {
  weights: { field: "weight_g", suffix: " g" },
};

// What a CREATE wrote, and what a DELETE destroyed (federfall-by7w / 9k2g).
//
// An update explains itself — a diff of what moved is inherently bounded. A
// create and a delete had nothing at all until now, so "Ausgang erfasst" never
// said whether the bird was released or died, which is the single most
// consequential fact this app records. A delete is worse: afterwards the row
// is gone and this is the only description of it that survives.
//
// An ALLOWLIST rather than the whole record, for three reasons: dumping every
// column would put relation ids and long free text into a table with no delete
// path; `changes` has a size limit; and a row nobody can read is not better
// than an empty one. So: the two or three fields that say what happened.
//
// Fields that ARE the subject label are left out — the label already shows the
// weight and the drug, and printing them twice in one line is noise.
//
// Empty by DESIGN, not omission:
//   journal_entries  — the text; see LABEL_FIELDS. The row records that a note
//                      was written on a case, never the note.
//   finders          — nothing, ever.
//   organisations    — settings is one json blob; the update diff covers it and
//                      a create/delete cannot happen through the API anyway.
const CONTENT_FIELDS = {
  cases: ["admitted_at", "age_class", "status"],
  animals: ["species", "name", "sex"],
  weights: ["measured_at"],
  markings: ["applied_at", "removed_at", "is_active"],
  case_conditions: ["certainty", "onset_date", "resolved_date"],
  medications: [
    "dose_rate",
    "dose_unit",
    "frequency_kind",
    "interval_hours",
    "started_at",
    "ended_at",
  ],
  medication_administrations: ["dose", "dose_unit", "administered_at"],
  placements: ["moved_in_at", "where_holding"],
  // `type` is the one that matters: released, died, euthanised, transferred.
  dispositions: ["type", "disposed_at", "release_type", "transfer_type"],
  exams: ["examined_at", "body_condition", "hydration", "mentation"],
  exam_findings: ["system", "status"],
  egg_records: ["count", "laid_at", "fate"],
  follow_ups: ["due_at", "done_at"],
  vet_appointments: ["starts_at", "attended_at", "cancelled_at"],
  quarantine_records: ["set_at", "quarantine_until"],
  aviaries: ["capacity", "active"],
  // case_shares: nothing — refine() already puts who and what access in detail.
  users: ["role", "is_active"],
  conditions: ["label", "active"],
  admission_reasons: ["label", "active"],
  marking_types: ["label", "active"],
  medication_routes: ["label", "active"],
  medication_products: ["active"],
  journal_entries: [],
  finders: [],
  organisations: [],
};

// Ids worth correlating on beyond `case_id`, when the record carries them.
const REF_FIELDS = ["animal", "aviary", "to_user", "from_user", "shared_with"];

/**
 * The allowlisted content of [record] as change entries.
 *
 * @param created true for a create (values land in `to`), false for a delete
 *                (they land in `from`, which is what "cleared (was X)" reads
 *                as — the right sentence for something that no longer exists).
 */
function contentOf(collection, record, created) {
  const out = [];
  for (const field of CONTENT_FIELDS[collection] || []) {
    let value;
    try {
      value = normalize(record.get(field));
    } catch (_) {
      continue; // not a field on this collection
    }
    // An unset field is not content. `false` and `0` are, so this cannot be a
    // truthiness test: "quarantine lifted" and "capacity 0" both matter.
    if (value === "" || value === null || value === undefined) continue;

    if (isSensitive(collection, field)) {
      out.push({ field: field, redacted: true });
      continue;
    }
    const c = clamp(value);
    const entry = created
      ? { field: field, to: c.value }
      : { field: field, from: c.value };
    if (c.truncated) entry.truncated = true;
    out.push(entry);
  }
  return out;
}

/**
 * What to call this record in the log.
 *
 * @param app resolves LABEL_RELATIONS. Omit it and only the record's own fields
 *            are consulted — callers outside a hook (or looking at a
 *            collection with no relation labels) lose nothing.
 */
function subjectLabel(record, app) {
  try {
    const name = String(record.collection().name);
    if (name === "finders") return "";

    for (const f of LABEL_FIELDS[name] || []) {
      const v = String(record.get(f) || "").trim();
      if (v) return v.slice(0, 200);
    }

    const quantity = LABEL_QUANTITIES[name];
    if (quantity) {
      const v = record.get(quantity.field);
      if (v !== null && v !== undefined && String(v) !== "" && Number(v) !== 0) {
        return String(v) + quantity.suffix;
      }
    }

    const relations = LABEL_RELATIONS[name];
    if (relations && app) {
      for (const field in relations) {
        const id = String(record.get(field) || "").trim();
        if (!id) continue;
        try {
          const target = app.findRecordById(relations[field], id);
          // One level only: the target's own label fields, never its relations.
          for (const f of LABEL_FIELDS[relations[field]] || []) {
            const v = String(target.get(f) || "").trim();
            if (v) return v.slice(0, 200);
          }
        } catch (_) {
          // Target gone or unreadable — try the next relation.
        }
      }
    }
  } catch (_) {
    // Unknown shape — no label.
  }
  return "";
}

function refsFor(record) {
  const refs = {};
  let any = false;
  for (const f of REF_FIELDS) {
    try {
      const v = String(record.get(f) || "");
      if (v) {
        refs[f] = v;
        any = true;
      }
    } catch (_) {
      // Field not on this collection.
    }
  }
  return any ? refs : null;
}

// The few places where the verb alone is too coarse to be worth reading.
// Derived side effects are folded in here rather than emitted as their own
// events: a handoff's share-on-handoff and carer change are consequences of one
// human action, not three things that happened.
function refine(collection, verb, record, changes, hints) {
  // One update can flip several of these at once; the FIRST match wins, so the
  // order here is the priority order — the row is still filed under the most
  // consequential thing that happened, and `changes` carries the rest.
  if (collection === "users" && verb === "updated") {
    const by = {};
    for (const c of changes || []) by[c.field] = c;
    if (by.role) {
      return {
        action: ACTIONS.USER_ROLE_CHANGED,
        detail: { from: by.role.from, to: by.role.to },
      };
    }
    if (by.is_active) {
      return {
        action: by.is_active.to
          ? ACTIONS.USER_REACTIVATED
          : ACTIONS.USER_DEACTIVATED,
        detail: null,
      };
    }
    if (by.mfa_enabled) {
      return {
        action: by.mfa_enabled.to
          ? ACTIONS.AUTH_MFA_ENABLED
          : ACTIONS.AUTH_MFA_DISABLED,
        detail: null,
      };
    }
    // A password change is invisible in the record: PocketBase keeps the hash
    // out of fieldsData(), so all a diff sees is the tokenKey it rotated — and
    // an email change rotates that too. The request body is the honest signal
    // of what was asked for, and the save has already succeeded by the time
    // this runs, so it is also the signal of what happened.
    if (hints && (hints.bodyKeys || []).indexOf("password") !== -1) {
      return { action: ACTIONS.AUTH_PASSWORD_CHANGED, detail: null };
    }
  }
  if (collection === "case_shares" && (verb === "created" || verb === "deleted")) {
    return {
      action:
        verb === "created" ? ACTIONS.CASE_SHARED : ACTIONS.CASE_SHARE_REVOKED,
      detail: {
        with: String(record.getString("shared_with") || ""),
        access: String(record.getString("access") || ""),
      },
    };
  }
  if (collection === "placements" && verb === "created") {
    const to = String(record.getString("to_user") || "");
    if (to) {
      return {
        action: ACTIONS.CASE_HANDOFF,
        detail: {
          from: String(record.getString("from_user") || ""),
          to: to,
          // main.pb.js moves cases.active_carer and leaves the previous carer a
          // read share, both inside this same request.
          carer_moved: true,
        },
      };
    }
  }
  return null;
}

/**
 * The whole Tier A body: turn one collection-API write into one audit row.
 * Called from audit_domain.pb.js AFTER e.next(), so a rejected save logs
 * nothing.
 *
 * @param verb   "created" | "updated" | "deleted"
 * @param before for "updated" only, e.record.original().fieldsData() captured
 *               BEFORE e.next().
 */
function emitRecordChange(e, verb, before, hints) {
  try {
    const record = e.record;
    const collection = String(record.collection().name);
    const spec = COLLECTION_ACTIONS[collection];
    if (!spec) return; // not an audited collection
    let action = spec[verb];
    if (!action) return; // this verb is covered elsewhere (or cannot happen)

    let changes = null;
    if (verb === "created" || verb === "deleted") {
      // Same shape as an update, so one renderer handles all three: a create
      // reads "set to X" and a delete "cleared (was X)" with no new strings.
      changes = contentOf(collection, record, verb === "created");
    }
    if (verb === "updated") {
      changes = diff(collection, before, record.fieldsData());
      // A changed password shows up only as the tokenKey PocketBase rotated
      // with it (the hash is not in fieldsData). Name the field that actually
      // changed — redacted, like every other credential — so the line reads as
      // what happened rather than as an internal key rotation.
      if (
        hints &&
        (hints.bodyKeys || []).indexOf("password") !== -1 &&
        !changes.some((c) => c.field === "password")
      ) {
        changes.push({ field: "password", redacted: true });
      }
      // Nothing actually changed (a no-op PATCH, or only autodates moved).
      if (!changes.length) return;
    }

    let detail = null;
    const refined = refine(collection, verb, record, changes, hints);
    if (refined) {
      action = refined.action;
      detail = refined.detail;
    }

    emit(e, action, {
      record: record,
      subject: {
        collection: collection,
        id: record.id,
        label: subjectLabel(record, e.app),
      },
      refs: refsFor(record),
      changes: changes,
      detail: detail,
    });
  } catch (err) {
    $app
      .logger()
      .warn("audit: record change not recorded", "verb", String(verb), "err", String(err));
  }
}

// One id per HTTP request, so the rows a single action produced can be read
// back together. The router event carries a per-request store; anything without
// one (a cron tick, a model-only hook) gets a fresh id, which is correct — it
// IS its own unit of work.
function requestId(e) {
  try {
    if (e && typeof e.get === "function") {
      const existing = e.get("auditRequestId");
      if (existing) return String(existing);
      const fresh = $security.randomString(15);
      e.set("auditRequestId", fresh);
      return fresh;
    }
  } catch (_) {
    // No store on this event kind — fall through.
  }
  try {
    return $security.randomString(15);
  } catch (_) {
    return "";
  }
}

// Whether this org opted into storing client IP / user agent. Personal data
// about staff, so it is off unless asked for. Re-read per emit: caching it
// would be module state, which is per-VM and therefore a lie (see the header).
function wantsClientInfo(app, orgId) {
  try {
    const org = app.findRecordById("organisations", orgId);
    // get() on a json field returns BYTES in the JSVM, not an object — the
    // property read would silently be undefined. See federfall-jumi.
    const settings = JSON.parse(org.getString("settings") || "{}");
    return settings.audit_log_client_info === true;
  } catch (_) {
    return false;
  }
}

/**
 * Append one event to the audit log. Never throws.
 *
 * @param e     the hook event (RequestEvent-ish) the action happened in, or
 *              null for a cron/system path. `e.auth` is what makes an actor
 *              resolvable — model-only RecordEvents have none, which is why
 *              Tier A emitters hang off the *Request hooks.
 * @param action one of ACTIONS.
 * @param opts  {app, org, subject:{collection,id,label}, record, caseId, refs,
 *               changes, detail, severity, actorKind}
 *              `app` must be the transaction app when emitting from inside a
 *              route's runInTransaction, so the event commits with the writes
 *              it describes. `record` is a shorthand for `subject` and also
 *              supplies org/case_id when they are not given explicitly.
 */
function emit(e, action, opts) {
  const o = opts || {};
  try {
    const app = o.app || (e && e.app) || $app;

    // ── actor ────────────────────────────────────────────────────────────────
    let actorId = "";
    let actorLabel = "";
    let actorRole = "";
    let actorKind = o.actorKind || "";
    let authOrg = "";

    let auth = null;
    if (!actorKind) {
      try {
        // opts.actor is for the auth hooks: during a login the caller is not
        // authenticated yet, so e.auth is empty and the acting user has to be
        // handed in explicitly.
        auth = o.actor || (e ? e.auth : null);
      } catch (_) {
        auth = o.actor || null;
      }
    }
    if (auth) {
      actorId = String(auth.id || "");
      let collName = "";
      try {
        collName = String(auth.collection().name);
      } catch (_) {
        collName = "";
      }
      if (collName === "_superusers") {
        // The dashboard operator. No org of their own — the subject supplies it.
        actorKind = ACTOR.SUPERUSER;
        actorLabel = auth.getString("email");
      } else {
        actorKind = ACTOR.USER;
        actorLabel = auth.getString("name") || auth.getString("email");
        actorRole = auth.getString("role");
        authOrg = auth.getString("org");
      }
    } else if (!actorKind) {
      actorKind = ACTOR.SYSTEM;
    }

    // ── subject ──────────────────────────────────────────────────────────────
    const rec = o.record || null;
    const subject = o.subject || {};
    let subjectCollection = String(subject.collection || "");
    let subjectId = String(subject.id || "");
    let subjectLabel = subject.label === undefined ? "" : String(subject.label);
    if (rec) {
      if (!subjectId) subjectId = String(rec.id || "");
      if (!subjectCollection) {
        try {
          subjectCollection = String(rec.collection().name);
        } catch (_) {
          subjectCollection = "";
        }
      }
    }
    // Hard rule, enforced here rather than trusted to every call site: a finder
    // is never named in the log.
    if (subjectCollection === "finders") subjectLabel = "";

    // ── org: the scoping boundary, and the one field with no fallback ────────
    let org = String(o.org || "") || authOrg;
    if (!org && rec) {
      try {
        org = rec.getString("org");
      } catch (_) {
        org = "";
      }
    }
    // An organisation has no `org` field — it IS one. Without this, a superuser
    // editing org settings from the dashboard would fall through to the "no org"
    // branch below and go unlogged, which is the opposite of who most needs
    // logging (a supervisor's own edit resolves via their auth record).
    if (!org && subjectCollection === "organisations") org = subjectId;
    if (!org) {
      // Refusing to guess: a row in the wrong org is visible to the wrong
      // supervisors. A superuser acting outside any org, or a failed login for
      // an unknown email, legitimately lands here.
      $app
        .logger()
        .warn("audit: no org, event not recorded", "action", String(action));
      return;
    }

    // ── case correlation ─────────────────────────────────────────────────────
    let caseId = String(o.caseId || "");
    if (!caseId && subjectCollection === "cases") caseId = subjectId;
    if (!caseId && rec) {
      try {
        caseId = rec.getString("case");
      } catch (_) {
        caseId = "";
      }
    }

    // The case NUMBER, snapshotted like every other label here (federfall-
    // by7w.2). Free when the subject IS the case; otherwise one indexed read,
    // and only for rows that belong to a case at all.
    let caseLabel = String(o.caseLabel || "");
    if (!caseLabel && caseId) {
      if (subjectCollection === "cases" && subjectLabel) {
        caseLabel = subjectLabel;
      } else {
        try {
          caseLabel = app.findRecordById("cases", caseId).getString("case_number");
        } catch (_) {
          // Case already gone — the id still correlates the rows.
        }
      }
    }

    const row = new Record(app.findCollectionByNameOrId("audit_events"));
    row.set("org", org);
    row.set("action", String(action));
    row.set("actor_id", actorId);
    row.set("actor_label", actorLabel);
    row.set("actor_role", actorRole);
    row.set("actor_kind", actorKind);
    row.set("subject_collection", subjectCollection);
    row.set("subject_id", subjectId);
    row.set("subject_label", subjectLabel);
    row.set("case_id", caseId);
    row.set("case_label", caseLabel);
    if (o.refs) row.set("refs", o.refs);
    if (o.changes && o.changes.length) row.set("changes", o.changes);
    if (o.detail) row.set("detail", o.detail);
    row.set(
      "severity",
      o.severity || DEFAULT_SEVERITY[String(action)] || SEVERITY.INFO,
    );
    row.set("request_id", requestId(e));

    if (e && wantsClientInfo(app, org)) {
      try {
        row.set("ip", String(e.realIP() || ""));
      } catch (_) {
        // Not a request event.
      }
      try {
        const headers = e.requestInfo().headers || {};
        row.set("user_agent", String(headers.user_agent || "").slice(0, 512));
      } catch (_) {
        // Not a request event.
      }
    }

    app.save(row);
  } catch (err) {
    // Property 2 in the header: the log never breaks the thing it observes.
    $app
      .logger()
      .warn(
        "audit: emit failed",
        "action",
        String(action),
        "err",
        String(err),
      );
  }
}

/**
 * A failed password login, collapsed to AT MOST ONE ROW per user per
 * five-minute wall-clock bucket. Never throws.
 *
 * Someone hammering a login form must not be able to fill a table that has no
 * delete path — but the honest alternative, a counter on one row, would need an
 * UPDATE, which the append-only guard forbids absolutely, and module state
 * cannot hold the count either (per-JSVM, divergent under concurrency). So the
 * row means "at least one failure in this window", which is what a supervisor
 * acts on anyway; `detail.window_minutes` says so explicitly rather than
 * letting anyone read it as an exact count.
 *
 * The bucket is a floored wall-clock slot, not "the last five minutes", so two
 * concurrent requests agree on which window they are in without coordinating.
 *
 * @param record the user the identity resolved to. An unknown email has no
 *               user and therefore no org — it goes to the logger only, since
 *               an unauthenticated caller must never be able to write a row
 *               into some organisation's table by guessing addresses.
 */
function emitLoginFailed(e, record, detail) {
  try {
    if (!record) {
      $app.logger().info("audit: failed login for an unknown identity");
      return;
    }
    const BUCKET_MINUTES = 5;
    const slotMs = BUCKET_MINUTES * 60 * 1000;
    const start = new Date(Math.floor(new Date().getTime() / slotMs) * slotMs);
    // PocketBase compares datetimes as "YYYY-MM-DD HH:MM:SS.sssZ" strings.
    const since = start.toISOString().replace("T", " ");

    const existing = $app.findRecordsByFilter(
      "audit_events",
      'action = "auth.login_failed" && actor_id = {:a} && created >= {:since}',
      "",
      1,
      0,
      { a: record.id, since: since },
    );
    if (existing.length > 0) return; // already one row for this window

    const d = detail || {};
    d.window_minutes = BUCKET_MINUTES;
    emit(e, ACTIONS.AUTH_LOGIN_FAILED, {
      actor: record,
      org: record.getString("org"),
      subject: {
        collection: "users",
        id: record.id,
        label: subjectLabel(record),
      },
      detail: d,
    });
  } catch (err) {
    $app.logger().warn("audit: failed login not recorded", "err", String(err));
  }
}

module.exports = {
  ACTIONS: ACTIONS,
  ACTION_LIST: ACTION_LIST,
  SEVERITY: SEVERITY,
  ACTOR: ACTOR,
  SENSITIVE: SENSITIVE,
  COLLECTION_ACTIONS: COLLECTION_ACTIONS,
  AUDITED_COLLECTIONS: Object.keys(COLLECTION_ACTIONS),
  diff: diff,
  emit: emit,
  emitRecordChange: emitRecordChange,
  emitLoginFailed: emitLoginFailed,
  subjectLabel: subjectLabel,
};
