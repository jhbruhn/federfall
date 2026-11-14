/// <reference path="../pb_data/types.d.ts" />

// Provisioning a `users` record for somebody arriving through an identity
// provider. Registration here is invite-only, so an OAuth2 sign-in that finds no
// account has to either create one or be refused — and which of those it is
// depends on the groups the provider asserts.
//
// zv_oauth2_provisioning.js holds the mechanics and the reasoning: why the email
// is resolved from the provider's raw claims rather than trusted from one field,
// why a role is decided by the FIRST matching group so the most privileged entry
// must come first, and why the very first user is a special case that two
// concurrent sign-ins could both think they are.
//
// What stays here is federfall's vocabulary — its roles, its group variables,
// its seeded org, its audit action, and the sentence somebody sees when their
// account is not permitted to register.

onRecordAuthWithOAuth2Request((e) => {
  // federfall-j3t5 — the client's `createData` is DISCARDED before the library
  // sees it. The library merges its own fields over it with Object.assign, which
  // replaces a plain `role` but not PocketBase's field-modifier keys: `role+`,
  // `+role`, `role-`, `org+` survive the merge, and PocketBase applies them
  // AFTER the plain key, so `{"role+": "supervisor"}` made any first-time
  // arrival an active supervisor (users.createRule passes on the oauth2 context
  // and nothing re-checks the role afterwards). Every field a provisioned
  // account needs is decided server-side by the library, and the app never
  // sends createData, so there is nothing legitimate to lose. Keep this even
  // once the base image fixes the merge: it is what makes the guarantee
  // independent of the library's next change. Asserted by test_rules.py's
  // [oauth2 provisioning] block through a real OAuth2 round trip.
  e.createData = {};
  return require(`${__hooks}/zv_oauth2_provisioning.js`).provision(e, {
    envPrefix: "FEDERFALL",
    // Written by this app's own migration, which is why the id is the app's to
    // state rather than the library's to know.
    defaultOrgId: "org00000default",
    roles: {
      // A guest is walled off from every collection: the safe landing place for
      // somebody who authenticated but matched no group.
      walledOff: "guest",
      // The first account on a fresh instance. Somebody has to be able to invite
      // the others.
      bootstrap: "supervisor",
      // Order is the privilege order — first match wins.
      groupMap: [
        { env: "OIDC_SUPERVISOR_GROUP", role: "supervisor" },
        { env: "OIDC_COORDINATOR_GROUP", role: "coordinator" },
        { env: "OIDC_CARER_GROUP", role: "carer" },
      ],
    },
    forbiddenMessage: "Your account is not permitted to register.",
    audit: require(`${__hooks}/lib_audit.js`),
    auditAction: "oauth2.user_provisioned",
  });
});
