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
//   minClient            — minimum client build the server supports (the app
//                          may warn "update required" when its build is older).
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
    // `MIN_CLIENT` is a manual policy value (oldest client build still
    // served), not derived from VERSION — bump it deliberately when a release
    // breaks compatibility with older clients.
    const VERSION = $os.getenv("FEDERFALL_VERSION") || "0.0.0-dev";
    const MIN_CLIENT = "1.0.0";

    // Read live capabilities defensively — a missing/renamed field must never
    // 500 the discovery endpoint, so every probe falls back to a safe default.
    let name = "Federfall";
    let password = true;
    let oauth2 = [];
    let passwordReset = false;

    try {
      const settings = $app.settings();
      if (settings.meta && settings.meta.appName) name = settings.meta.appName;
      passwordReset = !!(settings.smtp && settings.smtp.enabled);
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
