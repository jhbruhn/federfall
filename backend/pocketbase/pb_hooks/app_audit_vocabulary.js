/// <reference path="../pb_data/types.d.ts" />

// federfall's audit VOCABULARY. Every table the audit log is driven by, and
// nothing else — no machinery, no emitters.
//
// ── Why this is a file of its own ──────────────────────────────────────────
//
// zugvogel owns the audit MACHINERY (zv_audit.js): redaction, the diff, label
// snapshotting, actor and org resolution, the request id, the never-throw
// wrapper, the failed-login bucketing. It owns none of the WORDS. Which action
// strings exist, which collections are audited, which fields are a member of
// the public's contact details, what labels a record — that is a product's
// vocabulary, and two products do not share one. eiermann has no cases, no
// finders and no medications at all; a shared table would be two disjoint
// halves in one file, each carrying the other's as dead weight in its image.
//
// So: the machinery is required, the vocabulary is passed in.
// `REGISTRY` at the bottom is these tables in the shape `withRegistry()` wants.
//
// ── Three suites read this file, and one of them cannot ask the server ─────
//
// The tables are parsed out of this SOURCE TEXT rather than mirrored in a test
// fixture, so that a copy cannot go on passing after the real map changed:
//
//   backend/pocketbase/tests/test_rules.py — COLLECTION_ACTIONS, SENSITIVE,
//     FREE_TEXT, IGNORED_FIELDS, LABEL_FIELDS, RELATION_TARGETS,
//     RELATION_FIELDS and the ACTIONS lines, checked against the LIVE schema
//   packages/federfall_models/test/audit_event_test.dart — the ACTIONS lines,
//     which must equal AuditAction.values exactly, in both directions
//   apps/federfall/test/features/admin/audit_labels_test.dart — CONTENT_FIELDS,
//     every recorded field needing a translated name in both languages
//
// Which is why the tables are not simply exported and read at runtime: the Dart
// suites are unit tests with no server to ask, `audit_events.action` is
// deliberately TEXT rather than a select so the list is not in the schema
// either, and federfall's CI has no node to load a JS module from. Parsing the
// source is the one channel all three share. It costs a formatting constraint —
// the tables are `^  key: {` and `^  KEY: "value",` and a reformat that changed
// that would be caught by the parse guards, not by silence.
//
// Keeping them in one file whose only job is to hold them is what makes that
// coupling tolerable. It used to live in lib_audit.js next to the emitters,
// where every reader had to be told why.

// ── The public's PII, restated because it is the rule most easily broken ────
//
// A finder and a sponsor are members of the public whose contact details
// finder_retention.pb.js and sponsorship_retention.pb.js scrub on a schedule; a
// copy of them sitting in an append-only table nothing can delete would defeat
// that scrub with the app's own audit trail. Their subjects carry an empty
// label (NEVER_LABELLED) and their identity/contact fields are redacted to the
// FACT of a change (SENSITIVE).


