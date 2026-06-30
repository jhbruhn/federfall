/// <reference path="../pb_data/types.d.ts" />

// Cross-origin isolation for the Flutter WASM SPA.
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
  if (!path.startsWith("/api/") && !path.startsWith("/_/")) {
    const h = e.response.header();
    h.set("Cross-Origin-Opener-Policy", "same-origin");
    h.set("Cross-Origin-Embedder-Policy", "credentialless");
  }
  return e.next();
});
