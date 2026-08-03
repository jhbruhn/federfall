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

# A real 1x1 PNG (RGBA, Pillow-encoded — CRC-correct), for exercising file-
# field uploads. The previous fixture here decoded as an image fine everywhere
# it was only ever stored/served, but had a broken IDAT CRC that Typst's
# stricter PNG decoder rejects outright — surfaced by federfall-gdp8's report
# photo (backend/pocketbase/tests's own `docker logs` showed "CRC error...
# decoding IDAT chunk" once a case's animal photo actually got embedded via
# `image()`). A real photo from any camera/phone would never have this
# problem; only this hand-crafted fixture did.
_PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4"
    "z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="
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


def req_bytes(method, path, token=None):
    """Like [req], but for a binary (non-JSON) response body — e.g. the PDF
    case report. Return (status, raw_bytes_or_None, headers). `req`'s
    `.decode()` would raise on PDF bytes (not valid UTF-8), hence a separate
    helper rather than a mode flag on the shared one."""
    headers = {}
    if token:
        headers["Authorization"] = token
    r = urllib.request.Request(BASE + path, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(r)
        return resp.status, resp.read(), dict(resp.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)


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
    # federfall-1wm: the major IS the app<->server wire contract, so minClient
    # is DERIVED as "<major>.0.0" — never a hand-set constant that can drift
    # above every client in existence (it sat at "1.0.0" for all of 0.x).
    check("minClient floors at the running major",
          bool(info)
          and info.get("minClient") == info.get("version", "").split(".")[0] + ".0.0",
          info)
    auth = (info or {}).get("auth") or {}
    check("password auth is enabled", auth.get("password") is True, auth)
    check("oauth2 is a list", isinstance(auth.get("oauth2"), list), auth)
    check("self-signup is off (invite-only)", auth.get("selfSignup") is False, auth)
    # federfall-lnz3: PocketBase hardcodes its OAuth2 scopes and has no
    # server-side way to widen them, so the server publishes the set the APP
    # should request instead. Derived from the group mapping being configured
    # (run.sh sets FEDERFALL_OIDC_CARER_GROUP) — there is no scope env.
    check("the configured providers are advertised",
          set(auth.get("oauth2") or []) == {"oidc", "google"}, auth)
    scopes = (auth.get("oauth2Scopes") or {})
    check("a group mapping makes OIDC request the groups scope",
          scopes.get("oidc") == ["openid", "email", "profile", "groups"], auth)
    # A social provider rejects the whole authorization request over an unknown
    # scope, and can't do OIDC group mapping anyway.
    check("a social provider keeps PocketBase's own scopes",
          "google" not in scopes, auth)
    # federfall-el1f: the tile source is a build-time define in the app, so the
    # server prescribes one here for self-hosters on the published image.
    m = (info or {}).get("map") or {}
    check("the configured map source is prescribed",
          m.get("mode") == "raster"
          and m.get("tileUrl") == "https://raster.invalid/{z}/{x}/{y}.png",
          m)
    # Only the URL for the active mode: a leftover variable for the other
    # rendering path must not travel along and get read as the wrong thing.
    check("the other mode's URL is not prescribed", "styleUrl" not in m, m)
    # The credit travels with the URL or neither applies — tiles from one
    # provider under another's attribution is a licensing problem.
    check("the prescription carries its attribution",
          m.get("attribution") == "© Test Tiles", m)
    check("an unset attribution link stays absent (plain text, not a wrong "
          "copyright page)", "attributionUrl" not in m, m)
    # Commercial providers key their tiles, and a vector style needs the key
    # substituted into the style's own source/sprite URLs — only the client can
    # do that, so the key travels as its own field. This endpoint is public, so
    # a key set here is public: see the note in info.pb.js.
    check("the provider API key is handed to the client",
          m.get("apiKey") == "test-map-key", m)

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

    # ── hooks: aviary_stays residency ledger (federfall-d5co.1) ─────────────
    # The centralized `animals` hook (not the dispositions hook itself) must
    # open/close ledger rows for every current_aviary writer.
    print("\n[hooks: aviary_stays residency ledger]")
    stays = listf(T, "aviary_stays", f'animal="{animal}"')
    open_stays = [s for s in stays if s["ended_at"] == ""]
    check("placed_in_aviary opens a stay",
          len(open_stays) == 1 and open_stays[0]["aviary"] == av, stays)

    # Move the same animal to a second aviary via a fresh case's disposition —
    # the old stay must close and a new one must open, without touching the
    # dispositions hook itself (it only ever sets current_aviary).
    av2 = mk(T, "aviaries", {"name": "Voliere 2", "org": ORG})["id"]
    c2b = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    mk(T, "dispositions", {"case": c2b, "type": "placed_in_aviary", "aviary": av2, "org": ORG})
    stays = listf(T, "aviary_stays", f'animal="{animal}"')
    open_stays = [s for s in stays if s["ended_at"] == ""]
    closed_av_stays = [s for s in stays if s["aviary"] == av and s["ended_at"] != ""]
    check("moving aviaries closes the old stay", len(closed_av_stays) == 1, stays)
    check("moving aviaries opens exactly one new stay",
          len(open_stays) == 1 and open_stays[0]["aviary"] == av2, stays)

    # Losing residency (a disposition edit that reconciles current_aviary back
    # to "") must close the stay and open no replacement.
    rav = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    rac = mk(T, "cases", {"animal": rav, "active_carer": A, "org": ORG})["id"]
    rad = mk(T, "dispositions", {"case": rac, "type": "placed_in_aviary", "aviary": av, "org": ORG})["id"]
    stays = listf(T, "aviary_stays", f'animal="{rav}"')
    check("fresh resident opens a stay",
          len(stays) == 1 and stays[0]["ended_at"] == "", stays)
    req("PATCH", f"/api/collections/dispositions/records/{rad}", T, {"type": "died"})
    stays = listf(T, "aviary_stays", f'animal="{rav}"')
    open_stays = [s for s in stays if s["ended_at"] == ""]
    check("losing residency closes the stay with none reopened",
          len(stays) == 1 and len(open_stays) == 0, stays)

    # The case-less "add resident directly to an aviary" create path
    # (add_animal_sheet.dart) sets current_aviary on animals.create — same
    # centralized hook, no disposition involved.
    zoi = mk(T, "animals", {
        "species": "Stadttaube", "org": ORG,
        "current_aviary": av, "lifetime_status": "in_aviary",
    })["id"]
    zoi_stays = listf(T, "aviary_stays", f'animal="{zoi}"')
    check("case-less resident create opens a stay",
          len(zoi_stays) == 1 and zoi_stays[0]["aviary"] == av
          and zoi_stays[0]["ended_at"] == "", zoi_stays)

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

    # ── journal_entries: dual-parent (federfall-d5co.2) ─────────────────────
    print("\n[journal_entries: aviary-scoped entries]")
    s, _ = req("POST", "/api/collections/journal_entries/records", toks["a"],
               {"text": "no parent set", "org": ORG})
    check("journal entry with neither case nor aviary is rejected", s >= 400, f"status {s}")
    s, _ = req("POST", "/api/collections/journal_entries/records", toks["a"],
               {"case": case, "aviary": av, "text": "both parents set", "org": ORG})
    check("journal entry with BOTH case and aviary is rejected", s >= 400, f"status {s}")
    s, _ = req("POST", "/api/collections/journal_entries/records", toks["a"],
               {"aviary": av, "text": "carer CANNOT log an aviary entry", "org": ORG})
    check("plain carer CANNOT create an aviary journal entry", s >= 400, f"status {s}")
    s, ajr = req("POST", "/api/collections/journal_entries/records", toks["coord"],
                 {"aviary": av, "text": "cleaned the aviary", "org": ORG})
    check("coordinator CAN create an aviary journal entry", s == 200, f"{s} {ajr}")
    s, _ = req("GET", f"/api/collections/journal_entries/records/{ajr['id']}", toks["a"])
    check("any active member CAN view the aviary journal entry", s == 200, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/journal_entries/records/{ajr['id']}", toks["a"],
               {"text": "carer cannot edit it"})
    check("plain carer CANNOT edit the aviary journal entry", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/journal_entries/records/{ajr['id']}", toks["coord"],
               {"aviary": av2})
    check("aviary journal_entry.aviary is immutable (no re-pointing)", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/journal_entries/records/{ajr['id']}", toks["coord"],
               {"text": "cleaned the aviary and refilled feeders"})
    check("aviary journal entry content stays editable", s == 200, f"status {s}")

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

    # ── egg_records (federfall-4agw.1) ──────────────────────────────────────
    # Egg-laying is an animal identity-layer ledger (5yg.4's stance for
    # weights): org-wide read/create/update, author-or-supervisor delete
    # (1700000047). The reassignment feature depends on `animal` staying
    # MUTABLE — it is deliberately exempt from 1700000043's :isset guards, so
    # that exemption is asserted here rather than left to be "fixed" later.
    print("\n[egg_records]")
    animal2 = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    animal_org2 = mk(T, "animals", {"species": "Stadttaube", "org": org2})["id"]
    s, egg = req("POST", "/api/collections/egg_records/records", toks["a"], {
        "animal": animal, "laid_at": "2026-06-01 07:00:00.000Z", "count": 2,
        "fertility": "unknown", "fate": "in_nest", "attribution": "presumed",
        "author": A, "org": ORG,
    })
    check("org member can log an egg record", s == 200, f"{s} {egg}")
    s, _ = req("POST", "/api/collections/egg_records/records", toks["a"],
               {"animal": animal, "count": 0, "org": ORG})
    check("count below the minimum is rejected", s >= 400, f"status {s}")
    s, _ = req("GET", f"/api/collections/egg_records/records/{egg['id']}", toks["d"])
    check("any org member can view an egg record", s == 200, f"status {s}")
    check("egg records are org-scoped readable",
          len(listf(toks["d"], "egg_records", f"id = \"{egg['id']}\"")) == 1)
    s, _ = req("PATCH", f"/api/collections/egg_records/records/{egg['id']}",
               toks["d"], {"notes": "Windei"})
    check("any org member can edit an egg record", s == 200, f"status {s}")
    # Cross-org: neither readable nor writable.
    s, _ = req("GET", f"/api/collections/egg_records/records/{egg['id']}", te)
    check("other-org member CANNOT view an egg record", s != 200, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/egg_records/records/{egg['id']}", te,
               {"notes": "x"})
    check("other-org member CANNOT edit an egg record", s >= 400, f"status {s}")
    s, _ = req("POST", "/api/collections/egg_records/records", te,
               {"animal": animal, "count": 1, "org": ORG})
    check("other-org member CANNOT create in this org", s >= 400, f"status {s}")

    # Reassignment: `animal` IS mutable (the 1700000043 exemption), `org` is not.
    s, moved = req("PATCH", f"/api/collections/egg_records/records/{egg['id']}",
                   toks["b"], {"animal": animal2, "attribution": "confirmed"})
    check("egg.animal IS mutable (reassignment)",
          s == 200 and moved.get("animal") == animal2
          and moved.get("attribution") == "confirmed", f"{s} {moved}")
    s, _ = req("PATCH", f"/api/collections/egg_records/records/{egg['id']}",
               toks["a"], {"org": org2})
    check("egg.org is immutable", s >= 400, f"status {s}")
    # ...but not across orgs. A rule can't express this (a field ref in an
    # update rule sees the STORED animal), so animal_org_scope.pb.js enforces
    # it — for every collection with an `animal`, swept below.
    s, _ = req("PATCH", f"/api/collections/egg_records/records/{egg['id']}",
               toks["a"], {"animal": animal_org2})
    check("reassignment to another org's animal is rejected", s >= 400,
          f"status {s}")
    s, _ = req("POST", "/api/collections/egg_records/records", toks["a"],
               {"animal": animal_org2, "count": 1, "org": ORG})
    check("an egg CANNOT be created on another org's animal", s >= 400,
          f"status {s}")
    s, _ = req("POST", "/api/collections/egg_records/records", toks["a"],
               {"animal": "doesnotexist000", "count": 1, "org": ORG})
    check("an egg on an unknown animal is rejected", s >= 400, f"status {s}")

    # photos: born protected + MIME-allowlisted (no retrofit migration needed).
    s, d = upload_file(
        "PATCH", f"/api/collections/egg_records/records/{egg['id']}",
        toks["a"], "photos", "evil.svg", "image/svg+xml", _SVG,
    )
    check("SVG upload to egg_records.photos is rejected", s >= 400, f"{s} {d}")
    s, d = upload_file(
        "PATCH", f"/api/collections/egg_records/records/{egg['id']}",
        toks["a"], "photos", "egg.png", "image/png", _PNG_1X1,
    )
    check("PNG upload to egg_records.photos works",
          s == 200 and bool(d.get("photos")), f"{s} {d}")
    egg_photo = (d or {}).get("photos") or [None]
    egg_file = f"/api/files/egg_records/{egg['id']}/{egg_photo[0]}"
    check("egg photo URL WITHOUT a token is rejected",
          file_status(egg_file) != 200, file_status(egg_file))
    check("same-org member's file token serves the egg photo",
          file_status(f"{egg_file}?token={file_token(toks['d'])}") == 200)
    check("the 200x200 thumb is generated (thumbs whitelist)",
          file_status(f"{egg_file}?thumb=200x200&token={file_token(toks['d'])}")
          == 200)

    # delete: author or supervisor only (1700000047's stance).
    s, _ = req("DELETE", f"/api/collections/egg_records/records/{egg['id']}",
               toks["b"])
    check("another member CANNOT delete A's egg record", s != 204, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/egg_records/records/{egg['id']}",
               toks["a"])
    check("the author can delete their own egg record", s == 204, f"status {s}")
    s, eggB = req("POST", "/api/collections/egg_records/records", toks["b"],
                  {"animal": animal, "count": 1, "author": B, "org": ORG})
    check("setup: B logs an egg record", s == 200, f"{s} {eggB}")
    s, _ = req("DELETE", f"/api/collections/egg_records/records/{eggB['id']}",
               toks["sup"])
    check("a supervisor can delete any egg record", s == 204, f"status {s}")
    # Leave one row behind so the guest sweep's member check stays non-vacuous.
    mk(T, "egg_records", {"animal": animal, "count": 1, "org": ORG})

    # ── animal org scope (federfall-ti77) ───────────────────────────────────
    # Every collection carrying an `animal` relation must reject a bird from
    # another org, on create and on update. `animal` is deliberately exempt from
    # 1700000043's :isset guards on the identity-layer collections, and an
    # UPDATE rule's field references resolve against the STORED record, so no
    # rule can see the incoming value — animal_org_scope.pb.js does.
    #
    # Without it a row scoped to org A could hang off org B's animal, whose
    # cascadeDelete would then destroy A's clinical history.
    print("\n[animal org scope]")
    # `markings.type` became a relation into the marking_types code list
    # (1700000040), so a wire string no longer validates.
    ti77_type = listf(T, "marking_types", "id != ''")[0]["id"]
    # One in-org row per collection to PATCH, each created the way the app does.
    ti77_rows = {
        "weights": mk(T, "weights", {
            "animal": animal, "weight_g": 300, "org": ORG,
        })["id"],
        "markings": mk(T, "markings", {
            "animal": animal, "type": ti77_type, "org": ORG,
        })["id"],
        "exams": mk(T, "exams", {
            "case": case, "animal": animal, "org": ORG,
        })["id"],
        "cases": mk(T, "cases", {
            "animal": animal, "active_carer": A, "org": ORG,
        })["id"],
        "egg_records": mk(T, "egg_records", {
            "animal": animal, "count": 1, "org": ORG,
        })["id"],
    }
    ti77_creates = {
        "weights": {"weight_g": 301, "org": ORG},
        "markings": {"type": ti77_type, "org": ORG},
        "exams": {"case": case, "org": ORG},
        "cases": {"active_carer": A, "org": ORG},
        "egg_records": {"count": 1, "org": ORG},
    }
    for coll, rec_id in ti77_rows.items():
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{rec_id}", T,
                   {"animal": animal_org2})
        check(f"{coll}.animal cannot be re-pointed across orgs", s >= 400,
              f"status {s}")
        s, _ = req("POST", f"/api/collections/{coll}/records", T,
                   {"animal": animal_org2, **ti77_creates[coll]})
        check(f"{coll} cannot be created on another org's animal", s >= 400,
              f"status {s}")
        # Same-org moves stay legitimate (merge_animals re-points cases and
        # markings at a surviving animal, and eggs are re-attributed by design).
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{rec_id}", T,
                   {"animal": animal2})
        check(f"{coll}.animal still moves within the org", s == 200,
              f"status {s}")
    # An exam carries an optional `org`; the guard then falls back to the parent
    # case's, so the check cannot be dodged by simply omitting it.
    s, _ = req("POST", "/api/collections/exams/records", T,
               {"case": case, "animal": animal_org2})
    check("an exam with no org still cannot name a foreign animal", s >= 400,
          f"status {s}")
    # The hook only validates when `animal` CHANGES, so an unrelated field edit
    # never re-checks the relation. That matters for rows orphaned before
    # 1700000057 made `cases.animal` cascade: re-validating every save would
    # make them permanently unsaveable and break unrelated writes such as the
    # dispositions hook bumping `case.status`. Such a row can no longer be
    # produced through the API (deleting the animal now takes the case with it —
    # asserted below), so what is checked here is the change-only behaviour
    # itself: editing another field passes, re-pointing still does not.
    # A throwaway animal, not `animal2`: deleting one still in use would cascade
    # away rows later sections depend on (the guest sweep needs an egg record).
    ti77_doomed = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    ti77_orphan = mk(T, "cases", {
        "animal": ti77_doomed, "active_carer": A, "org": ORG,
    })
    s, _ = req("PATCH", f"/api/collections/cases/records/{ti77_orphan['id']}", T,
               {"intake_notes": "unrelated edit"})
    check("an unrelated edit does not re-validate the animal", s == 200,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/cases/records/{ti77_orphan['id']}", T,
               {"animal": animal_org2})
    check("...but a re-point across orgs is still rejected", s >= 400,
          f"status {s}")
    req("DELETE", f"/api/collections/animals/records/{ti77_doomed}", T)

    # ── supervisor deletion + animal cascade (federfall-vfl7) ────────────────
    # `animals.delete` and `cases.delete` have been supervisor-only since
    # 1700000010; 1700000057 makes `cases.animal` cascade so deleting a bird
    # actually takes its whole history, rather than orphaning cases whose
    # children hang off `case` and would otherwise survive.
    print("\n[supervisor deletion & cascade]")
    del_animal = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    del_case = mk(T, "cases", {
        "animal": del_animal, "active_carer": A, "org": ORG,
    })["id"]
    del_journal = mk(T, "journal_entries", {
        "case": del_case, "text": "wound check", "org": ORG,
    })["id"]
    del_disp = mk(T, "dispositions", {
        "case": del_case, "type": "released",
        "disposed_at": "2026-06-01 09:00:00.000Z", "org": ORG,
    })["id"]
    del_weight = mk(T, "weights", {
        "animal": del_animal, "case": del_case, "weight_g": 300, "org": ORG,
    })["id"]
    del_egg = mk(T, "egg_records", {
        "animal": del_animal, "count": 1, "org": ORG,
    })["id"]
    # The hook creates a quarantine row per case; grab it to prove it goes too.
    del_quar = listf(T, "quarantine_records", f'case = "{del_case}"')

    # Only supervisors may delete either record.
    s, _ = req("DELETE", f"/api/collections/cases/records/{del_case}", toks["a"])
    check("the active carer CANNOT delete their own case", s != 204,
          f"status {s}")
    s, _ = req("DELETE", f"/api/collections/animals/records/{del_animal}",
               toks["a"])
    check("a carer CANNOT delete an animal", s != 204, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/animals/records/{del_animal}",
               toks["coord"])
    check("a coordinator CANNOT delete an animal", s != 204, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/animals/records/{del_animal}", te)
    check("another org's supervisor CANNOT delete this animal", s != 204,
          f"status {s}")

    # A case delete leaves the animal-level history on the bird.
    s, _ = req("DELETE", f"/api/collections/cases/records/{del_case}",
               toks["sup"])
    check("a supervisor can delete a case", s == 204, f"status {s}")
    s, _ = req("GET", f"/api/collections/journal_entries/records/{del_journal}",
               T)
    check("the case's journal entry is cascaded away", s == 404, f"status {s}")
    s, _ = req("GET", f"/api/collections/dispositions/records/{del_disp}", T)
    check("the case's disposition is cascaded away", s == 404, f"status {s}")
    if del_quar:
        s, _ = req(
            "GET",
            f"/api/collections/quarantine_records/records/{del_quar[0]['id']}",
            T,
        )
        check("the case's quarantine record is cascaded away", s == 404,
              f"status {s}")
    s, _ = req("GET", f"/api/collections/weights/records/{del_weight}", T)
    check("a weight SURVIVES its case (animal-level history)", s == 200,
          f"status {s}")
    s, _ = req("GET", f"/api/collections/egg_records/records/{del_egg}", T)
    check("an egg record survives its case (it has no case link)", s == 200,
          f"status {s}")

    # Deleting the animal takes everything, including a second live case.
    del_case2 = mk(T, "cases", {
        "animal": del_animal, "active_carer": A, "org": ORG,
    })["id"]
    del_journal2 = mk(T, "journal_entries", {
        "case": del_case2, "text": "still in care", "org": ORG,
    })["id"]
    del_marking = mk(T, "markings", {
        "animal": del_animal, "type": ti77_type, "org": ORG,
    })["id"]
    s, _ = req("DELETE", f"/api/collections/animals/records/{del_animal}",
               toks["sup"])
    check("a supervisor can delete an animal", s == 204, f"status {s}")
    for coll, rec_id, label in [
        ("cases", del_case2, "its open case"),
        ("journal_entries", del_journal2, "that case's journal entry"),
        ("weights", del_weight, "its weights"),
        ("egg_records", del_egg, "its egg records"),
        ("markings", del_marking, "its markings"),
    ]:
        s, _ = req("GET", f"/api/collections/{coll}/records/{rec_id}", T)
        check(f"deleting the animal removes {label}", s == 404, f"status {s}")

    # ── code-list delete semantics (federfall-58t1) ──────────────────────────
    # The code-list delete confirmation names how many live records reference an
    # entry and states what deleting it would do to them. That copy is only true
    # while these schema facts hold, so pin them:
    #
    #   * referenced through an OPTIONAL relation (cascadeDelete false) -> the
    #     delete SUCCEEDS and PocketBase silently BLANKS the field. Nothing is
    #     orphaned; the recorded value is simply gone. Hence "Deactivate
    #     instead" as the primary action.
    #   * `markings.type` is REQUIRED -> the delete is REFUSED outright, which
    #     is why that one list offers no "Delete anyway" at all.
    #
    # Flip any of these (make a relation required, or add a cascade) and the
    # dialog starts lying — this block fails first.
    print("\n[code-list delete semantics]")
    cl_case = mk(T, "cases", {
        "animal": animal, "active_carer": A, "org": ORG,
    })["id"]

    cl_cond = mk(T, "conditions", {
        "label": "58t1 condition", "active": True, "org": ORG,
    })["id"]
    cl_cc = mk(T, "case_conditions", {
        "case": cl_case, "condition": cl_cond, "org": ORG,
    })["id"]
    check("a referenced condition is countable via case_conditions.condition",
          len(listf(T, "case_conditions", f'condition = "{cl_cond}"')) == 1)
    s, _ = req("DELETE", f"/api/collections/conditions/records/{cl_cond}",
               toks["sup"])
    check("deleting a REFERENCED condition succeeds (optional relation)",
          s == 204, f"status {s}")
    s, d = req("GET", f"/api/collections/case_conditions/records/{cl_cc}", T)
    check("...and the diagnosis survives with condition BLANKED, not orphaned",
          s == 200 and d.get("condition") == "", f"{s} {d}")

    cl_reason = mk(T, "admission_reasons", {
        "label": "58t1 reason", "active": True, "org": ORG,
    })["id"]
    req("PATCH", f"/api/collections/cases/records/{cl_case}", T,
        {"admission_reasons": [cl_reason]})
    # `~`, NOT `=`/`?=`: on a MULTI relation column those match zero rows, so a
    # count built on them would silently report "not referenced".
    check("a referenced admission reason is countable with ~",
          len(listf(T, "cases", f'admission_reasons ~ "{cl_reason}"')) == 1)
    check("...while = matches nothing there (why the count must use ~)",
          len(listf(T, "cases", f'admission_reasons = "{cl_reason}"')) == 0)
    s, _ = req("DELETE",
               f"/api/collections/admission_reasons/records/{cl_reason}",
               toks["sup"])
    check("deleting a REFERENCED admission reason succeeds", s == 204,
          f"status {s}")
    s, d = req("GET", f"/api/collections/cases/records/{cl_case}", T)
    check("...and the case silently loses that reason",
          s == 200 and cl_reason not in (d.get("admission_reasons") or []),
          f"{s} {d}")

    cl_type = mk(T, "marking_types", {
        "label": "58t1 type", "active": True, "org": ORG,
    })["id"]
    mk(T, "markings", {"animal": animal, "type": cl_type, "org": ORG})
    s, _ = req("DELETE", f"/api/collections/marking_types/records/{cl_type}",
               toks["sup"])
    check("deleting a REFERENCED marking type is refused (required relation)",
          s >= 400, f"status {s}")
    s, _ = req("GET", f"/api/collections/marking_types/records/{cl_type}", T)
    check("...so the type is still there", s == 200, f"status {s}")
    # Deactivating is the way out the UI offers in its place.
    s, d = req("PATCH", f"/api/collections/marking_types/records/{cl_type}",
               toks["sup"], {"active": False})
    check("a supervisor can deactivate the in-use type instead",
          s == 200 and d.get("active") is False, f"{s} {d}")

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

    # ── vet_appointments (federfall-fnpo) ───────────────────────────────────
    # Case-scoped exactly like follow_ups: the owner can book and read a visit;
    # a same-org outsider with no share cannot; another org sees nothing.
    print("\n[vet_appointments]")
    vacase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]

    def mk_appointment(tok, **extra):
        body = {
            "case": vacase, "starts_at": "2026-08-06 12:30:00.000Z",
            "vet": "Tierklinik Dr. Meyer", "reason": "Roentgen Fluegel",
            "org": ORG,
        }
        body.update(extra)
        return req("POST", "/api/collections/vet_appointments/records", tok, body)

    s, va = mk_appointment(toks["a"])
    check("owner can book a vet appointment", s == 200, f"{s} {va}")
    s, _ = req("GET", f"/api/collections/vet_appointments/records/{va['id']}", toks["a"])
    check("owner can read the appointment", s == 200, f"status {s}")
    s, _ = mk_appointment(td)
    check("same-org outsider CANNOT book an appointment", s != 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/vet_appointments/records/{va['id']}", td)
    check("same-org outsider CANNOT read the appointment", s != 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/vet_appointments/records/{va['id']}", te)
    check("other-org member CANNOT read the appointment", s != 200, f"status {s}")

    # starts_at is the one required field — an appointment with no "when" is not
    # an appointment, and the worklist/reminder planner both key off it.
    s, _ = mk_appointment(toks["a"], starts_at="")
    check("an appointment without starts_at is rejected", s != 200, f"status {s}")

    # The outcome is written after the visit, on the same record.
    s, _ = req("PATCH", f"/api/collections/vet_appointments/records/{va['id']}",
               toks["a"], {"outcome": "Fraktur verheilt",
                           "attended_at": "2026-08-06 13:10:00.000Z"})
    check("owner can add the outcome afterwards", s == 200, f"status {s}")

    # reminder_lead_minutes: PocketBase has no null for a number field, and it
    # skips min/max validation for a zero on an optional field — so 0 IS
    # accepted and is indistinguishable from "never set". That is precisely why
    # VetAppointment.fromRecord reads 0 as "follow the device default", and why
    # muting is a separate bool rather than a 0/-1 sentinel here.
    s, _ = req("PATCH", f"/api/collections/vet_appointments/records/{va['id']}",
               toks["a"], {"reminder_lead_minutes": 180})
    check("a positive reminder lead is accepted", s == 200, f"status {s}")
    s, back = req("PATCH", f"/api/collections/vet_appointments/records/{va['id']}",
                  toks["a"], {"reminder_lead_minutes": 0})
    check("a zero reminder lead round-trips as 0, not null — the client must "
          "treat it as unset", s == 200 and (back or {}).get("reminder_lead_minutes") == 0,
          f"{s} {back}")
    # min:1 still earns its place: it rejects a negative, so no client can
    # smuggle in a sentinel the mapper would misread as a real lead.
    s, _ = req("PATCH", f"/api/collections/vet_appointments/records/{va['id']}",
               toks["a"], {"reminder_lead_minutes": -30})
    check("a negative reminder lead is rejected", s != 200, f"status {s}")

    # Deleting the case takes its appointments with it (cascadeDelete), like
    # every other case relation.
    delcase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    s, delva = req("POST", "/api/collections/vet_appointments/records", toks["a"], {
        "case": delcase, "starts_at": "2026-08-06 12:30:00.000Z", "org": ORG,
    })
    check("appointment on the throwaway case created", s == 200, f"status {s}")
    req("DELETE", f"/api/collections/cases/records/{delcase}", toks["sup"])
    s, _ = req("GET", f"/api/collections/vet_appointments/records/{delva['id']}", toks["a"])
    check("deleting the case cascades to its appointments", s == 404, f"status {s}")

    # ── medication_due view (cr3.6) ─────────────────────────────────────────
    # next_due = last_dose + interval_hours for a scheduled med; the view is the
    # carer's worklist source, scoped to their own cases.
    print("\n[medication_due view]")
    mdcase = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    med = mk(T, "medications", {
        "case": mdcase, "drug": "Meloxicam", "frequency_kind": "scheduled",
        "interval_hours": 12, "dose_unit": "mg", "dose_rate": 0.5,
        "concentration_per_ml": 1.5, "org": ORG,
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
    # 6d3a.2 — the rate and the product strength travel through the view, since
    # the worklist rebuilds a plan from it to log a dose straight from there.
    check("medication_due exposes dose_rate", (row or {}).get("dose_rate") == 0.5,
          f"{(row or {}).get('dose_rate')}")
    check("medication_due exposes concentration_per_ml",
          (row or {}).get("concentration_per_ml") == 1.5,
          f"{(row or {}).get('concentration_per_ml')}")
    # Scoped to the carer: another carer in the org does not see the row.
    s, _ = req("GET", f"/api/collections/medication_due/records/{med}", toks["b"])
    check("other carer CANNOT read the medication_due row", s != 200, f"status {s}")

    # 6d3a.2 — a carer records what a calculated dose was derived from, under
    # the same child rules as the rest of the timeline (no new rule shape).
    s, adm = req("POST", "/api/collections/medication_administrations/records",
                 toks["a"], {
                     "case": mdcase, "medication": med, "drug": "Meloxicam",
                     "dose": 0.131, "dose_unit": "mg", "weight_g_used": 262,
                     "volume_ml": 0.0873,
                     "administered_at": "2026-06-21 08:00:00.000Z", "org": ORG,
                 })
    check("carer can store the derivation of a dose", s == 200, f"{s} {adm}")
    check("weight_g_used round-trips", (adm or {}).get("weight_g_used") == 262,
          f"{(adm or {}).get('weight_g_used')}")
    check("volume_ml round-trips", (adm or {}).get("volume_ml") == 0.0873,
          f"{(adm or {}).get('volume_ml')}")

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

    # ── medication_products catalogue (6d3a.3) ──────────────────────────────
    # Read by everyone in the org (it prefills their prescription form), written
    # only by a supervisor — same split as the other code lists.
    print("\n[medication_products catalogue]")
    seeded = listf(toks["a"], "medication_products", "id != ''")
    check("migration seeds placeholder entries, not real drugs",
          sorted(p["label"] for p in seeded) ==
          ["Medikament 1", "Medikament 2", "Medikament 3"],
          str([p["label"] for p in seeded]))
    # 1700000061 fills them with example VALUES so an entry's purpose is
    # visible — every one must say it is an example, so a round number in a
    # dose field can never be mistaken for the org's protocol.
    check("every seeded entry is marked as an example",
          all("Beispiel" in (p["note"] or "") for p in seeded),
          str([p["note"] for p in seeded]))
    check("example rates sit inside their own advisory range",
          all(p["rate_min"] <= p["dose_rate"] <= p["rate_max"]
              for p in seeded if p["dose_rate"]),
          str([(p["rate_min"], p["dose_rate"], p["rate_max"]) for p in seeded]))
    check("an ml/kg example carries no concentration (nothing to draw up)",
          all(not p["concentration_per_ml"]
              for p in seeded if p["dose_unit"] == "ml"),
          str([(p["dose_unit"], p["concentration_per_ml"]) for p in seeded]))
    s, _ = req("POST", "/api/collections/medication_products/records",
               toks["a"], {"label": "Carer's own", "org": ORG})
    check("carer CANNOT add a catalogue entry", s != 200, f"status {s}")
    s, prod = req("POST", "/api/collections/medication_products/records",
                  toks["sup"], {
                      "label": "Medikament 4", "dose_unit": "mg",
                      "dose_rate": 20, "rate_min": 10, "rate_max": 30,
                      "concentration_per_ml": 15, "active": True, "org": ORG,
                  })
    check("supervisor CAN add a catalogue entry", s == 200, f"{s} {prod}")
    s, _ = req("PATCH",
               f"/api/collections/medication_products/records/{(prod or {}).get('id')}",
               toks["a"], {"dose_rate": 200})
    check("carer CANNOT edit the dosing of a catalogue entry", s != 200,
          f"status {s}")
    s, _ = req("DELETE",
               f"/api/collections/medication_products/records/{(prod or {}).get('id')}",
               toks["sup"])
    check("supervisor CAN remove a catalogue entry", s == 204, f"status {s}")

    # ── federfall-ye5e: condition_labels view ───────────────────────────────
    # The distinct diagnoses actually recorded per org, with a per-label case
    # count. Unlike `animal_species` (same shape, for species) the source rows
    # are NOT org-wide readable, so free-text labels — user-typed prose on one
    # specific case — are gated to coordinators/supervisors, who already read
    # org-wide. Code-list labels stay open: `conditions` already is.
    print("\n[condition_labels view]")

    def cl_labels(tok):
        return {r["label"]: r for r in listf(tok, "condition_labels", "id != ''")}

    ye_cond = mk(T, "conditions", {
        "label": "ye5e Trichomoniasis", "active": True, "org": ORG,
    })["id"]
    # Two cases carrying the same code-list diagnosis, one of them twice, so
    # case_count can prove it counts CASES and not rows.
    ye_case1 = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    ye_case2 = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG})["id"]
    for c in (ye_case1, ye_case1, ye_case2):
        mk(T, "case_conditions", {"case": c, "condition": ye_cond, "org": ORG})
    # A free-text diagnosis with no code-list entry behind it…
    mk(T, "case_conditions", {
        "case": ye_case1, "free_text": "ye5e Katzenbiss", "org": ORG,
    })
    # …and one whose text happens to match a code-list label, which must
    # collapse into that entry's row rather than become a second one.
    mk(T, "case_conditions", {
        "case": ye_case2, "free_text": "ye5e Trichomoniasis", "org": ORG,
    })

    sup_rows = cl_labels(toks["sup"])
    check("supervisor sees a code-list diagnosis in the view",
          "ye5e Trichomoniasis" in sup_rows, sorted(sup_rows))
    check("case_count counts cases, not case_conditions rows",
          sup_rows.get("ye5e Trichomoniasis", {}).get("case_count") == 2,
          sup_rows.get("ye5e Trichomoniasis"))
    check("a free-text diagnosis matching a code-list label is ONE row",
          len([l for l in sup_rows if l == "ye5e Trichomoniasis"]) == 1
          and sup_rows["ye5e Trichomoniasis"]["condition"] == ye_cond,
          sup_rows.get("ye5e Trichomoniasis"))
    check("supervisor sees a free-text-only diagnosis",
          "ye5e Katzenbiss" in sup_rows, sorted(sup_rows))
    check("coordinator sees the free-text tail too",
          "ye5e Katzenbiss" in cl_labels(toks["coord"]), "missing")

    # D is an org carer with no access to either case — the whole point of the
    # gate: they may browse the org's recorded vocabulary, not read prose typed
    # on a case they cannot open.
    d_rows = cl_labels(toks["d"])
    check("carer sees code-list diagnoses (the vocabulary is already theirs)",
          "ye5e Trichomoniasis" in d_rows, sorted(d_rows))
    check("carer does NOT see free-text diagnoses from cases they can't read",
          "ye5e Katzenbiss" not in d_rows, sorted(d_rows))
    s, _ = req("POST", "/api/collections/condition_labels/records", toks["sup"],
               {"label": "nope", "org": ORG})
    check("the view is read-only even for a supervisor", s != 200, f"status {s}")

    # ── federfall-80tc: case_report_rows view ───────────────────────────────
    # The annual-report CSV pre-joined server-side: one row per case carrying
    # the animal's species/name, the LATEST disposition and the admission
    # reasons resolved to their labels, so the export stops pulling `cases` +
    # `dispositions` + `animals` whole to the device. Org-wide by construction,
    # hence coordinator/supervisor only — narrower than `case_summaries`,
    # because this row also carries find city/region and admission reasons.
    print("\n[case_report_rows view]")

    tc_r1 = mk(T, "admission_reasons",
               {"label": "80tc Verletzung", "active": True, "org": ORG})["id"]
    tc_r2 = mk(T, "admission_reasons",
               {"label": "80tc Katzenangriff", "active": True, "org": ORG})["id"]
    tc_animal = mk(T, "animals", {
        "species": "80tc Columba livia", "name": "80tc Pip", "org": ORG,
    })["id"]
    tc_case = mk(T, "cases", {
        "animal": tc_animal, "active_carer": A, "org": ORG,
        "admitted_at": "2026-03-10 09:00:00.000Z",
        "city": "Oldenburg", "region": "NI",
        "admission_reasons": [tc_r1, tc_r2],
    })["id"]
    # Two dispositions, out of order, so "the outcome" can only be right by
    # taking the LATEST — the same rule terminalDispositionByCase applies.
    mk(T, "dispositions", {"case": tc_case, "type": "died",
                           "disposed_at": "2026-03-15 09:00:00.000Z", "org": ORG})
    mk(T, "dispositions", {"case": tc_case, "type": "released",
                           "disposed_at": "2026-03-20 09:00:00.000Z", "org": ORG})
    # A second, still-open case: no disposition to join at all.
    tc_open = mk(T, "cases", {
        "animal": tc_animal, "active_carer": A, "org": ORG,
        "admitted_at": "2026-04-01 09:00:00.000Z",
    })["id"]

    def report_row(tok, cid):
        s, d = req("GET", f"/api/collections/case_report_rows/records/{cid}", tok)
        return d if s == 200 else None

    row = report_row(toks["sup"], tc_case) or {}
    check("supervisor reads the pre-joined report row", bool(row), row)
    check("the row joins the animal's species and name",
          row.get("species") == "80tc Columba livia"
          and row.get("name") == "80tc Pip", row)
    check("the row carries the LATEST disposition as the outcome",
          row.get("outcome") == "released", row.get("outcome"))
    check("ended_at is that disposition's date",
          str(row.get("ended_at", "")).startswith("2026-03-20"),
          row.get("ended_at"))
    check("admission reasons arrive resolved, in order and joined",
          row.get("reasons") == "80tc Verletzung; 80tc Katzenangriff",
          row.get("reasons"))
    check("the row carries the find city/region the CSV prints",
          row.get("city") == "Oldenburg" and row.get("region") == "NI", row)
    open_row = report_row(toks["coord"], tc_open) or {}
    check("coordinator reads the view too", bool(open_row), open_row)
    check("an open case joins no outcome",
          open_row.get("outcome") == "" and open_row.get("ended_at") == "",
          open_row)

    # A is the case's own active carer and still gets nothing: this view is the
    # org-wide export, gated to the roles that already read org-wide.
    check("the case's own carer CANNOT read the org-wide report row",
          report_row(toks["a"], tc_case) is None)
    check("a carer's list of report rows is empty",
          len(listf(toks["a"], "case_report_rows", "id != ''")) == 0, "non-empty")
    check("other-org member CANNOT read the report row",
          report_row(te, tc_case) is None)
    s, _ = req("POST", "/api/collections/case_report_rows/records", toks["sup"],
               {"case_number": "nope", "org": ORG})
    check("the view is read-only even for a supervisor", s != 200, f"status {s}")

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
                 "medication_products",
                 "quarantine_records", "case_quarantine", "animal_species",
                 "aviary_stays", "egg_records", "condition_labels"):
        n = len(listf(toks["a"], coll, "id != ''"))
        check(f"member sees {coll} (wall check is non-vacuous)", n > 0, "empty")
        check(f"guest sees no {coll}",
              len(listf(gtok, coll, "id != ''")) == 0, "non-empty")
    # case_report_rows can't join that sweep — it is coordinator/supervisor
    # only, so the carer token above would make the non-vacuous check fail for
    # the right reason. Same wall, checked against a supervisor instead.
    check("supervisor sees case_report_rows (wall check is non-vacuous)",
          len(listf(toks["sup"], "case_report_rows", "id != ''")) > 0, "empty")
    check("guest sees no case_report_rows",
          len(listf(gtok, "case_report_rows", "id != ''")) == 0, "non-empty")
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
    def multipart_intake(token, payload_obj, filename="in.png"):
        boundary = "----fedintakeboundary"
        payload = json.dumps(payload_obj)
        mp = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="@jsonPayload"\r\n\r\n'
            f"{payload}\r\n"
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="intake_photos"; filename="{filename}"\r\n'
            "Content-Type: image/png\r\n\r\n"
        ).encode() + _PNG_1X1 + f"\r\n--{boundary}--\r\n".encode()
        r = urllib.request.Request(
            BASE + "/api/federfall/intake", data=mp, method="POST",
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}",
                     "Authorization": token})
        try:
            resp = urllib.request.urlopen(r)
            return resp.status, json.loads(resp.read().decode())
        except urllib.error.HTTPError as err:
            return err.code, None

    s, mic = multipart_intake(toks["a"], {
        "species": "Stadttaube", "name": "Foto",
        "case": {"intake_notes": "with photo"}})
    check("multipart intake (jsonPayload + photos) succeeds",
          s == 200 and bool(mic and mic.get("id")), f"status {s}")
    _, mcase = req("GET", f"/api/collections/cases/records/{mic['id']}", T)
    check("multipart intake stored the photo",
          len(mcase.get("intake_photos") or []) == 1, mcase.get("intake_photos"))
    check("multipart intake parsed the jsonPayload fields",
          mcase.get("intake_notes") == "with photo", mcase.get("intake_notes"))

    # federfall-v1yh: the first intake photo is promoted to animals.photo in
    # the same transaction. cases.intake_photos is case-scoped while
    # animals.photo is org-wide identity data, so this promotion is the ONLY
    # reason a bird's portrait is visible to a member with no access to its
    # case — the client dropped its case-scoped avatar fallback.
    manimal = mic["animal"]
    _, mani = req("GET", f"/api/collections/animals/records/{manimal}", td)
    mportrait = mani.get("photo")
    check("intake promoted the first photo to animals.photo",
          bool(mportrait), mani)
    check("outsider carer CANNOT view the intake case (promotion is the point)",
          req("GET", f"/api/collections/cases/records/{mic['id']}", td)[0] != 200)
    mtok_d = file_token(td)
    check("outsider carer's file token serves the promoted portrait",
          file_status(
              f"/api/files/animals/{manimal}/{mportrait}?token={mtok_d}") == 200)

    # A later intake for the same bird must not replace the portrait (nor may
    # it overwrite one a user picked) — fill-when-empty only.
    s, mic2 = multipart_intake(toks["a"], {"animal": manimal}, "second.png")
    check("second intake for the same animal succeeds", s == 200, f"status {s}")
    _, mani2 = req("GET", f"/api/collections/animals/records/{manimal}", td)
    check("second intake does NOT overwrite the portrait",
          mani2.get("photo") == mportrait, mani2.get("photo"))

    # The portrait is an independent copy, not a pointer into the case's
    # storage dir: PocketBase deletes files by `<collection>/<record>/` prefix,
    # so a case delete (which takes its whole timeline) must leave it intact.
    s, _ = req("DELETE", f"/api/collections/cases/records/{mic['id']}",
               toks["sup"])
    check("supervisor deletes the photo intake case", s == 204, f"status {s}")
    mtok_d = file_token(td)
    check("promoted portrait survives deleting the case it came from",
          file_status(
              f"/api/files/animals/{manimal}/{mportrait}?token={mtok_d}") == 200)

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
    check("SPA CSP allows the default raster tile origin",
          "https://tile.openstreetmap.org" in spa_csp, spa_csp)
    check("SPA CSP allows the default vector style/tile origin",
          "https://tiles.openfreemap.org" in spa_csp, spa_csp)
    # federfall-el1f: the policy derives its origins from the configured map
    # URLs, so a server-prescribed tile source cannot end up blocked by the
    # very policy that server sent — that would just relocate the footgun into
    # "set these two unrelated variables consistently".
    check("SPA CSP derives the prescribed raster tile origin",
          "https://raster.invalid" in spa_csp, spa_csp)
    check("SPA CSP derives the configured vector style origin",
          "https://vector.invalid" in spa_csp, spa_csp)
    check("derived origins do not leak the URL path or template",
          "{z}" not in spa_csp and "style.json" not in spa_csp, spa_csp)
    # A key lives in the query string of a tile URL, and the derivation cuts at
    # the origin — so it cannot end up in a header sent to every visitor.
    check("derived origins carry no query string (no API key in the header)",
          "test-map-key" not in spa_csp and "?" not in spa_csp, spa_csp)
    check("SPA CSP lets connect-src read picked-image blobs",
          "connect-src 'self' blob:" in spa_csp, spa_csp)
    check("SPA keeps COOP/COEP isolation",
          sh.get("Cross-Origin-Opener-Policy") == "same-origin"
          and sh.get("Cross-Origin-Embedder-Policy") == "credentialless",
          f"{sh.get('Cross-Origin-Opener-Policy')}/{sh.get('Cross-Origin-Embedder-Policy')}")

    # ── federfall-xvlw: Referrer-Policy + Permissions-Policy on the SPA ──────
    # federfall-txxj: NOT "same-origin" — that stripped the Referer from map
    # tile requests, which on web is the only identification they can carry
    # (the browser forbids setting User-Agent), and OSM 403s such requests.
    check("SPA gets Referrer-Policy: strict-origin-when-cross-origin",
          sh.get("Referrer-Policy") == "strict-origin-when-cross-origin",
          sh.get("Referrer-Policy"))
    perms = sh.get("Permissions-Policy") or ""
    check("SPA Permissions-Policy allows camera/geolocation for self only",
          "camera=(self)" in perms and "geolocation=(self)" in perms, perms)
    check("SPA Permissions-Policy denies microphone",
          "microphone=()" in perms, perms)
    check("uploaded files get NO Referrer/Permissions-Policy (unchanged)",
          "Referrer-Policy" not in fh and "Permissions-Policy" not in fh,
          f"{fh.get('Referrer-Policy')}/{fh.get('Permissions-Policy')}")

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

    # federfall-yst5: to_user must exist, be active, and share the case's org
    # — otherwise the handoff orphans the case (assigned to a user nobody can
    # see / who can't act).
    s, _ = req("POST", "/api/collections/placements/records", toks["a"], {
        "case": hc, "to_user": "nonexistent0000000", "org": ORG,
    })
    check("handoff to a nonexistent user is rejected", s >= 400, f"status {s}")
    s, _ = req("POST", "/api/collections/placements/records", toks["a"], {
        "case": hc, "to_user": E, "org": ORG,
    })
    check("handoff to a foreign-org user is rejected", s >= 400, f"status {s}")
    s, _ = req("POST", "/api/collections/placements/records", toks["a"], {
        "case": hc, "to_user": INACTIVE, "org": ORG,
    })
    check("handoff to a deactivated user is rejected", s >= 400, f"status {s}")
    _, hcf = req("GET", f"/api/collections/cases/records/{hc}", T)
    check("rejected handoffs left active_carer unchanged",
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

    # ── federfall-gdp8: per-case PDF report route ────────────────────────────
    # Reuses aex_case (active carer A; C has a read-share, B an edit-share from
    # the exam block above) — its own view-rule permission mirror is the one
    # new edge here: a read-only share must ALSO get the report (unlike
    # editing, which the edit-share-only checks above already cover).
    print("\n[case report PDF route]")
    # federfall-wwn1: vet appointments and egg records belong to the chronology
    # this report claims to mirror. Each is a renderEvent branch in
    # report_common.typ with its own STRINGS entries in BOTH locales, and a key
    # missing from one of them is a Typst panic — i.e. a 500 out of this route.
    # Putting these rows on aex_case is what turns the de/en fetches below into
    # a real check on them (the PDF's own text is not inspectable from here:
    # subsetted fonts, compressed streams).
    mk(T, "vet_appointments", {
        "case": aex_case, "org": ORG, "starts_at": "2026-06-26 14:30:00.000Z",
        "vet": "Dr. Meyer", "reason": "Flügel röntgen",
        "outcome": "Fraktur verheilt", "attended_at": "2026-06-26 15:10:00.000Z"})
    mk(T, "vet_appointments", {
        "case": aex_case, "org": ORG, "starts_at": "2026-06-27 09:00:00.000Z",
        "vet": "Tierklinik Nord", "reason": "Kontrolle",
        "cancelled_at": "2026-06-26 18:00:00.000Z"})
    # Neither stamp set: renders as unresolved, NOT as attended.
    mk(T, "vet_appointments", {
        "case": aex_case, "org": ORG, "starts_at": "2026-06-28 09:00:00.000Z"})
    # A presumed layer, and a bare record with no enum values at all.
    mk(T, "egg_records", {"animal": animal, "org": ORG, "count": 2,
                          "laid_at": "2026-06-29 07:00:00.000Z",
                          "fertility": "fertile", "fate": "dummy_swapped",
                          "attribution": "presumed", "notes": "Attrappen rein"})
    mk(T, "egg_records", {"animal": animal, "org": ORG, "count": 1,
                          "laid_at": "2026-06-30 07:00:00.000Z"})

    s, _, _ = req_bytes("GET", f"/api/federfall/cases/{aex_case}/report.pdf")
    check("report route requires auth", s == 401, f"status {s}")
    s, _, _ = req_bytes("GET", f"/api/federfall/cases/{aex_case}/report.pdf", gtok)
    check("guest CANNOT fetch the report", s == 403, f"status {s}")
    s, _, _ = req_bytes("GET", f"/api/federfall/cases/{aex_case}/report.pdf", td)
    check("same-org outsider (no share) CANNOT fetch the report", s == 403,
          f"status {s}")
    s, _, _ = req_bytes("GET", "/api/federfall/cases/nonexistent0000000/report.pdf",
                         toks["a"])
    check("unknown case is rejected", s >= 400, f"status {s}")

    for label, tok in [("active carer", toks["a"]), ("read-share", tc),
                       ("edit-share", toks["b"]), ("supervisor", toks["sup"]),
                       ("coordinator", toks["coord"])]:
        s, body, hdrs = req_bytes(
            "GET", f"/api/federfall/cases/{aex_case}/report.pdf", tok)
        check(f"{label} can fetch the report (200, application/pdf)",
              s == 200 and hdrs.get("Content-Type") == "application/pdf"
              and bool(body) and body[:5] == b"%PDF-",
              f"status {s} content-type {hdrs.get('Content-Type')} "
              f"len {len(body) if body else 0}")

    # `?lang=` picks the translation dict in report.typ (all localization now
    # lives there, not in the hook — federfall-gdp8's refactor); unmapped
    # values fall back to German rather than erroring.
    s, body, _ = req_bytes(
        "GET", f"/api/federfall/cases/{aex_case}/report.pdf?lang=en", toks["a"])
    check("?lang=en renders (200, application/pdf)",
          s == 200 and bool(body) and body[:5] == b"%PDF-", f"status {s}")
    s, body, _ = req_bytes(
        "GET", f"/api/federfall/cases/{aex_case}/report.pdf?lang=fr", toks["a"])
    check("unmapped ?lang= falls back to German (200, application/pdf)",
          s == 200 and bool(body) and body[:5] == b"%PDF-", f"status {s}")

    # The thermal-receipt variant (federfall-i0wq) is the same payload through
    # the same renderEvent, so a template panic on either new kind surfaces here
    # too — and it is the layout with no width to spare (federfall-wwn1 had to
    # make the date column the flexible one so a long kind title stopped
    # overprinting it).
    s, body, hdrs = req_bytes(
        "GET", f"/api/federfall/cases/{aex_case}/report.pdf?widthDots=384",
        toks["a"])
    check("?widthDots= renders the thermal receipt (200, image/png)",
          s == 200 and hdrs.get("Content-Type") == "image/png"
          and bool(body) and body[:8] == b"\x89PNG\r\n\x1a\n",
          f"status {s} type {hdrs.get('Content-Type')}")

    # federfall-wwn1: egg records carry no `case` (1700000056) — the report
    # derives membership from the animal, and narrows it to the case's own
    # window exactly as eggsInCaseWindow does client-side, or one treatment
    # episode's chronology would list a lifetime of laying events. The window
    # here is pinned by a fixed admission + disposition, so this does not depend
    # on when the suite runs. The PDF text can't be read from here, but the
    # render IS deterministic in LENGTH for identical content (only an embedded
    # timestamp varies, at a fixed width), so a row that does or doesn't appear
    # shows up as a changed or unchanged byte count.
    wanimal = mk(T, "animals", {"species": "Ringeltaube", "org": ORG})["id"]
    wcase = mk(T, "cases", {"animal": wanimal, "active_carer": A, "org": ORG,
                            "admitted_at": "2026-03-01 08:00:00.000Z"})["id"]
    mk(T, "dispositions", {"case": wcase, "org": ORG, "type": "released",
                           "disposed_at": "2026-03-20 10:00:00.000Z"})

    def report_len(cid):
        st, bd, _ = req_bytes("GET", f"/api/federfall/cases/{cid}/report.pdf",
                              toks["a"])
        return len(bd) if st == 200 and bd else 0

    base_len = report_len(wcase)
    check("setup: the window case's report renders", base_len > 0)
    mk(T, "egg_records", {"animal": wanimal, "org": ORG, "count": 2,
                          "laid_at": "2026-03-10 06:00:00.000Z"})
    in_len = report_len(wcase)
    check("an egg laid inside the case window enters the chronology",
          in_len != base_len, f"{base_len} -> {in_len}")
    mk(T, "egg_records", {"animal": wanimal, "org": ORG, "count": 1,
                          "laid_at": "2026-02-01 06:00:00.000Z"})
    check("an egg laid BEFORE admission does not",
          report_len(wcase) == in_len, f"{in_len} -> {report_len(wcase)}")
    mk(T, "egg_records", {"animal": wanimal, "org": ORG, "count": 1,
                          "laid_at": "2026-04-01 06:00:00.000Z"})
    check("an egg laid AFTER the disposition does not",
          report_len(wcase) == in_len, f"{in_len} -> {report_len(wcase)}")

    # ── federfall-dk0c: annual report route (PDF + CSV) ──────────────────────
    # One route, two formats, one table: both read `case_report_rows`, so the
    # CSV assertions below are also assertions about the PDF's case list. The
    # PDF's own text is not inspectable from here (subsetted fonts, compressed
    # streams) — the CSV is, and it is the same columns.
    print("\n[annual report route]")
    ar_type = listf(T, "marking_types", "id != ''")[0]["id"]
    # A private year nothing else in this suite touches, so the counts below
    # are exact rather than "at least".
    ar_animal = mk(T, "animals", {"species": "Hohltaube", "org": ORG,
                                  "name": "Jahresvogel"})["id"]
    ar_case = mk(T, "cases", {"animal": ar_animal, "active_carer": A, "org": ORG,
                              "admitted_at": "2019-06-15 10:00:00.000Z",
                              "city": "Oldenburg", "region": "Niedersachsen"})["id"]
    mk(T, "dispositions", {"case": ar_case, "org": ORG, "type": "released",
                           "disposed_at": "2019-07-05 10:00:00.000Z"})
    # ── The `markings` cell is evaluated at the CASE'S OWN END (1700000067),
    # not "active on the animal today", so these four rings pin all four edges
    # of that window. `markings` is animal-scoped (no `case` field), which is
    # exactly why the window matters: without it a later admission's ring would
    # print on this 2019 row.
    # (1) applied during care, never removed → released with it.
    mk(T, "markings", {"animal": ar_animal, "org": ORG, "type": ar_type,
                       "code": "DEH-A9001", "colour": "rot", "is_active": True,
                       "applied_in_case": ar_case,
                       "applied_at": "2019-06-20 09:00:00.000Z"})
    # (2) already on the bird at admission and still on at release → the
    # "what did it arrive wearing" case, which needs no column of its own.
    mk(T, "markings", {"animal": ar_animal, "org": ORG, "type": ar_type,
                       "code": "DEH-A9002", "is_active": True,
                       "applied_at": "2017-04-01 09:00:00.000Z"})
    # (3) removed DURING care → not what the bird left with.
    mk(T, "markings", {"animal": ar_animal, "org": ORG, "type": ar_type,
                       "code": "DEH-A9003", "is_active": False,
                       "applied_at": "2019-06-21 09:00:00.000Z",
                       "removed_at": "2019-06-30 09:00:00.000Z"})
    # (4) applied AFTER this case closed (a later admission) → must not
    # backdate onto this row. Still active today, so an `is_active` filter
    # would have printed it.
    mk(T, "markings", {"animal": ar_animal, "org": ORG, "type": ar_type,
                       "code": "DEH-A9004", "is_active": True,
                       "applied_at": "2021-08-01 09:00:00.000Z"})
    # (5) released with it, removed LATER → the row must still record it, which
    # an `is_active` filter would have dropped.
    mk(T, "markings", {"animal": ar_animal, "org": ORG, "type": ar_type,
                       "code": "DEH-A9005", "is_active": False,
                       "applied_at": "2019-06-22 09:00:00.000Z",
                       "removed_at": "2020-01-15 09:00:00.000Z"})
    # (6) deactivated with no removal date at all: the date is the fact and it
    # is missing, so the report drops it rather than asserting the bird had it.
    mk(T, "markings", {"animal": ar_animal, "org": ORG, "type": ar_type,
                       "code": "DEH-A9006", "is_active": False,
                       "applied_at": "2019-06-23 09:00:00.000Z"})
    # A SECOND, still-open case for the same bird: with no disposition to
    # evaluate against, its window ends now — so the 2021 ring belongs on this
    # row (and not on the closed one above), which is the whole point of dating
    # the column per case rather than per animal.
    mk(T, "cases", {"animal": ar_animal, "active_carer": A, "org": ORG,
                    "admitted_at": "2019-11-20 10:00:00.000Z", "city": "Jever"})
    # A third 2019 case whose species is a spreadsheet formula: the CSV must
    # neutralise it (OWASP CSV injection) — several cells are user-authored.
    ar_animal2 = mk(T, "animals", {"species": "=cmd|'/c calc'!A1",
                                   "org": ORG})["id"]
    ar_case2 = mk(T, "cases", {"animal": ar_animal2, "active_carer": A,
                               "org": ORG,
                               "admitted_at": "2019-09-01 10:00:00.000Z"})["id"]

    def annual(query, token, method="GET"):
        return req_bytes(method, "/api/federfall/reports/annual" + query, token)

    s, _, _ = annual("", None)
    check("annual report requires auth", s == 401, f"status {s}")
    s, _, _ = annual("", gtok)
    check("guest CANNOT fetch the annual report", s == 403, f"status {s}")
    # The figures are org-wide by construction (every case, regardless of carer
    # or share), which is exactly why `case_report_rows` is coordinator/
    # supervisor-only. A carer must not get that roster through a report route.
    s, _, _ = annual("", toks["a"])
    check("a carer CANNOT fetch the annual report", s == 403, f"status {s}")
    s, _, _ = annual("", td)
    check("other-org member CANNOT fetch the annual report", s == 403,
          f"status {s}")

    for label, tok in [("coordinator", toks["coord"]), ("supervisor", toks["sup"])]:
        s, body, hdrs = annual("?year=2019", tok)
        check(f"{label} gets the annual PDF (200, application/pdf)",
              s == 200 and hdrs.get("Content-Type") == "application/pdf"
              and bool(body) and body[:5] == b"%PDF-",
              f"status {s} type {hdrs.get('Content-Type')}")
    s, body, hdrs = annual("", toks["sup"])
    check("no ?year= renders the all-time report",
          s == 200 and bool(body) and body[:5] == b"%PDF-", f"status {s}")
    check("all-time PDF is named for the whole period",
          "gesamt" in hdrs.get("Content-Disposition", ""),
          hdrs.get("Content-Disposition"))
    # A year with no intakes must still render (a page saying so), not 500.
    s, body, _ = annual("?year=1999", toks["sup"])
    check("an empty year still renders a PDF",
          s == 200 and bool(body) and body[:5] == b"%PDF-", f"status {s}")
    s, body, _ = annual("?year=2019&lang=en", toks["sup"])
    check("?lang=en renders the annual PDF",
          s == 200 and bool(body) and body[:5] == b"%PDF-", f"status {s}")
    for bad in ["?year=abc", "?year=42", "?year=99999", "?format=xlsx"]:
        s, _, _ = annual(bad, toks["sup"])
        check(f"annual report rejects {bad}", s == 400, f"status {s}")

    # ── CSV ──────────────────────────────────────────────────────────────────
    s, body, hdrs = annual("?year=2019&format=csv", toks["sup"])
    check("?format=csv returns a CSV (200, text/csv)",
          s == 200 and hdrs.get("Content-Type", "").startswith("text/csv"),
          f"status {s} type {hdrs.get('Content-Type')}")
    check("CSV is offered as a download named for the year",
          'filename="federfall-jahresbericht-2019.csv"'
          in hdrs.get("Content-Disposition", ""),
          hdrs.get("Content-Disposition"))
    # The BOM is what makes spreadsheet apps read the file as UTF-8 at all,
    # and the hook encodes UTF-8 by hand rather than trusting the host's
    # string→bytes conversion — so this checks the actual bytes, umlauts and
    # all, not just that a body came back.
    check("CSV starts with a UTF-8 BOM", body[:3] == b"\xef\xbb\xbf",
          repr(body[:6]))
    text_csv = body[3:].decode("utf-8")
    check("CSV uses CRLF line endings", "\r\n" in text_csv)
    lines = [ln for ln in text_csv.split("\r\n") if ln]
    header = lines[0].split(",")
    check("CSV header is the 13 report columns, localized",
          len(header) == 13 and header[0] == "Fallnummer"
          and header[3] == "Markierung" and header[12] == "Aufnahmegründe",
          header)
    check("CSV covers exactly the cases admitted in the year",
          len(lines) == 4, f"{len(lines)} lines: {lines}")
    # Picked by their own dates, not by animal: both rows below are the same
    # bird, which is exactly what the markings window has to tell apart.
    row = next((ln for ln in lines if "2019-06-15" in ln), "")
    open_row = next((ln for ln in lines if "2019-11-20" in ln), "")
    check("setup: both of the bird's 2019 cases are on the report",
          bool(row) and bool(open_row), lines)
    check("the row carries the animal, ISO dates and the localized outcome",
          "Hohltaube" in row and "Jahresvogel" in row
          and "2019-06-15" in row and "2019-07-05" in row
          and "Ausgewildert" in row and "Abgeschlossen" in row, row)
    check("the row's day count spans admission to disposition",
          ",20," in row, row)
    check("a ring applied during care and kept is on the row",
          "DEH-A9001" in row, row)
    check("a ring the bird arrived wearing is too",
          "DEH-A9002" in row, row)
    check("a ring removed DURING care is not",
          "DEH-A9003" not in row, row)
    check("a ring from a LATER admission does not backdate onto this case",
          "DEH-A9004" not in row, row)
    check("a ring removed AFTER release is still what it was released with",
          "DEH-A9005" in row, row)
    check("a ring deactivated with no removal date is dropped, not asserted",
          "DEH-A9006" not in row, row)
    # Oldest first, so the cell reads as the bird's own history.
    check("the cell orders markings by when they were applied",
          row.index("DEH-A9002") < row.index("DEH-A9001") < row.index("DEH-A9005"),
          row)
    # The still-open case on the SAME bird: window ends now, so the 2021 ring
    # is on this row though it is absent from the closed one, and the rings
    # removed since are gone from it though the closed row still records them.
    check("an open case's markings are those the bird carries now",
          "DEH-A9004" in open_row and "DEH-A9001" in open_row
          and "DEH-A9002" in open_row, open_row)
    check("...and not the ones removed since",
          "DEH-A9005" not in open_row and "DEH-A9003" not in open_row,
          open_row)
    check("the same bird's two cases therefore carry different markings",
          row != open_row and ("DEH-A9004" in open_row) != ("DEH-A9004" in row),
          f"closed: {row}\nopen:   {open_row}")
    check("a formula-looking cell is neutralised with a leading apostrophe",
          "'=cmd" in text_csv, [ln for ln in lines if "cmd" in ln])
    # English switches the header AND the enum cells, from the same file the
    # Typst templates read (shared_strings.json).
    s, body, hdrs = annual("?year=2019&format=csv&lang=en", toks["sup"])
    text_en = body[3:].decode("utf-8")
    check("?lang=en localizes the CSV header and its enum cells",
          s == 200 and text_en.split("\r\n")[0].split(",")[0] == "Case no."
          and "Released" in text_en and "Ausgewildert" not in text_en,
          text_en.split("\r\n")[:2])
    check("the English CSV is named for the English report",
          "annual-report-2019" in hdrs.get("Content-Disposition", ""),
          hdrs.get("Content-Disposition"))
    # The period is the CALLER'S calendar year, not UTC's: at UTC+1 an
    # admission stamped 23:30 on 31 December is a 1 January case. The old
    # client-side CSV formatted PocketBase's UTC instant instead and put it in
    # the wrong year — the same year it had just been filtered into.
    ar_animal3 = mk(T, "animals", {"species": "Turteltaube", "org": ORG})["id"]
    mk(T, "cases", {"animal": ar_animal3, "active_carer": A, "org": ORG,
                    "admitted_at": "2018-12-31 23:30:00.000Z"})
    s, body, _ = annual("?year=2019&format=csv&tzOffsetMinutes=60", toks["sup"])
    text_tz = body[3:].decode("utf-8")
    check("a New Year's Eve admission belongs to the caller's local year",
          "Turteltaube" in text_tz and "2019-01-01" in text_tz, text_tz)
    s, body, _ = annual("?year=2018&format=csv&tzOffsetMinutes=60", toks["sup"])
    check("...and not to the UTC one",
          "Turteltaube" not in body[3:].decode("utf-8"))
    # Write attempts have no business here (the route is GET-only).
    s, _, _ = annual("?year=2019", toks["sup"], method="POST")
    check("the annual report route rejects POST", s >= 400, f"status {s}")

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
    # federfall-2asj: guests are walled off from all data everywhere else —
    # the geocode proxy must reject them too, or an auto-created OAuth2 guest
    # could burn the upstream Nominatim budget for the whole org. The guest
    # check runs before any upstream call, so this never actually contacts
    # Nominatim even with a well-formed query.
    s, _ = req("GET", "/api/federfall/geocode?q=Berlin", gtok)
    check("guest CANNOT use forward geocode", s == 403, f"status {s}")
    s, _ = req("GET", "/api/federfall/geocode/reverse?lat=52.5&lon=13.4", gtok)
    check("guest CANNOT use reverse geocode", s == 403, f"status {s}")
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
