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
        maxEnv: "GEOCODE_RATE_MAX",
        windowEnv: "GEOCODE_RATE_WINDOW",
        maxDefault: 30,
        windowDefault: 60,
      },
      {
        name: "reports",
        labels: ["GET /api/federfall/reports/", "GET /api/federfall/cases/"],
        maxEnv: "REPORT_RATE_MAX",
        windowEnv: "REPORT_RATE_WINDOW",
        maxDefault: 20,
        windowDefault: 60,
      },
    ],
  });
});
