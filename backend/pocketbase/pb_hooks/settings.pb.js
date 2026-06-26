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

  if (changed) e.app.save(settings);
});
