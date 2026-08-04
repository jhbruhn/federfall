/// <reference path="../pb_data/types.d.ts" />

// federfall-qt96.1 — the audit log's tamper guard.
//
// 1700000068 already makes `audit_events` unwritable through the API by nulling
// its create/update/delete rules. This is the second layer, and it covers the
// caller rules do not: the superuser dashboard. An operator who can open the
// Admin UI can otherwise edit or erase any row in the collection that exists to
// record what operators did — which is most of the log's value gone.
//
// Model hooks (onRecordUpdate / onRecordDelete) fire for EVERY write path,
// including app.save() from other hooks and the dashboard, so they are the right
// level. Real removal stays possible for whoever holds the SQLite file; the guard
// is about the routine path, not an attacker with disk access (see the migration
// header on why there is no hash chain).
//
// ── The update guard has no carve-out, on purpose ────────────────────────────
//
// Not "no carve-out yet" — no carve-out ever. Every proposed exception so far
// (collapsing repeated failed logins into a counter, backfilling a label) is a
// reason to write a NEW row, and an append-only table with one blessed writer is
// exactly as tamperable as its exception list is long. This absoluteness is also
// why nothing in audit_events may be a relation to a routinely-deleted record:
// PocketBase nullifies non-cascade relations by SAVING the referring row, so a
// `users` relation here would make deleting an audited user throw. See the
// migration header — that is why the actor is stored as `actor_id` text.
//
// ── The delete guard checks the row's OWN age ────────────────────────────────
//
// The retention cron (federfall-qt96.12) has to be able to purge, and it cannot
// announce itself: JSVM module state is per-VM, not global (verified on 0.39.8),
// so there is no shared "I am the purger" flag a guard could trust — and one
// that could be set is one an attacker in another hook could set too. Deriving
// permission from the record instead removes the question: a row may be deleted
// only once it is older than its org's retention window, whoever is asking.
// Anything the cron is allowed to do, an operator was allowed to do anyway.
//
// Org settings JSON (snake_case, following `finder_retention_years`):
//   { "audit_retention_days": 730 }   // 0 = keep forever
// The epic sketched this key as `auditRetentionDays`; snake_case wins for
// consistency with the settings keys already in the collection.

// Append-only: no update, from anywhere, for any reason.
onRecordUpdate((e) => {
  throw new BadRequestError("audit_events is append-only.");
}, "audit_events");

onRecordDelete((e) => {
  const DEFAULT_RETENTION_DAYS = 730;
  const DAY_MS = 24 * 60 * 60 * 1000;

  const rec = e.record;

  // `created` is an autodate ("2026-08-04 09:12:33.123Z"); JS needs the T.
  const raw = rec.getString("created");
  const created = raw ? new Date(String(raw).replace(" ", "T")) : null;
  if (!created || isNaN(created.getTime())) {
    // A row whose age cannot be established can never clear the floor.
    throw new BadRequestError("audit_events is append-only.");
  }

  let days = DEFAULT_RETENTION_DAYS;
  try {
    const org = e.app.findRecordById("organisations", rec.getString("org"));
    // record.get() on a json field hands JS a types.JSONRaw — a BYTE ARRAY, not
    // a decoded object, so `settings.audit_retention_days` reads as undefined
    // and every org would silently keep the default window. getString() returns
    // the raw JSON text, which parses. (Passing get()'s value straight back to
    // Go is fine — JSONRaw marshals correctly; only property access in JS is
    // broken.) Verified on 0.39.8; see federfall-jumi for the same bug in
    // finder_retention.pb.js and main.pb.js.
    const settings = JSON.parse(org.getString("settings") || "{}");
    if (settings && settings.audit_retention_days !== undefined) {
      const d = parseFloat(settings.audit_retention_days);
      if (!isNaN(d) && d >= 0) days = d;
    }
  } catch (_) {
    // No org / no settings / unparseable → the default window.
  }

  if (days === 0) {
    throw new BadRequestError(
      "audit_events is append-only (retention is disabled for this organisation).",
    );
  }

  const floor = new Date().getTime() - days * DAY_MS;
  if (created.getTime() >= floor) {
    throw new BadRequestError(
      "audit_events is append-only until a row passes the retention window.",
    );
  }

  e.next();
}, "audit_events");
