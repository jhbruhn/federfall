# Security Review — Federfall PocketBase backend

**Scope:** `backend/pocketbase/` — schema migrations, JS hooks, and repo CI.
**Date:** review snapshot.
**Overall assessment:** This backend is exceptionally well-hardened. The access-rule
layer (org-scoped, private-by-default, opt-in sharing, guest wall) is the real
security boundary and is consistently re-stated inside every custom route that
bypasses it. Most OWASP classes (IDOR, cross-org escalation, custody enforcement,
path traversal, command injection, SQL injection, CSV injection, audit tampering,
MFA, lockout, guest wall) are addressed and backed by a rule-test suite
(`tests/test_rules.py`). The findings below are the residual issues that remain;
none is a trivial remote RCE or a blank-slate authentication bypass.

> **Audit limitation:** several security-critical implementations are *not in this
> repo*. The hooks `require()` `zv_*` libraries (`zv_web_headers.js` CSP,
> `zv_rate_limits.js` — including the `*:auth` credential-stuffing budget,
> `zv_geocode_route.js` proxy, `zv_oauth2_provisioning.js`, `zv_org.js`,
> `zv_settings.js`) that live in the `ZUGVOGEL_PB_BASE` base image — see the root
> `Dockerfile`. Those surfaces (CSP, network egress/SSRF in the geocode proxy,
> OAuth2 provisioning, SMTP) could not be audited from source here and should be
> reviewed separately. Findings in this report that touch them are flagged.

---

## Findings (by severity)

### F1 — Self-service `email` change enables silent, permanent account takeover (Medium)
*File: `pb_migrations/1700000011_users_self_update.js` + `main.pb.js` §5*

`users.updateRule` was widened to allow a member to update their own record
(`@request.auth.id = id …`). The field-guard hook that makes self-update safe
blocks only `role / org / is_active / verified`:

```js
for (const field of ["role", "org", "is_active", "verified"]) { … }
```

`email` is **not** guarded, so any authenticated member can `PATCH` their own
record and set any email address. PocketBase's routine record-update path does not
challenge the new address (no change-email verification is wired up), and
`request-password-reset` mails the reset token to whatever address is stored.
`lib_audit.js` even documents that an email change rotates the record's `tokenKey`
(password/email change invalidates existing sessions).

**Exploit chain:** an attacker who obtains a user's session token / a logged-in
device even once can:
1. `PATCH /api/collections/users/records/<id>  {"email": "attacker@example.com"}`
2. `POST /api/collections/users/request-password-reset` → token goes to the attacker's address.
3. `POST /api/collections/users/confirm-password-reset` with that token → new password set.

The legitimate owner is now locked out permanently (the recovery email no longer
belongs to them) and can only be restored by a supervisor manually. This converts
a temporary session leak into permanent account takeover.

**Remediation:** treat `email` like the guarded fields — only a supervisor (or the
self-user *with* a challenge) may change it. Either add `email` to the guard and
keep email changes supervisor-only, or require the current password and/or a
change-verification email (`request-email-change`) before applying. Also emit a
distinct audit action for email changes (currently only the tokenKey rotation is
logged).

---

### F2 — 30-day session tokens with no revocation / refresh rotation (Medium)
*File: `pb_migrations/1700000055_users_auth_token_duration.js`*

```
users.authToken.duration = 2592000; // 30 days
```

Sessions live up to 30 days (the app rolls them forward on every active use, so a
session in continuous use never expires). There is no per-device session registry,
no server-side revocation of a stolen token, and a token remains valid even if the
user is mid-session. Combined with F1, a single leaked token is a durable,
recover-the-account credential. For an app handling finder PII, sponsor addresses
and medical records, 30-day bearer tokens with no way to revoke a specific device
are generous. Consider shorter idle expiry, a rotation/refresh handshake, and a
"sign out all devices" / password-change revocation path.

---

### F3 — Controlled-substance flag is client-settable by any carer (Low–Medium)
*Files: `pb_migrations/1700000007_clinical_logs.js`, `pb_hooks/prescribe_batch.pb.js`*

`medications.is_controlled` is a plain `bool` with no server-side rule or hook
tying it to a vet/coordinator/supervisor. Any carer with edit access to a case can
set (or clear) it via the collection API or the batch route (`prescribe_batch`
copies `shared.is_controlled` straight from the body). If this flag feeds any
controlled-drugs compliance or audit workflow, it is an authorization gap — a carer
can mark a schedule-controlled drug as non-controlled (or vice-versa) and there is
no way to tell who authorised it. At minimum, decide whether it is a
role-gated assertion and gate it accordingly; if it must remain data only, that is
fine, but it should then not be used as a control signal.

---

### F4 — Server-side report rendering is an expensive per-request operation reachable by any member (Low)
*Files: `pb_hooks/case_report.pb.js`, `pb_hooks/annual_report.pb.js`*

