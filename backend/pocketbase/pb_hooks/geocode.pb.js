/// <reference path="../pb_data/types.d.ts" />

// FED-4.2 — geocoding proxy. The app never calls a geocoder directly; it calls
// these auth-only routes, which forward to a configurable Nominatim-compatible
// service and return a normalized shape. Routing through the backend keeps the
// contact/User-Agent + any API key server-side and avoids browser CORS.
//
// federfall-509 — every successful lookup is cached in the `geocode_cache`
// collection and served from there until it expires. Nominatim's usage policy
// *requires* caching, and the public server rate-limits repeated queries; the
// cache also cuts latency to a local DB read. Cache keys are normalized so
// equivalent inputs collapse to one entry (see normalizeKey in each handler).
// Negative ("not found") results are cached too, but with a short TTL so newly
// added addresses are retried soon. The cache is internal: the collection's API
// rules are null, so only these hooks (via $app.save, which bypasses rules) ever
// touch it. A daily cron purges expired rows.
//
// Configurable via env:
//   FEDERFALL_NOMINATIM_URL    base URL (default public OSM Nominatim; point
//                              this at a self-hosted instance or a permitted
//                              mirror for heavier use, see FED-8.6)
//   FEDERFALL_GEOCODER_KEY     optional API key, appended as &api_key= (for
//                              keyed Nominatim mirrors)
//   FEDERFALL_USER_AGENT       User-Agent sent upstream (default "Federfall/1.0")
//   FEDERFALL_GEOCODE_CACHE_DISABLED       "1" to bypass the cache entirely
//   FEDERFALL_GEOCODE_CACHE_TTL_DAYS       positive-result TTL (default 30)
//   FEDERFALL_GEOCODE_CACHE_NEG_TTL_HOURS  empty-result TTL (default 24)
//   FEDERFALL_GEOCODE_RATE_MAX             requests allowed per window per
//                                          client IP (default 30; 0 disables)
//   FEDERFALL_GEOCODE_RATE_WINDOW          window length in seconds (default 60)
// The last two are read by rate_limits.pb.js, which owns every rate-limit rule
// this app applies; see the note at the bottom of this file.
//
// PocketBase runs each route handler in an isolated JSVM context, so it cannot
// see file-level helpers — but a `require()`d module IS shared across those
// contexts, which is how the cache, the result normalization and the upstream
// config live in ONE place (`lib_geocode.js`, federfall-185w) instead of being
// written out once per handler. Anything else a handler needs is defined inside
// it.

// Forward geocode: address → candidates.
routerAdd(
  "GET",
  "/api/federfall/geocode",
  (e) => {
    // Guests are walled off from all data everywhere else; without this check
    // they could still drive the server-side geocoder and burn the upstream
    // Nominatim budget (federfall-2asj).
    if (e.auth && e.auth.getString("role") === "guest") {
      throw new ForbiddenError("Not allowed.");
    }
    const geo = require(`${__hooks}/lib_geocode.js`);
    const up = geo.upstream();

    const q = e.request.url.query().get("q");
    if (!q) return e.json(400, { error: "missing q" });
    // No legitimate address needs more — an unbounded q would be relayed
    // verbatim to the upstream geocoder (federfall-0tf).
    if (q.length > 256) return e.json(400, { error: "q too long" });
    // Normalization: lowercase + collapse whitespace so "Berlin" / "  berlin "
    // share one entry.
    const cacheKey = q.trim().toLowerCase().replace(/\s+/g, " ");
    if (!cacheKey) return e.json(400, { error: "missing q" });

    const cached = geo.cacheGet(e.app, "forward", cacheKey);
    if (cached !== null) return e.json(200, cached);

    // $http.send THROWS on a connection-level failure (refused, DNS, timeout)
    // rather than returning a status, and an uncaught throw here is rendered as
    // a generic 400 — telling the client its request was bad when the request
    // was fine and the geocoder was unreachable. That is the likeliest failure
    // of all, since FEDERFALL_NOMINATIM_URL is operator-set. Same 502 as an
    // upstream error status, and likewise never cached.
    let res;
    try {
      res = $http.send({
        url:
          up.base +
          "/search?format=jsonv2&addressdetails=1&limit=5&q=" +
          encodeURIComponent(q) +
          (up.key ? "&api_key=" + encodeURIComponent(up.key) : ""),
        method: "GET",
        headers: { "User-Agent": up.ua },
        timeout: 10,
      });
    } catch (err) {
      $app
        .logger()
        .warn(
          "geocoder forward unreachable",
          "err",
          String(err),
          "base",
          up.base,
        );
      return e.json(502, { error: "geocoder unavailable" });
    }
    if (res.statusCode !== 200) {
      $app
        .logger()
        .warn(
          "geocoder forward failed",
          "status",
          res.statusCode,
          "base",
          up.base,
        );
      // Don't cache upstream failures — a transient outage must not be stored
      // as "not found".
      return e.json(502, { error: "geocoder unavailable" });
    }

    const results = (res.json || []).map(geo.toResult);
    const payload = { results: results };
    geo.cachePut(e.app, "forward", cacheKey, payload, results.length);
    return e.json(200, payload);
  },
  $apis.requireAuth(),
);

