/// <reference path="../pb_data/types.d.ts" />

// federfall-7nf.1 — server identity & capabilities discovery.
//
// GET /api/federfall/info is UNAUTHENTICATED and is how the app verifies, on
// first run, that a URL points at a genuine Federfall backend (not some random
// host that merely answers /api/health with a 200). It also tells the login
// screen which auth options the server actually offers, so the UI can adapt.
//
// The response carries:
//   service / federfall  — the identity marker the client requires before it
//                          will accept the server (a generic PocketBase has no
//                          such route → 404 → "not a Federfall server").
//   version              — major.minor only (patch withheld from this
//                          unauthenticated endpoint), for display + diagnostics.
//   minClient            — oldest client build this server still serves.
//                          Derived from the running major; see below. The app
//                          blocks sign-in with an "update required" notice
//                          when its own build falls under it, or when the two
//                          majors disagree at all (federfall-1wm).
//   name                 — branding/instance name shown on the login screen.
//   auth                 — enabled auth methods, derived from live PB config:
//                            password       (users.passwordAuth.enabled)
//                            oauth2         (enabled provider names)
//                            passwordReset  (SMTP configured — reset mail can
//                                            actually be delivered)
//                            selfSignup     (always false — Federfall is
//                                            invite-only; users are created by
//                                            supervisors, never self-registered)
//
// PocketBase runs each route handler in an isolated JSVM context, so it cannot
// see file-level helpers — everything the handler needs is defined inside it.

routerAdd(
  "GET",
  "/api/federfall/info",
  (e) => {
    // Sourced from the image env (see Dockerfile's FEDERFALL_VERSION ARG/ENV),
    // set at build time from the release-please tag — never hand-edited.
    // Only major.minor is exposed below: the exact patch level is deliberately
    // withheld from this UNAUTHENTICATED endpoint so it can't be used to
    // fingerprint whether a specific CVE fix is deployed. The full version is
    // still visible via the image tag/label for operator use.
    const VERSION = $os.getenv("FEDERFALL_VERSION") || "0.0.0-dev";

    // `minClient` is the oldest client build this server still serves. It is
    // DERIVED from VERSION's major, because the major IS the app↔server wire
    // contract (federfall-1wm): every wire-breaking change is a `!` commit,
    // which bumps the major, so `<major>.0.0` is exactly the floor. It used to
    // be hardcoded "1.0.0" while releases were still on 0.x — a floor above
    // every client in existence, which would have locked out all of them the
    // moment anything enforced it.
    //
    // `FEDERFALL_MIN_CLIENT` overrides it upward for the rarer case: a floor
    // *within* a major, e.g. "1.4.0" when older 1.x clients must not be served
    // any more despite the contract itself being unchanged.
    const major = parseInt(VERSION, 10);
    const MIN_CLIENT =
      $os.getenv("FEDERFALL_MIN_CLIENT") ||
      (isNaN(major) ? "0.0.0" : major + ".0.0");

    // Read live capabilities defensively — a missing/renamed field must never
    // 500 the discovery endpoint, so every probe falls back to a safe default.
    let name = "Federfall";
    let password = true;
    let oauth2 = [];
    let smtpEnabled = false;

    try {
      const settings = $app.settings();
      if (settings.meta && settings.meta.appName) name = settings.meta.appName;
      smtpEnabled = !!(settings.smtp && settings.smtp.enabled);
    } catch (err) {
      $app.logger().warn("federfall info: settings read failed", "err", err);
    }

    try {
      const users = $app.findCollectionByNameOrId("users");
      if (users.passwordAuth) password = !!users.passwordAuth.enabled;
      if (users.oauth2 && users.oauth2.enabled) {
        oauth2 = (users.oauth2.providers || []).map((p) => p.name);
      }
    } catch (err) {
      $app.logger().warn("federfall info: users collection read failed", "err", err);
    }

    // Resetting a password only makes sense when password sign-in itself is
    // enabled — otherwise SMTP being configured (e.g. for an OIDC-only
    // instance) made this true with no password form to show the link on.
    const passwordReset = password && smtpEnabled;

    return e.json(200, {
      service: "federfall",
      federfall: true,
      version: VERSION.split(".").slice(0, 2).join("."),
      minClient: MIN_CLIENT,
      name: name,
      auth: {
        password: password,
        oauth2: oauth2,
        passwordReset: passwordReset,
        selfSignup: false,
      },
    });
  },
  // Unauthenticated: the client hits this before any login exists.
);
