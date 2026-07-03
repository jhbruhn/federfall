// Minimal pass-through service worker.
//
// federfall is online-only by design (see federfall-online-only-no-cache
// memory) — this SW does no caching. Its only job is to exist as an active,
// controlling worker with a `fetch` handler: Firefox for Android's PWA
// installability check requires exactly that before it will offer "Add to
// Home screen", and Flutter's own generated flutter_service_worker.js no
// longer qualifies — it unregisters itself right after activating (see
// https://github.com/flutter/flutter/issues/156910, and the comment on the
// registration in flutter_bootstrap.js).
'use strict';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request));
});