// Reverse geocode: pin → address.
routerAdd(
  "GET",
  "/api/federfall/geocode/reverse",
  (e) => {
    // Guests are walled off from all data everywhere else; without this check
    // they could still drive the server-side geocoder and burn the upstream
    // Nominatim budget (federfall-2asj).
    if (e.auth && e.auth.getString("role") === "guest") {
      throw new ForbiddenError("Not allowed.");
    }
    const geo = require(`${__hooks}/lib_geocode.js`);
    const up = geo.upstream();

    const query = e.request.url.query();
    const lat = query.get("lat");
    const lon = query.get("lon");
    if (!lat || !lon) return e.json(400, { error: "missing lat/lon" });
    // federfall-185w — a coordinate must be a plain number, not merely
    // something parseFloat can salvage: `52.5abc` passed parseFloat + isFinite
    // and was then relayed upstream verbatim. Forwarding the parsed pair below
    // already stops that from splitting a cache entry, but garbage in a
    // coordinate means the caller is confused, and saying so beats silently
    // geocoding a different point from the one asked about. Exponent form is
    // accepted because Dart's `double.toString()` can emit it.
    const NUMERIC = /^[+-]?\d+(\.\d+)?([eE][+-]?\d+)?$/;
    if (!NUMERIC.test(lat.trim()) || !NUMERIC.test(lon.trim())) {
      return e.json(400, { error: "invalid lat/lon" });
    }
    const latN = parseFloat(lat);
    const lonN = parseFloat(lon);
    if (
      !isFinite(latN) ||
      !isFinite(lonN) ||
      latN < -90 ||
      latN > 90 ||
      lonN < -180 ||
      lonN > 180
    ) {
      return e.json(400, { error: "invalid lat/lon" });
    }
    // Normalization: round to ~1m so near-identical pins share one entry.
    //
    // federfall-185w — ONE rounded pair feeds both the cache key and the
    // upstream query, so an entry cannot describe a different point from the one
    // that was asked about. It used to validate the PARSED coordinate and
    // forward the RAW string, which meant `lat=52.5abc` survived
    // parseFloat + isFinite, was keyed as "52.50000", and was then relayed
    // verbatim — two different upstream queries sharing one entry, whichever
    // landed first winning it.
    const latQ = latN.toFixed(5);
    const lonQ = lonN.toFixed(5);
    const cacheKey = latQ + "," + lonQ;

    const cached = geo.cacheGet(e.app, "reverse", cacheKey);
    if (cached !== null) return e.json(200, cached);

    // As on the forward route: a connection-level failure throws, and an
    // uncaught throw would report a fine request as a 400.
    let res;
    try {
      res = $http.send({
        url:
          up.base +
          "/reverse?format=jsonv2&addressdetails=1&lat=" +
          encodeURIComponent(latQ) +
          "&lon=" +
          encodeURIComponent(lonQ) +
          (up.key ? "&api_key=" + encodeURIComponent(up.key) : ""),
        method: "GET",
        headers: { "User-Agent": up.ua },
        timeout: 10,
      });
    } catch (err) {
      $app
        .logger()
        .warn(
          "geocoder reverse unreachable",
          "err",
          String(err),
          "base",
          up.base,
        );
      return e.json(502, { error: "geocoder unavailable" });
    }
    if (res.statusCode !== 200) {
      $app
        .logger()
        .warn(
          "geocoder reverse failed",
          "status",
          res.statusCode,
          "base",
          up.base,
        );
      return e.json(502, { error: "geocoder unavailable" });
    }

    // Nominatim returns 200 with {error: "Unable to geocode"} when nothing is
    // found — treat that as a (cacheable) negative result, not an address.
    const raw = res.json || {};
    const found = !raw.error && raw.lat != null;
    const payload = { result: found ? geo.toResult(raw) : null };
    geo.cachePut(e.app, "reverse", cacheKey, payload, found ? 1 : 0);
    return e.json(200, payload);
  },
  $apis.requireAuth(),
);

// federfall-509 — purge expired cache rows daily. Keeps the table bounded and
// guarantees stale entries eventually disappear even if they're never re-queried
// (a re-query refreshes in place; this is for the long tail that isn't). The
// handler runs in its own JSVM context, so everything it needs is defined here.
cronAdd("geocodeCachePurge", "0 4 * * *", () => {
  const PAGE = 500;
  const now = new Date().toISOString().replace("T", " ");
  let purged = 0;
  let offset = 0;
  // Re-query from the same offset each round: deleting shrinks the result set,
  // so the next page of still-expired rows slides back to the front.
  //
  // federfall-ex20 — but only rows that ACTUALLY went away slide. A row whose
  // delete keeps failing (locked, or held by a constraint) stays in the filter
  // at the same position, and with a fixed offset of 0 a full page of those
  // refills the batch forever: `batch.length < PAGE` never becomes true and the
  // cron spins until the process is killed. Advancing past a page that removed
  // nothing steps over the stuck rows instead — the same guard
  // finder_retention.pb.js uses.
  for (;;) {
    let batch;
    try {
      batch = $app.findRecordsByFilter(
        "geocode_cache",
        "expires_at < {:now}",
        "expires_at",
        PAGE,
        offset,
        { now: now },
      );
    } catch (_) {
      break;
    }
    if (!batch || batch.length === 0) break;
    let purgedThisBatch = 0;
    for (let i = 0; i < batch.length; i++) {
      try {
        $app.delete(batch[i]);
        purged++;
        purgedThisBatch++;
      } catch (_) {
        // skip a row already gone / locked; the next run retries it
      }
    }
    if (purgedThisBatch === 0) offset += batch.length;
    if (batch.length < PAGE) break;
  }
  if (purged > 0) {
    $app.logger().info("geocode cache purge", "removed", purged);
  }
});

// federfall-0tf — the geocode rate limit itself is applied in rate_limits.pb.js,
// with every other budget this app sets: PocketBase's limiter is configured
// through `settings.rateLimits`, one stored list, and a second hook rewriting
// that list is how a rule gets silently dropped (federfall-sjtg). The
// FEDERFALL_GEOCODE_RATE_* env vars documented at the top of this file are read
// there.
