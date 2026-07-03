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
//
// PocketBase runs each route handler in an isolated JSVM context, so it cannot
// see file-level helpers — everything a handler needs is defined inside it
// (hence the cache + normalization helpers are duplicated across handlers).

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
    const base =
      $os.getenv("FEDERFALL_NOMINATIM_URL") ||
      "https://nominatim.openstreetmap.org";
    const key = $os.getenv("FEDERFALL_GEOCODER_KEY") || "";
    const ua = $os.getenv("FEDERFALL_USER_AGENT") || "Federfall/1.0";

    const toResult = (r) => {
      const a = r.address || {};
      const city =
        a.city || a.town || a.village || a.municipality || a.hamlet || "";
      const region = a.state || a.region || "";
      const road = a.road || a.pedestrian || a.footway || a.path || "";
      const street = road
        ? a.house_number
          ? road + " " + a.house_number
          : road
        : "";
      const locality = [a.postcode, city].filter(Boolean).join(" ");
      // Tidy "Street 8, 26125 City" rather than Nominatim's long display_name.
      const composed = [street, locality].filter(Boolean).join(", ");
      return {
        lat: parseFloat(r.lat),
        lon: parseFloat(r.lon),
        displayName: composed || r.display_name || "",
        city: city,
        region: region,
      };
    };

    // --- cache (see header) ---------------------------------------------------
    const CACHE = $os.getenv("FEDERFALL_GEOCODE_CACHE_DISABLED") !== "1";
    const TTL_DAYS =
      parseFloat($os.getenv("FEDERFALL_GEOCODE_CACHE_TTL_DAYS")) || 30;
    const NEG_TTL_HOURS =
      parseFloat($os.getenv("FEDERFALL_GEOCODE_CACHE_NEG_TTL_HOURS")) || 24;
    const DAY_MS = 86400000;
    const HOUR_MS = 3600000;
    const nowMs = new Date().getTime();
    // PocketBase stores/compares dates as "YYYY-MM-DD HH:MM:SS.sssZ".
    const pbDate = (d) => d.toISOString().replace("T", " ");

    const cacheGet = (k) => {
      if (!CACHE) return null;
      let rec;
      try {
        rec = $app.findFirstRecordByFilter(
          "geocode_cache",
          "kind = {:kind} && cache_key = {:key}",
          { kind: "forward", key: k },
        );
      } catch (_) {
        return null; // miss
      }
      const exp = new Date(
        String(rec.get("expires_at")).replace(" ", "T"),
      ).getTime();
      if (isNaN(exp) || exp <= nowMs) return null; // stale → treat as miss
      try {
        rec.set("hits", (rec.getInt("hits") || 0) + 1);
        $app.save(rec);
      } catch (_) {
        // hit accounting is best-effort; never fail a read on a write error
      }
      return rec.get("response");
    };

    const cachePut = (k, response, count) => {
      if (!CACHE) return;
      const ttlMs = count > 0 ? TTL_DAYS * DAY_MS : NEG_TTL_HOURS * HOUR_MS;
      try {
        const col = $app.findCollectionByNameOrId("geocode_cache");
        let rec;
        try {
          rec = $app.findFirstRecordByFilter(
            "geocode_cache",
            "kind = {:kind} && cache_key = {:key}",
            { kind: "forward", key: k },
          );
        } catch (_) {
          rec = new Record(col);
          rec.set("kind", "forward");
          rec.set("cache_key", k);
          rec.set("hits", 0);
        }
        rec.set("response", response);
        rec.set("result_count", count);
        rec.set("expires_at", pbDate(new Date(nowMs + ttlMs)));
        $app.save(rec);
      } catch (_) {
        // A concurrent miss may have inserted the same key first (unique-index
        // conflict), or any other write error — the response is unaffected.
      }
    };

    const q = e.request.url.query().get("q");
    if (!q) return e.json(400, { error: "missing q" });
    // No legitimate address needs more — an unbounded q would be relayed
    // verbatim to the upstream geocoder (federfall-0tf).
    if (q.length > 256) return e.json(400, { error: "q too long" });
    // Normalization: lowercase + collapse whitespace so "Berlin" / "  berlin "
    // share one entry.
    const cacheKey = q.trim().toLowerCase().replace(/\s+/g, " ");
    if (!cacheKey) return e.json(400, { error: "missing q" });

    const cached = cacheGet(cacheKey);
    if (cached !== null) return e.json(200, cached);

    const res = $http.send({
      url:
        base +
        "/search?format=jsonv2&addressdetails=1&limit=5&q=" +
        encodeURIComponent(q) +
        (key ? "&api_key=" + encodeURIComponent(key) : ""),
      method: "GET",
      headers: { "User-Agent": ua },
      timeout: 10,
    });
    if (res.statusCode !== 200) {
      $app
        .logger()
        .warn("geocoder forward failed", "status", res.statusCode, "base", base);
      // Don't cache upstream failures — a transient outage must not be stored
      // as "not found".
      return e.json(502, { error: "geocoder unavailable" });
    }

    const results = (res.json || []).map(toResult);
    const payload = { results: results };
    cachePut(cacheKey, payload, results.length);
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
    const base =
      $os.getenv("FEDERFALL_NOMINATIM_URL") ||
      "https://nominatim.openstreetmap.org";
    const key = $os.getenv("FEDERFALL_GEOCODER_KEY") || "";
    const ua = $os.getenv("FEDERFALL_USER_AGENT") || "Federfall/1.0";

    const toResult = (r) => {
      const a = r.address || {};
      const city =
        a.city || a.town || a.village || a.municipality || a.hamlet || "";
      const region = a.state || a.region || "";
      const road = a.road || a.pedestrian || a.footway || a.path || "";
      const street = road
        ? a.house_number
          ? road + " " + a.house_number
          : road
        : "";
      const locality = [a.postcode, city].filter(Boolean).join(" ");
      // Tidy "Street 8, 26125 City" rather than Nominatim's long display_name.
      const composed = [street, locality].filter(Boolean).join(", ");
      return {
        lat: parseFloat(r.lat),
        lon: parseFloat(r.lon),
        displayName: composed || r.display_name || "",
        city: city,
        region: region,
      };
    };

    // --- cache (see header) ---------------------------------------------------
    const CACHE = $os.getenv("FEDERFALL_GEOCODE_CACHE_DISABLED") !== "1";
    const TTL_DAYS =
      parseFloat($os.getenv("FEDERFALL_GEOCODE_CACHE_TTL_DAYS")) || 30;
    const NEG_TTL_HOURS =
      parseFloat($os.getenv("FEDERFALL_GEOCODE_CACHE_NEG_TTL_HOURS")) || 24;
    const DAY_MS = 86400000;
    const HOUR_MS = 3600000;
    const nowMs = new Date().getTime();
    const pbDate = (d) => d.toISOString().replace("T", " ");

    const cacheGet = (k) => {
      if (!CACHE) return null;
      let rec;
      try {
        rec = $app.findFirstRecordByFilter(
          "geocode_cache",
          "kind = {:kind} && cache_key = {:key}",
          { kind: "reverse", key: k },
        );
      } catch (_) {
        return null;
      }
      const exp = new Date(
        String(rec.get("expires_at")).replace(" ", "T"),
      ).getTime();
      if (isNaN(exp) || exp <= nowMs) return null;
      try {
        rec.set("hits", (rec.getInt("hits") || 0) + 1);
        $app.save(rec);
      } catch (_) {
        // best-effort hit accounting
      }
      return rec.get("response");
    };

    const cachePut = (k, response, count) => {
      if (!CACHE) return;
      const ttlMs = count > 0 ? TTL_DAYS * DAY_MS : NEG_TTL_HOURS * HOUR_MS;
      try {
        const col = $app.findCollectionByNameOrId("geocode_cache");
        let rec;
        try {
          rec = $app.findFirstRecordByFilter(
            "geocode_cache",
            "kind = {:kind} && cache_key = {:key}",
            { kind: "reverse", key: k },
          );
        } catch (_) {
          rec = new Record(col);
          rec.set("kind", "reverse");
          rec.set("cache_key", k);
          rec.set("hits", 0);
        }
        rec.set("response", response);
        rec.set("result_count", count);
        rec.set("expires_at", pbDate(new Date(nowMs + ttlMs)));
        $app.save(rec);
      } catch (_) {
        // unique-conflict from a concurrent miss, or other write error
      }
    };

    const query = e.request.url.query();
    const lat = query.get("lat");
    const lon = query.get("lon");
    if (!lat || !lon) return e.json(400, { error: "missing lat/lon" });
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
    const cacheKey = latN.toFixed(5) + "," + lonN.toFixed(5);

    const cached = cacheGet(cacheKey);
    if (cached !== null) return e.json(200, cached);

    const res = $http.send({
      url:
        base +
        "/reverse?format=jsonv2&addressdetails=1&lat=" +
        encodeURIComponent(lat) +
        "&lon=" +
        encodeURIComponent(lon) +
        (key ? "&api_key=" + encodeURIComponent(key) : ""),
      method: "GET",
      headers: { "User-Agent": ua },
      timeout: 10,
    });
    if (res.statusCode !== 200) {
      $app
        .logger()
        .warn("geocoder reverse failed", "status", res.statusCode, "base", base);
      return e.json(502, { error: "geocoder unavailable" });
    }

    // Nominatim returns 200 with {error: "Unable to geocode"} when nothing is
    // found — treat that as a (cacheable) negative result, not an address.
    const raw = res.json || {};
    const found = !raw.error && raw.lat != null;
    const payload = { result: found ? toResult(raw) : null };
    cachePut(cacheKey, payload, found ? 1 : 0);
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
  // Re-query from offset 0 each round: deleting shrinks the result set, so the
  // next page of still-expired rows slides back to the front.
  for (;;) {
    let batch;
    try {
      batch = $app.findRecordsByFilter(
        "geocode_cache",
        "expires_at < {:now}",
        "expires_at",
        PAGE,
        0,
        { now: now },
      );
    } catch (_) {
      break;
    }
    if (!batch || batch.length === 0) break;
    for (let i = 0; i < batch.length; i++) {
      try {
        $app.delete(batch[i]);
        purged++;
      } catch (_) {
        // skip a row already gone / locked; the next run retries it
      }
    }
    if (batch.length < PAGE) break;
  }
  if (purged > 0) {
    $app.logger().info("geocode cache purge", "removed", purged);
  }
});

