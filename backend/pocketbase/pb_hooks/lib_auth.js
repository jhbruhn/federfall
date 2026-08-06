/// <reference path="../pb_data/types.d.ts" />

// federfall-75sy — the gate every hook ROUTE has to pass, written once.
//
// Usage — `require()` INSIDE the handler, never at file level, and always with
// the `${__hooks}` absolute form (see lib_audit.js):
//
//   routerAdd("POST", "/api/federfall/exam", (e) => {
//     const org = require(`${__hooks}/lib_auth.js`).requireMember(e);
//     ...
//   }, $apis.requireAuth());
//
// ── Why this is a module and not five copies ────────────────────────────────
// A route bypasses the collection rules it writes through, so each one has to
// re-state the boundary those rules express. That was hand-rolled in five
// places (exam, intake, merge_animals, case_report, and the reporting routes),
// and it is the kind of code where a missing clause is a hole rather than a
// blemish: the guest wall in particular has needed re-applying across the
// schema before (1700000045_guest_wall_refresh.js), and test_rules.py's guest
// sweep walks COLLECTIONS — a route that forgot `role !== "guest"` would sail
// through it. The copies had already drifted in shape, if not yet in effect.
//
// `$apis.requireAuth()` on the route only proves a token; it says nothing
// about the account being active, being a guest, or belonging to an org. That
// is what these do, and every one of them returns the caller's org id — no
// route may act without one, since org is the scope of everything.
//
// STATELESS (see lib_audit.js): each pooled JSVM holds its own instance, so
// nothing here may cache a decision between calls.

/** The caller's org id, or ForbiddenError. Shared by every gate below. */
function orgOf(auth) {
  const org = auth.getString("org");
  if (!org) throw new ForbiddenError("No organisation.");
  return org;
}

/**
 * An active, non-guest member of an org → their org id.
 *
 * The baseline for any route that writes what a member may write: it mirrors
 * the shared predicate the collection rules use (1700000010 + 1700000045),
 * including the guest exclusion — guests can authenticate but are walled off
 * from all data.
 */
function requireMember(e) {
  const auth = e.auth;
  if (
    !auth ||
    !auth.getBool("is_active") ||
    auth.getString("role") === "guest"
  ) {
    throw new ForbiddenError("Not allowed.");
  }
  return orgOf(auth);
}

/** An active supervisor → their org id. */
function requireSupervisor(e) {
  const auth = e.auth;
  if (!auth || !auth.getBool("is_active") ||
      auth.getString("role") !== "supervisor") {
    throw new ForbiddenError("Not allowed.");
  }
  return orgOf(auth);
}

/**
 * An active coordinator or supervisor → their org id.
 *
 * The gate for anything ORG-WIDE by construction: the statistics route, the
 * annual report, and the `case_report_rows` view they read (1700000063) all
 * cross every case regardless of carer or share. A carer must not obtain that
 * roster through a route when the collection rules would have refused it.
 */
function requireReporting(e) {
  const auth = e.auth;
  if (!auth || !auth.getBool("is_active")) {
    throw new ForbiddenError("Not allowed.");
  }
  const role = auth.getString("role");
  if (role !== "coordinator" && role !== "supervisor") {
    throw new ForbiddenError("Not allowed.");
  }
  return orgOf(auth);
}

module.exports = {
  requireMember: requireMember,
  requireSupervisor: requireSupervisor,
  requireReporting: requireReporting,
};
