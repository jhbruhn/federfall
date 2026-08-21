/// <reference path="../pb_data/types.d.ts" />

// Security headers for the Flutter WASM SPA and for uploaded files.
//
// The policy itself is zv_web_headers.js, and so is the reasoning behind every
// directive in it — why the SPA can be fully same-origin, why blocking
// fonts.gstatic.com makes an uncovered glyph an endless stream of console errors
// (federfall-sbtx), why COEP is `credentialless`, why the Referrer-Policy is not
// `same-origin` (federfall-txxj), and why the map origins are derived from the
// same URLs /info prescribes so a server cannot block what it asks for.
//
// It reads its env under the prefix given here: FEDERFALL_CSP,
// FEDERFALL_MAP_TILE_ORIGINS, FEDERFALL_MAP_TILE_URL, FEDERFALL_MAP_STYLE_URL.

routerUse((e) =>
  require(`${__hooks}/zv_web_headers.js`).apply(e, { envPrefix: "FEDERFALL" }),
);
