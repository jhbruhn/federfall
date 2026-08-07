/// <reference path="../pb_data/types.d.ts" />

// The ONE writer of `settings.rateLimits` (federfall-0tf, federfall-sjtg,
// federfall-ds0d). PocketBase's own limiter is configured through settings, so
// every budget this app wants has to be merged into a single stored ruleset —
// which is why this lives in its own file rather than beside the routes it
// protects. Two hooks each rewriting that list is how a rule gets silently
// dropped.
//
// ── The budgets ─────────────────────────────────────────────────────────────
//
// geocode (federfall-0tf) — the cache absorbs repeats, but unique queries are
// relayed upstream. Against public OSM Nominatim (1 req/s policy) a batch
// extraction could get the whole instance blocked.
//
// reports (federfall-ds0d) — GET /api/federfall/reports/annual and
// GET /api/federfall/cases/{id}/report.pdf each shell out to `typst compile`,
// synchronously, once per request. Nothing else in this app spawns a
// subprocess. The case report is gated by requireMember, i.e. ANY active
// non-guest member for any case they can view, so one authenticated account
// looping that URL spawns one process per request and can exhaust CPU and temp
// space on the small self-hosted boxes this is built for. The budget is what
// makes that loop cost the attacker time instead of the server.
//
// Both are deliberately burst-friendly: a carer searching a few addresses, or
// printing a receipt per intake and pulling the annual report twice, never
// comes near them. What they cap is SUSTAINED volume.
//
// ── Env ─────────────────────────────────────────────────────────────────────
//   FEDERFALL_GEOCODE_RATE_MAX      requests per window (default 30; 0 disables)
//   FEDERFALL_GEOCODE_RATE_WINDOW   window in seconds (default 60)
//   FEDERFALL_REPORT_RATE_MAX       requests per window (default 20; 0 disables)
//   FEDERFALL_REPORT_RATE_WINDOW    window in seconds (default 60)
//   FEDERFALL_RATE_LIMITS_DISABLED  "1" to leave settings.rateLimits entirely
//                                   alone (for an instance limited at the proxy)
//
// Disabling ONE group removes its rules rather than leaving the last applied
// ones stored, but does not touch the limiter itself or the defaults below —
// opting out of the geocode budget must not be a way to lose the brute-force
// brake on auth-with-password by accident. That is what the last variable is
// for, and it is deliberately the only way to get there.
//
// ── Why the factory defaults are restored on every boot ─────────────────────
// An earlier version of this code (then living in geocode.pb.js, federfall-sjtg)
// built the ruleset from a "clean slate", discarding PocketBase's inactive
// factory defaults on its way to enabling the limiter — shipping instances
// whose ONLY throttled paths were the geocode routes, i.e. no brute-force brake
// on auth-with-password at all. Any instance that ever booted that version has
// the defaults gone from its STORED settings, so preserving what is there is
// not enough: every factory rule whose label is absent is put back. To neuter
// one deliberately, raise its maxRequests — a deleted default comes back on the
// next boot. An operator's own edit under a factory label wins, because the
// restore only fills in labels that are missing.
//
// ── The limiter keys on client IP ───────────────────────────────────────────
// Not on the authenticated user, even for the auth-only routes above. Behind a
// reverse proxy that IP is the proxy's own unless FEDERFALL_TRUSTED_PROXY_HEADERS
// is set (settings.pb.js, federfall-223) — without it a budget is shared by ALL
// users instead of per client. It also means one account spread over many
// addresses is not what this stops; it raises the cost of the loop, it is not
// an authorization boundary.

