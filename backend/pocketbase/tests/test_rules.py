#!/usr/bin/env python3
"""FED-1.13 — backend rule & hook assertions against a running PocketBase.

Driven by run.sh (which provisions a throwaway instance). Standalone otherwise:
    FED_TEST_URL=http://localhost:8090 FED_ADMIN_EMAIL=... FED_ADMIN_PASS=... \
        python3 test_rules.py

Covers: schema/seed sanity, every FED-1.12 hook, and the FED-1.11 access-rule
matrix (private-by-default, read/edit shares, role & org scope, finder-PII
gating, handoff visibility, deactivated-auth, field-guard). Exits non-zero on
any failure.
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# Smallest valid 1x1 PNG, for exercising file-field uploads.
_PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk"
    "+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
)

BASE = os.environ.get("FED_TEST_URL", "http://localhost:8090")
ADMIN_EMAIL = os.environ.get("FED_ADMIN_EMAIL", "admin@federfall.local")
ADMIN_PASS = os.environ.get("FED_ADMIN_PASS", "Admin12345!")
ORG = "org00000default"

_passed = 0
_failed = 0


def check(name, ok, detail=""):
    global _passed, _failed
    if ok:
        _passed += 1
        print(f"  \033[32mPASS\033[0m {name}")
    else:
        _failed += 1
        print(f"  \033[31mFAIL\033[0m {name}  {detail}")


def req(method, path, token=None, body=None):
    """Return (status, parsed_json_or_None)."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = token
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(r)
        raw = resp.read().decode()
        return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, None


