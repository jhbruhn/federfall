/// <reference path="../pb_data/types.d.ts" />

// Apply operator settings from environment variables on bootstrap. PocketBase has
// no native env/flag config for settings, so this uses PocketBase's OWN
// recommended pattern — use it as a framework and load settings in an onBootstrap
// hook after e.next() (https://github.com/pocketbase/pocketbase/discussions/1551).
// It writes through PB's settings API (no reimplementation) and mirrors how
// geocode.pb.js already reads FEDERFALL_* env. Re-applied on every start: change
// the env in docker-compose.yml + restart to update.
//
// Env (set in docker-compose.yml; no .env is shipped):
//   FEDERFALL_APP_URL             public origin, used in email links ({APP_URL}),
//                                 e.g. https://federfall.yourdomain.tld
//   FEDERFALL_SMTP_HOST           mail server host        (enables SMTP when set)
//   FEDERFALL_SMTP_PORT           default 587
//   FEDERFALL_SMTP_USERNAME
//   FEDERFALL_SMTP_PASSWORD
//   FEDERFALL_SMTP_TLS           "true" => implicit TLS (465); else STARTTLS
//   FEDERFALL_SMTP_SENDER_ADDRESS From address (required for real delivery)
//   FEDERFALL_SMTP_SENDER_NAME    default: the app name (Federfall)
//
//   FEDERFALL_TRUSTED_PROXY_HEADERS  comma list of headers carrying the real
//                                 client IP (e.g. "X-Forwarded-For") when a
//                                 reverse proxy fronts PocketBase. Without it
//                                 PB sees the proxy's address for every
//                                 request, so per-client-IP rate limits (the
//                                 geocode budget) are shared by ALL users
//                                 (federfall-223). Only set headers your OWN
//                                 proxy overwrites — a spoofable header lets
//                                 clients dodge rate limits.
//   FEDERFALL_TRUSTED_PROXY_USE_LEFTMOST_IP  "true" to take the leftmost IP
//                                 from the header (multi-proxy chains);
//                                 default is the rightmost, the one appended
//                                 by the proxy directly in front — the only
//                                 value a client cannot forge.
//
//   FEDERFALL_OAUTH2_PROVIDERS    comma list of provider names to register as
//                                 alternative logins, e.g. "google,oidc". For
//                                 each NAME, read (NAME upper-cased):
//                                   FEDERFALL_OAUTH2_<NAME>_CLIENT_ID      (req)
//                                   FEDERFALL_OAUTH2_<NAME>_CLIENT_SECRET  (req)
//                                 Generic OIDC (oidc/oidc2/oidc3) also takes:
//                                   _DISPLAY_NAME / _AUTH_URL / _TOKEN_URL /
//                                   _USERINFO_URL / _PKCE ("true"/"false").
//
// (The static brand name `appName` is set separately, by migration.)

