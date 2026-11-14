/// <reference path="../pb_data/types.d.ts" />

// federfall-lebw — add `request_hash` to idempotency_keys.
//
// Its own migration rather than an edit to 1700000050, because that one has
// been applied: a migration is a historical fact, and editing an applied file
// produces a database no other machine can reach.
//
// ── What the field is for ──────────────────────────────────────────────────
//
// An idempotency key makes a retry safe by answering with the stored response
// instead of writing twice. But the key alone does not say WHICH request it
// stands for. The app keeps one key per screen/sheet and rebuilds the body on
// every submit, so: an intake times out but commits, the carer corrects the
// weight, taps save again — and the route replays the first response. The
// correction is never written, the app reports success, and nothing anywhere
// says so.
//
// With a fingerprint of the body stored beside the key, that retry is a 409
// the client can explain. lib_idempotency.js computes and checks it for every
// keyed route (intake, prescribe-batch, administer-batch, vaccinate-batch).
//
// Not required, and empty on every row written before this migration: those
// keep replaying on the key alone, exactly as they did — they expire within a
// day anyway (the purge cron in intake.pb.js).

migrate(
  (app) => {
    const collection = app.findCollectionByNameOrId("idempotency_keys");
    collection.fields.add(
      new TextField({
        name: "request_hash",
        required: false,
        // A hex SHA-256 is 64 characters; the headroom costs nothing.
        max: 80,
      }),
    );
    app.save(collection);
  },
  (app) => {
    const collection = app.findCollectionByNameOrId("idempotency_keys");
    collection.fields.removeByName("request_hash");
    app.save(collection);
  },
);
