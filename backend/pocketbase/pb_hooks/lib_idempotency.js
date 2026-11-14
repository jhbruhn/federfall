/// <reference path="../pb_data/types.d.ts" />

// federfall-3ty3 + federfall-lebw — replay protection for the keyed write
// routes, written once.
//
// Usage — `require()` INSIDE the handler (see lib_auth.js), once the body has
// been validated:
//
//   const idem = require(`${__hooks}/lib_idempotency.js`);
//   const idemKey = idem.keyOf(body);
//   const idemHash = idem.fingerprint(body);
//   if (idemKey) {
//     const prior = idem.replay(e.app, "vaccinate_batch", auth.id, idemKey, idemHash);
//     if (prior !== null) return e.json(200, prior);
//   }
//   e.app.runInTransaction((tx) => {
//     ...the writes...
//     idem.remember(tx, "vaccinate_batch", auth.id, idemKey, idemHash, response);
//   });
//
// Used by intake.pb.js, prescribe_batch.pb.js, administer_batch.pb.js and
// vaccinate_batch.pb.js. It was four hand-rolled copies of the same lookup and
// insert, and the fix below has to reach all four at once or the one left out
// keeps swallowing corrections.
//
// ── The key alone is not enough (federfall-lebw) ────────────────────────────
//
// The client keeps ONE key per screen/sheet and rebuilds the body on every
// submit. If a request times out but committed, and the user corrects
// something before retrying, a lookup by key alone replays the FIRST response:
// the correction is never written and the app reports success for a body the
// server never saw. So the key is stored with a fingerprint of the body, and a
// replay whose body differs is refused with a 409 instead.
//
// A stored key means the first request COMMITTED — the row is written in the
// same transaction as the records. So the 409 is not "something went wrong",
// it is "your first attempt landed, with its values, and this one did not".
// The client says exactly that and lets the user decide whether a second,
// separate write is what they want (with a fresh key).
//
// ── How the client recognises it ───────────────────────────────────────────
//
// By the STATUS: nothing else on these routes answers 409. The code also rides
// in `data` as a KEY (`idempotency_key_reused`), because PocketBase rewrites
// both `message` (capitalised, full-stopped) and every `data` VALUE, and the
// key is the one part that survives verbatim (zugvogel_data's
// RepositoryException documents the measurement). Renaming it is a wire
// change.
//
// ── Rows without a hash ─────────────────────────────────────────────────────
//
// Rows written before 1700000095 have an empty `request_hash` and keep
// replaying on the key alone — refusing them would turn a retry that worked
// yesterday into an error, for at most a day until the purge reaps them.
//
// STATELESS (see lib_audit.js): each pooled JSVM holds its own instance.

/** Body keys that are never part of the fingerprint. */
const UNHASHED = [
  // The key itself: it is what the row is looked up BY, so hashing it adds
  // nothing, and leaving it out keeps the fingerprint a statement about the
  // request's content alone.
  "idempotency_key",
  // A multipart request's JSON travels in this field and PocketBase merges its
  // fields into the body, which is what gets hashed. Should the raw string
  // also appear, it would hash the CLIENT's serialisation (key order and all),
  // so an identical retry could mismatch on formatting alone.
  "@jsonPayload",
];

/**
 * The same value with object keys sorted at every level.
 *
 * `JSON.stringify` alone is NOT stable here: `e.requestInfo().body` is a Go
 * `map[string]any`, and Go randomises map iteration order deliberately, so the
 * same bytes from the client serialise to a different key order on every
 * request — a legitimate retry would look like a different body and answer
 * 409 (eiermann hit exactly this). Sorting fixes it, and a client that reorders
 * its own JSON between attempts still matches. Arrays keep their order: the
 * order of the birds in a batch is part of what was sent.
 */
function canonical(value) {
  if (value === null || value === undefined || typeof value !== "object") {
    return value;
  }
  if (Array.isArray(value)) return value.map(canonical);
  const out = {};
  for (const key of Object.keys(value).sort()) out[key] = canonical(value[key]);
  return out;
}

/**
 * Hex SHA-256 of the request [body] (minus the [UNHASHED] keys and any
 * [ignore]d ones), plus [extra] — what a route wants fingerprinted that is not
 * in the body, e.g. a description of the uploaded files.
 */
function fingerprint(body, extra, ignore) {
  const skip = UNHASHED.concat(ignore || []);
  const hashed = {};
  const src = body || {};
  for (const key of Object.keys(src)) {
    if (skip.indexOf(key) === -1) hashed[key] = src[key];
  }
  const payload = { body: hashed };
  if (extra !== undefined) payload.extra = extra;
  return $security.sha256(JSON.stringify(canonical(payload)));
}

/** The trimmed idempotency key from [body] ("" if none), or a 400. */
function keyOf(body) {
  const raw = body ? body.idempotency_key : null;
  const key = raw === undefined || raw === null ? "" : String(raw).trim();
  if (key.length > 64) throw new BadRequestError("idempotency_key too long.");
  return key;
}

/**
 * The stored response for (endpoint, user, key), or null when there is none.
 *
 * Throws a 409 if the stored row carries a fingerprint and [hash] differs —
 * see the header for why answering with the first response would be wrong.
 */
function replay(app, endpoint, userId, key, hash) {
  if (!key) return null;
  let prior = null;
  try {
    prior = app.findFirstRecordByFilter(
      "idempotency_keys",
      "endpoint = {:e} && user = {:u} && key = {:k}",
      { e: endpoint, u: userId, k: key },
    );
  } catch (_) {
    return null; // no prior request with this key — proceed normally
  }
  const stored = String(prior.getString("request_hash") || "");
  if (stored && stored !== hash) {
    throw new ApiError(409, "idempotency key reused with a different body", {
      idempotency_key_reused: 1,
    });
  }
  // JSONRaw goes straight back to Go; reading into it in JS would yield a byte
  // array (federfall-jumi).
  return prior.get("response");
}

/**
 * Stores [response] under the key, in the caller's transaction [tx]: either the
 * writes and the key commit together, or neither does. The unique
 * (endpoint, user, key) index makes a concurrent duplicate roll back whole.
 */
function remember(tx, endpoint, userId, key, hash, response) {
  if (!key) return;
  const row = new Record(tx.findCollectionByNameOrId("idempotency_keys"));
  row.set("endpoint", endpoint);
  row.set("key", key);
  row.set("user", userId);
  row.set("request_hash", hash);
  row.set("response", response);
  // Retry protection only needs to outlive a retry window; the purge cron in
  // intake.pb.js reaps expired rows for every endpoint. PB compares
  // "YYYY-MM-DD HH:MM:SS".
  row.set(
    "expires_at",
    new Date(Date.now() + 24 * 3600000).toISOString().replace("T", " "),
  );
  tx.save(row);
}

module.exports = { canonical, fingerprint, keyOf, replay, remember };