const zv = require(`${__hooks}/zv_audit.js`);

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
  // One course written across a group of cases in one transaction
  // (prescribe_batch.pb.js). No per-row `medication.prescribed` beside it, for
  // the reason VACCINATION_BATCH_RECORDED gives below; each row is an ordinary
  // prescription afterwards and its own edits emit medication.updated.
  MEDICATION_BATCH_PRESCRIBED: "medication.batch_prescribed",
  ADMINISTRATION_LOGGED: "administration.logged",
  ADMINISTRATION_UPDATED: "administration.updated",
  ADMINISTRATION_DELETED: "administration.deleted",
  // One dose round given across a group in one transaction
  // (administer_batch.pb.js). Same stance as MEDICATION_BATCH_PRESCRIBED above:
  // one event for the round, and each row is an ordinary dose afterwards.
  ADMINISTRATION_BATCH_LOGGED: "administration.batch_logged",

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

  VACCINATION_CREATED: "vaccination.created",
  VACCINATION_UPDATED: "vaccination.updated",
  VACCINATION_DELETED: "vaccination.deleted",
  // A whole enclosure vaccinated in one transaction (vaccinate_batch.pb.js).
  // There is no per-row `vaccination.created` beside it — the route writes with
  // tx.save(), which fires no request hooks, and N identical rows would bury
  // the one fact worth reading. Editing one of them afterwards is an ordinary
  // vaccination.updated.
  VACCINATION_BATCH_RECORDED: "vaccination.batch_recorded",

  // A microscopy sample and the findings it replaced wholesale, as one event —
  // written from the route (microscopy.pb.js), the way exam.saved is. There is
  // no microscopy_finding.* triple: a finding is never written on its own, and
  // per-row events would bury the one fact worth reading.
  MICROSCOPY_SAVED: "microscopy.saved",
  MICROSCOPY_DELETED: "microscopy.deleted",
  // As with exam findings: these fire only for a finding edited on its own
  // through the collection API, which the rules still allow.
  MICROSCOPY_FINDING_CREATED: "microscopy_finding.created",
  MICROSCOPY_FINDING_UPDATED: "microscopy_finding.updated",
  MICROSCOPY_FINDING_DELETED: "microscopy_finding.deleted",

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

  // ── sponsorships (ids and amounts only — never the sponsor, see SENSITIVE) ─
  // A Patenschaft holds a member of the public's name, address and mobile.
  // Same stance as `finders`, for the same reason: this table is append-only
  // with a tamper guard nothing can delete from (1700000068), so a sponsor's
  // name logged here would outlive every scrub.
  SPONSORSHIP_CREATED: "sponsorship.created",
  SPONSORSHIP_UPDATED: "sponsorship.updated",
  SPONSORSHIP_DELETED: "sponsorship.deleted",
  // The bird moved enclosure, so its patronages did too — and with them, who can
  // read a sponsor's contact details. Emitted from
  // sponsorship_access_audit.pb.js, which hangs off `animals.current_aviary`
  // rather than off the disposition, because four other writers change that
  // field. A disclosure of personal data to a new reader, hence `security`.
  SPONSORSHIP_ACCESS_TRANSFERRED: "sponsorship.access_transferred",

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

// Re-exported, not re-declared: these are the `audit_events` wire values, and
// zv_audit.js is now the one place they are written down.
const SEVERITY = zv.SEVERITY;
const ACTOR = zv.ACTOR;

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
  "sponsorship.access_transferred": SEVERITY.SECURITY,
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
  // federfall-5s5j.1 — a sponsor is a member of the public too, and this row is
  // the only place their details live (1700000085 stores them INLINE rather than
  // in a shared person table). Unlike `finders`, the LOCATION fields are
  // redacted as well: there is no "where do birds come from" statistic to serve
  // here, and a postal code beside a name is an identification.
  sponsorships: [
    "sponsor_name",
    "sponsor_pronouns",
    "address",
    "postal_code",
    "city",
    "region",
    "mobile",
    "notes",
  ],
};

// ── Free prose is never copied into the log (federfall-g5ap) ────────────────
//
// SENSITIVE covers credentials and finder PII. This covers the other thing that
// must not land in an append-only table: text a person wrote in their own words
// and can still correct. CONTENT_FIELDS already excludes it on the create/delete
// path — `journal_entries` is empty there precisely so "the note stays where it
// can still be corrected" — but diff() is a DENYLIST, so before this list an
// EDIT logged 500 characters of the old AND the new prose. A carer editing a
// name out of a journal entry left the original in a table nothing can delete
// from, which is the same hole finder_retention.pb.js's scrub exists to close.
//
// Keyed by FIELD NAME, like RELATION_TARGETS, because this schema is consistent
// about it: a field called `notes` is somebody's prose wherever it appears. The
// row keeps the FACT of the change ({field, redacted: true}) — "someone rewrote
// this bird's journal entry" is the auditable part, and the structured siblings
// (dose_rate, disposition type, quarantine dates) carry the clinical meaning.
//
// A prose column NOT listed here fails test_rules.py's audit sweep, which asks
// the live schema for every text field long enough to hold a paragraph. The one
// deliberate exemption is a code list's `description` — a supervisor's own
// definition of a diagnosis code, org configuration rather than a record about a
// bird or a person, and useful to read back verbatim.
const FREE_TEXT = [
  "text",
  "note",
  "notes",
  "comments",
  "condition_at_handoff",
  "instructions",
  "intake_notes",
  "outcome",
  "reason",
  // The pre-`exams` per-system findings still on `cases` (1700000004).
  "exam_cardiopulmonary",
  "exam_cns",
  "exam_forelimb",
  "exam_gi",
  "exam_head",
  "exam_hindlimb",
  "exam_integument",
  "exam_musculoskeletal",
];

