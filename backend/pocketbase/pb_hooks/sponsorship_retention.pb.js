/// <reference path="../pb_data/types.d.ts" />

// federfall-5s5j.1 — a patronage whose bird is gone does not keep its sponsor's
// address forever.
//
// `sponsorships.animal` is `cascadeDelete: false` on purpose (1700000085): a
// donation record is not part of the bird's clinical history and must not be
// destroyed with it. Deleting an animal is supervisor-only and already takes its
// cases and their whole timeline (1700000010 / 1700000057), and taking the
// donation ledger too would erase the one record somebody reconciles against a
// bank statement.
//
// What is left is an orphan, and an orphan is unreachable in the only way that
// matters: the read predicate resolves through `animal.current_aviary.keeper`,
// so with no animal there is no keeper — coordinators and supervisors still see
// it, no keeper does. Holding a sponsor's name, postal address and mobile in
// that state indefinitely is exactly the data-minimisation problem
// `finder_retention.pb.js` exists to solve, so this closes it the same way:
// after the org's window, the row is DELETED.
//
// ── An ENDED patronage is not swept, and that is a decision ─────────────────
// federfall-5s5j.4: a patronage whose `ended_at` is set, on a bird that still
// exists, is kept indefinitely. Data minimisation argues for the finder
// treatment — the patronage is over, so drop the address and the mobile — but a
// donation that produced a Zuwendungsbestätigung falls under the retention duties
// in §147 AO / §257 HGB, and the receipt is worthless without the donor's name
// and address. Here the identity is the part that must be KEPT, which is the
// mirror image of the finder scrub. Splitting the row into "receipt fields" and
// "the rest" and getting that boundary wrong is a legal problem rather than a
// bug, so the whole row stays and this cron has exactly ONE deletion path: the
// orphan below. An ended patronage is history, and history is kept.
//
// Deleted rather than anonymised, which is the difference from the finder scrub.
// A scrubbed finder is kept because its location feeds a non-identifying
// statistic and its case→finder link still means something. A sponsorship
// stripped of its sponsor is a number with nothing to attach it to — the bird it
// documented does not exist any more either.
//
// ── The window ──────────────────────────────────────────────────────────────
// `organisations.settings` → `sponsorshipRetentionMonths`, read through
// `lib_org.js` (federfall-jumi). NEVER a fresh `getString()` + `JSON.parse` and
// never `record.get()`: `get()` on a JSON field hands JS a BYTE ARRAY, so
// `settings.someKey` is `undefined` and the code falls through to its default in
// total silence. That trap had already disabled two shipped, documented windows
// before it was given one reader.
//
// Default 24 months, matching `finderRetentionMonths` — the same kind of contact
// data under the same reasoning, so two different defaults would be a difference
// nobody could explain to a supervisor.
//
// ── ORPHAN_GRACE_MS ─────────────────────────────────────────────────────────
// Measured from the row's own `created`, like the finder orphan pass: a
// sponsorship written moments before its animal (an import, the Admin UI) must
// never be mistaken for one left behind by a delete.
//
// PocketBase isolates each hook/cron context, so everything is defined inside
// the handler — file-level helpers are not visible here.
//
// NB `cronAdd` jobs are invisible to tests/run.sh (nothing can trigger them).
// This one is covered by tests/run_cron.sh + test_cron.py, which rewrite the
// schedule to `* * * * *` in a throwaway copy of pb_hooks.

cronAdd("sponsorshipRetention", "0 4 * * *", () => {
  const DEFAULT_RETENTION_MONTHS = 24;
  const MONTH_MS = (365 * 24 * 60 * 60 * 1000) / 12;
  const PAGE = 200;
  // How long an orphan is left alone before deletion, so a row written moments
  // before its animal is never mistaken for one whose animal was deleted.
  const ORPHAN_GRACE_MS = 24 * 60 * 60 * 1000;

  const now = new Date();

  const toDate = (s) => {
    if (!s) return null;
    const d = new Date(String(s).replace(" ", "T"));
    return isNaN(d.getTime()) ? null : d;
  };

  // federfall-jumi: through lib_org.js, which decodes the JSON field.
  const orgs = require(`${__hooks}/lib_org.js`);
  const retentionMsForOrg = (orgId) => {
    const months = orgs.positiveNumber(
      orgs.settingsOf($app, orgId),
      "sponsorshipRetentionMonths",
      DEFAULT_RETENTION_MONTHS,
    );
    return months * MONTH_MS;
  };

  // An orphan is a row whose `animal` is empty (the relation is optional and
  // does not cascade, so deleting a bird NULLS it — see 1700000085) or points at
  // a row that is gone (an older delete, or one that bypassed the relation
  // bookkeeping).
  const animalExists = (animalId) => {
    if (!animalId) return false;
    try {
      $app.findRecordById("animals", animalId);
      return true;
    } catch (_) {
      return false;
    }
  };

  let deleted = 0;
  let offset = 0;
  for (;;) {
    let batch;
    try {
      batch = $app.findRecordsByFilter(
        "sponsorships",
        "id != ''",
        "created",
        PAGE,
        offset,
      );
    } catch (e) {
      $app.logger().warn("sponsorship retention: query failed", "err", String(e));
      break;
    }
    if (!batch || batch.length === 0) break;

    let deletedThisBatch = 0;
    for (const row of batch) {
      try {
        // A bird that still exists keeps its patronage, however old.
        if (animalExists(row.getString("animal"))) continue;

        // Measured from the row's own creation, not from the delete: nothing
        // records when an animal was destroyed (that is the point of a delete),
        // and `created` is a server-owned autodate no client can forge.
        const born = toDate(row.getString("created"));
        if (!born) continue;
        const age = now.getTime() - born.getTime();
        if (age < ORPHAN_GRACE_MS) continue;
        if (age < retentionMsForOrg(row.getString("org"))) continue;

        // Emitted BEFORE the delete: afterwards there is nothing left to
        // describe, and this row's id is the only remaining evidence the record
        // existed. No sponsor detail — SENSITIVE.sponsorships covers the value
        // path, and there is no reason to hand-write one here either.
        require(`${__hooks}/lib_audit.js`).emit(null, "sponsorship.deleted", {
          actorKind: "cron",
          org: row.getString("org"),
          subject: { collection: "sponsorships", id: row.id, label: "" },
          detail: { orphan: true },
        });
        $app.delete(row);
        deleted++;
        deletedThisBatch++;
      } catch (e) {
        $app
          .logger()
          .warn(
            "sponsorship retention: delete failed",
            "sponsorship",
            row.id,
            "err",
            String(e),
          );
      }
    }

    // Deleted rows leave the result set, so re-query from the same offset;
    // otherwise step past this page.
    if (deletedThisBatch === 0) offset += batch.length;
  }

  if (deleted > 0) {
    $app
      .logger()
      .info("sponsorship retention: deleted orphaned sponsorships", "count", deleted);
  }
});
