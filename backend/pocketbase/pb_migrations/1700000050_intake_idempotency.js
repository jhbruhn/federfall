/// <reference path="../pb_data/types.d.ts" />

// federfall-3ty3 — idempotency_keys: replay protection for multi-record write
// routes (currently POST /api/federfall/intake, pb_hooks/intake.pb.js).
//
// A timed-out intake may still have committed server-side, so a client retry
// could create a second animal+case (the app currently only WARNS via
// unknownOutcome). The true fix: the client sends a random `idempotency_key`
// with the payload; the route stores the key together with its JSON response
// in the same transaction as the created records, and a replay of the same
// key returns the stored response instead of writing anything.
//
// One row per completed keyed request:
//   endpoint    which route the key belongs to ("intake" for now; exam etc.
//               can join later) — keys never collide across routes
//   key         the client-generated random key (opaque, max 64 chars)
//   user        who sent it; keys are scoped per user so one user can never
//               replay (or probe) another user's response
//   response    the exact JSON payload the route returned on first success
//   expires_at  retry protection only needs to outlive a retry window — the
//               daily purge cron drops rows past this
//
// The unique (endpoint, user, key) index is what makes the pattern safe under
// concurrency: two simultaneous requests with the same key cannot both commit —
// the second transaction fails on the index and rolls back whole, and ITS
// retry is then served from the stored response.
//
// Access is hook-only: all collection rules are null (hooks bypass rules).

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");

    app.save(
      new Collection({
        type: "base",
        name: "idempotency_keys",
        indexes: [
          "CREATE UNIQUE INDEX `idx_idempotency_keys_key` ON `idempotency_keys` (`endpoint`, `user`, `key`)",
          "CREATE INDEX `idx_idempotency_keys_expires` ON `idempotency_keys` (`expires_at`)",
        ],
        fields: [
          { name: "endpoint", type: "text", required: true, max: 64 },
          { name: "key", type: "text", required: true, max: 64 },
          {
            name: "user",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: users.id,
            cascadeDelete: true,
          },
          { name: "response", type: "json", required: true, maxSize: 10000 },
          { name: "expires_at", type: "date", required: true },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
        ],
      }),
    );

    // Internal — never exposed through the API. Hooks bypass these rules.
    const c = app.findCollectionByNameOrId("idempotency_keys");
    c.listRule = null;
    c.viewRule = null;
    c.createRule = null;
    c.updateRule = null;
    c.deleteRule = null;
    app.save(c);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("idempotency_keys"));
  },
);