onBootstrap((e) => {
  e.next(); // let core finish bootstrapping (settings loaded) before touching them

  // PocketBase runs each handler in an isolated JSVM context — define every
  // helper the handler needs inside it.
  const env = (k) => {
    const v = $os.getenv(k);
    return v && v !== "" ? v : "";
  };

  const settings = e.app.settings();
  let changed = false;

  // App URL — resolves {APP_URL} in email templates (e.g. the password-reset
  // link) and other absolute links. Without it mail points at localhost.
  const appURL = env("FEDERFALL_APP_URL");
  if (appURL && settings.meta.appURL !== appURL) {
    settings.meta.appURL = appURL;
    changed = true;
  }

  // SMTP — stays at PocketBase's disabled default unless a host is provided.
  const host = env("FEDERFALL_SMTP_HOST");
  if (host) {
    const port = parseInt(env("FEDERFALL_SMTP_PORT"), 10);
    settings.smtp.enabled = true;
    settings.smtp.host = host;
    settings.smtp.port = isNaN(port) ? 587 : port;
    settings.smtp.username = env("FEDERFALL_SMTP_USERNAME");
    settings.smtp.password = env("FEDERFALL_SMTP_PASSWORD");
    settings.smtp.tls = env("FEDERFALL_SMTP_TLS").toLowerCase() === "true";

    const senderAddress = env("FEDERFALL_SMTP_SENDER_ADDRESS");
    if (senderAddress) settings.meta.senderAddress = senderAddress;
    settings.meta.senderName =
      env("FEDERFALL_SMTP_SENDER_NAME") || settings.meta.appName || "Federfall";
    changed = true;
  }

  // Trusted proxy — makes PB resolve the real client IP from the proxy's
  // forwarding header instead of the socket peer (the proxy itself), so
  // per-client-IP rate limits stay per client behind Caddy/nginx.
  const proxyHeaders = env("FEDERFALL_TRUSTED_PROXY_HEADERS")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s !== "");
  if (proxyHeaders.length > 0) {
    settings.trustedProxy.headers = proxyHeaders;
    settings.trustedProxy.useLeftmostIP =
      env("FEDERFALL_TRUSTED_PROXY_USE_LEFTMOST_IP").toLowerCase() === "true";
    changed = true;
  }

  if (changed) e.app.save(settings);

  // OAuth2 providers live on the users COLLECTION (not app settings). Register
  // any provider listed in FEDERFALL_OAUTH2_PROVIDERS whose client id + secret
  // are present. When the env lists providers it is the source of truth; leave
  // it unset to manage providers from the Admin UI instead.
  const providerNames = env("FEDERFALL_OAUTH2_PROVIDERS")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s !== "");

  const providers = [];
  for (const name of providerNames) {
    const up = name.toUpperCase();
    const clientId = env("FEDERFALL_OAUTH2_" + up + "_CLIENT_ID");
    const clientSecret = env("FEDERFALL_OAUTH2_" + up + "_CLIENT_SECRET");
    if (!clientId || !clientSecret) {
      e.app
        .logger()
        .warn("federfall: oauth2 provider missing client id/secret", "provider", name);
      continue;
    }
    const p = { name: name, clientId: clientId, clientSecret: clientSecret };
    // Generic OIDC providers need the endpoint URLs; well-known ones don't.
    const authURL = env("FEDERFALL_OAUTH2_" + up + "_AUTH_URL");
    if (authURL) {
      p.authURL = authURL;
      p.tokenURL = env("FEDERFALL_OAUTH2_" + up + "_TOKEN_URL");
      p.userInfoURL = env("FEDERFALL_OAUTH2_" + up + "_USERINFO_URL");
      const displayName = env("FEDERFALL_OAUTH2_" + up + "_DISPLAY_NAME");
      if (displayName) p.displayName = displayName;
      p.pkce = env("FEDERFALL_OAUTH2_" + up + "_PKCE").toLowerCase() === "true";
    }
    providers.push(p);
  }

  // Password auth can be turned OFF so OAuth2 is the only sign-in method (the
  // info endpoint then reports auth.password:false and the app hides the password
  // form). Default ON; only act when explicitly set, so we never silently lock an
  // operator out.
  const pwEnv = env("FEDERFALL_PASSWORD_AUTH").toLowerCase();
  const togglePassword = pwEnv === "true" || pwEnv === "false";

  if (providers.length === 0 && !togglePassword) {
    return; // nothing collection-level to apply
  }

  try {
    const users = e.app.findCollectionByNameOrId("users");
    if (providers.length > 0) {
      users.oauth2.enabled = true;
      users.oauth2.providers = providers;
    }
    if (togglePassword) {
      users.passwordAuth.enabled = pwEnv === "true";
    }
    e.app.save(users);
    e.app
      .logger()
      .info(
        "federfall: users auth configured from env",
        "oauth2Providers",
        providers.length,
        "passwordAuth",
        togglePassword ? pwEnv : "unchanged",
      );
  } catch (err) {
    e.app.logger().warn("federfall: users auth config failed", "err", String(err));
  }
});
