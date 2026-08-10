/// <reference path="../pb_data/types.d.ts" />

// federfall-jo1l — no relation may name a row in another organisation.
//
// The check org_scope.pb.js runs, kept in a module because both of its callbacks
// need it and each pb_hooks callback runs in an isolated JSVM (a file-level
// helper is NOT in scope inside a handler — see lib_derive.js / lib_custody.js).
//
// Usage — `require()` INSIDE the handler, with the `${__hooks}` absolute form:
//
//   const bad = require(`${__hooks}/lib_org_scope.js`)
//     .foreignRelation(e.app, e.record, isCreate);
//
// ── Driven off the SCHEMA, not a list ───────────────────────────────────────
// The predecessor (animal_org_scope.pb.js, federfall-ti77) named five
// collections and one field. The `[relation guards]` sweep then enumerated every
// relation on every client-writable collection and found eleven more that
// nothing checked — `aviaries.keeper`, `cases.active_carer`,
// `placements.carer`/`from_user`/`to_user`, `dispositions.aviary`,
// `case_conditions.condition`, `cases.admission_reasons`, `markings.type`, the
// three `route`s, `microscopy_findings.finding_type`, `users.invited_by` — each
// able to name a row in a different tenant. Writing a twelfth hand-kept list
// would only have moved the next omission somewhere else, so this reads the live
// schema instead: every relation whose TARGET collection carries an `org` is in
// scope, and a new collection or field is covered the day it is added.
//
// ── What it is worth ────────────────────────────────────────────────────────
// Low, and worth saying so: naming a foreign row grants the named party nothing,
// because every access rule also compares `org = @request.auth.org`. A foreign
// user set as `active_carer` still cannot read the case. The realisable effect is
// a foreign LABEL rendered in this org's UI (expanding `case_conditions.condition`
// shows another org's code-list text) — a small cross-tenant read of vocabulary,
// not of clinical data. The one exception is the field this started with:
// `cascadeDelete` on `animal` meant deleting a bird destroyed ANOTHER org's
// clinical history, which is why that one was fixed first and alone.
//
// No client can produce any of it: every picker is fed from an org-scoped query.
//
// ── Why a hook and not a rule ───────────────────────────────────────────────
// A plain field reference in an UPDATE rule resolves against the STORED record
// (1700000043's finding), so `condition.org = @request.auth.org` would check the
// OLD target and ignore the incoming one. Only a hook sees what is arriving.
//
// ── The three carve-outs, all of them derived rather than named ─────────────
//   * Hook-only collections are skipped, by asking the schema whether a client
//     can send a body at all (both create and update rules null). That is the
//     same definition `[relation guards]` uses, and it is why `aviary_stays` is
//     absent here exactly as it was from animal_org_scope.pb.js: its rows are
//     built by a hook from the animals record itself, so the animal and the org
//     cannot disagree.
//   * A record's own org can be UNSET and still be knowable: `exams` carry an
//     optional `org` and hang off a case, which has a required one. Falling back
//     to the parent case is what keeps the check from being dodged by simply
//     omitting the field, and a naive generic sweep gets this wrong.
//   * The `org` relation itself needs no special case: it points at
//     `organisations`, which has no `org` of its own, so the schema rule already
//     excludes it.
//
// Only CHANGED relations are checked on update, matching the stance the
// predecessor took for `animal`: rows can point at records deleted before their
// collection cascaded (`cases.animal` only started cascading in 1700000057), and
// re-validating every save would make those permanently unsaveable and break
// unrelated writes such as the dispositions hook bumping `case.status`.
//
// STATELESS (see lib_audit.js): each pooled JSVM holds its own instance, so
// nothing here may cache a decision between calls — including a schema answer.

/** The ids a relation field holds, single- or multi-valued, empties dropped. */
function idsOf(value) {
  if (value === null || value === undefined || value === "") return [];
  if (typeof value === "string") return [value];
  const out = [];
  for (let i = 0; i < value.length; i++) {
    const id = String(value[i] || "");
    if (id) out.push(id);
  }
  return out;
}

/** Whether [collection] is org-scoped, i.e. worth comparing a target against. */
function isOrgScoped(collection) {
  for (const field of collection.fields) {
    if (field.getName() === "org") return true;
  }
  return false;
}

/**
 * The name of the first relation on [record] that names a row in another
 * organisation, or `""` when it is clean.
 *
 * [isCreate] checks every relation the record carries; otherwise only the ones
 * whose value differs from `record.original()`.
 */
function foreignRelation(app, record, isCreate) {
  const collection = record.collection();
  if (collection.system) return "";
  // Hook-only: no client write path, so nothing here applies (see the header).
  if (collection.createRule === null && collection.updateRule === null) {
    return "";
  }

  // Which relations actually need looking at — computed before the record's own
  // org is resolved, so an ordinary write costs no extra query at all.
  const pending = [];
  for (const field of collection.fields) {
    if (field.type() !== "relation") continue;
    const name = field.getName();
    const ids = idsOf(record.get(name));
    if (!ids.length) continue;
    if (!isCreate) {
      const before = idsOf(record.original().get(name)).join(",");
      if (before === ids.join(",")) continue;
    }
    let target;
    try {
      target = app.findCollectionByNameOrId(field.collectionId);
    } catch (_) {
      continue;
    }
    if (!isOrgScoped(target)) continue;
    pending.push({ name: name, ids: ids, target: String(target.name) });
  }
  if (!pending.length) return "";

  let orgId = record.getString("org");
  if (orgId === "" && record.getString("case") !== "") {
    try {
      orgId = app
        .findRecordById("cases", record.getString("case"))
        .getString("org");
    } catch (_) {
      orgId = "";
    }
  }
  // Nothing to compare against — leave it to the collection's own rules.
  if (orgId === "") return "";

  for (const rel of pending) {
    for (const id of rel.ids) {
      let row;
      try {
        row = app.findRecordById(rel.target, id);
      } catch (_) {
        // A dangling id is PocketBase's own relation validation to refuse; this
        // hook has no opinion it could state more precisely.
        continue;
      }
      if (row.getString("org") !== orgId) return rel.name;
    }
  }
  return "";
}

module.exports = {
  idsOf: idsOf,
  isOrgScoped: isOrgScoped,
  foreignRelation: foreignRelation,
};
