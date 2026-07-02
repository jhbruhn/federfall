/// <reference path="../pb_data/types.d.ts" />

// federfall-49l.3 — provision self-registered OAuth2 users.
//
// When someone signs in via OAuth2 and no users record matches yet, PocketBase
// creates the auth record itself (e.record is null until then). We let it do
// that — and crucially DON'T build the record by hand, so PB still links the
// external identity (_externalAuths / recordRef) correctly. We only inject the
// app fields the collection requires (role/org/is_active, plus a verified email)
// through `e.createData`, the official channel for seeding the new record.
//
// Role (hybrid model):
//   - the FIRST user, when no active supervisor exists yet, becomes supervisor
//     (bootstraps the instance — no invite, no env seed needed); OR
//   - if the IdP sends groups, an optional group->role mapping applies; else
//   - the user lands as `guest` — able to log in but walled off from all data
//     (see 1700000033) until a supervisor promotes them.
//
// Optional gating: if FEDERFALL_OIDC_ALLOWED_GROUPS is set, only users in one of
// those groups may register (others are rejected) — except the first user, who
// may always bootstrap.
//
// FEDERFALL_OIDC_TRUST_EMAIL=true treats the IdP's email claim as verified even
// when the provider didn't send email_verified (for trusted private IdPs).
//
// Existing users (linking OAuth2 to an already-provisioned account) pass through
// untouched. PocketBase isolates each handler's JSVM context, so everything is
// defined inside it.

onRecordAuthWithOAuth2Request((e) => {
  if (!e.isNewRecord) {
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

  // Groups from the IdP claims (OIDC providers send them; plain social do not).
  const ou = e.oAuth2User;
  let groups = [];
  try {
    const raw = ou ? ou.rawUser : null;
    const claim = env("FEDERFALL_OIDC_GROUPS_CLAIM") || "groups";
    const g = raw ? raw[claim] : null;
    if (Array.isArray(g)) groups = g.map((x) => String(x));
    else if (typeof g === "string" && g !== "") groups = [g];
  } catch (_) {
    groups = [];
  }
  const inAny = (names) => names.some((n) => groups.includes(n));

  // First account (no active supervisor yet)?
  let firstUser = false;
  try {
    e.app.findFirstRecordByFilter(
      "users",
      "role = 'supervisor' && is_active = true",
    );
  } catch (_) {
    firstUser = true;
  }

  // Gate registration to allowed groups, if configured (first user is exempt).
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

  // Seeded launch organisation (single-org instance), with a fallback.
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

  // Resolve the email. PocketBase only populates `ou.email` when the provider
  // reported it as verified; the fallback to the raw `email` claim (for IdPs/
  // mocks that omit email_verified) is UNVERIFIED — with an IdP that lets
  // users type any address, trusting it would plant an attacker-chosen email
  // in the roster as verified (federfall-bsv). Track the distinction and only
  // mark the account verified below when the claim actually was.
  let email = ou ? ou.email || "" : "";
  let emailVerified = email !== "";
  if (!email && ou && ou.rawUser) {
    try {
      email = ou.rawUser.email ? String(ou.rawUser.email) : "";
    } catch (_) {
      email = "";
    }
  }
  // Operator override for a trusted private IdP that never sends
  // email_verified (self-hosted Authentik/Keycloak holding vetted accounts).
  if (env("FEDERFALL_OIDC_TRUST_EMAIL").toLowerCase() === "true") {
    emailVerified = email !== "";
  }

  // Seed the to-be-created record. Let PocketBase build + persist it (and link
  // the external identity) — we only add the fields it can't infer from OAuth2.
  // createData may be undefined here, so assign a fresh object (merging anything
  // the client already supplied). `verified` is NOT set here — it's a protected
  // system field PocketBase rejects via createData — it's set after creation
  // below instead.
  const data = { role: role, is_active: true };
  if (orgId) data.org = orgId;
  // Expose the email to fellow org members so the team roster shows it.
  if (email) {
    data.email = email;
    data.emailVisibility = true;
  }
  e.createData = Object.assign({}, e.createData, data);

  e.app
    .logger()
    .info("federfall: provisioning oauth2 user", "role", role, "firstUser", firstUser);

  e.next(); // PocketBase creates + links the record here

  // Mark the new account verified — but ONLY when the IdP actually verified
  // the email (or the operator opted into trusting it, see above). An account
  // left unverified still works: the guest wall keys off `role`, and
  // `verified` only shows an "invite pending" badge in the team roster until
  // a supervisor confirms the person. It can't go through createData
  // (protected there); a programmatic save from a hook is allowed and doesn't
  // trip the API-only field guard in main.pb.js.
  try {
    if (e.record && emailVerified && !e.record.getBool("verified")) {
      e.record.set("verified", true);
      e.app.save(e.record);
    }
  } catch (err) {
    e.app
      .logger()
      .warn("federfall: could not mark oauth user verified", "err", String(err));
  }
});