onBootstrap((e) => {
  e.next();

  if ($os.getenv("FEDERFALL_RATE_LIMITS_DISABLED") === "1") {
    e.app
      .logger()
      .warn("federfall: rate limits not applied (FEDERFALL_RATE_LIMITS_DISABLED)");
    return;
  }

  const num = (key, fallback) => {
    const raw = $os.getenv(key);
    const n = parseInt(raw && raw !== "" ? raw : "", 10);
    return isNaN(n) ? fallback : n;
  };
  const windowOf = (key, fallback) => {
    const n = num(key, fallback);
    return n <= 0 ? fallback : n;
  };

  // ── Every label is METHOD-QUALIFIED, and that is load-bearing ─────────────
  //
  // PocketBase treats a label ending in "/" as a path PREFIX and anything else
  // as a complete path — but a bare prefix is NOT enough here, because matching
  // is not longest-prefix-wins. Probed against 0.39.8: for each search label
  // ("GET <path>" first, then "<path>") an exact rule wins, and failing that
  // the FIRST prefix rule in stored order does. The factory `/api/` default is
  // a prefix rule and it is stored ahead of these, so a bare
  // "/api/federfall/cases/" silently loses to it and budgets nothing —
  // "/api/federfall/geocode/" had been dead that way since federfall-0tf,
  // leaving reverse geocoding on the 300-per-10s general default while the
  // comment beside it claimed otherwise.
  //
  // "GET /api/federfall/cases/" is matched against the FIRST search label,
  // which "/api/" cannot prefix (it starts with "GET "), so the order of the
  // stored list stops mattering. Every route below is GET-only.
  //
  // The two prefixes are exact in reach: one route lives under
  // ".../cases/" (report.pdf) and one under ".../reports/" (annual).
  //
  // This list is every label the hook owns whether or not it ends up applied —
  // a group that is switched off has to have its stored rules dropped too.
  const groups = [
    {
      name: "geocode",
      labels: ["GET /api/federfall/geocode", "GET /api/federfall/geocode/"],
      maxRequests: num("FEDERFALL_GEOCODE_RATE_MAX", 30),
      duration: windowOf("FEDERFALL_GEOCODE_RATE_WINDOW", 60),
    },
    {
      name: "reports",
      labels: ["GET /api/federfall/reports/", "GET /api/federfall/cases/"],
      maxRequests: num("FEDERFALL_REPORT_RATE_MAX", 20),
      duration: windowOf("FEDERFALL_REPORT_RATE_WINDOW", 60),
    },
  ];

  // The unqualified labels earlier versions stored. They are inert, but left
  // alone they would sit in the settings forever looking like a budget.
  const legacy = [
    "/api/federfall/geocode",
    "/api/federfall/geocode/",
    "/api/federfall/reports/",
    "/api/federfall/cases/",
  ];

  const ours = legacy.slice();
  for (let i = 0; i < groups.length; i++) {
    for (let j = 0; j < groups[i].labels.length; j++) ours.push(groups[i].labels[j]);
  }

  const settings = e.app.settings();
  const others = (settings.rateLimits.rules || []).filter(
    (r) => ours.indexOf(String(r.label)) < 0,
  );

  // PocketBase 0.39's factory defaults, probed from a pristine instance.
  const factory = [
    { label: "*:auth", audience: "", duration: 3, maxRequests: 2 },
    { label: "*:create", audience: "", duration: 5, maxRequests: 20 },
    { label: "/api/batch", audience: "", duration: 1, maxRequests: 3 },
    { label: "/api/", audience: "", duration: 10, maxRequests: 300 },
  ];
  const present = others.map((r) => String(r.label));
  const restored = factory.filter((d) => present.indexOf(d.label) < 0);

  let applied = others.concat(restored);
  const enabled = [];
  for (let i = 0; i < groups.length; i++) {
    const g = groups[i];
    if (g.maxRequests <= 0) continue; // explicit opt-out
    applied = applied.concat(
      g.labels.map((l) => ({
        label: l,
        audience: "",
        duration: g.duration,
        maxRequests: g.maxRequests,
      })),
    );
    enabled.push(g.name + "=" + g.maxRequests + "/" + g.duration + "s");
  }

  settings.rateLimits.enabled = true;
  settings.rateLimits.rules = applied;
  e.app.save(settings);
  e.app
    .logger()
    .info(
      "federfall: rate limits applied",
      "budgets",
      enabled.length > 0 ? enabled.join(" ") : "none (defaults only)",
    );
});
