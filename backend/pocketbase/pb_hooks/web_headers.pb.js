/// <reference path="../pb_data/types.d.ts" />

// Security headers for the Flutter WASM SPA (and uploaded files).
//
// ── Content-Security-Policy (federfall-jfe) ───────────────────────────────────
//
// The web build stores the auth token in localStorage (federfall-xe9), so XSS
// is the attack that matters — CSP is the mitigation that caps its blast
// radius. The SPA is fully same-origin by construction: the bundle is built
// with --no-web-resources-cdn (no gstatic canvaskit), index.html loads
// flutter_bootstrap.js as an external file (no inline script), Roboto is a
// bundled asset font (pubspec.yaml — the engine would otherwise download it
// from fonts.gstatic.com at startup), and the API is the serving origin
// itself. The only cross-origin traffic left is map tiles.
//
// Known tradeoff: the engine also fetches per-glyph Noto FALLBACK fonts from
// fonts.gstatic.com for glyphs no bundled font covers (mainly emoji in
// user-entered text). This policy blocks that — such glyphs render as boxes
// on web. Operators who prefer emoji over strict same-origin can set
// FEDERFALL_CSP and append https://fonts.gstatic.com to font-src/connect-src.
//
//   script-src 'self' 'wasm-unsafe-eval'  wasm-unsafe-eval is what lets the
//                                         browser instantiate the dart2wasm /
//                                         skwasm modules; no eval, no inline.
//   style-src  'unsafe-inline'            the Flutter engine injects its style
//                                         elements at runtime — required.
//   img-src / connect-src + tile origins  flutter_map fetches tiles as images
//                                         (JS renderer) or via fetch (wasm).
//   connect-src blob:                     image_picker_for_web hands the picked
//                                         file back as a blob: URL; reading its
//                                         bytes is a fetch of that URL. blob:
//                                         URLs are minted by the page itself and
//                                         origin-bound, so this allows nothing
//                                         cross-origin.
//   worker-src 'self' blob:               skwasm's render workers.
//   frame-ancestors 'none'                no embedding → no clickjacking.
//
// Env:
//   FEDERFALL_MAP_TILE_ORIGINS  comma list of tile-server origins to allow
//                               (default https://tile.openstreetmap.org, the
//                               production MAP_TILE_URL). Must match the
//                               MAP_TILE_URL the web bundle was built with.
//   FEDERFALL_CSP               full replacement policy for the SPA, for
//                               operators whose setup needs more; "off"
//                               disables the header entirely.
//
// Uploaded files (/api/files/…) get their own lockdown header: `sandbox` +
// default-src 'none' means a file that slips past the upload MIME allowlist
// (federfall-8a5) and is opened inline still cannot run script against the
// app origin; nosniff stops MIME guessing on top.
//
// ── Cross-origin isolation (COOP/COEP) ────────────────────────────────────────
//
// The web bundle is built with `flutter build web --wasm` (see the repo
// Dockerfile). Its skwasm renderer wants a cross-origin-isolated context to use
// threads (SharedArrayBuffer), which the browser only grants when the document
// is served with COOP + COEP. We set them here so the single-container stack —
// PocketBase serving the SPA from --publicDir — needs no reverse proxy.
//
// COEP value = "credentialless" (not "require-corp") on purpose: the app loads
// cross-origin map tiles (MAP_TILE_URL), and require-corp would BLOCK any
// cross-origin subresource that doesn't send CORP/CORS headers. credentialless
// still enables crossOriginIsolated but fetches such no-cors resources without
// credentials, so the public tiles keep loading. Everything else the app needs
// (API, /api/files images, the wasm/canvaskit assets) is same-origin.
//
// Scope: only the SPA. The PocketBase REST API (/api/…) and Admin UI (/_/…) are
// left untouched, so isolation can never interfere with them.
//
// Graceful by design: a browser without credentialless support (older Safari)
// simply isn't isolated, and Flutter falls back to the single-threaded
// renderer — the app still works, just without the threaded fast path.
//
// PocketBase runs each hook callback in an isolated JSVM context, so everything
// the middleware needs is defined inside it (no file-level helpers in scope).
routerUse((e) => {
  const path = e.request.url.path;

  // Uploaded files: never let a served file act as a document of this origin.
  if (path.startsWith("/api/files/")) {
    const h = e.response.header();
    h.set("Content-Security-Policy", "default-src 'none'; sandbox");
    h.set("X-Content-Type-Options", "nosniff");
    return e.next();
  }

  if (!path.startsWith("/api/") && !path.startsWith("/_/")) {
    const h = e.response.header();
    h.set("Cross-Origin-Opener-Policy", "same-origin");
    h.set("Cross-Origin-Embedder-Policy", "credentialless");

    const cspEnv = $os.getenv("FEDERFALL_CSP") || "";
    if (cspEnv.toLowerCase() !== "off") {
      let csp = cspEnv;
      if (!csp) {
        const tiles = ($os.getenv("FEDERFALL_MAP_TILE_ORIGINS") ||
          "https://tile.openstreetmap.org")
          .split(",")
          .map((s) => s.trim())
          .filter((s) => s !== "")
          .join(" ");
        csp = [
          "default-src 'self'",
          "script-src 'self' 'wasm-unsafe-eval'",
          "style-src 'self' 'unsafe-inline'",
          "img-src 'self' blob: data: " + tiles,
          "font-src 'self'",
          "connect-src 'self' blob: " + tiles,
          "worker-src 'self' blob:",
          "object-src 'none'",
          "base-uri 'self'",
          "frame-ancestors 'none'",
          "form-action 'self'",
        ].join("; ");
      }
      h.set("Content-Security-Policy", csp);
    }
    h.set("X-Content-Type-Options", "nosniff");
    // same-origin: cross-origin navigations get no Referer at all; same-origin
    // ones still get the full URL (harmless — it's our own origin).
    h.set("Referrer-Policy", "same-origin");
    // Deny everything except the device features intake photo capture and
    // location tagging actually use, and only for this origin (no iframes).
    h.set(
      "Permissions-Policy",
      "camera=(self), geolocation=(self), microphone=(), " +
        "payment=(), usb=(), magnetometer=(), gyroscope=()",
    );
  }
  return e.next();
});
