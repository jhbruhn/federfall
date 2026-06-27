/// <reference path="../pb_data/types.d.ts" />

// Bootstrap the FIRST app-level Supervisor from environment variables.
//
// Federfall registration is invite-only and every invite must be sent BY a
// supervisor — so the first supervisor is a chicken-and-egg that has to be
// created out-of-band. A PocketBase superuser (Admin UI) is NOT an app-level
// Supervisor (it's a separate `_superusers` record with no org/role), so it
// can't send invites or own cases.
//
// This seeds one `users` record with role=supervisor, is_active=true, attached to
// the seeded organisation — the same env-in-compose pattern used elsewhere
// (settings.pb.js), so a self-host operator gets a working login on first
// `docker compose up` without clicking through the Admin UI. It runs only when NO
// active supervisor exists, which makes it idempotent AND a lockout-recovery path
// (lost access → set the env, restart, get a supervisor again). Leave the env
// unset to use the manual Admin-UI runbook instead (see backend README).
//
// Env (set in docker-compose.yml):
//   FEDERFALL_SUPERVISOR_EMAIL     required to enable bootstrap
//   FEDERFALL_SUPERVISOR_PASSWORD  required to enable bootstrap
//   FEDERFALL_SUPERVISOR_NAME      optional display name (default: "Supervisor")

onBootstrap((e) => {
  e.next(); // collections/migrations must be applied before we query/insert

  // PocketBase isolates each handler's JSVM context — define helpers inside.
  const env = (k) => {
    const v = $os.getenv(k);
    return v && v !== "" ? v : "";
  };

  const email = env("FEDERFALL_SUPERVISOR_EMAIL");
  const password = env("FEDERFALL_SUPERVISOR_PASSWORD");
  if (!email || !password) {
    return; // not configured — operator will use the manual runbook
  }

  try {
    // Skip if an active supervisor already exists (idempotent / no duplicates).
    let activeSupervisor = null;
    try {
      activeSupervisor = e.app.findFirstRecordByFilter(
        "users",
        "role = 'supervisor' && is_active = true",
      );
    } catch (_) {
      activeSupervisor = null; // none found
    }
    if (activeSupervisor) {
      return;
    }

    // Attach to the seeded launch organisation (1700000001 seeds this id);
    // fall back to the first org if it was renamed/replaced.
    let org = null;
    try {
      org = e.app.findRecordById("organisations", "org00000default");
    } catch (_) {
      try {
        org = e.app.findFirstRecordByFilter("organisations", "id != ''");
      } catch (_) {
        org = null;
      }
    }
    if (!org) {
      e.app
        .logger()
        .warn("federfall: cannot bootstrap supervisor — no organisation exists yet");
      return;
    }

    const users = e.app.findCollectionByNameOrId("users");
    const rec = new Record(users);
    rec.set("email", email);
    rec.set("emailVisibility", true); // visible to fellow org members in the roster
    rec.setPassword(password);
    rec.set("role", "supervisor");
    rec.set("org", org.id);
    rec.set("is_active", true);
    rec.set("verified", true);
    rec.set("name", env("FEDERFALL_SUPERVISOR_NAME") || "Supervisor");
    e.app.save(rec);

    e.app
      .logger()
      .info("federfall: bootstrapped first supervisor from env", "email", email);
  } catch (err) {
    // Never brick startup over a bad bootstrap config — log and carry on.
    e.app.logger().warn("federfall: supervisor bootstrap failed", "err", String(err));
  }
});
