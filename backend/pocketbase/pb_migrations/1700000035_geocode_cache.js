/// <reference path="../pb_data/types.d.ts" />

// federfall-509 — geocode_cache: a server-side cache for the Nominatim proxy
// (pb_hooks/geocode.pb.js). Nominatim's usage policy *requires* that results be
// cached rather than re-requested, and the public server aggressively rate-limits
// repeated queries — so every forward/reverse lookup is stored here and served
// from the DB until it expires.
//
// One row per normalized lookup:
//   kind         "forward" (address → candidates) or "reverse" (pin → address)
//   cache_key    the normalization of the input (see the hook for the exact
//                rules): forward = lowercased, whitespace-collapsed query;
//                reverse = "lat,lon" rounded to a fixed precision (~1m bucket)
//   response     the *normalized* payload we hand back to the app verbatim
//                ({ results: [...] } for forward, { result: {...} } for reverse)
//                — cache reads need zero transformation
//   result_count number of hits in `response` (0 = a negative/"not found" entry,
//                which the hook gives a shorter TTL so new addresses retry sooner)
//   hits         how many times this entry has been served (observability)
//   expires_at   precomputed expiry; the daily purge cron deletes rows past it
//
// Access is hook-only: all collection rules are null, so no client can read,
// poison, or scrape the cache via the API. The hook writes through $app.save,
// which bypasses rules. Self-contained migration.

migrate(
  (app) => {
    app.save(
      new Collection({
        type: "base",
        name: "geocode_cache",
        // Unique per (kind, cache_key) so the hook can upsert safely; the
        // expires_at index keeps the purge cron's range scan cheap.
        indexes: [
          "CREATE UNIQUE INDEX `idx_geocode_cache_key` ON `geocode_cache` (`kind`, `cache_key`)",
          "CREATE INDEX `idx_geocode_cache_expires` ON `geocode_cache` (`expires_at`)",
        ],
        fields: [
          {
            name: "kind",
            type: "select",
            required: true,
            maxSelect: 1,
            values: ["forward", "reverse"],
          },
          { name: "cache_key", type: "text", required: true, max: 512 },
          { name: "response", type: "json", required: true, maxSize: 200000 },
          { name: "result_count", type: "number", required: false },
          { name: "hits", type: "number", required: false },
          { name: "expires_at", type: "date", required: true },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
          { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
        ],
      }),
    );

    // Internal cache — never exposed through the API. Hooks bypass these rules.
    const c = app.findCollectionByNameOrId("geocode_cache");
    c.listRule = null;
    c.viewRule = null;
    c.createRule = null;
    c.updateRule = null;
    c.deleteRule = null;
    app.save(c);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("geocode_cache"));
  },
);
