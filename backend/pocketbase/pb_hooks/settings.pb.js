/// <reference path="../pb_data/types.d.ts" />

// Application settings applied at boot from the environment, so a self-hoster
// configures the instance in compose rather than by clicking through the Admin
// UI — where a setting is invisible to anybody who did not do the clicking.
//
// zv_settings.js holds it, including which settings are refused (an operator's
// mail credentials are not the app's business to overwrite) and why the app URL
// matters for the links in reset mail.

onBootstrap((e) => {
  e.next();
  require(`${__hooks}/zv_settings.js`).apply(e, {
    envPrefix: "FEDERFALL",
    defaultName: "Federfall",
  });
});
