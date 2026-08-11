/// <reference path="../pb_data/types.d.ts" />

// federfall-5s5j.5 — moving a sponsored bird transfers personal data, so the
// transfer itself is logged.
//
// Access to a Patenschaft resolves LIVE through `animal.current_aviary.keeper`
// (1700000085), by design: moving a bird moves its patronage. That means every
// move is also a disclosure of a sponsor's name, address and mobile to a new
// reader — and nothing recorded it. The disposition that caused it IS logged,
// but answering "who could see this sponsor's address in March" out of the
// disposition history means replaying `lib_derive.js`'s ordering by hand. For a
// GDPR trail that is the wrong shape; one explicit event answers it directly.
//
// ── Where it hangs ──────────────────────────────────────────────────────────
// On `animals`, exactly where `aviary_stays.pb.js` hangs, and for its reason:
// `current_aviary` is written from five places (the disposition create/update/
// delete reconciles in main.pb.js, merge_animals.pb.js, and a case-less
// resident create), and every one of them ends in a saved `animals` record. The
// disposition hook would miss the other four.
//
// A MODEL event, not the *Request variant — `lib_derive.js` writes through
// `app.save()`, which fires no request hook, so a request hook would never see
// the field change at all. The cost is that `e.auth` does not exist here, so the
// row's actor is `system`: the human act is the disposition, logged beside this
// with the real actor. This event answers "who gained access, and when", which
// is a question about the bird, not about who typed.
//
// ── What it does NOT carry ──────────────────────────────────────────────────
// No sponsor name, address or mobile — not even for one row. `audit_events` is
// supervisor-only and append-only with a tamper guard nothing can delete from
// (1700000068), so anything in here outlives every scrub, which is the whole
// reason SENSITIVE.sponsorships exists. A COUNT plus the enclosures involved is
// what makes the disclosure legible.
//
// Emitted only when the count is > 0, so the log is not filled with the moves of
// unsponsored birds — which is nearly all of them.
//
// `emit()` never throws by contract, so a failed log cannot turn a successful
// disposition into a 500. This callback still guards its own body: an
// after-success hook that throws turns a committed write into an error response.

onRecordAfterUpdateSuccess((e) => {
  try {
    const animal = e.record;
    const before = animal.original().getString("current_aviary");
    const after = animal.getString("current_aviary");

    if (before !== after) {
      const rows = e.app.findRecordsByFilter(
        "sponsorships",
        "animal = {:a}",
        "",
        0,
        0,
        { a: animal.id },
      );
      if (rows.length > 0) {
        const audit = require(`${__hooks}/lib_audit.js`);
        // Whoever the new enclosure belongs to. Resolved here rather than left
        // as an id: the keeper may be reassigned or the account deleted later,
        // and the row has to keep saying who gained access at the time.
        let keeperLabel = "";
        if (after) {
          try {
            const aviary = e.app.findRecordById("aviaries", after);
            keeperLabel = audit.labelOf(
              e.app,
              "users",
              aviary.getString("keeper"),
            );
          } catch (_) {
            // A dangling enclosure names nobody; the transfer still happened.
          }
        }

        audit.emit(e, "sponsorship.access_transferred", {
          org: animal.getString("org"),
          subject: {
            collection: "animals",
            id: animal.id,
            label: animal.getString("name") || animal.getString("species"),
          },
          refs: after
            ? { animal: animal.id, aviary: after }
            : { animal: animal.id },
          severity: "security",
          // The move as a change entry, so it renders through the same
          // „Voliere: X → Y" path every other relation change uses.
          changes: [
            {
              field: "current_aviary",
              from: before,
              to: after,
              from_label: audit.labelOf(e.app, "aviaries", before),
              to_label: audit.labelOf(e.app, "aviaries", after),
            },
          ],
          detail: {
            sponsorships: rows.length,
            keeper_label: keeperLabel,
          },
        });
      }
    }
  } catch (err) {
    $app
      .logger()
      .warn(
        "sponsorship access transfer not recorded",
        "animal",
        String(e.record ? e.record.id : ""),
        "err",
        String(err),
      );
  }
  e.next();
}, "animals");
