/// <reference path="../pb_data/types.d.ts" />

// federfall-49l.3 — provision self-registered OAuth2 users.
//
// When someone signs in via OAuth2 and no users record matches yet, PocketBase
// would create one — but our `role` field is required and `org` must be set, so
// the bare auto-create fails (400). This hook fills those in on the new record
// and decides the account's role, so OAuth2 can self-register.
//
// Role (hybrid model, federfall-49l.3):
//   - the FIRST user, when no active supervisor exists yet, becomes supervisor
//     (bootstraps the instance — no invite, no env seed needed); OR
//   - if the IdP sends groups, an optional group->role mapping applies; else
//   - the user lands as `guest` — able to log in but walled off from all data
//     (see 1700000033) until a supervisor promotes them.
//
// Optional gating: if FEDERFALL_OIDC_ALLOWED_GROUPS is set, only users in one of
// those groups may register at all (others are rejected) — except the very first
// user, who may always bootstrap.
//
// Existing users (linking OAuth2 to an already-provisioned account) are left
// untouched. PocketBase isolates each handler's JSVM context, so everything is
// defined inside it.

onRecordAuthWithOAuth2Request((e) => {
  // Only act on brand-new self-registrations; existing accounts pass through.
  if (!e.isNewRecord || !e.record) {
    e.next();
    return;
  }

  const env = (k) => {
    const v = $os.getenv(k);
    return v && v !== "" ? v : "";
  };
  const list = (k) =>
    env(k)
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s !== "");

  // Groups from the IdP claims (provider-dependent; OIDC providers like Authentik
  // /Keycloak send them, plain social logins do not).
  let groups = [];
  try {
    const raw = e.oAuth2User ? e.oAuth2User.rawUser : null;
    const claim = env("FEDERFALL_OIDC_GROUPS_CLAIM") || "groups";
    const g = raw ? raw[claim] : null;
    if (Array.isArray(g)) groups = g.map((x) => String(x));
    else if (typeof g === "string" && g !== "") groups = [g];
  } catch (_) {
    groups = [];
  }
  const inAny = (names) => names.some((n) => groups.includes(n));

  // Is this the first account (no active supervisor yet)?
  let firstUser = false;
  try {
    e.app.findFirstRecordByFilter(
      "users",
      "role = 'supervisor' && is_active = true",
    );
  } catch (_) {
    firstUser = true; // none found
  }

  // Gate registration to allowed groups, if configured (the first user is exempt
  // so an instance can always be bootstrapped).
  const allowed = list("FEDERFALL_OIDC_ALLOWED_GROUPS");
  if (!firstUser && allowed.length > 0 && !inAny(allowed)) {
    throw new ForbiddenError("Your account is not permitted to register.", null);
  }

  // Decide the role.
  const supGroups = list("FEDERFALL_OIDC_SUPERVISOR_GROUP");
  const coordGroups = list("FEDERFALL_OIDC_COORDINATOR_GROUP");
  const carerGroups = list("FEDERFALL_OIDC_CARER_GROUP");
  let role = "guest";
  if (firstUser || inAny(supGroups)) role = "supervisor";
  else if (inAny(coordGroups)) role = "coordinator";
  else if (inAny(carerGroups)) role = "carer";

  // Attach to the seeded launch organisation (single-org instance), falling back
  // to the first org if it was renamed/replaced.
  let orgId = "";
  try {
    orgId = e.app.findRecordById("organisations", "org00000default").id;
  } catch (_) {
    try {
      orgId = e.app.findFirstRecordByFilter("organisations", "id != ''").id;
    } catch (_) {
      orgId = "";
    }
  }

  e.record.set("role", role);
  if (orgId) e.record.set("org", orgId);
  e.record.set("is_active", true);

  e.app
    .logger()
    .info("federfall: provisioning oauth2 user", "role", role, "firstUser", firstUser);

  e.next();
});
