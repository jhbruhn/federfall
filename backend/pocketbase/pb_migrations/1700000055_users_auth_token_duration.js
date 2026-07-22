/// <reference path="../pb_data/types.d.ts" />

// Extend how long a users session token stays valid.
//
// The client (federfall_data AuthRepository) has no silent-refresh loop yet, so
// a session lived exactly as long as `users.authToken.duration` and then the
// router gate bounced the user to /login — felt worst under OIDC, where re-auth
// means another round-trip through the external provider. This lifts the ceiling
// to 30 days; the app-side SessionRefresher rolls it forward on every active use,
// so an in-use session effectively never lapses and only genuinely idle sessions
// (untouched for 30 days) require a fresh login.
//
// This is auth-method-agnostic: PocketBase issues its OWN JWT for OAuth2/OIDC
// logins too (the provider's tokens are not used to extend the session), so
// password and OIDC sessions share this duration.

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    users.authToken.duration = 2592000; // 30 days
    app.save(users);
  },
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    users.authToken.duration = 432000; // 5 days (prior default)
    app.save(users);
  },
);
