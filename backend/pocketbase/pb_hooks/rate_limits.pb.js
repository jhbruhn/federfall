/// <reference path="../pb_data/types.d.ts" />

// The app's own rate-limit budgets, merged into `settings.rateLimits` at boot.
//
// Two groups, and each is a budget on something that costs somebody else money
// or CPU: the geocode proxy hits an upstream with a usage policy, and a report
// renders a PDF through Typst. zv_rate_limits.js does the merging and holds the
// reasoning — in particular why it RESTORES the factory rules it does not own
// (a missing `*:auth` rule is an open door to credential stuffing, and merging
// naively drops the ones nobody named) and why a label that matches no route is
// refused rather than silently ignored.
//
// ── Why every group also names its `legacyLabels` ───────────────────────────
//
// The merge keeps every stored rule it does not recognise, so a label THIS file
// no longer writes is not replaced — it is inherited, forever. Up to v0.16 the
// geocode budget lived in geocode.pb.js under unqualified labels, and
// `/api/federfall/geocode` is an exact-path label: on an instance that ever
// booted that version it still binds, as a second rule over the same route
// carrying whatever numbers that version's env produced. The trailing-slash
// form is inert instead (it loses to the factory `/api/` rule ahead of it),
// which reads worse rather than better — it looks like a working budget.
//
// Naming them here is the only thing that clears them. Nothing tests it: a
// fresh data dir never had them, so the suite's "no inert unqualified label is
// left lying around" assertion passes either way. This list was dropped once
// already, in the move to zv_rate_limits.js, and nothing noticed.

onBootstrap((e) => {
  e.next();
  require(`${__hooks}/zv_rate_limits.js`).apply(e, {
    envPrefix: "FEDERFALL",
    groups: [
      {
        name: "geocode",
        labels: [
          "GET /api/federfall/geocode",
          "GET /api/federfall/geocode/",
        ],
        // The unqualified labels this hook's PREDECESSOR wrote, swept on every
        // boot so an upgrade does not leave one behind. See the note above
        // `groups` for why they cannot simply be forgotten.
        legacyLabels: [
          "/api/federfall/geocode",
          "/api/federfall/geocode/",
        ],
        maxEnv: "GEOCODE_RATE_MAX",
        windowEnv: "GEOCODE_RATE_WINDOW",
        maxDefault: 30,
        windowDefault: 60,
      },
      {
        name: "reports",
        labels: ["GET /api/federfall/reports/", "GET /api/federfall/cases/"],
        // Never written by a release — these two were method-qualified from
        // their first commit. Listed anyway, because the sweep is also what
        // reclaims a label somebody added by hand in the Admin UI, and because
        // an entry that is merely redundant costs nothing while a missing one
        // is invisible.
        legacyLabels: ["/api/federfall/reports/", "/api/federfall/cases/"],
        maxEnv: "REPORT_RATE_MAX",
        windowEnv: "REPORT_RATE_WINDOW",
        maxDefault: 20,
        windowDefault: 60,
      },
    ],
  });
});
