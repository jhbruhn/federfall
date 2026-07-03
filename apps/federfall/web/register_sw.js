// Registers our own minimal service worker (sw.js) instead of relying on
// Flutter's bootstrap, which — as of the flutter_service_worker.js
// deprecation (https://github.com/flutter/flutter/issues/156910) — either
// registers a self-unregistering "cleanup" worker or none at all. See
// web/flutter_bootstrap.js and web/sw.js for why this matters (Firefox for
// Android PWA installability).
'use strict';

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js');
  });
}
