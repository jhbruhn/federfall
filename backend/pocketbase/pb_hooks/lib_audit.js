/// <reference path="../pb_data/types.d.ts" />

// federfall-qt96.2 — the audit log's emitters. Every row in `audit_events`
// (1700000068) is written from here; the tables that drive them are
// app_audit_vocabulary.js.
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
//       changes: audit.diff("weights", before, e.record.fieldsData(), e.app),
//     });
//   }, "weights");
//
// This file is NOT named *.pb.js, so PocketBase does not load it as a hook — it
// is only ever reachable through that require(). Unlike a hook file, a required
// module keeps its own file-level scope, which is why the tables below and the
// file-level require of zv_audit.js can live out here (verified on 0.39.8).
//
// ── What moved out, and what stayed ─────────────────────────────────────────
//
// The MACHINERY is zugvogel's now — zv_audit.js, which the base image lays
// down in this same directory: redaction, the diff, label snapshotting, actor
// and org resolution, the request id, the never-throw wrapper, the failed-login
// bucketing. Some 700 lines, identical in both products, and the three
// properties it must keep (stateless, emit never throws, no PII of the public)
// are stated in its header rather than restated here.
//
// What is left here is the BINDING and the two emitters that need federfall's
// own tables to work: `emitRecordChange`, which picks an action out of
// COLLECTION_ACTIONS, and `contentOf`, which is a CONTENT_FIELDS lookup from
// top to bottom.
//
// The tables themselves are app_audit_vocabulary.js — a file whose only job is
// to hold them. Three test suites parse them out of its source (its header says
// which, and why that channel rather than a nicer one), and a coupling like
// that deserves a file of its own rather than a paragraph of apology next to an
// emitter.


const zv = require(`${__hooks}/zv_audit.js`);
const vocab = require(`${__hooks}/app_audit_vocabulary.js`);

// Pulled out for readability below; every one of them is the vocabulary's.
const ACTIONS = vocab.ACTIONS;
const COLLECTION_ACTIONS = vocab.COLLECTION_ACTIONS;
const CONTENT_FIELDS = vocab.CONTENT_FIELDS;

// The shared machinery bound to the tables above. `diff`, `emit`,
// `emitLoginFailed`, `subjectLabel`, `labelOf`, `labelsOf` and `relationTarget`
// are re-exported from here untouched — the export surface below is the one
// twenty-eight callers already use, and none of them had to change.
const shared = zv.withRegistry(vocab.REGISTRY);

/**
 * The allowlisted content of [record] as change entries.
 *
 * Stayed behind when the machinery left: every line of it is a CONTENT_FIELDS
 * lookup, and the allowlist is the whole idea. zugvogel's half is the four
 * helpers it borrows — `normalize`/`clamp` off the module, `isWithheld`,
 * `relationTarget` and `labelsOf` off the bound registry, so a field withheld
 * from a diff is withheld from a create too, by construction rather than by two
 * lists agreeing.
 *
 * @param created true for a create (values land in `to`), false for a delete
 *                (they land in `from`, which is what "cleared (was X)" reads
 *                as — the right sentence for something that no longer exists).
 * @param app     optional, as in diff(): resolves an allowlisted relation to a
 *                snapshotted label instead of leaving a bare id.
 */
function contentOf(collection, record, created, app) {
  const out = [];
  for (const field of CONTENT_FIELDS[collection] || []) {
    let value;
    try {
      value = zv.normalize(record.get(field));
    } catch (_) {
      continue; // not a field on this collection
    }
    // An unset field is not content. `false` and `0` are, so this cannot be a
    // truthiness test: "quarantine lifted" and "capacity 0" both matter.
    if (value === "" || value === null || value === undefined) continue;

    if (shared.isWithheld(collection, field)) {
      out.push({ field: field, redacted: true });
      continue;
    }
    const c = zv.clamp(value);
    const entry = created
      ? { field: field, to: c.value }
      : { field: field, from: c.value };
    if (c.truncated) entry.truncated = true;
    const target = shared.relationTarget(collection, field);
    if (target && app) {
      const label = shared.labelsOf(app, target, value);
      if (label) entry[created ? "to_label" : "from_label"] = label;
    }
    out.push(entry);
  }
  return out;
}

