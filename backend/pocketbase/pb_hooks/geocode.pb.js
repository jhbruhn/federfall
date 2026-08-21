/// <reference path="../pb_data/types.d.ts" />

// The geocode proxy: address → coordinates and back, through this server rather
// than from the browser.
//
// zv_geocode_route.js holds both handlers, the cache purge and the reasons — why
// a coordinate must be a plain number before it reaches the upstream URL, why
// one rounded pair feeds both the cache key and the query, and why an
// unreachable upstream is a 502 rather than the 400 an uncaught throw produces
// (a 400 tells the user their address was malformed when it was fine).
//
// The rate limit for these routes is applied by rate_limits.pb.js, not here.
//
// `walledOffRole: "guest"` is the one piece of app vocabulary: a guest is walled
// off from every collection, but could still drive the geocoder and burn the
// upstream budget — the one thing an access rule cannot stop, because there is
// no record to scope.

routerAdd(
  "GET",
  "/api/federfall/geocode",
  (e) =>
    require(`${__hooks}/zv_geocode_route.js`).forward(e, {
      envPrefix: "FEDERFALL",
      walledOffRole: "guest",
    }),
  $apis.requireAuth(),
);

routerAdd(
  "GET",
  "/api/federfall/geocode/reverse",
  (e) =>
    require(`${__hooks}/zv_geocode_route.js`).reverse(e, {
      envPrefix: "FEDERFALL",
      walledOffRole: "guest",
    }),
  $apis.requireAuth(),
);

// federfall-509 — expired rows daily. Keeps the table bounded and stops a stale
// answer outliving its usefulness.
cronAdd("geocodeCachePurge", "0 4 * * *", () =>
  require(`${__hooks}/zv_geocode_route.js`).purgeCache(),
);
