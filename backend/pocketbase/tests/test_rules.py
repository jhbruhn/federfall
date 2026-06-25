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
    check("quarantine_until = admitted + 14d", c1["quarantine_until"][:10] == "2026-03-24", c1["quarantine_until"])

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

    # ── org isolation ───────────────────────────────────────────────────────
    print("\n[org isolation]")
    org2 = mk(T, "organisations", {"name": "Andere Orga"})["id"]
    E = mkuser(T, "e@f.local", "supervisor", org=org2)["id"]
    te = login("e@f.local")[1]
    # E is a supervisor but in a DIFFERENT org — must not see org1's case
    s, _ = req("GET", f"/api/collections/cases/records/{case}", te)
    check("supervisor of another org CANNOT view this org's case", s != 200, f"status {s}")

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
                          "intake_photos", "reasons_for_admission") if k in srec]
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

    # ── summary ─────────────────────────────────────────────────────────────
    print(f"\n{'='*50}\n{_passed} passed, {_failed} failed")
    sys.exit(1 if _failed else 0)


if __name__ == "__main__":
    main()
