/// <reference path="../pb_data/types.d.ts" />

// Set the app name from PocketBase's "Acme" default to "Federfall". `appName` is
// the instance branding PocketBase shows in the Admin UI and uses in the default
// email templates (e.g. the "... team" sign-off on the password-reset mail). It
// lives in app settings; a migration is the committed, reproducible way to set it
// (rather than clicking it into the Admin UI on every fresh instance).

migrate(
  (app) => {
    const settings = app.settings();
    settings.meta.appName = "Federfall";
    app.save(settings);
  },
  (app) => {
    const settings = app.settings();
    settings.meta.appName = "Acme"; // PocketBase default
    app.save(settings);
  },
);
