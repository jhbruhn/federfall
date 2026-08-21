/// <reference path="../pb_data/types.d.ts" />

// Moved to zugvogel as zv_org_scope.js. What stays here is federfall's
// VOCABULARY: which relation a record inherits its org from when it has no `org`
// field of its own.
//
// ── Why that has to be passed in ───────────────────────────────────────────
//
// The original hard-coded it: no org on the record, but a `case` relation → take
// the org from that `cases` row. zugvogel generalised it to a list, because
// eiermann's records inherit from a `spot` and a `nest`, not a case.
//
// Getting this wrong is not loud. The check simply stops finding a scope and
// waves the write through — one rule assertion caught it here ("an exam with no
// org still cannot name a foreign animal", which passed with a 200) and nothing
// else would have.

/** Relations a record without its own `org` inherits one from, in order. */
const PARENT_ORG_FALLBACKS = [{ field: "case", collection: "cases" }];

module.exports = {
  idsOf: (...args) => require(`${__hooks}/zv_org_scope.js`).idsOf(...args),
  isOrgScoped: (...args) =>
    require(`${__hooks}/zv_org_scope.js`).isOrgScoped(...args),
  /**
   * Same signature the call sites already use; the fallback list is supplied
   * here so no caller has to know about it.
   */
  foreignRelation: (app, record, isCreate) =>
    require(`${__hooks}/zv_org_scope.js`).foreignRelation(
      app,
      record,
      isCreate,
      { parentOrgFallbacks: PARENT_ORG_FALLBACKS },
    ),
  PARENT_ORG_FALLBACKS: PARENT_ORG_FALLBACKS,
};
