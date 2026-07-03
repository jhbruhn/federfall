{{flutter_js}}
{{flutter_build_config}}

// Custom bootstrap template (see docs.flutter.dev/platform-integration/web/
// initialization#customize-initialization): deliberately omits
// `serviceWorkerSettings` so Flutter never registers its own
// flutter_service_worker.js. That worker is a deprecated, self-unregistering
// "cleanup" stub with no `fetch` handler (flutter/flutter#156910) — we
// register our own real one instead, see web/register_sw.js + web/sw.js.
_flutter.loader.load();
