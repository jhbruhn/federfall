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
//                            oauth2Scopes   (federfall-lnz3, optional) the OAuth2
//                                            scopes the app should request per
//                                            provider. PocketBase hardcodes its
//                                            own minimal set (openid/email/
//                                            profile for OIDC) and exposes no
//                                            way to widen it server-side —
//                                            upstream's position is that scopes
//                                            belong to the client, which builds
//                                            the authorization URL
//                                            (pocketbase#3727,
//                                            pocketbase/discussions#7114). So
//                                            the server can only PRESCRIBE them
//                                            here and let the app apply them.
//                                            Present only when a group->role
//                                            mapping is configured, since an
//                                            IdP releases the groups claim only
//                                            to a request that asked for the
//                                            matching scope — without it the
//                                            mapping in
//                                            oauth2_provisioning.pb.js can
//                                            never fire. Derived from that
//                                            config; there is no scope env.
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

    // Derived, not configured: asking for the groups scope is exactly what
    // configuring a group mapping implies, so there is no separate env for it
    // to drift out of sync with (an operator who has to restate the scope list
    // by hand is one `openid` away from breaking sign-in entirely).
    //
    // PocketBase's own OIDC scopes are openid/email/profile and it offers no
    // way to widen them server-side, so the full set is published here and the
    // app requests it in place of the one PocketBase built into the URL.
    const groupsEnv = [
      "FEDERFALL_OIDC_SUPERVISOR_GROUP",
      "FEDERFALL_OIDC_COORDINATOR_GROUP",
      "FEDERFALL_OIDC_CARER_GROUP",
      "FEDERFALL_OIDC_ALLOWED_GROUPS",
    ];
    let groupsConfigured = false;
    for (let i = 0; i < groupsEnv.length; i++) {
      const v = $os.getenv(groupsEnv[i]);
      if (v && v !== "") groupsConfigured = true;
    }
    // The scope is named after the claim it releases — the same value
    // oauth2_provisioning.pb.js reads the groups out of.
    const groupsClaim = $os.getenv("FEDERFALL_OIDC_GROUPS_CLAIM") || "groups";

    const oauth2Scopes = {};
    if (groupsConfigured) {
      for (let i = 0; i < oauth2.length; i++) {
        // Generic OIDC only (PocketBase names those oidc/oidc2/oidc3). Group
        // mapping is an OIDC feature, and handing an unknown scope to a social
        // provider like Google fails the whole authorization request.
        if (oauth2[i].indexOf("oidc") !== 0) continue;
        const scopes = ["openid", "email", "profile"];
        if (scopes.indexOf(groupsClaim) < 0) scopes.push(groupsClaim);
        oauth2Scopes[oauth2[i]] = scopes;
      }
    }

    const auth = {
      password: password,
      oauth2: oauth2,
      passwordReset: passwordReset,
      selfSignup: false,
    };
    // Omitted entirely when no provider has an override, so the payload stays
    // exactly as it was for the common case.
    if (Object.keys(oauth2Scopes).length > 0) auth.oauth2Scopes = oauth2Scopes;

    return e.json(200, {
      service: "federfall",
      federfall: true,
      version: VERSION.split(".").slice(0, 2).join("."),
      minClient: MIN_CLIENT,
      name: name,
      auth: auth,
    });
  },
  // Unauthenticated: the client hits this before any login exists.
);
