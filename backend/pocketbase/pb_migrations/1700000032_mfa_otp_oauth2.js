/// <reference path="../pb_data/types.d.ts" />

// FED-8.3 — optional per-user MFA (email OTP second factor) + enable OAuth2.
//
// All PocketBase-native. MFA in PocketBase requires two DIFFERENT auth methods:
// a successful password auth returns a 401 carrying an `mfaId` instead of a
// token, and the client completes a second method to finish. Here the second
// factor is an emailed one-time password (OTP), which reuses the SMTP the
// operator already configures — nothing for users to install.
//
// MFA is opt-in per user: the `mfa.rule` filter only triggers MFA for records
// where `mfa_enabled = true`, a flag each user can toggle on their own profile
// (the field guard in main.pb.js does not block it, and self-update is allowed
// since 1700000011). Users who leave it off log in with password only.
//
// OAuth2 is also enabled so an operator can register a provider (client id/secret
// via the Admin UI or settings) as an alternative login method. The provider
// list stays empty here — that is per-instance operator config, not schema.

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");

    // Per-user opt-in flag.
    users.fields.add(new BoolField({ name: "mfa_enabled" }));

    // MFA on, gated on the per-user flag.
    users.mfa.enabled = true;
    users.mfa.rule = "mfa_enabled = true";

    // OTP on (the second factor), with a German email template. {OTP} is the
    // code, {APP_NAME} the instance name.
    users.otp.enabled = true;
    users.otp.emailTemplate.subject = "{APP_NAME}: Dein Einmalpasswort";
    users.otp.emailTemplate.body =
      "<p>Hallo,</p>\n" +
      "<p>Dein Einmalpasswort lautet: <strong>{OTP}</strong></p>\n" +
      "<p><i>Wenn du kein Einmalpasswort angefordert hast, kannst du diese E-Mail ignorieren.</i></p>\n" +
      "<p>\n  Danke,<br/>\n  dein {APP_NAME}-Team\n</p>";

    // Allow OAuth2 logins (providers are registered per instance by the operator).
    users.oauth2.enabled = true;

    app.save(users);
  },
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    users.mfa.enabled = false;
    users.mfa.rule = "";
    users.otp.enabled = false;
    users.otp.emailTemplate.subject = "OTP for {APP_NAME}";
    users.otp.emailTemplate.body =
      "<p>Hello,</p>\n" +
      "<p>Your one-time password is: <strong>{OTP}</strong></p>\n" +
      "<p><i>If you didn't ask for the one-time password, you can ignore this email.</i></p>\n" +
      "<p>\n  Thanks,<br/>\n  {APP_NAME} team\n</p>";
    users.oauth2.enabled = false;
    users.fields.removeByName("mfa_enabled");
    app.save(users);
  },
);
