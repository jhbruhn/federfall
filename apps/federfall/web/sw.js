// No-op service worker.
//
// federfall is online-only by design (see federfall-online-only-no-cache
// memory) — this SW does no caching and never intercepts anything. Its only
// job is to exist as an active, controlling worker with a `fetch` handler:
// Firefox for Android's PWA installability check requires exactly that
// before it will offer "Add to Home screen", and Flutter's own generated
// flutter_service_worker.js no longer qualifies — it unregisters itself
// right after activating (see https://github.com/flutter/flutter/issues/
// 156910, and the comment on the registration in flutter_bootstrap.js).
// The check only requires the listener to be registered, not that it call
// respondWith — so it never touches request handling at all. An earlier
// version proxied requests via respondWith(fetch(event.request)), which hit
// a Firefox bug intercepting long-lived streaming responses (PocketBase's
// /api/realtime SSE connection): "ServiceWorker intercepted the request and
// encountered an unexpected error". Not intercepting anything sidesteps
// that whole class of bug rather than allowlisting one endpoint.
'use strict';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', () => {});
