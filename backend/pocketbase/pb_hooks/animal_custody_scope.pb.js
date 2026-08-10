/// <reference path="../pb_data/types.d.ts" />

// federfall-v9ap — re-attributing a record needs custody of the bird it lands on.
//
// The sibling of `animal_org_scope.pb.js`, one authority level in: that one keeps
// a row from crossing an ORG boundary, this one keeps it from crossing a CUSTODY
// boundary. Both exist because a rule cannot see the incoming value of a relation
// on UPDATE — a plain field reference resolves against the STORED record
// (1700000043's finding) — so 1700000079's custody predicate, reached through
// `animal.`, authorises the bird a row is moving AWAY FROM.
//
// ── Why exactly one collection ──────────────────────────────────────────────
// 1700000082 answers the same hole for `weights`, `markings` and `exams` by
// FREEZING `animal` on update, which is simpler and costs nothing because no
// client re-points those. `egg_records` cannot be frozen: re-attribution is a
// shipped feature — `egg_reassign_sheet.dart` moves a record to the bird that
// actually laid it, which is the whole point of recording a presumed layer — and
// test_rules.py pins `egg.animal IS mutable`. So this is the one collection where
// the incoming animal has to be checked rather than refused, and this hook is the
// only place that can look at it.
//
// If a second collection ever needs re-pointing as a feature, add it to
// COLLECTIONS rather than writing a second hook.
//
// ── Why the *Request variant ────────────────────────────────────────────────
// `RecordRequestEvent` is the only event kind carrying `e.auth` (see
// authorship.pb.js / audit_domain.pb.js), and it is also exactly the surface at
// issue: the server-side routes write with `tx.save()`, which fires no request
// hook, so `merge_animals.pb.js` can still re-point a duplicate's eggs onto the
// survivor. A superuser is exempt for the same reason it is everywhere else — it
// bypasses collection rules anyway, and `[animal org scope]` drives its whole
// sweep with that token, so exempting it here keeps that block testing the ORG
// guard instead of silently passing on this one.
//
// Only fires when `animal` actually CHANGES, matching animal_org_scope.pb.js: a
// row whose stored animal the writer no longer holds must stay editable in every
// other respect, and re-validating on every save would make an unrelated content
// edit fail for a reason that has nothing to do with it.

const COLLECTIONS = ["egg_records"];

onRecordUpdateRequest((e) => {
  if (!e.hasSuperuserAuth()) {
    const incoming = e.record.getString("animal");
    const stored = e.record.original().getString("animal");
    if (incoming && incoming !== stored) {
      const auth = e.auth;
      if (
        !auth ||
        !require(`${__hooks}/lib_custody.js`).holds(e.app, auth, incoming)
      ) {
        throw new ForbiddenError("That animal is in someone else's care.");
      }
    }
  }
  e.next();
}, ...COLLECTIONS);