// federfall-0tf — rate-limit the geocode routes. The cache absorbs repeats,
// but unique queries were relayed upstream unthrottled; against public OSM
// Nominatim (1 req/s policy) a batch extraction could get the whole instance
// blocked. The budget is deliberately burst-friendly — a carer typing a few
// address searches never hits it — while capping sustained extraction. Uses
// PocketBase's own per-client-IP rate limiter via settings, applied on every
// start like settings.pb.js.
//
// Behind a reverse proxy the "client IP" is the proxy's own address unless
// FEDERFALL_TRUSTED_PROXY_HEADERS is set (settings.pb.js, federfall-223) —
// without it this budget is shared by ALL users instead of per client.
onBootstrap((e) => {
  e.next();

  const env = (k) => {
    const v = $os.getenv(k);
    return v && v !== "" ? v : "";
  };
  const max = parseInt(env("FEDERFALL_GEOCODE_RATE_MAX"), 10);
  const maxRequests = isNaN(max) ? 30 : max;
  if (maxRequests <= 0) return; // explicit opt-out
  const win = parseInt(env("FEDERFALL_GEOCODE_RATE_WINDOW"), 10);
  const duration = isNaN(win) || win <= 0 ? 60 : win;

  // An exact-path label plus a trailing-slash prefix label: PocketBase treats
  // "/x" as a complete path and "/x/" as a prefix, so the pair covers both
  // /geocode and /geocode/reverse.
  const labels = ["/api/federfall/geocode", "/api/federfall/geocode/"];

  const settings = e.app.settings();
  // When rate limiting was off, the stored rule set is just PocketBase's
  // inactive factory default — start from a clean slate so ONLY the geocode
  // routes get limited (the suite and normal API traffic stay unthrottled).
  // When the operator already enabled it, keep their rules and merge ours in.
  const others = settings.rateLimits.enabled
    ? (settings.rateLimits.rules || []).filter(
        (r) => labels.indexOf(String(r.label)) < 0,
      )
    : [];
  settings.rateLimits.enabled = true;
  settings.rateLimits.rules = others.concat(
    labels.map((l) => ({
      label: l,
      audience: "",
      duration: duration,
      maxRequests: maxRequests,
    })),
  );
  e.app.save(settings);
  e.app
    .logger()
    .info(
      "federfall: geocode rate limit applied",
      "maxRequests",
      maxRequests,
      "windowSec",
      duration,
    );
});