def upload_file(method, path, token, field, filename, content_type, blob):
    """Multipart upload of a single [blob] to [field]. Returns (status, json)."""
    boundary = "----fedtestboundary"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
        f"Content-Type: {content_type}\r\n\r\n"
    ).encode() + blob + f"\r\n--{boundary}--\r\n".encode()
    headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Authorization": token,
    }
    r = urllib.request.Request(BASE + path, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(r)
        raw = resp.read().decode()
        return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, None


def admin_token():
    s, d = req("POST", "/api/collections/_superusers/auth-with-password",
               body={"identity": ADMIN_EMAIL, "password": ADMIN_PASS})
    if s != 200:
        print("FATAL: cannot authenticate superuser", s, d)
        sys.exit(2)
    return d["token"]


def login(email, pw="Pass12345!"):
    s, d = req("POST", "/api/collections/users/auth-with-password",
               body={"identity": email, "password": pw})
    return (s, d["token"] if s == 200 else None)


def mk(token, coll, body):
    s, d = req("POST", f"/api/collections/{coll}/records", token, body)
    if s != 200:
        print(f"FATAL: failed to create {coll}: {s} {d}")
        sys.exit(2)
    return d


def mkuser(token, email, role, org=ORG, active=True):
    return mk(token, "users", {
        "email": email, "password": "Pass12345!", "passwordConfirm": "Pass12345!",
        "role": role, "org": org, "is_active": active, "verified": True,
    })


def listf(token, coll, flt):
    s, d = req("GET", f"/api/collections/{coll}/records?filter=" + urllib.parse.quote(flt), token)
    return d["items"] if s == 200 else []


def main():
    T = admin_token()

    # ── schema / seed sanity ────────────────────────────────────────────────
    print("\n[schema & seed]")
    s, d = req("GET", f"/api/collections/organisations/records/{ORG}", T)
    check("launch org seeded", s == 200 and d.get("name") == "Federfall", f"{s} {d}")
    conds = listf(T, "conditions", "active = true")
    check("conditions code list seeded (>=20)", len(conds) >= 20, f"got {len(conds)}")
    notif = [c["label"] for c in listf(T, "conditions", "is_notifiable = true")]
    check("PMV is NOT flagged notifiable", not any("PMV" in x for x in notif), notif)

    # ── federfall-7nf.1: server identity & capabilities discovery ────────────
    print("\n[federfall info]")
    s, info = req("GET", "/api/federfall/info")  # no token: must be public
    check("GET /api/federfall/info is unauthenticated (200)", s == 200, f"status {s}")
    check("carries the federfall identity marker",
          bool(info) and info.get("federfall") is True
          and info.get("service") == "federfall", info)
    check("reports a version and minClient",
          bool(info) and bool(info.get("version")) and bool(info.get("minClient")),
          info)
    auth = (info or {}).get("auth") or {}
    check("password auth is enabled", auth.get("password") is True, auth)
    check("oauth2 is a list", isinstance(auth.get("oauth2"), list), auth)
    check("self-signup is off (invite-only)", auth.get("selfSignup") is False, auth)

    # ── fixtures ────────────────────────────────────────────────────────────
    A = mkuser(T, "a@f.local", "carer")["id"]
    B = mkuser(T, "b@f.local", "carer")["id"]
    C = mkuser(T, "c@f.local", "carer")["id"]
    D = mkuser(T, "d@f.local", "carer")["id"]
    SUP = mkuser(T, "sup@f.local", "supervisor")["id"]
    COORD = mkuser(T, "coord@f.local", "coordinator")["id"]
    INACTIVE = mkuser(T, "inactive@f.local", "carer", active=False)["id"]
    animal = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]

    # ── hooks: case_number / quarantine / status ────────────────────────────
    print("\n[hooks: case create]")
    c1 = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG, "admitted_at": "2026-03-10 09:00:00.000Z"})
    c2 = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG, "admitted_at": "2026-05-01 09:00:00.000Z"})
    c3 = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG, "admitted_at": "2025-12-01 09:00:00.000Z"})
    check("case_number 1st of 2026 = 2026-001", c1["case_number"] == "2026-001", c1["case_number"])
    check("case_number increments = 2026-002", c2["case_number"] == "2026-002", c2["case_number"])
    check("case_number resets per year = 2025-001", c3["case_number"] == "2025-001", c3["case_number"])
    check("status defaults to in_care", c1["status"] == "in_care", c1["status"])
    # Quarantine is a timeline record (federfall-uvm), not a case field: the
    # hook creates one default 14-day quarantine_records row on intake.
    qrows = listf(T, "quarantine_records", f'case="{c1["id"]}"')
    check("default quarantine row = admitted + 14d",
          len(qrows) == 1 and qrows[0]["quarantine_until"][:10] == "2026-03-24",
          qrows)
    # federfall-4k4: the max must be derived numerically ("2024-1000" >
    # "2024-999" only as numbers) and the prefix match anchored (a manual
    # "ALT-2024-7" CONTAINS "2024-" but must not pollute the sequence).
    # Year 2024 keeps this independent of the 2026/2025 sequences above.
    mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG,
                    "admitted_at": "2024-02-01 09:00:00.000Z",
                    "case_number": "2024-999"})
    c4 = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG,
                         "admitted_at": "2024-02-02 09:00:00.000Z"})
    check("case_number crosses 1000 (numeric max)",
          c4["case_number"] == "2024-1000", c4["case_number"])
    mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG,
                    "admitted_at": "2024-02-03 09:00:00.000Z",
                    "case_number": "ALT-2024-7"})
    c5 = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG,
                         "admitted_at": "2024-02-04 09:00:00.000Z"})
    check("foreign-format manual number does not pollute the sequence",
          c5["case_number"] == "2024-1001", c5["case_number"])
    # federfall-28m: numbering is generated per org, so the unique index must
    # be org-scoped too — a second org's first 2026 case gets "2026-001" even
    # though this org already minted that number above.
    xorg = mk(T, "organisations", {"name": "Index-Orga"})["id"]
    xanimal = mk(T, "animals", {"species": "Stadttaube", "org": xorg})["id"]
    s, x1 = req("POST", "/api/collections/cases/records", T,
                {"animal": xanimal, "active_carer": A, "org": xorg,
                 "admitted_at": "2026-03-15 09:00:00.000Z"})
    check("second org can mint the same per-year number (org-scoped index)",
          s == 200 and x1.get("case_number") == "2026-001",
          f"{s} {x1.get('case_number') if x1 else x1}")

    # ── hooks: dispositions ─────────────────────────────────────────────────
    print("\n[hooks: dispositions]")
    mk(T, "dispositions", {"case": c1["id"], "type": "released", "org": ORG})
    _, c1f = req("GET", f"/api/collections/cases/records/{c1['id']}", T)
    _, anf = req("GET", f"/api/collections/animals/records/{animal}", T)
    check("released -> case disposed", c1f["status"] == "disposed", c1f["status"])
    check("released -> animal at_large_released", anf["lifetime_status"] == "at_large_released", anf["lifetime_status"])
    av = mk(T, "aviaries", {"name": "Voliere 1", "org": ORG})["id"]
    mk(T, "dispositions", {"case": c2["id"], "type": "placed_in_aviary", "aviary": av, "org": ORG})
    _, c2f = req("GET", f"/api/collections/cases/records/{c2['id']}", T)
    _, an2 = req("GET", f"/api/collections/animals/records/{animal}", T)
    check("placed_in_aviary -> case disposed", c2f["status"] == "disposed", c2f["status"])
    check("placed_in_aviary -> animal in_aviary", an2["lifetime_status"] == "in_aviary", an2["lifetime_status"])
    check("placed_in_aviary -> current_aviary set", an2["current_aviary"] == av, an2["current_aviary"])

    # ── hooks: disposition edit/delete reconciliation (UX Phase B) ──────────
    # Fresh animal/case so we don't disturb the shared `animal` state above.
    ra = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    rc = mk(T, "cases", {"animal": ra, "active_carer": A, "org": ORG})["id"]
    rd = mk(T, "dispositions", {"case": rc, "type": "released", "org": ORG})["id"]
    _, raf = req("GET", f"/api/collections/animals/records/{ra}", T)
    check("reconcile setup -> at_large_released",
          raf["lifetime_status"] == "at_large_released", raf["lifetime_status"])

    # Editing the outcome type re-derives the animal's lifetime.
    req("PATCH", f"/api/collections/dispositions/records/{rd}", T, {"type": "died"})
    _, raf = req("GET", f"/api/collections/animals/records/{ra}", T)
    _, rcf = req("GET", f"/api/collections/cases/records/{rc}", T)
    check("edit outcome died -> animal deceased",
          raf["lifetime_status"] == "deceased", raf["lifetime_status"])
    check("edit outcome -> case stays disposed", rcf["status"] == "disposed", rcf["status"])

    # Deleting the only disposition re-opens the case and reverts the animal.
    req("DELETE", f"/api/collections/dispositions/records/{rd}", T)
    _, raf = req("GET", f"/api/collections/animals/records/{ra}", T)
    _, rcf = req("GET", f"/api/collections/cases/records/{rc}", T)
    check("delete outcome -> case re-opens (in_care)",
          rcf["status"] == "in_care", rcf["status"])
    check("delete outcome -> animal back to in_care",
          raf["lifetime_status"] == "in_care", raf["lifetime_status"])

    # ── hooks: share-on-handoff ─────────────────────────────────────────────
    print("\n[hooks: share-on-handoff]")
    req("PATCH", f"/api/collections/cases/records/{c3['id']}", T, {"active_carer": B})
    shares = {s["shared_with"]: s["access"] for s in listf(T, "case_shares", f'case="{c3["id"]}"')}
    check("handoff A->B leaves A a read share", shares.get(A) == "read", shares)
    req("PATCH", f"/api/collections/cases/records/{c3['id']}", T, {"active_carer": A})
    shares = {s["shared_with"]: s["access"] for s in listf(T, "case_shares", f'case="{c3["id"]}"')}
    check("handoff B->A leaves B a read share (A preserved)", shares.get(B) == "read" and A in shares, shares)

    # ── access rules: the matrix ────────────────────────────────────────────
    # fresh case owned by A, B=read share, C=edit share
    print("\n[access rules]")
    case = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    finder = mk(T, "finders", {"last_name": "Müller", "org": ORG})["id"]
    req("PATCH", f"/api/collections/cases/records/{case}", T, {"finder": finder})
    mk(T, "case_shares", {"case": case, "shared_with": B, "access": "read", "org": ORG})
    mk(T, "case_shares", {"case": case, "shared_with": C, "access": "edit", "org": ORG})
    weight = mk(T, "weights", {"animal": animal, "case": case, "weight_g": 300, "org": ORG})["id"]

    toks = {who: login(f"{who}@f.local")[1] for who in ["a", "b", "c", "d", "sup", "coord"]}

    def can_view(tok):
        s, _ = req("GET", f"/api/collections/cases/records/{case}", tok)
        return s == 200

    def can_edit(tok):
        s, _ = req("PATCH", f"/api/collections/cases/records/{case}", tok, {"intake_notes": "x"})
        return s == 200

    def can_view_finder(tok):
        s, _ = req("GET", f"/api/collections/finders/records/{finder}", tok)
        return s == 200

    def can_create_weight(tok):
        s, _ = req("POST", "/api/collections/weights/records", tok, {"animal": animal, "case": case, "weight_g": 310, "org": ORG})
        return s == 200

    def can_create_admin(tok):
        s, _ = req("POST", "/api/collections/medication_administrations/records", tok,
                   {"case": case, "drug": "Baytril", "administered_at": "2026-06-09 08:00:00.000Z", "org": ORG})
        return s == 200

    # owner
    check("owner can view case", can_view(toks["a"]))
    check("owner can edit case", can_edit(toks["a"]))
    # outsider — private by default
    check("outsider CANNOT view case", not can_view(toks["d"]))
    check("outsider CANNOT edit case", not can_edit(toks["d"]))
    check("outsider CANNOT view finder PII", not can_view_finder(toks["d"]))
    check("outsider CANNOT log administration", not can_create_admin(toks["d"]))
    # read share
    check("read-share can view case", can_view(toks["b"]))
    check("read-share CANNOT edit case (no escalation)", not can_edit(toks["b"]))
    check("read-share can view finder PII", can_view_finder(toks["b"]))
    # edit share
    check("edit-share can view case", can_view(toks["c"]))
    check("edit-share can edit case", can_edit(toks["c"]))
    check("edit-share can log administration", can_create_admin(toks["c"]))
    # weights are an animal-level layer (5yg.4): org-wide, not case-private —
    # so any active org member may add one, with or without a case.
    check("any org member can add a weight", can_create_weight(toks["d"]))
    s, _ = req("POST", "/api/collections/weights/records", toks["d"],
               {"animal": animal, "weight_g": 305, "org": ORG})
    check("a weight can be recorded with no case", s == 200, f"status {s}")
    # coordinator: all-read, no edit
    check("coordinator can view any case", can_view(toks["coord"]))
    check("coordinator CANNOT edit", not can_edit(toks["coord"]))
    check("coordinator can view finder PII", can_view_finder(toks["coord"]))
    # supervisor: all
    check("supervisor can view", can_view(toks["sup"]))
    check("supervisor can edit", can_edit(toks["sup"]))

    # handoff visibility: previous carer keeps read but not edit
    print("\n[handoff visibility]")
    req("PATCH", f"/api/collections/cases/records/{case}", T, {"active_carer": D})
    td = login("d@f.local")[1]
    check("post-handoff: new carer D can edit", can_edit(td))
    ta = toks["a"]
    check("post-handoff: previous carer A still views", can_view(ta))
    check("post-handoff: previous carer A cannot edit", not can_edit(ta))
    # restore A as carer for any later checks
    req("PATCH", f"/api/collections/cases/records/{case}", T, {"active_carer": A})

    # ── opt-in share lifecycle (FED-5.2) ────────────────────────────────────
    # End-to-end via carer tokens (not admin): the owner grants/revokes a share
    # and a non-owner cannot; visibility flips accordingly.
    print("\n[opt-in share lifecycle]")
    ta = toks["a"]
    td = login("d@f.local")[1]
    shareCase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]

    def d_views():
        s, _ = req("GET", f"/api/collections/cases/records/{shareCase}", td)
        return s == 200

    def d_edits():
        s, _ = req(
            "PATCH", f"/api/collections/cases/records/{shareCase}", td,
            {"intake_notes": "x"},
        )
        return s == 200

    check("before share: outsider cannot view", not d_views())
    # An outsider cannot grant a share on a case they don't own.
    s, _ = req("POST", "/api/collections/case_shares/records", td, {
        "case": shareCase, "shared_with": D, "access": "read",
        "shared_by": D, "org": ORG,
    })
    check("outsider CANNOT grant themselves a share", s >= 400, f"status {s}")
    # The owner (carer, not admin) grants a read share to D.
    s, sh = req("POST", "/api/collections/case_shares/records", ta, {
        "case": shareCase, "shared_with": D, "access": "read",
        "shared_by": A, "org": ORG,
    })
    check("owner can grant a read share", s == 200, f"{s} {sh}")
    check("after share: D can view", d_views())
    check("read share: D still cannot edit", not d_edits())
    if s == 200:
        sd, _ = req(
            "DELETE", f"/api/collections/case_shares/records/{sh['id']}", ta,
        )
        check("owner can revoke the share", sd == 204, f"status {sd}")
        check("after revoke: D can no longer view", not d_views())

    # ── deactivated user cannot authenticate ────────────────────────────────
    print("\n[auth gate]")
    s, _ = login("inactive@f.local")
    check("deactivated user cannot authenticate", s != 200, f"status {s}")

    # ── users field guard ───────────────────────────────────────────────────
    print("\n[field guard]")
    ta = toks["a"]
    s, _ = req("PATCH", f"/api/collections/users/records/{A}", ta, {"name": "Alice"})
    check("self can edit own name", s == 200, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/users/records/{A}", ta, {"role": "supervisor"})
    check("self CANNOT escalate role", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/users/records/{A}", ta, {"is_active": False})
    check("self CANNOT change is_active", s >= 400, f"status {s}")

    # ── federfall-d1uv: cross-org move via users.updateRule ─────────────────
    # A supervisor may not plant a same-org user (or themselves) into another
    # org by setting `org` in the update body — even though the target's
    # CURRENT org still matches the caller's, which the old rule alone allowed.
    tsup = toks["sup"]
    xorg2 = mk(T, "organisations", {"name": "Cross-Org-Target"})["id"]
    s, _ = req("PATCH", f"/api/collections/users/records/{B}", tsup, {"org": xorg2})
    check("supervisor CANNOT move another user cross-org", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/users/records/{SUP}", tsup, {"org": xorg2})
    check("supervisor CANNOT move themselves cross-org", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/users/records/{B}", tsup, {"org": ORG})
    check("same-org 'update' (org unchanged) still allowed", s == 200, f"status {s}")

    # ── federfall-0kl: last-supervisor lockout guard ────────────────────────
    # An isolated org with a single supervisor: demoting, deactivating, moving
    # or deleting them must be blocked (even for a superuser) until another
    # active supervisor exists in that org.
    print("\n[last-supervisor lockout guard]")
    lorg = mk(T, "organisations", {"name": "Lockout-Orga"})["id"]
    S1 = mkuser(T, "lock-sup1@f.local", "supervisor", org=lorg)["id"]
    ts1 = login("lock-sup1@f.local")[1]
    s, _ = req("PATCH", f"/api/collections/users/records/{S1}", ts1,
               {"is_active": False})
    check("last supervisor CANNOT deactivate themselves", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/users/records/{S1}", ts1,
               {"role": "carer"})
    check("last supervisor CANNOT demote themselves", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/users/records/{S1}", T,
               {"role": "carer"})
    check("superuser CANNOT demote the last supervisor either", s >= 400,
          f"status {s}")
    s, _ = req("DELETE", f"/api/collections/users/records/{S1}", T)
    check("last supervisor CANNOT be deleted", s >= 400, f"status {s}")
    # With a second active supervisor the same changes go through.
    S2 = mkuser(T, "lock-sup2@f.local", "supervisor", org=lorg)["id"]
    s, _ = req("PATCH", f"/api/collections/users/records/{S1}", ts1,
               {"role": "carer"})
    check("demotion allowed once another supervisor exists", s == 200,
          f"status {s}")
    # ...which makes S2 the last one — now S2 is protected.
    s, _ = req("DELETE", f"/api/collections/users/records/{S2}", T)
    check("the remaining supervisor is now protected", s >= 400, f"status {s}")

    # ── federfall-p5n: weights delete is author-or-supervisor ───────────────
    # Weights stay org-wide creatable/updatable (identity layer), but only the
    # author or a supervisor may delete one — a carer can no longer erase
    # another carer's clinical weight history.
    print("\n[weights delete guard]")
    s, wA = req("POST", "/api/collections/weights/records", toks["a"],
                {"animal": animal, "weight_g": 321, "org": ORG, "author": A})
    check("setup: A logs a weight", s == 200, f"{s} {wA}")
    s, _ = req("DELETE", f"/api/collections/weights/records/{wA['id']}", toks["b"])
    check("another member CANNOT delete A's weight", s != 204, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/weights/records/{wA['id']}", toks["a"])
    check("the author can delete their own weight", s == 204, f"status {s}")
    s, wB = req("POST", "/api/collections/weights/records", toks["b"],
                {"animal": animal, "weight_g": 322, "org": ORG, "author": B})
    check("setup: B logs a weight", s == 200, f"{s} {wB}")
    s, _ = req("DELETE", f"/api/collections/weights/records/{wB['id']}", toks["sup"])
    check("a supervisor can delete any weight", s == 204, f"status {s}")

    # ── org isolation ───────────────────────────────────────────────────────
    print("\n[org isolation]")
    org2 = mk(T, "organisations", {"name": "Andere Orga"})["id"]
    E = mkuser(T, "e@f.local", "supervisor", org=org2)["id"]
    te = login("e@f.local")[1]
    # E is a supervisor but in a DIFFERENT org — must not see org1's case
    s, _ = req("GET", f"/api/collections/cases/records/{case}", te)
    check("supervisor of another org CANNOT view this org's case", s != 200, f"status {s}")

    # ── immutable boundary relations (federfall-621) ────────────────────────
    # PocketBase evaluates plain field refs in UPDATE rules against the STORED
    # record, so without the :isset guards a carer could create a share on
    # their own case and then re-point it at a private foreign case
    # (privilege escalation), or an edit-share holder could re-point a child
    # record into a foreign case's timeline.
    print("\n[immutable boundary relations]")
    ta = toks["a"]
    td = login("d@f.local")[1]
    victim = mk(T, "cases", {"animal": animal, "active_carer": B, "org": ORG})["id"]
    s, _ = req("GET", f"/api/collections/cases/records/{victim}", ta)
    check("setup: A cannot view B's private case", s != 200, f"status {s}")
    # A legitimately shares their OWN (fresh) case with D — `case` already
    # carries a hook-created share for D from the handoff tests above.
    atkcase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    s, sh = req("POST", "/api/collections/case_shares/records", ta, {
        "case": atkcase, "shared_with": D, "access": "read",
        "shared_by": A, "org": ORG,
    })
    check("setup: A shares own case with D", s == 200, f"{s} {sh}")
    # ...then tries to re-point the share at the victim case.
    s, _ = req("PATCH", f"/api/collections/case_shares/records/{sh['id']}", ta,
               {"case": victim})
    check("share.case is immutable (no re-point escalation)", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/case_shares/records/{sh['id']}", ta,
               {"shared_with": A})
    check("share.shared_with is immutable", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/case_shares/records/{sh['id']}", ta,
               {"org": org2})
    check("share.org is immutable", s >= 400, f"status {s}")
    s, _ = req("GET", f"/api/collections/cases/records/{victim}", td)
    check("D still cannot view the victim case", s != 200, f"status {s}")
    # Changing only the access level remains a legitimate update.
    s, _ = req("PATCH", f"/api/collections/case_shares/records/{sh['id']}", ta,
               {"access": "edit"})
    check("share.access alone stays editable", s == 200, f"status {s}")
    req("DELETE", f"/api/collections/case_shares/records/{sh['id']}", ta)
    # A case's org scope is immutable too.
    s, _ = req("PATCH", f"/api/collections/cases/records/{case}", ta, {"org": org2})
    check("case.org is immutable", s >= 400, f"status {s}")
    # Child records: C holds an edit share on A's case — content edits are
    # fine, but re-pointing the row's case (or org) must be rejected.
    tc = toks["c"]
    s, je = req("POST", "/api/collections/journal_entries/records", tc,
                {"case": case, "text": "wound check", "org": ORG})
    check("setup: edit-share C can add a journal entry", s == 200, f"{s} {je}")
    s, _ = req("PATCH", f"/api/collections/journal_entries/records/{je['id']}", tc,
               {"case": victim})
    check("journal_entry.case is immutable (no timeline injection)",
          s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/journal_entries/records/{je['id']}", tc,
               {"org": org2})
    check("journal_entry.org is immutable", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/journal_entries/records/{je['id']}", tc,
               {"text": "wound check — healing well"})
    check("journal_entry content stays editable", s == 200, f"status {s}")

    # ── case_summaries view (FED-7.6) ───────────────────────────────────────
    # Org-wide, clinical-detail-free projection: an outsider in the same org may
    # read a case's SUMMARY (for the animal lifetime record) but never the full
    # case; another org sees nothing.
    print("\n[case summaries view]")
    sumcase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    td = login("d@f.local")[1]

    def full_case(tok, cid):
        s, _ = req("GET", f"/api/collections/cases/records/{cid}", tok)
        return s == 200

    def summary(tok, cid):
        s, _ = req("GET", f"/api/collections/case_summaries/records/{cid}", tok)
        return s == 200

    # D is not the carer of sumcase and holds no share on it.
    check("same-org outsider CANNOT view full case", not full_case(td, sumcase))
    check("same-org outsider CAN view case summary", summary(td, sumcase))
    check("owner can view case summary", summary(toks["a"], sumcase))
    # Summary carries no clinical fields (notes/exam/weight/photos/reasons).
    _, srec = req("GET", f"/api/collections/case_summaries/records/{sumcase}", td)
    leaked = [k for k in ("intake_notes", "intake_weight_g", "exam_bcs",
                          "intake_photos", "admission_reasons") if k in srec]
    check("summary exposes no clinical fields", not leaked, leaked)
    # Org isolation: another org's member sees no summary.
    check("other-org member CANNOT view case summary", not summary(te, sumcase))

    # ── animal photo upload (ctw.7) ─────────────────────────────────────────
    # The animals.photo file field accepts an image upload from an org member
    # and stores a filename; it's then readable (org-wide identity layer).
    print("\n[animal photo upload]")
    s, d = upload_file(
        "PATCH", f"/api/collections/animals/records/{animal}",
        toks["a"], "photo", "p.png", "image/png", _PNG_1X1,
    )
    check("org member can upload an animal photo", s == 200 and bool(d.get("photo")), f"{s} {d}")
    _, dd = req("GET", f"/api/collections/animals/records/{animal}", toks["d"])
    check("uploaded animal photo is stored & readable", bool(dd.get("photo")), dd)

    # ── protected file access (FED-8.1 / 49l.1) ─────────────────────────────
    # animals.photo is a Protected file field: its URL is only served with a
    # short-lived file token issued for an auth model that can read the owning
    # record. A bare URL must be rejected; a same-org member's token works; an
    # other-org member's token does not (they cannot view this org's animal).
    print("\n[protected file access]")
    photo = dd.get("photo")
    file_path = f"/api/files/animals/{animal}/{photo}"

    def file_status(path):
        r = urllib.request.Request(BASE + path, method="GET")
        try:
            return urllib.request.urlopen(r).status
        except urllib.error.HTTPError as e:
            return e.code

    def file_token(tok):
        s, d = req("POST", "/api/files/token", tok)
        return d["token"] if s == 200 else None

    # No token → rejected (the whole point of Protected).
    check("protected file URL WITHOUT a token is rejected",
          file_status(file_path) != 200, file_status(file_path))
    # Same-org member's token → served.
    tok_d = file_token(toks["d"])
    check("same-org member's file token serves the photo",
          file_status(f"{file_path}?token={tok_d}") == 200)
    # Other-org member's token → rejected (cannot view this org's animal).
    tok_e = file_token(te)
    check("other-org member's file token CANNOT serve the photo",
          file_status(f"{file_path}?token={tok_e}") != 200)

    # ── upload MIME allowlist (federfall-8a5) ───────────────────────────────
    # intake_photos / attachments are Protected but same-origin: an active
    # (HTML/SVG) upload would be stored XSS for any org member who opens the
    # file URL. Both fields must only accept the image allowlist.
    print("\n[upload MIME allowlist]")
    _SVG = b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
    _HTML = b"<!DOCTYPE html><script>alert(1)</script>"
    s, d = upload_file(
        "PATCH", f"/api/collections/cases/records/{case}",
        ta, "intake_photos", "evil.svg", "image/svg+xml", _SVG,
    )
    check("SVG upload to cases.intake_photos is rejected", s >= 400, f"{s} {d}")
    s, d = upload_file(
        "PATCH", f"/api/collections/cases/records/{case}",
        ta, "intake_photos", "evil.html", "text/html", _HTML,
    )
    check("HTML upload to cases.intake_photos is rejected", s >= 400, f"{s} {d}")
    s, d = upload_file(
        "PATCH", f"/api/collections/cases/records/{case}",
        ta, "intake_photos", "ok.png", "image/png", _PNG_1X1,
    )
    check("PNG upload to cases.intake_photos still works",
          s == 200 and bool(d.get("intake_photos")), f"{s} {d}")
    s, d = upload_file(
        "PATCH", f"/api/collections/journal_entries/records/{je['id']}",
        tc, "attachments", "evil.svg", "image/svg+xml", _SVG,
    )
    check("SVG upload to journal_entries.attachments is rejected",
          s >= 400, f"{s} {d}")
    s, d = upload_file(
        "PATCH", f"/api/collections/journal_entries/records/{je['id']}",
        tc, "attachments", "ok.png", "image/png", _PNG_1X1,
    )
    check("PNG upload to journal_entries.attachments still works",
          s == 200 and bool(d.get("attachments")), f"{s} {d}")

    # ── case_activity view (cr3.5) ──────────────────────────────────────────
    # last_activity reflects the newest child-record touch and is org-scoped
    # readable (timestamp only, no clinical detail). Powers the worklist's
    # "stale cases" source.
    print("\n[case activity view]")
    actcase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]

    def activity(tok, cid):
        s, d = req("GET", f"/api/collections/case_activity/records/{cid}", tok)
        return s, d

    s, rec = activity(toks["a"], actcase)
    check("owner can read case_activity", s == 200, f"{s} {rec}")
    base = rec.get("last_activity") if rec else None
    check("case_activity has a last_activity stamp", bool(base), rec)
    # A fresh child touch must move last_activity forward.
    mk(T, "weights", {"animal": animal, "case": actcase, "weight_g": 333, "org": ORG})
    _, rec2 = activity(toks["a"], actcase)
    check("last_activity advances after a new child record",
          rec2 and rec2.get("last_activity") >= base, f"{base} -> {rec2}")
    # Org isolation: another org's member sees nothing.
    s, _ = activity(te, actcase)
    check("other-org member CANNOT read case_activity", s != 200, f"status {s}")

    # ── follow_ups (cr3.4) ──────────────────────────────────────────────────
    # Case-scoped like the other clinical child records: the owner can schedule
    # and read a recheck; a same-org outsider with no share cannot; another org
    # sees nothing.
    print("\n[follow_ups]")
    fucase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]

    def mk_followup(tok):
        return req("POST", "/api/collections/follow_ups/records", tok, {
            "case": fucase, "due_at": "2026-07-01 09:00:00.000Z",
            "note": "recheck wound", "org": ORG,
        })

    s, fu = mk_followup(toks["a"])
    check("owner can schedule a recheck", s == 200, f"{s} {fu}")
    s, _ = req("GET", f"/api/collections/follow_ups/records/{fu['id']}", toks["a"])
    check("owner can read the recheck", s == 200, f"status {s}")
    s, _ = mk_followup(td)
    check("same-org outsider CANNOT schedule a recheck", s != 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/follow_ups/records/{fu['id']}", td)
    check("same-org outsider CANNOT read the recheck", s != 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/follow_ups/records/{fu['id']}", te)
    check("other-org member CANNOT read the recheck", s != 200, f"status {s}")

    # ── medication_due view (cr3.6) ─────────────────────────────────────────
    # next_due = last_dose + interval_hours for a scheduled med; the view is the
    # carer's worklist source, scoped to their own cases.
    print("\n[medication_due view]")
    mdcase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    med = mk(T, "medications", {
        "case": mdcase, "drug": "Meloxicam", "frequency_kind": "scheduled",
        "interval_hours": 12, "org": ORG,
    })["id"]
    mk(T, "medication_administrations", {
        "case": mdcase, "medication": med, "drug": "Meloxicam",
        "administered_at": "2026-06-20 08:00:00.000Z", "org": ORG,
    })
    s, row = req("GET", f"/api/collections/medication_due/records/{med}", toks["a"])
    check("owner can read medication_due row", s == 200, f"{s} {row}")
    # 2026-06-20 08:00 + 12h = 2026-06-20 20:00.
    nd = (row or {}).get("next_due", "")
    check("next_due = last dose + interval", nd.startswith("2026-06-20 20:00"), nd)
    # Scoped to the carer: another carer in the org does not see the row.
    s, _ = req("GET", f"/api/collections/medication_due/records/{med}", toks["b"])
    check("other carer CANNOT read the medication_due row", s != 200, f"status {s}")

    # ── exams + exam_findings (FED-4.8 / blp.6) ─────────────────────────────
    # exams is a case-scoped clinical record like the others. exam_findings is a
    # GRANDCHILD whose rules traverse exam.case — verify that traversal grants
    # the owner access and still denies a same-org outsider / another org.
    print("\n[exams]")
    excase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]

    def mk_exam(tok):
        return req("POST", "/api/collections/exams/records", tok, {
            "case": excase, "animal": animal, "body_condition": 3,
            "hydration": "moderate", "mentation": "quiet", "org": ORG,
        })

    s, ex = mk_exam(toks["a"])
    check("owner can record an exam", s == 200, f"{s} {ex}")
    s, _ = req("GET", f"/api/collections/exams/records/{ex['id']}", toks["a"])
    check("owner can read the exam", s == 200, f"status {s}")
    s, _ = mk_exam(td)
    check("same-org outsider CANNOT record an exam", s != 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/exams/records/{ex['id']}", td)
    check("same-org outsider CANNOT read the exam", s != 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/exams/records/{ex['id']}", te)
    check("other-org member CANNOT read the exam", s != 200, f"status {s}")

    print("\n[exam_findings]")

    def mk_finding(tok):
        return req("POST", "/api/collections/exam_findings/records", tok, {
            "exam": ex["id"], "system": "legs_feet", "status": "abnormal",
            "note": "pododermatitis", "org": ORG,
        })

    s, ef = mk_finding(toks["a"])
    check("owner can add a finding (exam.case traversal)", s == 200, f"{s} {ef}")
    s, _ = req("GET", f"/api/collections/exam_findings/records/{ef['id']}", toks["a"])
    check("owner can read the finding", s == 200, f"status {s}")
    s, _ = mk_finding(td)
    check("same-org outsider CANNOT add a finding", s != 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/exam_findings/records/{ef['id']}", td)
    check("same-org outsider CANNOT read the finding", s != 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/exam_findings/records/{ef['id']}", te)
    check("other-org member CANNOT read the finding", s != 200, f"status {s}")
    # Grandchild boundary (federfall-621): the finding's `exam` relation is
    # its access path — re-pointing it at a foreign exam must be rejected.
    vexcase = mk(T, "cases", {"animal": animal, "active_carer": B, "org": ORG})["id"]
    vexam = mk(T, "exams", {"case": vexcase, "animal": animal, "org": ORG})["id"]
    s, _ = req("PATCH", f"/api/collections/exam_findings/records/{ef['id']}",
               toks["a"], {"exam": vexam})
    check("finding.exam is immutable (no re-point)", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/exam_findings/records/{ef['id']}",
               toks["a"], {"note": "pododermatitis, improving"})
    check("finding content stays editable", s == 200, f"status {s}")

    # ── guest role: can authenticate, but walled off from all data ──────────
    print("\n[guest role]")
    mkuser(T, "guest@f.local", "guest")
    gs, gtok = login("guest@f.local")
    check("guest can authenticate", gs == 200 and bool(gtok), f"status {gs}")
    s, _ = req("POST", "/api/collections/animals/records", gtok,
               {"species": "Stadttaube", "org": ORG})
    check("guest CANNOT create an animal", s != 200, f"status {s}")
    s, _ = req("POST", "/api/collections/finders/records", gtok,
               {"first_name": "X", "org": ORG})
    check("guest CANNOT create a finder (PII)", s != 200, f"status {s}")
    s, _ = req("POST", "/api/collections/cases/records", gtok,
               {"animal": animal, "active_carer": A, "org": ORG})
    check("guest CANNOT create a case", s != 200, f"status {s}")
    check("guest sees no animals (list filtered)",
          len(listf(gtok, "animals", "id != ''")) == 0, "non-empty")
    check("guest sees no cases (list filtered)",
          len(listf(gtok, "cases", "id != ''")) == 0, "non-empty")
    # federfall-7ok: collections/views created AFTER the guest-role migration
    # must carry the same wall (1700000045 re-applies it; this sweep catches
    # any future migration that copies the auth predicate without the guest
    # exclusion). The member check keeps the guest check non-vacuous.
    for coll in ("admission_reasons", "marking_types", "medication_routes",
                 "quarantine_records", "case_quarantine", "animal_species"):
        n = len(listf(toks["a"], coll, "id != ''"))
        check(f"member sees {coll} (wall check is non-vacuous)", n > 0, "empty")
        check(f"guest sees no {coll}",
              len(listf(gtok, coll, "id != ''")) == 0, "non-empty")
    # The OAuth2 createRule (@request.context = "oauth2") must NOT let an
    # anonymous API client create users directly (that path is context default).
    s, _ = req("POST", "/api/collections/users/records", None, {
        "email": "intruder@f.local", "password": "Pass12345!",
        "passwordConfirm": "Pass12345!", "role": "supervisor", "org": ORG,
    })
    check("anonymous direct user creation is denied", s != 200, f"status {s}")

    # ── federfall-zod: atomic intake route + cases.finder lock ──────────────
    print("\n[atomic intake route]")
    s, _ = req("POST", "/api/federfall/intake", None, {"species": "Stadttaube"})
    check("intake requires auth", s == 401, f"status {s}")
    s, _ = req("POST", "/api/federfall/intake", gtok, {"species": "Stadttaube"})
    check("guest CANNOT intake", s == 403, f"status {s}")
    s, _ = req("POST", "/api/federfall/intake", toks["a"], {})
    check("intake without animal/species is rejected", s == 400, f"status {s}")

    s, ic = req("POST", "/api/federfall/intake", toks["a"], {
        "species": "Stadttaube", "name": "Zoe",
        "finder": {"last_name": "Fund", "phone": "0151 999"},
        "case": {"intake_notes": "thin but alert",
                 "admitted_at": "2026-06-01 10:00:00.000Z"},
        "weight_g": 250, "quarantine_days": 10,
    })
    check("intake creates the case", s == 200 and bool(ic and ic.get("id")), f"{s} {ic}")
    _, icase = req("GET", f"/api/collections/cases/records/{ic['id']}", T)
    check("intake case_number assigned by hook",
          bool(icase.get("case_number")), icase.get("case_number"))
    check("intake org/carer come from the session",
          icase["org"] == ORG and icase["active_carer"] == A,
          f"{icase.get('org')}/{icase.get('active_carer')}")
    ifinders = listf(T, "finders", 'last_name = "Fund"')
    check("intake created + linked the finder",
          len(ifinders) == 1 and icase["finder"] == ifinders[0]["id"],
          icase.get("finder"))
    iw = listf(T, "weights", f'case = "{ic["id"]}"')
    check("intake weight became a weights row",
          len(iw) == 1 and iw[0]["weight_g"] == 250, iw)
    iq = listf(T, "quarantine_records", f'case = "{ic["id"]}"')
    check("quarantine override row (admitted+10d), no default duplicate",
          len(iq) == 1 and iq[0]["quarantine_until"][:10] == "2026-06-11", iq)

    # Multipart intake: the Dart SDK sends the payload as an `@jsonPayload`
    # field next to the `intake_photos` files — exactly what the app does for
    # a photo intake.
    boundary = "----fedintakeboundary"
    payload = json.dumps({"species": "Stadttaube", "name": "Foto",
                          "case": {"intake_notes": "with photo"}})
    mp = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="@jsonPayload"\r\n\r\n'
        f"{payload}\r\n"
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="intake_photos"; filename="in.png"\r\n'
        "Content-Type: image/png\r\n\r\n"
    ).encode() + _PNG_1X1 + f"\r\n--{boundary}--\r\n".encode()
    r = urllib.request.Request(
        BASE + "/api/federfall/intake", data=mp, method="POST",
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}",
                 "Authorization": toks["a"]})
    try:
        resp = urllib.request.urlopen(r)
        s, mic = resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as err:
        s, mic = err.code, None
    check("multipart intake (jsonPayload + photos) succeeds",
          s == 200 and bool(mic and mic.get("id")), f"status {s}")
    _, mcase = req("GET", f"/api/collections/cases/records/{mic['id']}", T)
    check("multipart intake stored the photo",
          len(mcase.get("intake_photos") or []) == 1, mcase.get("intake_photos"))
    check("multipart intake parsed the jsonPayload fields",
          mcase.get("intake_notes") == "with photo", mcase.get("intake_notes"))

    # Atomicity: a case that fails validation must roll back the already-
    # created finder + animal (no orphaned, carer-invisible PII).
    s, _ = req("POST", "/api/federfall/intake", toks["a"], {
        "species": "Stadttaube", "name": "Ghostbird",
        "finder": {"last_name": "Ghost"},
        "case": {"admission_reasons": ["nonexistent00000"]},
    })
    check("intake with invalid case data fails", s >= 400, f"status {s}")
    check("failed intake strands no finder PII",
          len(listf(T, "finders", 'last_name = "Ghost"')) == 0)
    check("failed intake strands no animal",
          len(listf(T, "animals", 'name = "Ghostbird"')) == 0)

    # Re-identification must not accept a foreign org's animal.
    fanimal = mk(T, "animals", {"species": "Stadttaube", "org": org2})["id"]
    s, _ = req("POST", "/api/federfall/intake", toks["a"], {"animal": fanimal})
    check("intake CANNOT reuse a foreign-org animal", s == 400, f"status {s}")

    # cases.finder is locked for direct writes (federfall-9hy): linking is
    # exclusively the intake route's job.
    s, _ = req("POST", "/api/collections/cases/records", toks["a"],
               {"animal": animal, "active_carer": A, "org": ORG,
                "finder": ifinders[0]["id"]})
    check("direct case create with finder is rejected", s >= 400, f"status {s}")
    own = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    s, _ = req("PATCH", f"/api/collections/cases/records/{own}", toks["a"],
               {"finder": ifinders[0]["id"]})
    check("re-pointing cases.finder is rejected", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/cases/records/{own}", toks["a"],
               {"intake_notes": "still editable"})
    check("case content stays editable", s == 200, f"status {s}")

    # ── federfall-3ty3: intake idempotency key ───────────────────────────────
    print("\n[intake idempotency]")
    ikey = "itest-0123456789abcdef0123456789abcdef"
    s, i1 = req("POST", "/api/federfall/intake", toks["a"], {
        "species": "Stadttaube", "name": "Idem", "weight_g": 111,
        "idempotency_key": ikey,
    })
    check("keyed intake succeeds",
          s == 200 and bool(i1 and i1.get("id")), f"{s} {i1}")
    s, i2 = req("POST", "/api/federfall/intake", toks["a"], {
        "species": "Stadttaube", "name": "Idem", "weight_g": 111,
        "idempotency_key": ikey,
    })
    check("replaying the key returns the ORIGINAL result",
          s == 200 and bool(i2) and i2.get("id") == i1["id"]
          and i2.get("animal") == i1["animal"]
          and i2.get("case_number") == i1.get("case_number"), f"{s} {i2}")
    check("replay created no second animal",
          len(listf(T, "animals", 'name = "Idem"')) == 1)
    check("replay created no second weight row",
          len(listf(T, "weights", f'case = "{i1["id"]}"')) == 1)
    # Keys are scoped per user: another carer reusing the same key gets their
    # OWN intake, never user A's stored response.
    s, i3 = req("POST", "/api/federfall/intake", toks["b"], {
        "species": "Stadttaube", "name": "IdemB",
        "idempotency_key": ikey,
    })
    check("same key from another user creates a fresh intake",
          s == 200 and bool(i3) and i3.get("id") != i1["id"], f"{s} {i3}")
    s, _ = req("POST", "/api/federfall/intake", toks["a"], {
        "species": "Stadttaube", "idempotency_key": "x" * 65,
    })
    check("oversized idempotency_key is rejected", s == 400, f"status {s}")
    # Without a key, every request keeps creating (the pre-3ty3 behaviour).
    s, i4 = req("POST", "/api/federfall/intake", toks["a"],
                {"species": "Stadttaube", "name": "NoKey"})
    s, i5 = req("POST", "/api/federfall/intake", toks["a"],
                {"species": "Stadttaube", "name": "NoKey"})
    check("unkeyed intakes stay independent",
          bool(i4 and i5) and i4["id"] != i5["id"])

    # ── federfall-jfe: security headers (CSP + COOP/COEP scope) ─────────────
    print("\n[security headers]")

    def headers_of(path):
        r = urllib.request.Request(BASE + path, method="GET")
        try:
            return dict(urllib.request.urlopen(r).headers)
        except urllib.error.HTTPError as e:
            return dict(e.headers)

    fh = headers_of(f"/api/files/cases/{own}/nonexistent.png")
    check("uploaded files get the sandbox CSP",
          fh.get("Content-Security-Policy") == "default-src 'none'; sandbox",
          fh.get("Content-Security-Policy"))
    check("uploaded files get nosniff",
          fh.get("X-Content-Type-Options") == "nosniff")
    ah = headers_of("/api/health")
    check("API responses carry NO SPA CSP",
          "Content-Security-Policy" not in ah,
          ah.get("Content-Security-Policy"))
    sh = headers_of("/")
    spa_csp = sh.get("Content-Security-Policy") or ""
    check("SPA gets the CSP",
          spa_csp.startswith("default-src 'self'"), spa_csp)
    check("SPA CSP allows wasm + blocks embedding",
          "'wasm-unsafe-eval'" in spa_csp and "frame-ancestors 'none'" in spa_csp,
          spa_csp)
    check("SPA CSP allows the default tile origin",
          "https://tile.openstreetmap.org" in spa_csp, spa_csp)
    check("SPA CSP lets connect-src read picked-image blobs",
          "connect-src 'self' blob:" in spa_csp, spa_csp)
    check("SPA keeps COOP/COEP isolation",
          sh.get("Cross-Origin-Opener-Policy") == "same-origin"
          and sh.get("Cross-Origin-Embedder-Policy") == "credentialless",
          f"{sh.get('Cross-Origin-Opener-Policy')}/{sh.get('Cross-Origin-Embedder-Policy')}")

    # ── federfall-h5m: handoff derived from the placement record ────────────
    print("\n[atomic handoff via placement]")
    hc = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    s, hp = req("POST", "/api/collections/placements/records", toks["a"], {
        "case": hc, "to_user": B, "org": ORG,
        # a stale/lying client from_user must be corrected server-side
        "from_user": D,
    })
    check("handoff placement accepted", s == 200, f"{s} {hp}")
    _, hcf = req("GET", f"/api/collections/cases/records/{hc}", T)
    check("active_carer derived from to_user",
          hcf["active_carer"] == B, hcf.get("active_carer"))
    check("from_user pinned to the real previous carer",
          bool(hp) and hp.get("from_user") == A, hp and hp.get("from_user"))
    hshares = listf(T, "case_shares", f'case = "{hc}" && shared_with = "{A}"')
    check("previous carer keeps a read share",
          len(hshares) == 1 and hshares[0]["access"] == "read", hshares)
    # A plain move (no to_user) must not touch the carer.
    s, _ = req("POST", "/api/collections/placements/records", toks["b"], {
        "case": hc, "enclosure": "Box 3", "org": ORG,
    })
    check("move logged by the new carer", s == 200, f"status {s}")
    _, hcf = req("GET", f"/api/collections/cases/records/{hc}", T)
    check("plain move leaves active_carer unchanged",
          hcf["active_carer"] == B, hcf.get("active_carer"))

    # ── federfall-lov0: atomic exam save route ───────────────────────────────
    # Exam + findings (+ optional exam weight) are persisted in one server-side
    # transaction; an edit REPLACES the findings set. Before this route the
    # client deleted the old findings and re-created the new ones as separate
    # calls — a mid-save failure permanently lost clinical findings.
    print("\n[atomic exam route]")
    aex_case = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    s, _ = req("POST", "/api/federfall/exam", None, {"case": aex_case})
    check("exam save requires auth", s == 401, f"status {s}")
    s, _ = req("POST", "/api/federfall/exam", gtok, {"case": aex_case})
    check("guest CANNOT save an exam", s == 403, f"status {s}")
    s, _ = req("POST", "/api/federfall/exam", toks["a"], {})
    check("exam save without case/animal is rejected", s == 400, f"status {s}")

    s, aex = req("POST", "/api/federfall/exam", toks["a"], {
        "case": aex_case, "animal": animal,
        "exam": {"body_condition": 3, "hydration": "moderate",
                 "notes": "first pass", "examined_at": "2026-06-25 09:00:00.000Z"},
        "findings": [{"system": "eyes", "status": "abnormal", "note": "cloudy"},
                     {"system": "wings", "status": "normal", "note": ""}],
        "weight_g": 312,
    })
    check("owner creates exam via route", s == 200 and bool(aex and aex.get("id")),
          f"{s} {aex}")
    aex_id = aex["id"]
    _, aexr = req("GET", f"/api/collections/exams/records/{aex_id}", T)
    check("exam org/examiner come from the session",
          aexr["org"] == ORG and aexr["examiner"] == A,
          f"{aexr['org']} {aexr['examiner']}")
    afinds = listf(T, "exam_findings", f'exam = "{aex_id}"')
    check("exam findings created in the same call", len(afinds) == 2, afinds)
    aweights = listf(T, "weights", f'case = "{aex_case}" && weight_g = 312')
    check("exam weight became a weights row", len(aweights) == 1, aweights)

    # Same-org outsider / read-share cannot use the route; edit-share can.
    s, _ = req("POST", "/api/federfall/exam", td,
               {"case": aex_case, "animal": animal})
    check("same-org outsider CANNOT save an exam via route", s == 403,
          f"status {s}")
    mk(T, "case_shares", {"case": aex_case, "shared_with": C, "shared_by": A,
                          "access": "read", "org": ORG})
    tc = login("c@f.local")[1]
    s, _ = req("POST", "/api/federfall/exam", tc,
               {"id": aex_id, "exam": {"notes": "read share"}})
    check("read-share CANNOT edit the exam via route", s == 403, f"status {s}")
    mk(T, "case_shares", {"case": aex_case, "shared_with": B, "shared_by": A,
                          "access": "edit", "org": ORG})
    s, _ = req("POST", "/api/federfall/exam", toks["b"],
               {"id": aex_id, "exam": {"notes": "edit share",
                                       "body_condition": 3}})
    check("edit-share CAN edit the exam via route", s == 200, f"status {s}")

    # Edit replaces the findings set atomically.
    s, _ = req("POST", "/api/federfall/exam", toks["a"], {
        "id": aex_id,
        "exam": {"notes": "second pass", "hydration": "mild"},
        "findings": [{"system": "legs_feet", "status": "abnormal",
                      "note": "pododermatitis"}],
    })
    check("owner edits exam via route", s == 200, f"status {s}")
    afinds = listf(T, "exam_findings", f'exam = "{aex_id}"')
    check("edit REPLACES the findings set",
          len(afinds) == 1 and afinds[0]["system"] == "legs_feet", afinds)
    _, aexr = req("GET", f"/api/collections/exams/records/{aex_id}", T)
    check("omitted exam field is cleared on edit (full replace)",
          aexr.get("body_condition") in (None, 0, ""), aexr.get("body_condition"))
    aweights = listf(T, "weights", f'case = "{aex_case}"')
    check("edit does not duplicate the exam weight", len(aweights) == 1, aweights)

    # THE point of the route: a failed save must not eat the previous findings.
    s, _ = req("POST", "/api/federfall/exam", toks["a"], {
        "id": aex_id,
        "exam": {"notes": "broken"},
        "findings": [{"system": "legs_feet", "status": "abnormal", "note": "ok"},
                     {"system": "no_such_system", "status": "abnormal",
                      "note": "boom"}],
    })
    check("invalid finding rejects the whole save", s >= 400, f"status {s}")
    afinds = listf(T, "exam_findings", f'exam = "{aex_id}"')
    check("failed edit keeps the previous findings intact (atomic)",
          len(afinds) == 1 and afinds[0]["system"] == "legs_feet"
          and afinds[0]["note"] == "pododermatitis", afinds)
    s, _ = req("POST", "/api/federfall/exam", toks["a"],
               {"case": aex_case, "animal": fanimal})
    check("exam save CANNOT denormalize a foreign-org animal", s == 400,
          f"status {s}")

    # ── federfall-oxqk / federfall-zdcb: member removal ──────────────────────
    # oxqk turned out to be a false positive (users.deleteRule IS
    # supervisor-scoped; the reviewer read the down-migration), but the suite
    # only ever deleted users with the superuser token — cover the real rule.
    # zdcb: the open-caseload invariant is enforced by the delete hook, not
    # just the client pre-check (racy + bypassable).
    print("\n[member removal]")
    rorg = mk(T, "organisations", {"name": "Removal-Orga"})["id"]
    RSUP = mkuser(T, "rm-sup@f.local", "supervisor", org=rorg)["id"]
    RSUP2 = mkuser(T, "rm-sup2@f.local", "supervisor", org=rorg)["id"]
    RCARER = mkuser(T, "rm-carer@f.local", "carer", org=rorg)["id"]
    RVICTIM = mkuser(T, "rm-victim@f.local", "carer", org=rorg)["id"]
    trsup = login("rm-sup@f.local")[1]
    trcarer = login("rm-carer@f.local")[1]

    s, _ = req("DELETE", f"/api/collections/users/records/{RVICTIM}", trcarer)
    check("a carer CANNOT remove a member", s >= 400, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/users/records/{RVICTIM}",
               toks["sup"])
    check("a foreign-org supervisor CANNOT remove the member", s >= 400,
          f"status {s}")

    # Open caseload blocks removal server-side (federfall-zdcb) — even for a
    # superuser, and regardless of any client-side pre-check.
    ranimal = mk(T, "animals", {"species": "Stadttaube", "org": rorg})["id"]
    rcase = mk(T, "cases", {"animal": ranimal, "active_carer": RVICTIM,
                            "org": rorg})["id"]
    s, _ = req("DELETE", f"/api/collections/users/records/{RVICTIM}", trsup)
    check("supervisor CANNOT remove a member with open cases", s >= 400,
          f"status {s}")
    s, _ = req("DELETE", f"/api/collections/users/records/{RVICTIM}", T)
    check("superuser CANNOT either (hook, not rule)", s >= 400, f"status {s}")

    # Once the caseload is closed, the org's supervisor can remove the member
    # (the oxqk regression: this must work with a plain supervisor token).
    mk(T, "dispositions", {"case": rcase, "type": "released", "org": rorg})
    s, _ = req("DELETE", f"/api/collections/users/records/{RVICTIM}", trsup)
    check("supervisor CAN remove a member without open cases", s == 204,
          f"status {s}")
    s, _ = req("DELETE", f"/api/collections/users/records/{RSUP2}", trsup)
    check("supervisor CAN remove another supervisor (not the last one)",
          s == 204, f"status {s}")

    # ── federfall-0tf: geocode proxy guards ─────────────────────────────────
    # Runs LAST: the flood exhausts the geocode rate budget for this client IP,
    # so nothing may query the geocode routes after this block. All requests
    # here fail input validation (no/overlong q), so no upstream geocoder is
    # ever contacted — the rate limiter counts them regardless, because it runs
    # as middleware before the handler.
    print("\n[geocode proxy guards]")
    s, _ = req("GET", "/api/federfall/geocode", toks["a"])
    check("geocode without q is rejected", s == 400, f"status {s}")
    s, _ = req("GET", "/api/federfall/geocode?q=" + "x" * 300, toks["a"])
    check("geocode with overlong q is rejected", s == 400, f"status {s}")
    statuses = []
    for _ in range(45):
        s, _ = req("GET", "/api/federfall/geocode", toks["a"])
        statuses.append(s)
    check("sustained geocode traffic hits the rate limit (429)",
          429 in statuses, f"statuses {sorted(set(statuses))}")
    check("small bursts stay under the limit (first requests pass)",
          statuses[0] == 400 and statuses[1] == 400,
          f"first {statuses[:2]}")

    # ── summary ─────────────────────────────────────────────────────────────
    print(f"\n{'='*50}\n{_passed} passed, {_failed} failed")
    sys.exit(1 if _failed else 0)


if __name__ == "__main__":
    main()
