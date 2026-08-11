/// <reference path="../pb_data/types.d.ts" />

// federfall-5s5j.1 — Patenschaften: who sponsors an aviary resident.
//
// A sponsorship names a member of the public (name, pronouns, postal address,
// mobile) and what they give. That is PII of the same kind `finders` holds, and
// it is treated the same way: readable by the people who need it and nobody
// else, kept out of the audit log's values, and swept when its subject is gone.
//
// ── ONE collection, sponsor details INLINE ──────────────────────────────────
// Not a shared `sponsors` person table on the `finders` pattern. A shared table
// would let keeper A read a sponsor's address the moment keeper B's bird
// acquired the same sponsor — the row would be reachable through the other
// bird's predicate. Inline means each keeper only ever holds their own copy.
// Accepted cost: somebody sponsoring two birds is entered twice.
//
// ── Access follows the bird, live ───────────────────────────────────────────
// There is deliberately NO frozen `aviary` snapshot here. The predicate
// resolves through `animal.current_aviary.keeper`, so MOVING A BIRD MOVES ITS
// SPONSORSHIP with it — nothing to re-point, nothing that can drift. That is
// the requested behaviour, not a side effect of the schema.
//
// The one-hop-through-`animal` read form is proven ground: 1700000079 probed
// exactly this predicate against a live 0.39.8, including the trap case where a
// second clause on the same back-relation is satisfied INDEPENDENTLY
// (cases_repository.dart:301). `[sponsorships]` in test_rules.py pins it here
// too rather than trusting that note, and pins BOTH directions of a move — a
// rule that returned nothing to anybody would pass a one-sided test as well.
//
// The bird's own carer is NOT a reader. Custody of the bird is not access to
// the patronage; that is the point of the feature, not an omission.
//
// When the bird leaves aviary care entirely (released / died / transferred),
// `lib_derive.js` clears `current_aviary` and no keeper can read the row any
// more — only coordinator/supervisor. Correct (there is no keeper to be the
// keeper) and accepted: winding a patronage down then needs a coord/sup. The
// app's disposition sheet warns before that happens.
//
// ── create is gated by the hook, not by this rule ───────────────────────────
// `create` is only org-scoped here. "This bird is currently in an aviary you
// keep" is a cross-record invariant, and a two-hop body resolution
// (`@request.body.animal.current_aviary.keeper`) is not something this repo has
// proven — `pb_hooks/sponsorships.pb.js` is the real gate.
//
// ── `animal` and `org` are frozen on update ─────────────────────────────────
// 1700000082's shape for 1700000082's reason: a plain field reference in an
// UPDATE rule resolves against the STORED record (1700000043's finding), so a
// rule cannot guard the DESTINATION of a re-point. Freezing also closes the
// only other route for pushing sponsor PII into another keeper's view — the
// aviary transfer is the one route, and the app warns about it.
//
// Rules carry the guest-safe AUTH form 1700000045 requires of anything new; the
// guest sweep in tests/test_rules.py fails loudly without it.

const INTERVALS = ["monthly", "quarterly", "yearly", "one_time"];

migrate(
  (app) => {
    const animals = app.findCollectionByNameOrId("animals");
    const organisations = app.findCollectionByNameOrId("organisations");

    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

    const READ =
      `${AUTH} && org = @request.auth.org` +
      ` && (${COORD_SUP} || animal.current_aviary.keeper = @request.auth.id)`;

    app.save(
      new Collection({
        type: "base",
        name: "sponsorships",
        listRule: READ,
        viewRule: READ,
        createRule: `${AUTH} && org = @request.auth.org`,
        updateRule:
          `(${READ})` +
          " && @request.body.animal:isset = false" +
          " && @request.body.org:isset = false",
        deleteRule: READ,
        fields: [
          // cascadeDelete: false ON PURPOSE. A donation record is not part of
          // the bird's clinical history and must not vanish with it — deleting
          // an animal is supervisor-only and already takes its cases and their
          // whole timeline (1700000010 / 1700000057). What is left is an orphan
          // that no keeper predicate can reach (it has no animal, so no
          // current_aviary), readable by coord/sup, and swept by
          // pb_hooks/sponsorship_retention.pb.js after the org's window.
          //
          // And NOT `required`, which is the pairing that actually makes the
          // above happen: PocketBase refuses to delete a record that is part of
          // a *required* relation reference (the same 400 `markings.type`
          // produces — "Make sure that the record is not part of a required
          // relation reference"). Required + no cascade would therefore not
          // leave an orphan behind; it would make deleting a sponsored bird
          // impossible — a supervisor-only operation blocked by a donation
          // record, with nothing on screen to explain why. Optional + no
          // cascade nulls the relation instead, which is exactly the orphan the
          // retention cron exists for.
          //
          // "A patronage names a bird" is still enforced, one level up:
          // pb_hooks/sponsorships.pb.js refuses a create it cannot follow to a
          // current enclosure, and an empty `animal` has none.
          {
            name: "animal",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: animals.id,
            cascadeDelete: false,
          },
          { name: "sponsor_name", type: "text", required: true, max: 200 },
          // Free text, not a select: a fixed list of pronouns would be
          // presumptuous, and this is written by the person who spoke to them.
          { name: "sponsor_pronouns", type: "text", required: false, max: 50 },
          // Mirrors `finders` (1700000003), field for field, so the app's
          // address form and the report vocabulary carry over unchanged.
          { name: "address", type: "text", required: false, max: 300 },
          { name: "postal_code", type: "text", required: false, max: 20 },
          { name: "city", type: "text", required: false, max: 150 },
          // Subdivision / Bundesland / region.
          { name: "region", type: "text", required: false, max: 150 },
          { name: "mobile", type: "text", required: false, max: 50 },
          // INTEGER CENTS, never a float: money in a binary float accumulates
          // error the moment anything sums it, and a donation total is read by
          // people who reconcile it against a bank statement. The Dart side
          // parses and renders at the edge and holds an int throughout.
          {
            name: "amount_cents",
            type: "number",
            required: false,
            min: 0,
            onlyInt: true,
          },
          // How often that amount is given. Optional: a patronage agreed in
          // conversation may have no figure attached yet, and refusing the row
          // until it does would push it into someone's notebook.
          {
            name: "interval",
            type: "select",
            required: false,
            maxSelect: 1,
            values: INTERVALS,
          },
          { name: "started_at", type: "date", required: false },
          // Empty means active. A date rather than a bool so "supported this
          // bird from March to September" stays answerable afterwards.
          { name: "ended_at", type: "date", required: false },
          { name: "notes", type: "text", required: false, max: 2000 },
          {
            name: "org",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: organisations.id,
            cascadeDelete: false,
          },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
          { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
        ],
        indexes: [
          "CREATE INDEX `idx_sponsorships_animal` ON `sponsorships` (`animal`)",
          "CREATE INDEX `idx_sponsorships_org` ON `sponsorships` (`org`)",
        ],
      }),
    );
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("sponsorships"));
  },
);