// The few places where the verb alone is too coarse to be worth reading.
// Derived side effects are folded in here rather than emitted as their own
// events: a handoff's share-on-handoff and carer change are consequences of one
// human action, not three things that happened.
function refine(collection, verb, record, changes, hints, app) {
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
    const sharedWith = String(record.getString("shared_with") || "");
    return {
      action:
        verb === "created" ? ACTIONS.CASE_SHARED : ACTIONS.CASE_SHARE_REVOKED,
      detail: {
        with: sharedWith,
        // Who that is. The id alone told a supervisor nothing — and the name
        // was already resolved for subject_label, one line away.
        with_label: shared.labelOf(app, "users", sharedWith),
        access: String(record.getString("access") || ""),
      },
    };
  }
  // A disposition is the one action whose consequences are bigger than itself:
  // main.pb.js closes the case and re-derives the bird's lifetime status from
  // it. Those are consequences of one human act, so they belong in that act's
  // detail rather than as events of their own (the same rule that makes a
  // handoff one row) — and until now they were recorded nowhere at all.
  //
  // Read AFTER e.next(), so the model hook has already reconciled them. The
  // delete case is the interesting one: removing the last disposition reopens
  // the case, and that reversal was invisible.
  if (collection === "dispositions" && app) {
    try {
      const caseRec = app.findRecordById("cases", record.getString("case"));
      const detail = { case_status: caseRec.getString("status") };
      const animalId = caseRec.getString("animal");
      if (animalId) {
        const animal = app.findRecordById("animals", animalId);
        detail.lifetime_status = animal.getString("lifetime_status");
        const aviary = animal.getString("current_aviary");
        if (aviary) {
          detail.current_aviary = aviary;
          detail.current_aviary_label = shared.labelOf(app, "aviaries", aviary);
        }
      }
      return { action: null, detail: detail };
    } catch (_) {
      // Case or animal already gone (a cascading delete) — the envelope and
      // the recorded content still stand on their own.
    }
  }

  if (collection === "placements" && verb === "created") {
    const to = String(record.getString("to_user") || "");
    if (to) {
      const from = String(record.getString("from_user") || "");
      return {
        action: ACTIONS.CASE_HANDOFF,
        detail: {
          from: from,
          // The names, snapshotted. A handoff is the event most often read back
          // and it named both people by id until now.
          from_label: shared.labelOf(app, "users", from),
          to: to,
          to_label: shared.labelOf(app, "users", to),
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
      changes = contentOf(collection, record, verb === "created", e.app);
    }
    if (verb === "updated") {
      changes = shared.diff(collection, before, record.fieldsData(), e.app);
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
    const refined = refine(collection, verb, record, changes, hints, e.app);
    if (refined) {
      // A refinement may enrich the detail without renaming the action.
      if (refined.action) action = refined.action;
      detail = refined.detail;
    }

    shared.emit(e, action, {
      record: record,
      subject: {
        collection: collection,
        id: record.id,
        label: shared.subjectLabel(record, e.app),
      },
      refs: shared.refsFor(record),
      changes: changes,
      detail: detail,
    });
  } catch (err) {
    $app
      .logger()
      .warn("audit: record change not recorded", "verb", String(verb), "err", String(err));
  }
}

// The surface twenty-eight callers already use, unchanged. The vocabulary half
// is re-exported from app_audit_vocabulary.js rather than moved out of reach:
// `audit.ACTIONS.WEIGHT_UPDATED` reads correctly at a call site and splitting
// the import in two would make every one of them worse to read.
module.exports = {
  ACTIONS: vocab.ACTIONS,
  ACTION_LIST: vocab.ACTION_LIST,
  SEVERITY: vocab.SEVERITY,
  ACTOR: vocab.ACTOR,
  SENSITIVE: vocab.SENSITIVE,
  FREE_TEXT: vocab.FREE_TEXT,
  COLLECTION_ACTIONS: vocab.COLLECTION_ACTIONS,
  AUDITED_COLLECTIONS: Object.keys(vocab.COLLECTION_ACTIONS),
  diff: shared.diff,
  emit: shared.emit,
  emitRecordChange: emitRecordChange,
  emitLoginFailed: shared.emitLoginFailed,
  subjectLabel: shared.subjectLabel,
  labelOf: shared.labelOf,
  labelsOf: shared.labelsOf,
  relationTarget: shared.relationTarget,
};
