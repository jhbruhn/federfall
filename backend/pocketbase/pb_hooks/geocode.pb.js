/// <reference path="../pb_data/types.d.ts" />

// FED-4.2 — geocoding proxy. The app never calls a geocoder directly; it calls
// these auth-only routes, which forward to a configurable Nominatim-compatible
// service and return a normalized shape. Routing through the backend keeps the
// contact/User-Agent + any API key server-side and avoids browser CORS.
//
// Configurable via env:
//   FEDERFALL_NOMINATIM_URL    base URL (default public OSM Nominatim — note
//                              the public server blocks most server traffic;
//                              point this at a self-hosted instance or a
//                              permitted mirror for real use, see FED-8.6)
//   FEDERFALL_GEOCODER_KEY     optional API key, appended as &api_key= (for
//                              keyed Nominatim mirrors)
//   FEDERFALL_USER_AGENT       User-Agent sent upstream (default "Federfall/1.0")
//
// PocketBase runs each route handler in an isolated JSVM context, so it cannot
// see file-level helpers — everything a handler needs is defined inside it.

// Forward geocode: address → candidates.
routerAdd(
  "GET",
  "/api/federfall/geocode",
  (e) => {
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

    const q = e.request.url.query().get("q");
    if (!q) return e.json(400, { error: "missing q" });

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
      return e.json(502, { error: "geocoder unavailable" });
    }

    return e.json(200, { results: (res.json || []).map(toResult) });
  },
  $apis.requireAuth(),
);

// Reverse geocode: pin → address.
routerAdd(
  "GET",
  "/api/federfall/geocode/reverse",
  (e) => {
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

    const query = e.request.url.query();
    const lat = query.get("lat");
    const lon = query.get("lon");
    if (!lat || !lon) return e.json(400, { error: "missing lat/lon" });

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

    return e.json(200, { result: toResult(res.json) });
  },
  $apis.requireAuth(),
);
