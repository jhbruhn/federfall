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
  PLACEMENT_DELETED: "placement.deleted",

  DISPOSITION_CREATED: "disposition.created",
  DISPOSITION_UPDATED: "disposition.updated",
  DISPOSITION_DELETED: "disposition.deleted",

  EXAM_SAVED: "exam.saved",
  EXAM_DELETED: "exam.deleted",

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
  AVIARY_STAY_STARTED: "aviary_stay.started",
  AVIARY_STAY_UPDATED: "aviary_stay.updated",
  AVIARY_STAY_ENDED: "aviary_stay.ended",

  // ── finders (ids only — never names, see the header) ───────────────────────
  FINDER_CREATED: "finder.created",
  FINDER_UPDATED: "finder.updated",
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
  AUTH_LOGIN_BLOCKED: "auth.login_blocked",
  AUTH_PASSWORD_RESET: "auth.password_reset",
  AUTH_PASSWORD_CHANGED: "auth.password_changed",
  AUTH_MFA_ENABLED: "auth.mfa_enabled",
  AUTH_MFA_DISABLED: "auth.mfa_disabled",

  // ── data leaving the system ────────────────────────────────────────────────
  REPORT_EXPORTED: "report.exported",
  CASE_REPORT_PRINTED: "case_report.printed",
  GDPR_EXPORT: "gdpr.export",

  // ── system paths (no human actor) ──────────────────────────────────────────
  OAUTH2_USER_PROVISIONED: "oauth2.user_provisioned",
  SUPERVISOR_BOOTSTRAPPED: "supervisor.bootstrapped",
  AUDIT_PURGED: "audit.purged",
};

const ACTION_LIST = Object.keys(ACTIONS).map((k) => ACTIONS[k]);

const SEVERITY = { INFO: "info", NOTICE: "notice", SECURITY: "security" };
const ACTOR = { USER: "user", SYSTEM: "system", CRON: "cron", SUPERUSER: "superuser" };

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
const IGNORED_FIELDS = ["updated", "created"];

// Long free text (a 2000-char notes field) would bloat a row that can never be
// deleted, and `changes` has a maxSize. What matters is THAT the text changed.
const MAX_VALUE_CHARS = 500;

function isSensitive(collection, field) {
  const list = SENSITIVE[collection];
  return !!list && list.indexOf(field) !== -1;
}

function normalize(v) {
  if (v === null || v === undefined) return "";
  if (typeof v === "object") {
    try {
      return JSON.stringify(v);
    } catch (_) {
      return String(v);
    }
  }
  return v;
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
        auth = e ? e.auth : null;
      } catch (_) {
        auth = null;
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
    if (o.refs) row.set("refs", o.refs);
    if (o.changes && o.changes.length) row.set("changes", o.changes);
    if (o.detail) row.set("detail", o.detail);
    row.set("severity", o.severity || SEVERITY.INFO);
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

module.exports = {
  ACTIONS: ACTIONS,
  ACTION_LIST: ACTION_LIST,
  SEVERITY: SEVERITY,
  ACTOR: ACTOR,
  SENSITIVE: SENSITIVE,
  diff: diff,
  emit: emit,
};
