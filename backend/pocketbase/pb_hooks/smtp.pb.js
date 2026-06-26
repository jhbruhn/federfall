/// <reference path="../pb_data/types.d.ts" />

// Configure SMTP from environment variables on bootstrap, so a self-host operator
// enables mail delivery via env in docker-compose.yml (no Admin-UI clicking, no
// .env). This is PocketBase's OWN recommended pattern for env-driven settings —
// use it as a framework and load settings in a bootstrap hook after e.next()
// (https://github.com/pocketbase/pocketbase/discussions/1551). It mirrors how
// geocode.pb.js already reads FEDERFALL_* env, and writes through PB's settings
// API rather than reimplementing anything.
//
// Re-applied on every start: change the env + restart to update. SMTP stays OFF
// unless FEDERFALL_SMTP_HOST is set, so a default instance keeps PB's disabled
// default and /api/federfall/info reports passwordReset:false.
//
// Env (set in docker-compose.yml):
//   FEDERFALL_SMTP_HOST            mail server host        (enables SMTP when set)
//   FEDERFALL_SMTP_PORT            default 587
//   FEDERFALL_SMTP_USERNAME
//   FEDERFALL_SMTP_PASSWORD
//   FEDERFALL_SMTP_TLS            "true" => implicit TLS (465); else STARTTLS
//   FEDERFALL_SMTP_SENDER_ADDRESS From address (required for real delivery)
//   FEDERFALL_SMTP_SENDER_NAME    default: the app name (Federfall)

onBootstrap((e) => {
  e.next(); // let core finish bootstrapping (settings loaded) before touching them

  // PocketBase runs each handler in an isolated JSVM context — define every
  // helper the handler needs inside it.
  const env = (k) => {
    const v = $os.getenv(k);
    return v && v !== "" ? v : "";
  };

  const host = env("FEDERFALL_SMTP_HOST");
  if (!host) {
    return; // no SMTP configured — leave PocketBase's default (disabled)
  }

  const settings = e.app.settings();

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

  e.app.save(settings);
  e.app
    .logger()
    .info("federfall: SMTP configured from env", "host", host, "port", settings.smtp.port);
});
