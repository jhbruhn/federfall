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

// federfall-qt96.12 — the only way a row ever leaves this table.
//
// It needs no privilege the guard below does not already grant: it deletes
// exactly what an operator would be allowed to delete, which is why the guard
// can be absolute and stateless at the same time. Anything it tries that is
// still inside the window is refused by the same check that refuses everyone
// else, so a bug here degrades to "nothing was purged", never to "history was
// quietly rewritten".
cronAdd("auditRetention", "30 3 * * *", () => {
  const DEFAULT_RETENTION_DAYS = 730;
  const DAY_MS = 24 * 60 * 60 * 1000;
  const PAGE = 500;

  let orgs = [];
  try {
    orgs = $app.findRecordsByFilter("organisations", "id != ''", "", 500, 0);
  } catch (err) {
    $app.logger().warn("audit retention: cannot list orgs", "err", String(err));
    return;
  }

  const orgSettings = require(`${__hooks}/zv_org.js`);
  for (const org of orgs) {
    // `allowZero`: unlike a retention WINDOW elsewhere, 0 is a legitimate
    // instruction here — it disables the sweep for that org.
    const days = orgSettings.positiveNumber(
      orgSettings.settingsOf($app, org.id),
      "audit_retention_days",
      DEFAULT_RETENTION_DAYS,
      { allowZero: true },
    );
    if (days === 0) continue; // 0 means keep forever

    const cutoff = new Date(new Date().getTime() - days * DAY_MS)
      .toISOString()
      .replace("T", " ");

    let purged = 0;
    // Re-query from offset 0 each round: deleting shrinks the result set, so
    // the next page of still-expired rows slides to the front.
    for (;;) {
      let batch;
      try {
        batch = $app.findRecordsByFilter(
          "audit_events",
          "org = {:org} && created < {:cutoff}",
          "created",
          PAGE,
          0,
          { org: org.id, cutoff: cutoff },
        );
      } catch (err) {
        $app
          .logger()
          .warn("audit retention: query failed", "org", org.id, "err", String(err));
        break;
      }
      if (!batch || batch.length === 0) break;

      let deletedThisBatch = 0;
      for (const row of batch) {
        try {
          $app.delete(row);
          purged++;
          deletedThisBatch++;
        } catch (_) {
          // The guard refused it (a row right on the boundary, or the org's
          // window changed under us). Next run reconsiders it.
        }
      }
      // Nothing went: everything left is refused, so stop rather than spin.
      if (deletedThisBatch === 0) break;
      if (batch.length < PAGE) break;
    }

    if (purged > 0) {
      $app
        .logger()
        .info("audit retention: purged", "org", org.id, "count", purged);
      // The purge is itself an audited act — and the only record that these
      // rows ever existed. It ages out under the same window.
      require(`${__hooks}/lib_audit.js`).emit(null, "audit.purged", {
        actorKind: "cron",
        org: org.id,
        subject: { collection: "audit_events", id: "", label: "" },
        detail: { count: purged, retention_days: days },
      });
    }
  }
});

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

  // The same window the retention cron applies, read the same way — see
  // zv_org.js for why a json field must never be reached through `get()`.
  // `allowZero` because 0 disables retention for that org, which this guard
  // then treats as "nothing may ever be deleted".
  const orgSettings = require(`${__hooks}/zv_org.js`);
  const days = orgSettings.positiveNumber(
    orgSettings.settingsOf(e.app, rec.getString("org")),
    "audit_retention_days",
    DEFAULT_RETENTION_DAYS,
    { allowZero: true },
  );

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