// Fields that change on every write and say nothing about intent. Credentials
// are deliberately NOT here: "this account's password changed" is exactly the
// kind of thing a supervisor needs to see. SENSITIVE strips the values; leaving
// the fields out entirely would strip the signal too.
// PocketBase's own auth bookkeeping stamps (a reset mail was sent, a login
// alert went out) are internal side effects, not something a person did.
//
// zv_audit.js declares the same five and CONCATENATES whatever `ignoredFields`
// adds, so handing it this list changes nothing today. It is handed over, and
// kept here, because test_rules.py's prose sweep reads it out of THIS file to
// decide which columns it may skip: the list the sweep trusts has to be the
// list the emitter uses, and a duplicate in a denylist is inert.
const IGNORED_FIELDS = [
  "updated",
  "created",
  "lastResetSentAt",
  "lastVerificationSentAt",
  "lastLoginAlertSentAt",
];

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
  vaccinations: {
    created: ACTIONS.VACCINATION_CREATED,
    updated: ACTIONS.VACCINATION_UPDATED,
    deleted: ACTIONS.VACCINATION_DELETED,
  },
  egg_records: {
    created: ACTIONS.EGG_RECORD_CREATED,
    updated: ACTIONS.EGG_RECORD_UPDATED,
    deleted: ACTIONS.EGG_RECORD_DELETED,
  },
  // `created`/`updated` normally come from the route as one microscopy.saved;
  // these cover a sample written straight through the collection API (the Admin
  // UI, an import, an older client), which the rules still allow. `deleted` is
  // the ordinary path — the route does not delete, and the findings cascade.
  microscopy_samples: {
    created: ACTIONS.MICROSCOPY_SAVED,
    updated: ACTIONS.MICROSCOPY_SAVED,
    deleted: ACTIONS.MICROSCOPY_DELETED,
  },
  microscopy_findings: {
    created: ACTIONS.MICROSCOPY_FINDING_CREATED,
    updated: ACTIONS.MICROSCOPY_FINDING_UPDATED,
    deleted: ACTIONS.MICROSCOPY_FINDING_DELETED,
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

  // ── sponsorships: amounts and dates only, never the sponsor ────────────────
  // SENSITIVE.sponsorships redacts every personal field, so what a row here
  // says is "somebody entered / changed / removed a patronage on this bird, and
  // it was worth this much" — the auditable part, and the part that is not
  // personal data. The bird arrives as `refs.animal`.
  sponsorships: {
    created: ACTIONS.SPONSORSHIP_CREATED,
    updated: ACTIONS.SPONSORSHIP_UPDATED,
    deleted: ACTIONS.SPONSORSHIP_DELETED,
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
  microscopy_finding_types: {
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
// to survive anyway. Three collections are absent ON PURPOSE, not by oversight:
//
//   finders          — additionally forced to "" by NEVER_LABELLED, wherever
//                      the label would otherwise have come from. A member of
//                      the public is never named in this table.
//   sponsorships     — the same, and forced the same way. The only name a
//                      patronage has is its sponsor's, so a label here would BE
//                      the PII that SENSITIVE.sponsorships redacts out of the
//                      values. The row is located by `refs.animal` instead.
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
  // The product as written on the vial — neutral text a user typed, never a
  // translated phrase. `target` is deliberately not a fallback: "Pocken" is a
  // German word, and a label is stored verbatim and read in both languages.
  vaccinations: ["vaccine"],
  organisations: ["name"],
  conditions: ["label"],
  admission_reasons: ["label"],
  marking_types: ["label"],
  medication_routes: ["label"],
  medication_products: ["name", "label"],
  microscopy_finding_types: ["label"],
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
  // A finding is named by the vocabulary entry it points at (or by its own
  // free_text, which needs no lookup).
  microscopy_findings: { finding_type: "microscopy_finding_types" },
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

// The collection a relation field points INTO, so a change to one can record
// what the target is called and not only its id (federfall-ybua.2). Without
// this, moving a bird between aviaries logs "Voliere: 8k2m4p7q1w3e5r9" — an
// event nobody can read, on one of the paths this log exists for.
//
// Keyed by FIELD NAME, because this schema names a relation the same thing
// wherever it appears: `animal` is always an animal, `case` always a case, and
// a field named after a person (`*_by`, `*_user`, `keeper`, `examiner`) always
// points at a member. `finder` is deliberately absent — nothing may name a
// member of the public here, whichever direction it is reached from.
const RELATION_TARGETS = {
  active_carer: "users",
  administered_by: "users",
  // The one MULTI relation in the schema (maxSelect 99, 1700000039) — resolved
  // through labelsOf(), which is why it can sit in the same table as the rest.
  admission_reasons: "admission_reasons",
  admitted_by: "users",
  animal: "animals",
  applied_by: "users",
  applied_in_case: "cases",
  author: "users",
  aviary: "aviaries",
  carer: "users",
  case: "cases",
  condition: "conditions",
  finding_type: "microscopy_finding_types",
  created_by: "users",
  invited_by: "users",
  current_aviary: "aviaries",
  examiner: "users",
  from_user: "users",
  // NOT `exam`: an examination has no name of its own (LABEL_FIELDS could only
  // offer a date, and a label must be neutral text) — a finding is located by
  // the case and the examiner instead. Exempted explicitly in test_rules.py.
  keeper: "users",
  medication: "medications",
  org: "organisations",
  performed_by: "users",
  route: "medication_routes",
  set_by: "users",
  shared_by: "users",
  shared_with: "users",
  to_user: "users",
  transported_by: "users",
};

// Where a field name means different things in different collections, the
// per-collection entry wins. `type` is the whole reason this table exists and
// why RELATION_TARGETS cannot simply be widened: it is a relation into
// marking_types on `markings` and a plain text outcome on `dispositions`.
const RELATION_FIELDS = {
  markings: { type: "marking_types" },
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
  markings: ["applied_at", "present_at_find", "removed_at", "is_active"],
  case_conditions: ["certainty", "onset_date", "resolved_date"],
  medications: [
    "dose_rate",
    "dose_unit",
    "frequency_kind",
    "interval_hours",
    "cycle_on_days",
    "cycle_off_days",
    "started_at",
    "ended_at",
  ],
  medication_administrations: ["dose", "dose_unit", "administered_at"],
  placements: ["moved_in_at", "where_holding"],
  // `type` is the one that matters: released, died, euthanised, transferred.
  // `aviary` matters as much as the type: since 1700000075 a client cannot
  // write `animals.current_aviary` at all, and the reconcile that does write it
  // runs through `app.save()` — which fires no request hook and so emits
  // nothing. This disposition is therefore the ONLY record of which enclosure
  // the bird went into. relationTarget() already knows `aviary` names an
  // aviary, so the label comes for free (federfall-7no9).
  dispositions: [
    "type", "disposed_at", "aviary", "release_type", "transfer_type",
  ],
  exams: ["examined_at", "body_condition", "hydration", "mentation"],
  exam_findings: ["system", "status"],
  egg_records: ["count", "laid_at", "fate"],
  // `batch` is the one that has to survive: a vaccine failure or a recall is
  // traced by Chargennummer, and an edit to it is the edit somebody would most
  // want to reconstruct. `vet` is left out on purpose — it is already the
  // subject label's neighbour in `changes` only when it changes, and naming an
  // external practice on every create is not what this row is for.
  vaccinations: [
    "vaccine",
    "target",
    "administered_at",
    "batch",
    "series",
    "next_due_at",
    "dose",
    "dose_unit",
  ],
  // `no_findings` is the one that matters as much as the grades: "ohne Befund"
  // is an assertion somebody made, not an absence of data.
  microscopy_samples: [
    "sample_type",
    "method",
    "examined_at",
    "examined_by",
    "external_lab",
    "no_findings",
  ],
  microscopy_findings: ["severity", "free_text"],
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
  // `sample_types` decides which probe offers this finding, so narrowing it is
  // a change to what carers can record — worth reading back.
  microscopy_finding_types: ["label", "active", "sample_types"],
  journal_entries: [],
  finders: [],
  organisations: [],
  // Everything a sponsorship says about the SPONSOR is redacted (SENSITIVE), so
  // what is left is the arrangement: how much, how often, and for how long.
  // That is enough for the row to be worth reading — a create or delete
  // otherwise carried nothing but an id, which test_rules.py's
  // uninformative-event check rejects.
  sponsorships: ["amount_cents", "interval", "started_at", "ended_at"],
};

// Ids worth correlating on beyond `case_id`, when the record carries them.
const REF_FIELDS = ["animal", "aviary", "to_user", "from_user", "shared_with"];

// Where a record's case is one hop away, because it has no `case` of its own:
// {collection: {field, collection}}. Handed to zv_audit as `correlation.via`,
// which is what makes a finding edited on its own file under the case it was
// about rather than under nothing at all (federfall-01wb).
const CASE_VIA = {
  exam_findings: { field: "exam", collection: "exams" },
  microscopy_findings: { field: "sample", collection: "microscopy_samples" },
};

// Nobody from the public is ever NAMED in this table — see the header. This one
// list replaces both halves of how that used to be enforced: labelOf() and
// subjectLabel() refused `finders`, and emit() additionally blanked a
// `sponsorships` subject label whatever the call site passed. Naming both in
// both places is not a widening — neither collection has a LABEL_FIELDS,
// LABEL_QUANTITIES or LABEL_RELATIONS entry, so every one of those paths
// already returned "" for them, and nothing in RELATION_TARGETS points at
// either.
const NEVER_LABELLED = ["finders", "sponsorships"];

// federfall's half of the audit API, in the shape zv_audit.withRegistry()
// expects. A key it accepts that is missing here is one federfall has no use
// for.
const REGISTRY = {
  defaultSeverity: DEFAULT_SEVERITY,
  sensitive: SENSITIVE,
  freeText: FREE_TEXT,
  ignoredFields: IGNORED_FIELDS,
  neverLabelled: NEVER_LABELLED,
  labelFields: LABEL_FIELDS,
  labelQuantities: LABEL_QUANTITIES,
  labelRelations: LABEL_RELATIONS,
  relationTargets: RELATION_TARGETS,
  relationFields: RELATION_FIELDS,
  refFields: REF_FIELDS,
  // The one central record everything else hangs off. `field` is the relation
  // most audited collections reach it by; `via` is the hop for the two that
  // reach it only through a parent, and `labelField` the human-readable number
  // snapshotted onto every row (federfall-by7w.2).
  correlation: {
    collection: "cases",
    field: "case",
    labelField: "case_number",
    via: CASE_VIA,
  },
  loginFailedAction: ACTIONS.AUTH_LOGIN_FAILED,
};


module.exports = {
  ACTIONS: ACTIONS,
  ACTION_LIST: ACTION_LIST,
  SEVERITY: SEVERITY,
  ACTOR: ACTOR,
  SENSITIVE: SENSITIVE,
  FREE_TEXT: FREE_TEXT,
  COLLECTION_ACTIONS: COLLECTION_ACTIONS,
  CONTENT_FIELDS: CONTENT_FIELDS,
  REGISTRY: REGISTRY,
};
