/// <reference path="../pb_data/types.d.ts" />

// Point the users "forgot password" email at the FEDERFALL app's reset route, in
// German (the primary UI language). PocketBase's default template links to the PB
// Admin UI ({APP_URL}/_/#/auth/confirm-password-reset/{TOKEN}); the app instead
// handles resets at /auth/confirm-reset?token={TOKEN} (ConfirmResetScreen reads
// ?token=). {APP_URL} resolves from settings.meta.appURL — set per instance via
// FEDERFALL_APP_URL (see pb_hooks/settings.pb.js).

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    users.resetPasswordTemplate.subject = "{APP_NAME}: Passwort zurücksetzen";
    users.resetPasswordTemplate.body =
      "<p>Hallo,</p>\n" +
      "<p>Klicke auf die Schaltfläche unten, um dein Passwort zurückzusetzen.</p>\n" +
      "<p>\n" +
      '  <a class="btn" href="{APP_URL}/auth/confirm-reset?token={TOKEN}" target="_blank" rel="noopener">Passwort zurücksetzen</a>\n' +
      "</p>\n" +
      "<p><i>Wenn du keine Zurücksetzung angefordert hast, kannst du diese E-Mail ignorieren.</i></p>\n" +
      "<p>\n  Danke,<br/>\n  dein {APP_NAME}-Team\n</p>";
    app.save(users);
  },
  (app) => {
    // Restore PocketBase's default (English, Admin-UI link).
    const users = app.findCollectionByNameOrId("users");
    users.resetPasswordTemplate.subject = "Reset your {APP_NAME} password";
    users.resetPasswordTemplate.body =
      "<p>Hello,</p>\n" +
      "<p>Click on the button below to reset your password.</p>\n" +
      "<p>\n" +
      '  <a class="btn" href="{APP_URL}/_/#/auth/confirm-password-reset/{TOKEN}" target="_blank" rel="noopener">Reset password</a>\n' +
      "</p>\n" +
      "<p><i>If you didn't ask to reset your password, please ignore this email.</i></p>\n" +
      "<p>\n  Thanks,<br/>\n  {APP_NAME} team\n</p>";
    app.save(users);
  },
);