Each report is a full Typst compile that shells out (`$os.cmd("typst","compile"…`),
writes a photo + the whole timeline JSON (including finder PII) to a temp dir, and
rasterises a PNG when `?widthDots=` is set. It is gated on being able to view the
case (correct), and the `reports` rate-limit group (`GET /api/federfall/cases/`,
`GET /api/federfall/reports/`) applies, but the budget is 20/60s per IP and a
member can still grind out PDFs across many cases they are authorised to see.
Consider a per-user budget and an output-size ceiling on the data.json (an
extremely long timeline) to bound CPU and temp-disk usage. The temp
`data.json`/photo are written `0644` world-readable on the host for the duration of
the compile — acceptable in a single-tenant container, but worth noting for
multi-process hosts.

---

### F5 — `sponsorships.deleteRule = READ` — any reader of a patronage can delete it (Low)
*File: `pb_migrations/1700000085_sponsorships.js`*

```
deleteRule: READ   // keeper OR coordinator OR supervisor
```

Deleting a sponsor's patronage (PII + donation record) is allowed to the bird's
current keeper, not just its creator or a coordinator/supervisor. This is stated as
intentional design in the comments, but it is a data-integrity/authorization
consideration: a keeper can silently erase a donor's record about a bird that is
not theirs, with the audit event as the only trace. Consider limiting delete to
coordinator/supervisor (matching `finders`), keeping create/update on the keeper.

---

### F6 — `case_number` is client-writable through the normal update rule (Low)
*File: `pb_migrations/1700000004_cases.js` / `1700000046_case_number_org_unique.js`*

`cases.updateRule` is `caseEdit` (active carer / supervisor / edit-share) and does
not free `case_number` (unlike the frozen relations in `1700000043`). A carer can
PATCH their own case's `case_number` to an arbitrary value within org-scoped
uniqueness. It is a display/derived value (used in report filenames, deep-links and
audit labels), so impact is low, but it is a `presentable` identifier that other
workflows trust — worth freezing like the other business fields.

---

### F7 — `GET /api/federfall/info` discloses the exact server version (Info/Low)
*File: `pb_hooks/info.pb.js` (payload in `zv_info.js`, external)*

The info endpoint reports the running PocketBase/app version to unauthenticated
callers. This is intentional (client compatibility contract and, notably, a
`selfSignup:false` denial that makes invite-only explicit), but it does surface an
enumeration aid for anyone targeting known CVE versions. Acceptable trade-off;
flagging for completeness.

---

### F8 — Auth rate limiting / credential probing depends on an out-of-repo factory rule (Info)
*File: `pb_hooks/rate_limits.pb.js`*

`zv_rate_limits.js` (base image) is documented to restore the factory `*:auth` rate
rule and to refuse unknown labels. Because the implementation is not auditable in
this repo, credential-stuffing protection on the auth endpoints cannot be confirmed
here. Recommend reviewing that module and confirming `*:auth` (or `*/api/collections/users/auth-with-password`) is actually enforced in production.

---

## Confirmed-as-defended (review notes)

Worth stating explicitly what was verified so a future reviewer does not re-litigate
it:

- **IDOR / cross-org:** every custom route re-validates the caller's org *and* the
  target record's org; relations carry org-scope guards (`org_scope.pb.js`) and
  custody guards (`lib_custody.js`, `animal_custody_scope.pb.js`).
- **Privilege escalation:** users role/org/is_active/verified guard (`main.pb.js`),
  org-lock on `users.updateRule` (1700000051), last-supervisor lockout guard.
- **SQL injection:** all queries use bound parameters (`{:x}`); no string-built SQL
  in hooks; `main.pb.js` case-number query is parameterised.
- **Command injection:** `typst` is invoked with an argument array (`$os.cmd`), not
  a shell; payload is passed via a file (`--input dataPath=`), not argv.
- **CSV injection:** formula-leading characters are neutralised (annual report).
- **Guest wall:** guest role is excluded from every collection rule and every custom
  route gate (`requireMember` etc.).
- **Audit integrity:** `audit_events` write rules nulled + a tamper guard with no
  carve-outs; retention only deletes rows older than the org window.
- **Finder PII / GDPR:** retention cron + orphan deletion; sponsorship PII kept out
  of audit values.
- **Path traversal (file fields):** uploads go through PocketBase's filesystem
  abstraction with a MIME allowlist (1700000048); report photo paths derive from
  PB-controlled filenames.
- **Secrets:** no keys/tokens committed; `pb_data` (live DB + uploads) is
  gitignored; release workflow secrets are GitHub Actions secrets on a
  `push: main`-only pipeline (not `pull_request_target`).

---

## Recommended priority order
1. F1 — gate/verify self-service email change (prevents permanent account takeover).
2. F2 — revisit 30-day token life + add revocation/rotation.
3. F3 — decide and enforce who may set `is_controlled`.
4. F4/F5/F6 — hardening: report budgets, sponsorship delete-rule, freeze
   `case_number`.
5. F8 — confirm the out-of-repo auth rate limit / geocode-proxy SSRF and CSP via the
   base-image sources.
