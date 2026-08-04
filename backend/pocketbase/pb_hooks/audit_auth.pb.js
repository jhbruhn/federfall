/// <reference path="../pb_data/types.d.ts" />

// federfall-qt96.5 — Tier D of the audit log: who got in, who failed to, and
// who reset a password.
//
// The rest of Tier D — user.invited / role_changed / deactivated / deleted and
// case.shared / case.share_revoked — needs no code here: `users` and
// `case_shares` are ordinary collections, so they ride the generic Tier A hooks
// in audit_domain.pb.js and are refined into their specific actions by
// lib_audit.js's refine(). Only the auth flows, which are not record writes at
// all, need their own hooks.
//
// ── Why not onRecordAuthRequest ──────────────────────────────────────────────
//
// That one fires for every successful authentication INCLUDING token refresh,
// which every running client does on a timer — the log would be mostly refresh
// noise. Hooking the specific methods logs the thing a person actually did.
//
// ── During a login there is no e.auth ────────────────────────────────────────
//
// The caller is not authenticated yet, which is the whole point of the request,
// so the acting user has to be passed to emit() explicitly (`opts.actor`).
// Without it the events would all be attributed to "system".

onRecordAuthWithPasswordRequest((e) => {
  const audit = require(`${__hooks}/lib_audit.js`);

  // Checked BEFORE e.next(), because it is the only way to tell the three
  // reasons this request can fail apart:
  //   - wrong password        → a real failed login
  //   - correct password, MFA → PocketBase answers 401 with an mfaId; the user
  //                             did nothing wrong and the login is still in
  //                             progress, so logging a failure would cry wolf
  //                             at every single MFA login
  //   - correct password, but the account is deactivated → also not a guess
  // Only the first is worth an auth.login_failed row.
  let passwordOk = false;
  try {
    passwordOk = !!(
      e.record && e.record.validatePassword(String(e.password || ""))
    );
  } catch (_) {
    passwordOk = false;
  }

  try {
    e.next();
  } catch (err) {
    if (!passwordOk) {
      audit.emitLoginFailed(e, e.record, { method: "password" });
    }
    throw err;
  }

  if (e.record) {
    audit.emit(e, audit.ACTIONS.AUTH_LOGIN, {
      actor: e.record,
      org: e.record.getString("org"),
      subject: {
        collection: "users",
        id: e.record.id,
        label: audit.subjectLabel(e.record),
      },
      detail: { method: "password" },
    });
  }
}, "users");

// A first OAuth2 sign-in also PROVISIONS the account (oauth2_provisioning.pb.js);
// that side of it is federfall-qt96.6's oauth2.user_provisioned. This is the
// login itself.
onRecordAuthWithOAuth2Request((e) => {
  const audit = require(`${__hooks}/lib_audit.js`);
  e.next();
  if (e.record) {
    audit.emit(e, audit.ACTIONS.AUTH_OAUTH2_LOGIN, {
      actor: e.record,
      org: e.record.getString("org"),
      subject: {
        collection: "users",
        id: e.record.id,
        label: audit.subjectLabel(e.record),
      },
      detail: {
        method: "oauth2",
        provider: String((e.providerName || "")),
        // Whether this sign-in created the account. `isNewRecord` is the only
        // place that distinction is visible.
        new_account: !!e.isNewRecord,
      },
    });
  }
}, "users");

// The confirm, not the request: anyone can ask for a reset mail, but only
// somebody holding the token can change the password with it. That is the
// event with security meaning — and the account's password is now different
// from whatever its owner last set.
onRecordConfirmPasswordResetRequest((e) => {
  const audit = require(`${__hooks}/lib_audit.js`);
  e.next();
  if (e.record) {
    audit.emit(e, audit.ACTIONS.AUTH_PASSWORD_RESET, {
      actor: e.record,
      org: e.record.getString("org"),
      subject: {
        collection: "users",
        id: e.record.id,
        label: audit.subjectLabel(e.record),
      },
    });
  }
}, "users");
