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
import datetime
import json
import os
import re
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


def stamp(**delta):
    """A PocketBase-shaped UTC timestamp [delta] from NOW, e.g. `stamp(days=2)`.

    Relative rather than hard-coded, because the thing under test
    (disposition_dates.pb.js, federfall-j163) is a window around the server's
    own clock: a literal would stop meaning "the future" the day it passes.
    """
    when = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(**delta)
    return when.strftime("%Y-%m-%d %H:%M:%S.000Z")


def main():
    T = admin_token()

    # ── federfall-sjtg: geocode limiter must not disarm the default brakes ──
    # geocode.pb.js switches PocketBase's rate limiter on to budget the
    # geocode proxy. It used to do that from a "clean slate", discarding the
    # inactive factory default rules — shipping instances whose ONLY throttled
    # paths were the geocode routes, i.e. no server-side brake on
    # auth-with-password at all. Assert the merge keeps the defaults active,
    # and that hammering auth actually draws a 429.
    #
    # Runs FIRST (right after the one superuser auth): the `*:auth` budget is
    # 2 requests per 3 s, so this block must trip it deliberately and then
    # raise the caps before the suite's own logins start.
    print("\n[rate limiting]")
    s, st = req("GET", "/api/settings", T)
    check("settings readable", s == 200 and bool(st), f"status {s}")
    rl = (st or {}).get("rateLimits") or {}
    rules = rl.get("rules") or []
    labels = [str(r.get("label")) for r in rules]
    check("rate limiting is enabled", rl.get("enabled") is True, rl)
    # Every federfall label is METHOD-QUALIFIED. Matching is not
    # longest-prefix-wins: an exact rule wins, and failing that the first prefix
    # rule in STORED ORDER does — so a bare "/api/federfall/cases/" loses to the
    # factory "/api/" rule ahead of it and budgets nothing. Only the first
    # search label ("GET <path>") is out of "/api/"'s reach. See
    # rate_limits.pb.js; the two flood tests at the end of this file are what
    # prove the labels actually bind.
    check("the geocode budget is applied",
          "GET /api/federfall/geocode" in labels
          and "GET /api/federfall/geocode/" in labels, labels)
    # federfall-ds0d: both report routes shell out to `typst compile`, once per
    # request, synchronously — the only subprocess this app spawns. The case
    # report is open to any active member for any case they can view, so an
    # authenticated loop over it is a CPU/temp-space exhaustion primitive
    # without a budget. Prefix labels: exactly one route lives under each.
    check("the report budget is applied",
          "GET /api/federfall/reports/" in labels
          and "GET /api/federfall/cases/" in labels, labels)
    check("no inert unqualified label is left lying around",
          not [x for x in labels if x.startswith("/api/federfall/")], labels)
    check("PocketBase's default auth brake survives the federfall merge",
          "*:auth" in labels, labels)
    got429 = False
    for _ in range(8):
        s, _ = req("POST", "/api/collections/users/auth-with-password",
                   body={"identity": "nobody@f.local",
                         "password": "WrongWrong1!"})
        if s == 429:
            got429 = True
            break
    check("hammering auth-with-password hits a 429", got429,
          "no 429 within 8 attempts")
    # The suite itself must not run throttled: raise every non-geocode cap
    # sky-high. The geocode budget stays untouched — the flood test at the
    # very end relies on it.
    for r in rules:
        if "/api/federfall/geocode" not in str(r.get("label", "")):
            r["maxRequests"] = 100000
    s, _ = req("PATCH", "/api/settings", T,
               {"rateLimits": {"enabled": True, "rules": rules}})
    check("suite raised the default caps for itself", s == 200, f"status {s}")

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

    # ...and that 14 is only the FALLBACK: the duration is org-configurable
    # (organisations.settings.quarantineDefaultDays). federfall-jumi: this was
    # read with record.get() on a json field, which hands the JSVM a byte array
    # rather than an object, so the key was always undefined and every org
    # silently got 14 days however it had configured itself. The setting is
    # restored immediately after, so the rest of the suite keeps the default.
    req("PATCH", f"/api/collections/organisations/records/{ORG}", T,
        {"settings": {"quarantineDefaultDays": 5}})
    cq = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG,
                         "admitted_at": "2026-03-10 09:00:00.000Z"})
    cqrows = listf(T, "quarantine_records", f'case="{cq["id"]}"')
    check("the org's configured quarantine default is applied (admitted + 5d)",
          len(cqrows) == 1
          and cqrows[0]["quarantine_until"][:10] == "2026-03-15",
          cqrows)
    req("PATCH", f"/api/collections/organisations/records/{ORG}", T,
        {"settings": {}})
    cq2 = mk(T, "cases", {"animal": animal, "active_carer": A, "org": ORG,
                          "admitted_at": "2026-03-10 09:00:00.000Z"})
    cq2rows = listf(T, "quarantine_records", f'case="{cq2["id"]}"')
    check("clearing the setting falls back to 14 days again",
          len(cq2rows) == 1
          and cq2rows[0]["quarantine_until"][:10] == "2026-03-24",
          cq2rows)
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
    # A carer OF that org: this case used to name A, who is a member of the
    # default one, and org_scope.pb.js refuses that now (federfall-jo1l). The
    # fixture was quietly standing on the hole it closes.
    xcarer = mkuser(T, "x@f.local", "carer", org=xorg)["id"]
    s, x1 = req("POST", "/api/collections/cases/records", T,
                {"animal": xanimal, "active_carer": xcarer, "org": xorg,
                 "admitted_at": "2026-03-15 09:00:00.000Z"})
    check("second org can mint the same per-year number (org-scoped index)",
          s == 200 and x1.get("case_number") == "2026-001",
          f"{s} {x1.get('case_number') if x1 else x1}")

    # ── aviaries always have a keeper (federfall-q7ks.1) ────────────────────
    # 1700000076. The custody model resolves a resident's write authority
    # through `current_aviary.keeper`, so a keeperless enclosure would hold
    # birds nobody but a coordinator/supervisor could write about. Required is
    # what turns the display-only label from 1700000008 into that actor.
    #
    # The backfill (org's oldest active supervisor) cannot be exercised here:
    # migrations run against an empty database, so there is no legacy aviary to
    # adopt. What is checkable is the constraint it exists to enable.
    print("\n[aviary keeper]")
    s, d = req("POST", "/api/collections/aviaries/records", T,
               {"name": "Ohne Betreuer", "org": ORG})
    check("an aviary cannot be created without a keeper", s >= 400, f"{s} {d}")
    s, kept = req("POST", "/api/collections/aviaries/records", T,
                  {"name": "Mit Betreuer", "keeper": SUP, "org": ORG})
    check("...and is created once one is named", s == 200, f"{s} {kept}")
    # Required means required on every save, not only the first: clearing it
    # later would strand the residents just as thoroughly.
    s, _ = req("PATCH", f"/api/collections/aviaries/records/{kept['id']}", T,
               {"keeper": ""})
    check("an existing aviary cannot have its keeper cleared", s >= 400,
          f"status {s}")

    # ── hooks: dispositions ─────────────────────────────────────────────────
    print("\n[hooks: dispositions]")
    mk(T, "dispositions", {"case": c1["id"], "type": "released", "org": ORG})
    _, c1f = req("GET", f"/api/collections/cases/records/{c1['id']}", T)
    _, anf = req("GET", f"/api/collections/animals/records/{animal}", T)
    check("released -> case disposed", c1f["status"] == "disposed", c1f["status"])
    check("released -> animal at_large_released", anf["lifetime_status"] == "at_large_released", anf["lifetime_status"])
    av = mk(T, "aviaries", {"name": "Voliere 1", "keeper": SUP,
                            "org": ORG})["id"]
    mk(T, "dispositions", {"case": c2["id"], "type": "placed_in_aviary", "aviary": av, "org": ORG})
    _, c2f = req("GET", f"/api/collections/cases/records/{c2['id']}", T)
    _, an2 = req("GET", f"/api/collections/animals/records/{animal}", T)
    check("placed_in_aviary -> case disposed", c2f["status"] == "disposed", c2f["status"])
    check("placed_in_aviary -> animal in_aviary", an2["lifetime_status"] == "in_aviary", an2["lifetime_status"])
    check("placed_in_aviary -> current_aviary set", an2["current_aviary"] == av, an2["current_aviary"])
    # Both answers above are stated with a THIRD case, c3, still open on this
    # same bird — and they are still `at_large_released` / `in_aviary` rather
    # than `in_care`. That is federfall-8f1m's modelling decision showing its
    # other side: an open case only decides the lifetime state when it is the
    # LATEST event (c3 was admitted 2025-12-01, both dispositions were entered
    # just now). "Any open case wins" would make one case somebody forgot to
    # close pin the bird to `in_care` forever, which no disposition could repair
    # — the same bug in the other direction. Asserted rather than assumed,
    # because a c3 that had quietly become disposed would make the two checks
    # above pass for a reason that has nothing to do with this.
    _, c3f = req("GET", f"/api/collections/cases/records/{c3['id']}", T)
    check("...with a stale case still open, which is what makes that a choice",
          c3f["status"] == "in_care", c3f["status"])

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
    av2 = mk(T, "aviaries", {"name": "Voliere 2", "keeper": SUP,
                             "org": ORG})["id"]
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
    # Weights are animal-level (5yg.4) and READABLE org-wide, but since
    # 1700000079 recording one follows CUSTODY (federfall-q7ks.3): the bird's
    # carer and its edit-share holders, not the whole org. `animal` is held by A
    # through this open case, and by C through the edit share on it.
    check("the bird's carer can add a weight", can_create_weight(toks["a"]))
    check("so can an edit-share holder", can_create_weight(toks["c"]))
    check("a read-share holder CANNOT add a weight",
          not can_create_weight(toks["b"]))
    check("an outsider CANNOT add a weight", not can_create_weight(toks["d"]))
    # Case-less weights are still the point of the animal-level layer — an
    # aviary resident gets weighed without any case at all. Custody, not a case,
    # is what is required.
    s, _ = req("POST", "/api/collections/weights/records", toks["a"],
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
    # C, not B: since 1700000079 deleting also requires custody, so the actor
    # here has to HOLD the bird — otherwise this passes on missing custody and
    # stops testing the author guard it exists for. C holds `animal` through the
    # edit share on `case`; B has only a read share.
    s, _ = req("DELETE", f"/api/collections/weights/records/{wA['id']}", toks["c"])
    check("another member who holds the bird still CANNOT delete A's weight",
          s != 204, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/weights/records/{wA['id']}", toks["a"])
    check("the author can delete their own weight", s == 204, f"status {s}")
    s, wC = req("POST", "/api/collections/weights/records", toks["c"],
                {"animal": animal, "weight_g": 322, "org": ORG, "author": C})
    check("setup: C logs a weight", s == 200, f"{s} {wC}")
    s, _ = req("DELETE", f"/api/collections/weights/records/{wC['id']}", toks["sup"])
    check("a supervisor can delete any weight", s == 204, f"status {s}")
    # And custody is a floor under the author rule, not a replacement for it:
    # once the bird has left your care its history is not yours to erase.
    s, wOwn = req("POST", "/api/collections/weights/records", toks["a"],
                  {"animal": animal, "weight_g": 323, "org": ORG})
    check("setup: A logs another weight", s == 200, f"{s} {wOwn}")
    gone_animal = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    gone_case = mk(T, "cases", {"animal": gone_animal, "active_carer": A,
                                "org": ORG})["id"]
    s, wGone = req("POST", "/api/collections/weights/records", toks["a"],
                   {"animal": gone_animal, "weight_g": 324, "org": ORG})
    check("setup: A logs a weight on a second bird", s == 200, f"{s} {wGone}")
    mk(T, "dispositions", {"case": gone_case, "type": "released", "org": ORG})
    s, _ = req("DELETE", f"/api/collections/weights/records/{wGone['id']}",
               toks["a"])
    check("the author CANNOT delete it once the bird has left their care",
          s != 204, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/weights/records/{wGone['id']}",
               toks["sup"])
    check("...but a supervisor still can", s == 204, f"status {s}")

    # ── authorship is the server's to state (federfall-vfry) ────────────────
    # `author` / `created_by` / `applied_by` and the rest of the actor fields
    # were ordinary writable fields, so a member could attribute a record to a
    # colleague just by naming them in the body. authorship.pb.js pins them to
    # the authenticated caller on create and puts them back on update. This
    # matters twice over for weights: the delete guard right above hands a
    # weight's own author rights over it, so a spoofed author is also a way to
    # hand someone else the power to erase the row.
    print("\n[authorship pinning]")
    # C rather than D: recording a weight needs custody since 1700000079, and C
    # holds `animal` through the edit share on `case`. The point is unchanged —
    # someone with legitimate write access still cannot attribute the entry to a
    # colleague.
    s, spoof = req("POST", "/api/collections/weights/records", toks["c"],
                   {"animal": animal, "weight_g": 333, "org": ORG, "author": A})
    check("C can log a weight naming A as author", s == 200, f"{s} {spoof}")
    check("...but the stored author is C, not A",
          spoof.get("author") == C, f"{spoof.get('author')} (A={A}, C={C})")
    s, patched = req("PATCH",
                     f"/api/collections/weights/records/{spoof['id']}",
                     toks["c"], {"author": A, "weight_g": 334})
    check("an update cannot rewrite authorship either",
          s == 200 and patched.get("author") == C, f"{s} {patched.get('author')}")
    check("...while the rest of the update still lands",
          patched.get("weight_g") == 334, patched.get("weight_g"))
    # A carer with edit rights on the case cannot forge a colleague's clinical
    # entry there either — C holds an edit share on `case`.
    s, adm = req("POST", "/api/collections/medication_administrations/records",
                 toks["c"], {"case": case, "drug": "Baytril",
                             "administered_at": "2026-06-09 09:00:00.000Z",
                             "org": ORG, "administered_by": A})
    check("an edit-share holder cannot log a dose as someone else",
          s == 200 and adm.get("administered_by") == C,
          f"{s} {adm.get('administered_by')}")

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
    # vet_appointments shipped (1700000064) without the :isset suffix —
    # federfall-nbqy: the stored-record grant let the carer or an edit-share
    # holder re-point an appointment into ANY case, even another org's.
    # 1700000072 closes it; same probe as the journal entry above.
    s, vab = req("POST", "/api/collections/vet_appointments/records", tc,
                 {"case": case, "starts_at": "2026-08-06 09:00:00.000Z",
                  "reason": "Nachkontrolle", "org": ORG})
    check("setup: edit-share C can book an appointment", s == 200, f"{s} {vab}")
    s, _ = req("PATCH", f"/api/collections/vet_appointments/records/{vab['id']}",
               tc, {"case": victim})
    check("vet_appointment.case is immutable (no timeline injection)",
          s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/vet_appointments/records/{vab['id']}",
               tc, {"org": org2})
    check("vet_appointment.org is immutable", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/vet_appointments/records/{vab['id']}",
               tc, {"outcome": "alles verheilt"})
    check("vet_appointment content stays editable", s == 200, f"status {s}")
    req("DELETE", f"/api/collections/vet_appointments/records/{vab['id']}", tc)
    # The sweep that stops the NEXT collection repeating this: every base
    # collection whose UPDATE grant traverses `case.` / `exam.` (resolved
    # against the STORED record) must pin that relation and `org` with :isset
    # guards. Read from the live schema rather than a list of names — a
    # sampled list is exactly how vet_appointments slipped through.
    s, cols = req("GET", "/api/collections?perPage=200", T)
    check("setup: collections listed for the boundary sweep",
          s == 200 and bool(cols), f"status {s}")
    unguarded = []
    for col in (cols or {}).get("items", []):
        if col.get("type") != "base":
            continue
        rule = col.get("updateRule") or ""
        for parent in ("case", "exam"):
            # Top-level traversals only: `exam.case.org` grants via `exam`,
            # not `case`, so a dot-preceded segment does not count.
            if not re.search(rf"(?<![.\w]){parent}\.", rule):
                continue
            for f in (parent, "org"):
                if f"@request.body.{f}:isset = false" not in rule:
                    unguarded.append(f"{col['name']}: no {f} guard")
    check("every update rule granting via case/exam pins its boundary "
          "relations", not unguarded, "; ".join(unguarded))

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
    check("a carer who keeps nothing here CANNOT create an aviary journal entry",
          s >= 400, f"status {s}")
    s, ajr = req("POST", "/api/collections/journal_entries/records", toks["coord"],
                 {"aviary": av, "text": "cleaned the aviary", "org": ORG})
    check("coordinator CAN create an aviary journal entry", s == 200, f"{s} {ajr}")
    # 1700000089: the flock log is the enclosure's, not the org's. `av` is kept
    # by SUP, so carer "a" is an outsider to it in both directions — and the
    # LIST rule is asserted next to the view rule, because that is the call the
    # app makes and PocketBase filters it rather than refusing it (a 200 with
    # the row in it would be the leak, not a 4xx).
    s, _ = req("GET", f"/api/collections/journal_entries/records/{ajr['id']}", toks["a"])
    check("a carer who keeps nothing here CANNOT view the aviary journal entry",
          s >= 400, f"status {s}")
    listed = listf(toks["a"], "journal_entries", f'aviary="{av}"')
    check("…nor list it", listed == [], listed)
    s, _ = req("GET", f"/api/collections/journal_entries/records/{ajr['id']}", toks["sup"])
    check("the enclosure's keeper CAN view the aviary journal entry",
          s == 200, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/journal_entries/records/{ajr['id']}", toks["a"],
               {"text": "carer cannot edit it"})
    check("plain carer CANNOT edit the aviary journal entry", s >= 400, f"status {s}")
    # The other half of 1700000089: whoever does the cleaning writes it down.
    # A fresh enclosure kept by the plain carer — nothing else in this file
    # depends on it, so its ledger/rollup side effects stay contained.
    jav = mk(T, "aviaries", {"name": "Voliere Journal", "keeper": A,
                             "org": ORG})["id"]
    s, kjr = req("POST", "/api/collections/journal_entries/records", toks["a"],
                 {"aviary": jav, "text": "eingestreut", "org": ORG})
    check("a keeper CAN log an entry in their OWN enclosure", s == 200, f"{s} {kjr}")
    s, _ = req("PATCH", f"/api/collections/journal_entries/records/{kjr['id']}", toks["a"],
               {"text": "eingestreut und Futter gewechselt"})
    check("…and edit it", s == 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/journal_entries/records/{kjr['id']}", toks["coord"])
    check("a coordinator still reads any enclosure's journal", s == 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/journal_entries/records/{kjr['id']}", toks["b"])
    check("another carer CANNOT read the keeper's entry", s >= 400, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/journal_entries/records/{kjr['id']}", toks["b"])
    check("another carer CANNOT delete it", s >= 400, f"status {s}")
    # Keeping ONE enclosure is not keeping enclosures. Stated after "a" became a
    # keeper, because the create refusal above was made while they kept nothing
    # at all — that version passes on a rule that says "no carer writes any
    # aviary journal", which is exactly what 1700000089 stopped saying. Here the
    # caller IS a keeper and the rule must still resolve `aviary.keeper` against
    # the enclosure the body names, not against the caller's own.
    s, _ = req("POST", "/api/collections/journal_entries/records", toks["a"],
               {"aviary": av, "text": "not my enclosure", "org": ORG})
    check("a keeper CANNOT log an entry in somebody ELSE's enclosure",
          s >= 400, f"status {s}")
    s, _ = req("GET", f"/api/collections/journal_entries/records/{ajr['id']}", toks["a"])
    check("…nor read one there", s >= 400, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/journal_entries/records/{kjr['id']}", toks["a"])
    check("the keeper CAN delete their own entry", s == 204, f"status {s}")
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

    # ── quarantine view scope (federfall-teh6) ──────────────────────────────
    # `case_quarantine` is org-wide BY DESIGN, and deliberately more permissive
    # than the `quarantine_records` rows it summarises: a quarantine end date is
    # an operational fact the whole org needs ("this bird may be contagious
    # until D"), in the same class as the status and dates case_summaries
    # already publishes; the reason, who set it and the history stay behind the
    # case rule. This block is what makes that a decision rather than a drift —
    # if the predicate is ever narrowed to the case view rule, these three
    # checks are where it must be re-stated. See 1700000037's header.
    print("\n[quarantine view scope]")
    # Every case gets a quarantine row from the cases create hook, so sumcase —
    # which D can neither view nor holds a share on — already has one.
    s, qrows = req(
        "GET",
        "/api/collections/quarantine_records/records?filter="
        + urllib.parse.quote(f"case = '{sumcase}'"), td)
    check("same-org outsider CANNOT read the quarantine_records rows",
          s != 200 or not (qrows or {}).get("items"), f"{s} {qrows}")
    s, qv = req("GET",
                f"/api/collections/case_quarantine/records/{sumcase}", td)
    check("same-org outsider CAN read the quarantine view (org-wide by design)",
          s == 200 and bool(qv.get("quarantine_until")), f"{s} {qv}")
    s, _ = req("GET", f"/api/collections/case_quarantine/records/{sumcase}", te)
    check("other-org member CANNOT read the quarantine view", s != 200,
          f"status {s}")

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
    # A holds animal2 as well, and C through an edit share — the egg record gets
    # reassigned onto it below, and since 1700000079 writing an animal-scoped row
    # needs custody of the bird it hangs off. Without this the reassignment would
    # strand the record where its own author can no longer touch it.
    animal2_case = mk(T, "cases", {"animal": animal2, "active_carer": A,
                                   "org": ORG})["id"]
    mk(T, "case_shares", {"case": animal2_case, "shared_with": C,
                          "shared_by": A, "access": "edit", "org": ORG})
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
    # Reading is org-wide; WRITING follows custody since 1700000079 (q7ks.3).
    s, _ = req("PATCH", f"/api/collections/egg_records/records/{egg['id']}",
               toks["d"], {"notes": "Windei"})
    check("an outsider CANNOT edit an egg record", s >= 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/egg_records/records/{egg['id']}",
               toks["a"], {"notes": "Windei"})
    check("the bird's carer can", s == 200, f"status {s}")
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
                   toks["a"], {"animal": animal2, "attribution": "confirmed"})
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

    # delete: author or supervisor only (1700000047's stance), now with custody
    # as a floor under it (1700000079). C is used rather than an outsider so the
    # refusal is the AUTHOR guard talking and not a missing custody — the record
    # sits on animal2, which both A and C hold.
    s, _ = req("DELETE", f"/api/collections/egg_records/records/{egg['id']}",
               toks["c"])
    check("another member who holds the bird CANNOT delete A's egg record",
          s != 204, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/egg_records/records/{egg['id']}",
               toks["a"])
    check("the author can delete their own egg record", s == 204, f"status {s}")
    s, eggC = req("POST", "/api/collections/egg_records/records", toks["c"],
                  {"animal": animal2, "count": 1, "author": C, "org": ORG})
    check("setup: C logs an egg record", s == 200, f"{s} {eggC}")
    s, _ = req("DELETE", f"/api/collections/egg_records/records/{eggC['id']}",
               toks["sup"])
    check("a supervisor can delete any egg record", s == 204, f"status {s}")
    # Leave one row behind so the guest sweep's member check stays non-vacuous.
    mk(T, "egg_records", {"animal": animal, "count": 1, "org": ORG})

    # ── vaccinations (1700000087) ───────────────────────────────────────────
    # The identity-layer ledger again — org-wide read, custody-gated write,
    # author-or-supervisor delete — with ONE deliberate difference from
    # egg_records that this block exists to pin: `animal` is FROZEN here.
    # Re-attributing an egg is a feature (the presumed layer being corrected);
    # moving a vaccination to another bird is a mistake to be deleted and
    # re-entered, so it takes 1700000082's treatment rather than
    # animal_custody_scope.pb.js's. If someone ever unfreezes it, the custody
    # predicate silently starts authorising the bird the row is leaving.
    print("\n[vaccinations]")
    s, vacc = req("POST", "/api/collections/vaccinations/records", toks["a"], {
        "animal": animal, "vaccine": "Colombovac PMV",
        "target": "Paramyxovirose", "administered_at": "2026-06-02 08:00:00.000Z",
        "batch": "C-4711", "dose": 0.2, "dose_unit": "ml", "series": "primary",
        "next_due_at": "2027-06-02 08:00:00.000Z", "vet": "TA Praxis Müller",
        "author": A, "org": ORG,
    })
    check("the bird's carer can record a vaccination", s == 200, f"{s} {vacc}")
    s, _ = req("POST", "/api/collections/vaccinations/records", toks["a"],
               {"animal": animal, "batch": "no-product", "org": ORG})
    check("a vaccination without a product is rejected", s >= 400, f"status {s}")
    s, _ = req("GET", f"/api/collections/vaccinations/records/{vacc['id']}",
               toks["d"])
    check("any org member can view a vaccination", s == 200, f"status {s}")
    check("vaccinations are org-scoped readable",
          len(listf(toks["d"], "vaccinations", f"id = \"{vacc['id']}\"")) == 1)
    # Read is org-wide because "is this bird vaccinated" is exactly the
    # cross-case question the collection exists to answer; writing is not.
    s, _ = req("PATCH", f"/api/collections/vaccinations/records/{vacc['id']}",
               toks["d"], {"batch": "C-0000"})
    check("a member who does not hold the bird CANNOT edit it", s >= 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/vaccinations/records/{vacc['id']}",
               toks["a"], {"batch": "C-4712"})
    check("the bird's carer can", s == 200, f"status {s}")
    s, _ = req("GET", f"/api/collections/vaccinations/records/{vacc['id']}", te)
    check("other-org member CANNOT view a vaccination", s != 200, f"status {s}")
    s, _ = req("POST", "/api/collections/vaccinations/records", te,
               {"animal": animal, "vaccine": "x", "org": ORG})
    check("other-org member CANNOT create in this org", s >= 400, f"status {s}")

    # The freeze, and the guards around it.
    s, _ = req("PATCH", f"/api/collections/vaccinations/records/{vacc['id']}",
               toks["a"], {"animal": animal2})
    check("vaccination.animal is FROZEN (unlike an egg's)", s >= 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/vaccinations/records/{vacc['id']}",
               toks["a"], {"org": org2})
    check("vaccination.org is immutable", s >= 400, f"status {s}")
    s, _ = req("POST", "/api/collections/vaccinations/records", toks["a"],
               {"animal": animal_org2, "vaccine": "Colombovac PMV", "org": ORG})
    check("a vaccination CANNOT be created on another org's animal", s >= 400,
          f"status {s}")

    # attachments: born protected + MIME-allowlisted, so no repair migration
    # ever has to find this field (1700000027 / 1700000048 / 1700000049).
    s, d = upload_file(
        "PATCH", f"/api/collections/vaccinations/records/{vacc['id']}",
        toks["a"], "attachments", "evil.svg", "image/svg+xml", _SVG,
    )
    check("SVG upload to vaccinations.attachments is rejected", s >= 400,
          f"{s} {d}")
    s, d = upload_file(
        "PATCH", f"/api/collections/vaccinations/records/{vacc['id']}",
        toks["a"], "attachments", "vial.png", "image/png", _PNG_1X1,
    )
    check("PNG upload to vaccinations.attachments works",
          s == 200 and bool(d.get("attachments")), f"{s} {d}")
    vacc_att = ((d or {}).get("attachments") or [None])[0]
    vacc_file = f"/api/files/vaccinations/{vacc['id']}/{vacc_att}"
    check("vaccination attachment URL WITHOUT a token is rejected",
          file_status(vacc_file) != 200, file_status(vacc_file))
    check("same-org member's file token serves it",
          file_status(f"{vacc_file}?token={file_token(toks['d'])}") == 200)
    check("the 200x200 thumb is generated (thumbs whitelist)",
          file_status(f"{vacc_file}?thumb=200x200&token={file_token(toks['d'])}")
          == 200)

    # delete: author or supervisor, with custody as a floor (1700000079's
    # stance). C holds `animal2` through an edit share, so its refusal below is
    # the AUTHOR guard talking rather than a missing custody.
    s, vaccC = req("POST", "/api/collections/vaccinations/records", toks["c"],
                   {"animal": animal2, "vaccine": "Colombovac Paratyphus",
                    "author": C, "org": ORG})
    check("setup: C records a vaccination", s == 200, f"{s} {vaccC}")
    s, _ = req("DELETE", f"/api/collections/vaccinations/records/{vaccC['id']}",
               toks["a"])
    check("another member who holds the bird CANNOT delete C's vaccination",
          s != 204, f"status {s}")
    s, _ = req("DELETE", f"/api/collections/vaccinations/records/{vaccC['id']}",
               toks["c"])
    check("the author can delete their own vaccination", s == 204,
          f"status {s}")
    s, vaccC2 = req("POST", "/api/collections/vaccinations/records", toks["c"],
                    {"animal": animal2, "vaccine": "Taubenpocken", "author": C,
                     "org": ORG})
    s, _ = req("DELETE", f"/api/collections/vaccinations/records/{vaccC2['id']}",
               toks["sup"])
    check("a supervisor can delete any vaccination", s == 204, f"status {s}")

    # ── vaccine_labels (1700000088) ────────────────────────────────────────
    # The vocabulary view that makes free-text `vaccine`/`target` converge:
    # DISTINCT pairs actually recorded, per org. It is what a code list would
    # have been, built out of use instead of curated (and so immune to
    # federfall-buqb, where code lists are not seeded for later orgs).
    labels = listf(toks["d"], "vaccine_labels", "vaccine != ''")
    pmv = [r for r in labels if r["vaccine"] == "Colombovac PMV"]
    check("a recorded vaccine appears in the suggestion view", len(pmv) == 1,
          labels)
    check("...paired with the target it was recorded against",
          bool(pmv) and pmv[0]["target"] == "Paramyxovirose", pmv)
    check("...and counted, so suggestions can rank by use",
          bool(pmv) and int(pmv[0]["use_count"]) >= 1, pmv)
    check("the view is org-scoped",
          all(r["org"] == ORG for r in labels), labels)
    check("another org sees none of this org's vocabulary",
          not [r for r in listf(te, "vaccine_labels", "vaccine != ''")
               if r["org"] == ORG])

    # Leave one row behind so the guest sweep's member check stays non-vacuous.
    mk(T, "vaccinations", {"animal": animal, "vaccine": "Colombovac PMV",
                           "target": "Paramyxovirose", "org": ORG})

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
        # Driven with T, so the `animal` freeze on the rule is bypassed and what
        # is exercised here is the ORG hook — which is the point: the freeze
        # protects the client path, org_scope.pb.js protects every path.
        "vaccinations": mk(T, "vaccinations", {
            "animal": animal, "vaccine": "Colombovac PMV", "org": ORG,
        })["id"],
    }
    ti77_creates = {
        "weights": {"weight_g": 301, "org": ORG},
        "markings": {"type": ti77_type, "org": ORG},
        "exams": {"case": case, "org": ORG},
        "cases": {"active_carer": A, "org": ORG},
        "egg_records": {"count": 1, "org": ORG},
        "vaccinations": {"vaccine": "Colombovac PMV", "org": ORG},
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

    # ── every OTHER relation, too (federfall-jo1l) ──────────────────────────
    # `animal` was checked and nothing else was, so eleven relations could name
    # a row in another organisation — found by the `[relation guards]` sweep
    # below, not by anyone probing. org_scope.pb.js now asks the SCHEMA which
    # relations are org-scoped rather than being handed a list, which is why
    # animal_org_scope.pb.js is gone and the block above passes unchanged.
    #
    # Driven with T for the same reason as ti77's: a superuser bypasses
    # collection rules, so a refusal here can only be this hook. Under a user
    # token most of these would be refused by `org = @request.auth.org` first
    # and the guard itself would go untested.
    #
    # Both directions on every field: an in-org value must still go through, or
    # a hook that refused everything would pass this block just as well.
    print("\n[relation org scope]")
    jo_av = mk(T, "aviaries", {"name": "Fremde Voliere", "keeper": E,
                               "org": org2})["id"]
    jo_type = mk(T, "marking_types", {"label": "Fremdring", "active": True,
                                      "org": org2})["id"]
    jo_reason = mk(T, "admission_reasons", {"label": "Fremdgrund",
                                            "active": True, "org": org2})["id"]
    jo_own_reason = mk(T, "admission_reasons", {"label": "jo1l Grund",
                                                "active": True,
                                                "org": ORG})["id"]
    jo_own_av = mk(T, "aviaries", {"name": "Eigene Voliere jo1l",
                                   "keeper": SUP, "org": ORG})["id"]

    # A user of another org as an enclosure's keeper. This one is worth more
    # than a label: `current_aviary.keeper` is a custody branch (1700000077), so
    # a foreign keeper is a foreign name in an authority position — it still
    # grants nothing, because the rule ALSO compares orgs, but the enclosure
    # would list somebody its org cannot see.
    s, _ = req("POST", "/api/collections/aviaries/records", T,
               {"name": "Fremdbetreut", "keeper": E, "org": ORG})
    check("an aviary cannot be kept by another org's user", s == 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/aviaries/records/{jo_own_av}", T,
               {"keeper": E})
    check("...nor re-assigned to one", s == 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/aviaries/records/{jo_own_av}", T,
               {"keeper": B})
    check("...while a keeper change within the org still works", s == 200,
          f"status {s}")

    # The handoff target. `active_carer` is THE mutable relation on cases.
    jo_case = mk(T, "cases", {"animal": animal, "active_carer": A,
                              "org": ORG})["id"]
    s, _ = req("POST", "/api/collections/cases/records", T,
               {"animal": animal, "active_carer": E, "org": ORG})
    check("a case cannot be opened by another org's carer", s == 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/cases/records/{jo_case}", T,
               {"active_carer": E})
    check("...nor handed to one", s == 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/cases/records/{jo_case}", T,
               {"active_carer": B})
    check("...while a handoff inside the org still works", s == 200,
          f"status {s}")

    # A code list is the realisable half of this bug: expanding the relation
    # renders another org's vocabulary inside this one's UI.
    jo_marking = mk(T, "markings", {"animal": animal, "type": ti77_type,
                                    "org": ORG})["id"]
    s, _ = req("POST", "/api/collections/markings/records", T,
               {"animal": animal, "type": jo_type, "org": ORG})
    check("a marking cannot use another org's ring type", s == 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/markings/records/{jo_marking}", T,
               {"type": jo_type})
    check("...nor be corrected onto one", s == 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/markings/records/{jo_marking}", T,
               {"type": ti77_type})
    check("...while the org's own list still works", s == 200, f"status {s}")

    # A MULTI-valued relation: every element is checked, not just the first —
    # which is the half a single-value implementation gets wrong silently.
    s, _ = req("PATCH", f"/api/collections/cases/records/{jo_case}", T,
               {"admission_reasons": [jo_reason]})
    check("a case cannot cite another org's admission reason", s == 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/cases/records/{jo_case}", T,
               {"admission_reasons": [jo_own_reason, jo_reason]})
    check("...not even smuggled in behind one of its own", s == 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/cases/records/{jo_case}", T,
               {"admission_reasons": [jo_own_reason]})
    check("...while its own reasons still apply", s == 200, f"status {s}")

    # `dispositions.aviary` feeds `current_aviary`, i.e. the custody pointer.
    jo_animal = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    jo_disp_case = mk(T, "cases", {"animal": jo_animal, "active_carer": A,
                                   "org": ORG})["id"]
    s, _ = req("POST", "/api/collections/dispositions/records", T,
               {"case": jo_disp_case, "type": "placed_in_aviary",
                "aviary": jo_av, "org": ORG})
    check("a bird cannot be placed into another org's enclosure", s == 400,
          f"status {s}")
    _, jo_animal_rec = req("GET",
                           f"/api/collections/animals/records/{jo_animal}", T)
    check("...so nothing pointed its custody at one",
          (jo_animal_rec or {}).get("current_aviary") == "", jo_animal_rec)
    s, _ = req("POST", "/api/collections/dispositions/records", T,
               {"case": jo_disp_case, "type": "placed_in_aviary",
                "aviary": jo_own_av, "org": ORG})
    check("...while its own enclosure still houses it", s == 200, f"status {s}")

    # The identity collection points at itself, and that relation was as open
    # as the rest.
    jo_user = mkuser(T, "jo1l@f.local", "carer")["id"]
    s, _ = req("PATCH", f"/api/collections/users/records/{jo_user}", T,
               {"invited_by": E})
    check("a user cannot be invited by another org's supervisor", s == 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/users/records/{jo_user}", T,
               {"invited_by": SUP})
    check("...while their own supervisor still works", s == 200, f"status {s}")

    # ── identity-layer write guards (federfall-1hgp + federfall-7no9) ────────
    # 1700000075. Everything here is driven with USER tokens on purpose: a
    # superuser bypasses collection rules entirely, so the ti77 block above
    # (which uses T) could not have caught any of this.
    #
    # 1hgp: `org` is the scope everything hangs on. An UPDATE rule resolves a
    # plain field reference against the STORED record, so `org = @request.auth.org`
    # passes on the row's OLD org while the body moves it to another tenant —
    # and since the children keep pointing at it, a supervisor in the target org
    # deleting that bird cascades away the first org's history.
    #
    # 7no9: `current_aviary` / `lifetime_status` are derived from the case's
    # dispositions. A client that can set them directly can relocate a bird with
    # no disposition to explain it, or declare it dead.
    print("\n[identity layer write guards]")
    g_animal = mk(T, "animals", {"species": "Stadttaube", "name": "Wächter",
                                 "org": ORG})["id"]
    # A HOLDS this bird — an open case makes them its custodian (1700000077).
    # That matters for what follows: driven by an outsider, every refusal below
    # would pass for the wrong reason (no custody) and the guards themselves
    # would go untested. A custodian isolates them as the only thing saying no.
    g_case = mk(T, "cases", {"animal": g_animal, "active_carer": A,
                             "org": ORG})["id"]
    g_marking = mk(T, "markings", {"animal": g_animal, "type": ti77_type,
                                   "code": "DE-GUARD", "org": ORG})["id"]
    g_weight = mk(T, "weights", {"animal": g_animal, "weight_g": 300,
                                 "org": ORG})["id"]
    g_egg = mk(T, "egg_records", {"animal": g_animal, "count": 1,
                                  "org": ORG})["id"]

    for coll, rec in (("animals", g_animal), ("markings", g_marking),
                      ("weights", g_weight), ("egg_records", g_egg)):
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{rec}", toks["a"],
                   {"org": org2})
        check(f"{coll} cannot be pushed into another org", s >= 400, f"status {s}")
    _, still = req("GET", f"/api/collections/animals/records/{g_animal}", toks["a"])
    check("...and the bird is still where it was",
          (still or {}).get("org") == ORG, still)
    # Not even a supervisor: this is a tenant boundary, not a permission level.
    # (A supervisor also clears custody outright, so the guard is the only thing
    # left that can refuse them.)
    s, _ = req("PATCH", f"/api/collections/animals/records/{g_animal}",
               toks["sup"], {"org": org2})
    check("a supervisor cannot either", s >= 400, f"status {s}")

    for field, value in (("current_aviary", av), ("lifetime_status", "deceased")):
        s, _ = req("PATCH", f"/api/collections/animals/records/{g_animal}",
                   toks["a"], {field: value})
        check(f"the bird's own carer cannot write the derived {field}", s >= 400,
              f"status {s}")
        s, _ = req("PATCH", f"/api/collections/animals/records/{g_animal}",
                   toks["sup"], {field: value})
        check(f"...nor a supervisor ({field})", s >= 400, f"status {s}")

    # The guards must not have cost the real edit paths anything: this is the
    # whole app-facing surface of these three collections.
    s, _ = req("PATCH", f"/api/collections/animals/records/{g_animal}", toks["a"],
               {"name": "Umbenannt", "species": "Ringeltaube", "sex": "female"})
    check("the custodian can still edit the bird's identity", s == 200,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/markings/records/{g_marking}",
               toks["a"], {"code": "DE-NEU", "present_at_find": True})
    check("editing a marking still works", s == 200, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/weights/records/{g_weight}", toks["a"],
               {"weight_g": 305})
    check("editing a weight still works", s == 200, f"status {s}")

    # And the hooks that OWN the derived fields still write them: `app.save()`
    # bypasses API rules, so a disposition remains the one way into an aviary.
    mk(toks["a"], "dispositions", {"case": g_case, "type": "placed_in_aviary",
                                   "aviary": av, "org": ORG})
    _, housed = req("GET", f"/api/collections/animals/records/{g_animal}", toks["b"])
    check("a disposition still houses the bird the client could not",
          (housed or {}).get("current_aviary") == av
          and (housed or {}).get("lifetime_status") == "in_aviary", housed)
    open_stays = listf(T, "aviary_stays",
                       f'animal = "{g_animal}" && ended_at = ""')
    check("...and the residency ledger recorded exactly one open stay",
          len(open_stays) == 1 and open_stays[0]["aviary"] == av, open_stays)

    # ── custody: writing about a bird requires holding it (q7ks.2) ───────────
    # 1700000077. Reads stay org-wide (re-identification needs them); WRITES
    # follow whoever currently holds the animal — the active carer of a
    # non-disposed case plus its edit-share holders, or the keeper of the
    # enclosure it lives in. Coordinator/supervisor override throughout.
    print("\n[custody: animals]")
    # An enclosure kept by a plain CARER, so the keeper branch is
    # distinguishable from the coordinator/supervisor override.
    cu_av = mk(T, "aviaries", {"name": "Voliere B", "keeper": B, "org": ORG})["id"]
    cu_resident = mk(T, "animals", {
        "species": "Stadttaube", "name": "Bewohnerin", "org": ORG,
        "current_aviary": cu_av, "lifetime_status": "in_aviary",
    })["id"]
    # A bird in A's acute care, shared with D at edit and with C read-only.
    cu_incare = mk(T, "animals", {"species": "Stadttaube", "name": "Patient",
                                  "org": ORG})["id"]
    cu_case = mk(T, "cases", {"animal": cu_incare, "active_carer": A,
                              "org": ORG})["id"]
    mk(T, "case_shares", {"case": cu_case, "shared_with": D, "shared_by": A,
                          "access": "edit", "org": ORG})
    mk(T, "case_shares", {"case": cu_case, "shared_with": C, "shared_by": A,
                          "access": "read", "org": ORG})
    # A bird at large: its only case is closed, so nobody holds it.
    cu_gone = mk(T, "animals", {"species": "Stadttaube", "name": "Frei",
                                "org": ORG})["id"]
    cu_gone_case = mk(T, "cases", {"animal": cu_gone, "active_carer": A,
                                   "org": ORG})["id"]
    mk(T, "dispositions", {"case": cu_gone_case, "type": "released", "org": ORG})

    def edits_animal(tok, animal, value):
        s, _ = req("PATCH", f"/api/collections/animals/records/{animal}", tok,
                   {"name": value})
        return s == 200

    for i, (who, target, want, label) in enumerate([
        ("a", cu_incare, True, "the active carer edits the bird in their care"),
        ("d", cu_incare, True, "an EDIT-share holder on that case edits it"),
        ("c", cu_incare, False, "a READ-share holder cannot"),
        ("b", cu_incare, False, "an unrelated carer cannot"),
        ("b", cu_resident, True, "the aviary's keeper edits its resident"),
        ("a", cu_resident, False, "...but a carer who is not the keeper cannot"),
        ("a", cu_gone, False, "nobody holds a released bird — not even its "
                              "former carer"),
        # Keeping an enclosure is authority over THAT enclosure, not a standing
        # rank: B keeps cu_av and still holds nothing outside it.
        ("b", cu_gone, False, "...nor a keeper whose enclosure the bird is "
                              "not in"),
        ("coord", cu_gone, True, "a coordinator overrides"),
        ("sup", cu_gone, True, "a supervisor overrides"),
    ]):
        got = edits_animal(toks[who], target, f"custody-{i}")
        check(label, got == want, f"got {'allowed' if got else 'refused'}")

    # ready_for_release is still custody: the bird is in the carer's hands until
    # it actually leaves. Same status set the case browser calls active
    # (federfall-jt5u), named rather than negated so the two cannot drift.
    s, _ = req("PATCH", f"/api/collections/cases/records/{cu_case}", T,
               {"status": "ready_for_release"})
    check("setup: the case moves to ready_for_release", s == 200, f"status {s}")
    check("a carer keeps custody through ready_for_release",
          edits_animal(toks["a"], cu_incare, "bereit"), "refused")

    # ── the one fact the whole design rests on ──────────────────────────────
    # Two `?=` clauses on the same back-relation must bind to the SAME joined
    # row. B is the carer of a CLOSED case on a bird that ALSO carries A's open
    # one: evaluated independently, `active_carer` would match on B's row and
    # `status` on A's, and B would be let through. That correlation is why there
    # is no denormalized `custodian` column (1700000077's header). If a
    # PocketBase upgrade changes it, THIS is the check that must fail — the fix
    # is a denormalized column, not a widened rule.
    cu_two = mk(T, "animals", {"species": "Stadttaube", "name": "Zwei Fälle",
                               "org": ORG})["id"]
    cu_closed = mk(T, "cases", {"animal": cu_two, "active_carer": B,
                                "org": ORG})["id"]
    mk(T, "cases", {"animal": cu_two, "active_carer": A, "org": ORG})
    mk(T, "dispositions", {"case": cu_closed, "type": "released", "org": ORG})
    check("a FORMER carer is refused while the bird carries someone else's "
          "open case (the ?= clauses correlate)",
          not edits_animal(toks["b"], cu_two, "korr-b"), "B got through")
    check("...while the current carer is unaffected",
          edits_animal(toks["a"], cu_two, "korr-a"), "A was refused")
    # The same trap one hop deeper, through the share chain.
    mk(T, "case_shares", {"case": cu_closed, "shared_with": C, "shared_by": B,
                          "access": "edit", "org": ORG})
    check("an EDIT share on a DISPOSED case grants nothing either "
          "(the 2-hop chain correlates)",
          not edits_animal(toks["c"], cu_two, "korr-c"), "C got through")

    # ── create: placing a bird into an enclosure is the keeper's call ────────
    # CREATE resolves plain field references against the SUBMITTED record, so
    # `current_aviary.keeper` reads the INCOMING aviary — the opposite of the
    # UPDATE behaviour this schema keeps tripping over, and what makes this
    # expressible as a rule at all. Supersedes federfall-ftm2, where the UI
    # gated its "add resident" FAB behind canManageAviaries and the server let
    # anyone through.
    def adds_resident(tok, aviary):
        s, _ = req("POST", "/api/collections/animals/records", tok, {
            "species": "Stadttaube", "org": ORG,
            "current_aviary": aviary, "lifetime_status": "in_aviary",
        })
        return s == 200

    check("the keeper can add a resident to their own aviary",
          adds_resident(toks["b"], cu_av), "refused")
    check("a carer cannot add one to someone else's aviary",
          not adds_resident(toks["a"], cu_av), "allowed")
    check("a coordinator can", adds_resident(toks["coord"], cu_av), "refused")
    s, _ = req("POST", "/api/collections/animals/records", toks["a"],
               {"species": "Stadttaube", "org": ORG})
    check("a bird created into NO enclosure stays open to any member",
          s == 200, f"status {s}")

    # ── custody reaches the animal-scoped records too (q7ks.3) ──────────────
    # 1700000079. Same predicate as above, one hop further through `animal.` —
    # and that hop is the risky one: cases_repository.dart:301 documents a
    # forward-then-back path (`animal.markings_via_animal`) where a second clause
    # on the same back-relation is satisfied INDEPENDENTLY. If that applied here,
    # the trap row below would let a former carer through whenever the bird also
    # carried somebody else's open case. It does not (probed on 0.39.8; the
    # difference appears to be `?=` any-of vs the `=`/`~` all-of forms in that
    # comment), so this is the pin. Reads stay org-wide throughout.
    print("\n[custody: animal-scoped records]")
    for coll, payload, patch in (
        ("weights", {"weight_g": 300}, {"notes": "korrigiert"}),
        ("markings", {"type": ti77_type, "code": "KEEP-1"}, {"colour": "blau"}),
        ("egg_records", {"count": 1}, {"notes": "korrigiert"}),
    ):
        # The keeper branch: B keeps cu_av, where cu_resident lives, and that
        # bird has no case at all — so nothing but the enclosure can grant this.
        s, kept = req("POST", f"/api/collections/{coll}/records", toks["b"],
                      {"animal": cu_resident, "org": ORG, **payload})
        check(f"the keeper can record a {coll[:-1]} on their resident",
              s == 200, f"status {s}")
        kept_id = (kept or {}).get("id", "")
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["a"],
                   {"animal": cu_resident, "org": ORG, **payload})
        check(f"a non-keeper carer cannot ({coll})", s >= 400, f"status {s}")
        # Org-wide READ is untouched: re-identification depends on it.
        rows = listf(toks["a"], coll, f'animal = "{cu_resident}"')
        check(f"...but can still READ that {coll[:-1]}", len(rows) >= 1, rows)
        # UPDATE runs the same predicate, and needs its own row: an update rule
        # resolves `animal.` against the STORED record (1700000043's finding),
        # which is a different evaluation path from create's submitted one.
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{kept_id}",
                   toks["b"], patch)
        check(f"the keeper can edit that {coll[:-1]}", s == 200, f"status {s}")
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{kept_id}",
                   toks["a"], patch)
        check(f"a non-keeper carer cannot edit it ({coll})", s >= 400,
              f"status {s}")
        # The share branch reaches these rows too, and only at `edit`: D holds
        # an edit share on cu_case, C only a read one.
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["d"],
                   {"animal": cu_incare, "org": ORG, **payload})
        check(f"an EDIT-share holder can record a {coll[:-1]}", s == 200,
              f"status {s}")
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["c"],
                   {"animal": cu_incare, "org": ORG, **payload})
        check(f"a READ-share holder cannot ({coll})", s >= 400, f"status {s}")
        # The trap: B is the carer of a CLOSED case on cu_two, which also
        # carries A's OPEN one.
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["b"],
                   {"animal": cu_two, "org": ORG, **payload})
        check(f"a former carer cannot record a {coll[:-1]} while the bird "
              f"carries another's open case", s >= 400, f"status {s}")
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["a"],
                   {"animal": cu_two, "org": ORG, **payload})
        check(f"...while the current carer can ({coll})", s == 200,
              f"status {s}")

    # DELETE keeps whatever was already NARROWER — custody is a floor, not a
    # widening. `weights` and `egg_records` stay author-or-supervisor with
    # custody under them ([weights delete guard] / [egg_records] pin both
    # halves), and `markings.delete` was already supervisor-only in 1700000010,
    # so 1700000079 left it untouched. Nothing was checking that last one, and
    # the app leans on it: the timeline tile and the animal detail both offer the
    # delete only to a supervisor (federfall-q7ks.6). B here is the row's own
    # author AND the keeper of the bird's enclosure, so custody and authorship
    # are both satisfied and the role is the only thing left saying no.
    s, mk_del = req("POST", "/api/collections/markings/records", toks["b"],
                    {"animal": cu_resident, "type": ti77_type,
                     "code": "DEL-1", "org": ORG})
    check("setup: the keeper applies a marking", s == 200, f"{s} {mk_del}")
    s, _ = req("DELETE",
               f"/api/collections/markings/records/{(mk_del or {}).get('id')}",
               toks["b"])
    check("its own author, holding the bird, still CANNOT delete a marking",
          s != 204, f"status {s}")
    s, _ = req("DELETE",
               f"/api/collections/markings/records/{(mk_del or {}).get('id')}",
               toks["sup"])
    check("...only a supervisor can", s == 204, f"status {s}")

    # ── case-scoped writes (federfall-piu5) ──────────────────────────────────
    # Custody says WHICH BIRD you may write about; it says nothing about which
    # CASE you may file the row into. `weights.case` and
    # `markings.applied_in_case` were unconstrained, so a carer who legitimately
    # holds a bird could attach a weight or a ring to a DIFFERENT, older case of
    # that same bird — one belonging to another carer, which they cannot even
    # read — and it would surface in that carer's timeline, in case_report_rows
    # and in the annual report. Private-by-default held for reads and not for
    # writes. 1700000081 closes it with 1700000010's own `childEdit`, reached
    # through the row's relation field.
    print("\n[case-scoped writes]")
    # One bird, two cases with DIFFERENT carers, both open — so custody of the
    # animal is satisfied for each of them and the case is the only thing left
    # that can refuse. A's case is private to A; B's is private to B.
    cs_animal = mk(T, "animals", {"species": "Stadttaube", "name": "Zweigeteilt",
                                  "org": ORG})["id"]
    cs_a = mk(T, "cases", {"animal": cs_animal, "active_carer": A,
                           "org": ORG})["id"]
    cs_b = mk(T, "cases", {"animal": cs_animal, "active_carer": B,
                           "org": ORG})["id"]
    check("setup: B cannot even read A's case on the shared bird",
          req("GET", f"/api/collections/cases/records/{cs_a}", toks["b"])[0]
          != 200, "B could read it")
    check("setup: ...yet B holds the bird through their own open case",
          edits_animal(toks["b"], cs_animal, "geteilt"), "B was refused")

    for coll, field, payload in (
        ("weights", "case", {"weight_g": 404}),
        ("markings", "applied_in_case", {"type": ti77_type, "code": "PIU5"}),
    ):
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["b"],
                   {"animal": cs_animal, "org": ORG, field: cs_a, **payload})
        check(f"a {coll[:-1]} CANNOT be filed into a case its writer cannot "
              f"read", s >= 400, f"status {s}")
        s, own = req("POST", f"/api/collections/{coll}/records", toks["b"],
                     {"animal": cs_animal, "org": ORG, field: cs_b, **payload})
        check(f"...but can be filed into their own ({coll})", s == 200,
              f"status {s}")
        # The case-less path is the aviary one and stays open to whoever holds
        # the bird — this is what keeps the identity-layer stance intact.
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["b"],
                   {"animal": cs_animal, "org": ORG, **payload})
        check(f"...and a case-less {coll[:-1]} needs only custody", s == 200,
              f"status {s}")
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["b"],
                   {"animal": cs_animal, "org": ORG, field: "", **payload})
        check(f"...an explicitly EMPTY case reads as none, not as a refusal "
              f"({coll})", s == 200, f"status {s}")
        # An EDIT share on the foreign case is the way in — same predicate every
        # other case child uses (1700000010's childEdit).
        cs_share = mk(T, "case_shares", {"case": cs_a, "shared_with": B,
                                         "shared_by": A, "access": "edit",
                                         "org": ORG})["id"]
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["b"],
                   {"animal": cs_animal, "org": ORG, field: cs_a, **payload})
        check(f"an EDIT share on that case opens it ({coll})", s == 200,
              f"status {s}")
        s, _ = req("DELETE", f"/api/collections/case_shares/records/{cs_share}",
                   T)
        check(f"setup: the share is revoked ({coll})", s == 204, f"status {s}")
        # A read share is not enough, for the same reason it is not enough
        # anywhere else.
        cs_share = mk(T, "case_shares", {"case": cs_a, "shared_with": B,
                                         "shared_by": A, "access": "read",
                                         "org": ORG})["id"]
        s, _ = req("POST", f"/api/collections/{coll}/records", toks["b"],
                   {"animal": cs_animal, "org": ORG, field: cs_a, **payload})
        check(f"a READ share does not ({coll})", s >= 400, f"status {s}")
        s, _ = req("DELETE", f"/api/collections/case_shares/records/{cs_share}",
                   T)
        check(f"setup: the read share is revoked ({coll})", s == 204,
              f"status {s}")

        # UPDATE freezes the field rather than checking it: on update the same
        # reference resolves against the STORED record (1700000043), i.e. against
        # the case the row is being moved AWAY from. No client path sends it —
        # both sheets put it in their create branch only.
        own_id = (own or {}).get("id", "")
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{own_id}",
                   toks["b"], {field: cs_a})
        check(f"an existing {coll[:-1]} cannot be RE-FILED into a foreign case",
              s >= 400, f"status {s}")
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{own_id}",
                   toks["b"], {field: cs_b})
        check(f"...not even into the one it already names ({coll})", s >= 400,
              f"status {s}")
        # The rest of the row stays editable — the guard must not have cost the
        # ordinary correction path anything.
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{own_id}",
                   toks["b"], {"notes": "korrigiert"}
                   if coll == "weights" else {"colour": "gruen"})
        check(f"...while its content is still editable ({coll})", s == 200,
              f"status {s}")

    # ── cases.animal, the same hole one level up ─────────────────────────────
    # Re-pointing your OWN case onto somebody else's bird is a way to rewrite
    # THAT bird's derived state: a disposition on the case then decides its
    # `lifetime_status` and `current_aviary`, and since 1700000077 the latter is
    # a custody pointer — so it evicts another keeper's resident and takes their
    # write access with it. Exactly what federfall-sinp caused by accident.
    cs_target = mk(T, "animals", {"species": "Stadttaube", "name": "Fremd",
                                  "org": ORG, "current_aviary": cu_av,
                                  "lifetime_status": "in_aviary"})["id"]
    s, _ = req("PATCH", f"/api/collections/cases/records/{cs_b}", toks["b"],
               {"animal": cs_target})
    check("a carer cannot re-point their own case onto another keeper's bird",
          s >= 400, f"status {s}")
    _, cs_still = req("GET", f"/api/collections/cases/records/{cs_b}", T)
    check("...and the case still names the bird it was opened for",
          (cs_still or {}).get("animal") == cs_animal, cs_still)
    s, _ = req("PATCH", f"/api/collections/cases/records/{cs_b}", toks["b"],
               {"animal": cs_animal})
    check("...not even a no-op re-point of the bird it already names", s >= 400,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/cases/records/{cs_b}", toks["b"],
               {"intake_notes": "weiterhin bearbeitbar"})
    check("...while the case itself stays editable", s == 200, f"status {s}")
    # The merge route re-points it legitimately, through tx.save() — which
    # bypasses API rules, so the guard must not have broken it. Pinned in
    # [animal merge]; asserted here as the reason this guard is safe.

    # ── the animal relation cannot be re-pointed (federfall-v9ap) ────────────
    # 1700000079's custody predicate is reached through `animal.`, so on UPDATE it
    # resolves against the STORED record (1700000043's finding) and authorises the
    # bird the row is moving AWAY FROM. Two calls sidestepped the whole control:
    # create a row on a bird you hold, then PATCH its `animal` to anyone else's.
    # These collections are org-wide READABLE, so the victim then sees the row.
    #
    # 1700000082 freezes the field for weights/markings/exams; egg_records keeps
    # it mutable (re-attribution is a shipped feature) and gets a destination-side
    # custody check in animal_custody_scope.pb.js instead.
    print("\n[animal relation is not re-pointable]")
    rp_mine = mk(T, "animals", {"species": "Stadttaube", "name": "Meiner",
                                "org": ORG})["id"]
    rp_case = mk(T, "cases", {"animal": rp_mine, "active_carer": A,
                              "org": ORG})["id"]
    # A holds rp_mine through their own open case; they hold NOTHING on cu_resident,
    # which carries another carer's open case.
    check("setup: A holds their own bird", edits_animal(toks["a"], rp_mine, "mein"),
          "A was refused")
    # cu_resident lives in B's enclosure and has no case at all, so A holds
    # nothing on it. NOT cu_two, which carries A's own open case — using that
    # would have made the egg-reassignment check below pass for the wrong reason
    # (custody satisfied), which is exactly what this setup assertion caught.
    check("setup: ...and holds nothing on the other one",
          not edits_animal(toks["a"], cu_resident, "nicht mein"), "A got through")

    for coll, payload in (
        ("weights", {"weight_g": 222}),
        ("markings", {"type": ti77_type, "code": "RP-1"}),
    ):
        s, row = req("POST", f"/api/collections/{coll}/records", toks["a"],
                     {"animal": rp_mine, "org": ORG, **payload})
        check(f"setup: A records a {coll[:-1]} on their own bird", s == 200,
              f"status {s}")
        row_id = (row or {}).get("id", "")
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{row_id}",
                   toks["a"], {"animal": cu_resident})
        check(f"a {coll[:-1]} cannot be moved onto a bird its writer does not "
              f"hold", s >= 400, f"status {s}")
        # Frozen, not checked: even the bird it already names is refused, which
        # is what an isset guard means and what keeps the guard cheap.
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{row_id}",
                   toks["a"], {"animal": rp_mine}) 
        check(f"...not even onto the bird it already names ({coll})", s >= 400,
              f"status {s}")
        s, _ = req("PATCH", f"/api/collections/{coll}/records/{row_id}",
                   toks["a"], {"notes": "inhalt"} if coll == "weights"
                   else {"colour": "rot"})
        check(f"...while its content stays editable ({coll})", s == 200,
              f"status {s}")
        # And the victim's bird never acquired the row.
        rows = listf(toks["b"], coll, f'animal = "{cu_resident}"')
        check(f"the other bird carries no injected {coll[:-1]}",
              all(x["id"] != row_id for x in rows), rows)

    # exams: case-scoped rather than custody-scoped, but its `animal` is
    # denormalized onto the lifetime view, so re-pointing files an exam onto a
    # bird the writer has no relationship with. 1700000043 already froze `case`
    # and `org`; this is the third of the three.
    s, rp_exam = req("POST", "/api/federfall/exam", toks["a"],
                     {"case": rp_case, "animal": rp_mine,
                      "exam": {"notes": "eigen"}})
    check("setup: A saves an exam on their own case", s == 200, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/exams/records/{(rp_exam or {}).get('id')}",
               toks["a"], {"animal": cu_resident})
    check("an exam cannot be re-pointed onto another bird", s >= 400,
          f"status {s}")

    # egg_records stay re-attributable — that is egg_reassign_sheet.dart — but
    # only onto a bird the writer holds.
    s, rp_egg = req("POST", "/api/collections/egg_records/records", toks["a"],
                    {"animal": rp_mine, "count": 1, "org": ORG})
    check("setup: A logs an egg record on their own bird", s == 200,
          f"status {s}")
    rp_egg_id = (rp_egg or {}).get("id", "")
    s, _ = req("PATCH", f"/api/collections/egg_records/records/{rp_egg_id}",
               toks["a"], {"animal": cu_resident})
    check("an egg record cannot be re-attributed to a bird its writer does not "
          "hold", s >= 400, f"status {s}")
    # The feature itself still works: A holds cu_incare through nothing, but D
    # holds it through an edit share — so use a bird A really does hold. A second
    # bird of A's own.
    rp_mine2 = mk(T, "animals", {"species": "Stadttaube", "name": "Meiner2",
                                 "org": ORG})["id"]
    mk(T, "cases", {"animal": rp_mine2, "active_carer": A, "org": ORG})
    s, moved = req("PATCH", f"/api/collections/egg_records/records/{rp_egg_id}",
                   toks["a"], {"animal": rp_mine2, "attribution": "confirmed"})
    check("...but re-attribution to a bird they DO hold still works",
          s == 200 and (moved or {}).get("animal") == rp_mine2, f"{s} {moved}")

    # ── the exam route wrote a weights row for any animal (federfall-v9ap) ───
    # The route bypasses collection rules, so 1700000079's custody predicate on
    # `weights.create` never applied to the row it writes — and 1700000082's
    # freeze cannot reach a tx.save() either. It validated only that the body's
    # `animal` existed and was same-org, so a weight could be laundered onto any
    # bird in the org: refused as a direct POST, accepted through here.
    s, d = req("POST", "/api/federfall/exam", toks["a"], {
        "case": rp_case, "animal": cu_resident,
        "exam": {"notes": "geschmuggelt"}, "weight_g": 42,
    })
    check("the exam route refuses an animal that is not its case's", s == 400,
          f"{s} {d}")
    smuggled = [x for x in listf(T, "weights", f'animal = "{cu_resident}"')
                if x.get("weight_g") == 42]
    check("...so no weight was laundered onto the other bird",
          len(smuggled) == 0, smuggled)
    # The same call as a direct write is what the route must not be a way around.
    s, _ = req("POST", "/api/collections/weights/records", toks["a"],
               {"animal": cu_resident, "weight_g": 42, "org": ORG})
    check("...which is exactly what the direct write refuses too", s >= 400,
          f"status {s}")

    # ── disposition ordering (federfall-sinp) ────────────────────────────────
    # `animals.lifetime_status` / `current_aviary` are derived from the LATEST
    # disposition, and "latest" used to mean the most recently INSERTED row —
    # every scan compared `created`, the autodate, while `dispositions` carries a
    # real event date in `disposed_at`. Live use enters things in order and never
    # noticed; archive work does not, and since 1700000077 `current_aviary` is a
    # CUSTODY pointer, so getting this wrong revokes a keeper's authority over a
    # live resident.
    #
    # lib_derive.js is now the single answer for all four writers (disposition
    # create / update / delete and merge_animals.pb.js), ordered by
    # COALESCE(NULLIF(disposed_at,''), created) DESC, id DESC — the expression
    # `case_summaries` and `case_report_rows` have always used. Until now a bird's
    # own record could disagree with the case browser and both reports about which
    # disposition ended its story.
    print("\n[disposition ordering]")

    def animal_state(animal_id):
        _, d = req("GET", f"/api/collections/animals/records/{animal_id}", T)
        return ((d or {}).get("lifetime_status"), (d or {}).get("current_aviary"))

    # ── THE headline: an archived disposition must not evict a live resident ──
    so_res = mk(T, "animals", {"species": "Stadttaube", "name": "Bestandsvogel",
                               "org": ORG})["id"]
    so_home = mk(T, "cases", {"animal": so_res, "active_carer": A,
                              "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_home, "type": "placed_in_aviary",
                           "aviary": cu_av,
                           "disposed_at": "2026-01-15 10:00:00.000Z",
                           "org": ORG})
    check("setup: the bird is a resident of B's enclosure",
          animal_state(so_res) == ("in_aviary", cu_av), animal_state(so_res))
    check("setup: ...and B holds it through that enclosure",
          edits_animal(toks["b"], so_res, "bestand"), "B was refused")
    so_stays = [x for x in listf(T, "aviary_stays", f'animal = "{so_res}"')
                if x["ended_at"] == ""]
    check("setup: with one open residency", len(so_stays) == 1, so_stays)

    # Now backfill an ARCHIVED release from BEFORE it moved in. This is the
    # data-entry action that used to empty current_aviary, close the running stay
    # with a present-dated ended_at, and take B's write access with it.
    so_old = mk(T, "cases", {"animal": so_res, "active_carer": A,
                             "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_old, "type": "released",
                           "disposed_at": "2025-06-01 10:00:00.000Z",
                           "org": ORG})
    check("an archived release does NOT evict a current resident",
          animal_state(so_res) == ("in_aviary", cu_av), animal_state(so_res))
    so_after = listf(T, "aviary_stays", f'animal = "{so_res}"')
    check("...and leaves the running residency alone — no false ended_at",
          len(so_after) == 1 and so_after[0]["ended_at"] == "", so_after)
    check("...so its keeper still holds it (1700000077 reads current_aviary)",
          edits_animal(toks["b"], so_res, "immer noch bestand"), "B was refused")
    # The order-INDEPENDENT half is untouched: any disposition closes its own
    # case, whichever one happens to be latest for the animal.
    _, so_old_rec = req("GET", f"/api/collections/cases/records/{so_old}", T)
    check("...while the archived case is still closed by its own disposition",
          (so_old_rec or {}).get("status") == "disposed", so_old_rec)

    # ── the ordering itself: enter the NEWER event first, then an older one ───
    # Insertion order and event order disagree here, which is the whole point:
    # by `created` the `died` row wins and the bird reads deceased; by
    # `disposed_at` the release does.
    # Three dispositions in strictly DESCENDING event order, so insertion order
    # and event order disagree at every step — including after a delete, which is
    # why there are three rather than two.
    #
    # Each case carries an `admitted_at` well before all three events, and that
    # is load-bearing for the delete below rather than decoration: deleting a
    # case's only disposition RE-OPENS it (reconcileCase), and since
    # federfall-8f1m an open case is an event too — one with no admission date
    # would fall back to its `created`, i.e. now, and out-date every survivor.
    # What is under test here is which DISPOSITION wins, so the admission is
    # dated where it belongs, in 2024.
    so_rev = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    so_rev_disp = []
    for kind, when in (("released", "2026-01-01"), ("transferred", "2025-09-01"),
                       ("died", "2025-01-01")):
        so_rev_case = mk(T, "cases", {"animal": so_rev, "active_carer": A,
                                      "org": ORG,
                                      "admitted_at": "2024-01-01 09:00:00.000Z"})["id"]
        so_rev_disp.append(mk(T, "dispositions", {
            "case": so_rev_case, "type": kind,
            "disposed_at": f"{when} 10:00:00.000Z", "org": ORG,
        })["id"])
    # By `created` the `died` row is last and the bird reads deceased; by
    # `disposed_at` the 2026 release is what ended its story.
    check("the LATEST EVENT decides, not the last row entered",
          animal_state(so_rev)[0] == "at_large_released", animal_state(so_rev))

    # Deleting the winner falls back to the next latest BY EVENT DATE — with the
    # two survivors again in the opposite order from how they were entered, so a
    # `created` comparison would answer deceased here.
    s, _ = req("DELETE",
               f"/api/collections/dispositions/records/{so_rev_disp[0]}", T)
    check("setup: the later disposition is deleted", s == 204, f"status {s}")
    check("deleting it falls back to the next latest event, not the next row",
          animal_state(so_rev)[0] == "at_large_released", animal_state(so_rev))

    # ── the after-UPDATE path: moving an event date moves the answer ──────────
    # The placement is entered FIRST and dated EARLIER, so both orders agree that
    # the release ends the story — and then the placement is re-dated past it.
    # Only an event-ordered reconcile changes its answer.
    #
    # "Past it" has to stay in the PAST: since federfall-j163 a disposition
    # cannot be dated more than a day ahead, so the correction moves it to
    # 2026-06-01 rather than to a date that would have been rejected outright
    # (which is a 400 the [disposition dates] block asserts on purpose).
    so_upd = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    so_upd_av = mk(T, "cases", {"animal": so_upd, "active_carer": A,
                                "org": ORG})["id"]
    so_upd_disp = mk(T, "dispositions", {
        "case": so_upd_av, "type": "placed_in_aviary", "aviary": cu_av,
        "disposed_at": "2026-01-01 10:00:00.000Z", "org": ORG,
    })["id"]
    so_upd_rel = mk(T, "cases", {"animal": so_upd, "active_carer": A,
                                 "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_upd_rel, "type": "released",
                           "disposed_at": "2026-05-01 10:00:00.000Z",
                           "org": ORG})
    check("setup: the release is the later event, so the bird is at large",
          animal_state(so_upd) == ("at_large_released", ""),
          animal_state(so_upd))
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{so_upd_disp}",
               T, {"disposed_at": "2026-06-01 10:00:00.000Z"})
    check("setup: the placement is corrected to a later date", s == 200,
          f"status {s}")
    check("re-dating a disposition re-derives the state from the new order",
          animal_state(so_upd) == ("in_aviary", cu_av), animal_state(so_upd))
    so_upd_stays = [x for x in listf(T, "aviary_stays", f'animal = "{so_upd}"')
                    if x["ended_at"] == ""]
    check("...and the ledger opens exactly one residency for it",
          len(so_upd_stays) == 1 and so_upd_stays[0]["aviary"] == cu_av,
          so_upd_stays)

    # ── no disposed_at: insertion order still decides ────────────────────────
    # An Admin-UI or imported row can carry no event date at all. `disposed_at`
    # unset is "", which would sort before every real date, so the fallback to
    # `created` is what keeps such a history from reading backwards.
    so_bare = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    so_bare_1 = mk(T, "cases", {"animal": so_bare, "active_carer": A,
                                "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_bare_1, "type": "released", "org": ORG})
    so_bare_2 = mk(T, "cases", {"animal": so_bare, "active_carer": A,
                                "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_bare_2, "type": "died", "org": ORG})
    # Both orders agree here by construction, so this is a regression guard on
    # the fallback rather than a pin on the ordering fix.
    check("with no event dates at all, the last row entered still decides",
          animal_state(so_bare)[0] == "deceased", animal_state(so_bare))
    # And a dated row beats an undated one entered after it: the undated one
    # falls back to its own `created`, which is NOW, so this also pins that the
    # fallback is per-row rather than "all or nothing".
    so_mix = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    so_mix_1 = mk(T, "cases", {"animal": so_mix, "active_carer": A,
                               "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_mix_1, "type": "released",
                           "disposed_at": "2020-01-01 10:00:00.000Z",
                           "org": ORG})
    so_mix_2 = mk(T, "cases", {"animal": so_mix, "active_carer": A,
                               "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_mix_2, "type": "died", "org": ORG})
    check("an undated row falls back to its own created, so today beats 2020",
          animal_state(so_mix)[0] == "deceased", animal_state(so_mix))

    # ── the merge route reconciles by the same order (the fourth writer) ──────
    # merge_animals.pb.js held its own copy of the scan and compared `created`
    # too. The duplicate's release is the later EVENT but the earlier ROW, so the
    # two answers differ.
    so_mg_keep = mk(T, "animals", {"species": "Stadttaube", "name": "Sieger",
                                   "org": ORG})["id"]
    so_mg_gone = mk(T, "animals", {"species": "Stadttaube", "name": "Dublette2",
                                   "org": ORG})["id"]
    so_mg_gone_case = mk(T, "cases", {"animal": so_mg_gone, "active_carer": A,
                                      "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_mg_gone_case, "type": "released",
                           "disposed_at": "2026-07-01 10:00:00.000Z",
                           "org": ORG})
    so_mg_keep_case = mk(T, "cases", {"animal": so_mg_keep, "active_carer": A,
                                      "org": ORG})["id"]
    mk(T, "dispositions", {"case": so_mg_keep_case, "type": "died",
                           "disposed_at": "2024-02-01 10:00:00.000Z",
                           "org": ORG})
    s, _ = req("POST", "/api/federfall/merge-animals", toks["sup"],
               {"survivor": so_mg_keep, "duplicate": so_mg_gone, "fields": {}})
    check("setup: the merge succeeds", s == 200, f"status {s}")
    check("the merged history settles on the latest EVENT across both records",
          animal_state(so_mg_keep)[0] == "at_large_released",
          animal_state(so_mg_keep))

    # ── an open case is an event too (federfall-8f1m) ────────────────────────
    # `lifetime_status` was derived from dispositions alone, and "this bird has
    # an open case" is not a disposition — so a returning bird read `Released`
    # through the whole of its second stay, and a resident under treatment read
    # `In Voliere`. The derivation now weighs the latest admission against the
    # latest disposition; `current_aviary` deliberately does NOT follow, because
    # since 1700000077 it is a custody pointer and emptying it on admission is
    # the eviction federfall-sinp just fixed.
    print("\n[open cases in the derivation]")

    # THE headline: released, then found again.
    oc_back = mk(T, "animals", {"species": "Stadttaube", "name": "Rückkehrerin",
                                "org": ORG})["id"]
    oc_first = mk(T, "cases", {"animal": oc_back, "active_carer": A,
                               "org": ORG,
                               "admitted_at": "2026-02-01 09:00:00.000Z"})["id"]
    mk(T, "dispositions", {"case": oc_first, "type": "released",
                           "disposed_at": "2026-03-01 10:00:00.000Z",
                           "org": ORG})
    check("setup: the bird was released in March",
          animal_state(oc_back) == ("at_large_released", ""),
          animal_state(oc_back))
    oc_second = mk(T, "cases", {"animal": oc_back, "active_carer": A,
                                "org": ORG,
                                "admitted_at": "2026-06-15 08:00:00.000Z"})["id"]
    check("a returning bird reads in_care for its whole second stay",
          animal_state(oc_back) == ("in_care", ""), animal_state(oc_back))
    # ...and hands the label back to the disposition once that stay ends.
    mk(T, "dispositions", {"case": oc_second, "type": "died",
                           "disposed_at": "2026-06-20 10:00:00.000Z",
                           "org": ORG})
    check("...and falls back to the latest disposition when it ends",
          animal_state(oc_back) == ("deceased", ""), animal_state(oc_back))

    # A resident under treatment: the enclosure and its keeper's custody must
    # both survive the admission. B keeps cu_av.
    oc_res = mk(T, "animals", {"species": "Stadttaube", "name": "Kranke Bewohnerin",
                               "org": ORG})["id"]
    oc_res_home = mk(T, "cases", {"animal": oc_res, "active_carer": A,
                                  "org": ORG,
                                  "admitted_at": "2026-01-05 09:00:00.000Z"})["id"]
    mk(T, "dispositions", {"case": oc_res_home, "type": "placed_in_aviary",
                           "aviary": cu_av,
                           "disposed_at": "2026-01-20 10:00:00.000Z",
                           "org": ORG})
    check("setup: the bird lives in B's enclosure",
          animal_state(oc_res) == ("in_aviary", cu_av), animal_state(oc_res))
    mk(T, "cases", {"animal": oc_res, "active_carer": A, "org": ORG,
                    "admitted_at": "2026-04-01 09:00:00.000Z"})
    check("a resident that falls ill reads in_care",
          animal_state(oc_res)[0] == "in_care", animal_state(oc_res))
    check("...without being evicted from its enclosure",
          animal_state(oc_res)[1] == cu_av, animal_state(oc_res))
    check("...so its keeper still holds it (1700000077 reads current_aviary)",
          edits_animal(toks["b"], oc_res, "krank"), "B was refused")
    oc_res_stays = [x for x in listf(T, "aviary_stays", f'animal = "{oc_res}"')
                    if x["ended_at"] == ""]
    check("...and the residency ledger sees no move at all",
          len(oc_res_stays) == 1 and oc_res_stays[0]["aviary"] == cu_av,
          oc_res_stays)

    # A case-less resident (add_animal_sheet.dart) has no disposition ANYWHERE,
    # so the enclosure lives only on the animal record. Opening a case on it is
    # the path where a plain reconcile would answer `aviary: ""` and evict it.
    oc_bare = mk(T, "animals", {
        "species": "Stadttaube", "name": "Direkt eingesetzt", "org": ORG,
        "current_aviary": cu_av, "lifetime_status": "in_aviary",
    })["id"]
    mk(T, "cases", {"animal": oc_bare, "active_carer": A, "org": ORG})
    check("admitting a case-less resident does not evict it",
          animal_state(oc_bare) == ("in_care", cu_av), animal_state(oc_bare))
    oc_bare_stays = listf(T, "aviary_stays", f'animal = "{oc_bare}"')
    check("...and opens no second residency, closes no first one",
          len(oc_bare_stays) == 1 and oc_bare_stays[0]["ended_at"] == "",
          oc_bare_stays)

    # The other direction, stated on purpose (see [hooks: dispositions]): an
    # open case OLDER than the latest disposition does not override it.
    oc_stale = mk(T, "animals", {"species": "Stadttaube", "name": "Alter Fall",
                                 "org": ORG})["id"]
    oc_stale_open = mk(T, "cases", {
        "animal": oc_stale, "active_carer": A, "org": ORG,
        "admitted_at": "2025-02-01 09:00:00.000Z",
    })["id"]
    oc_stale_later = mk(T, "cases", {
        "animal": oc_stale, "active_carer": A, "org": ORG,
        "admitted_at": "2026-01-01 09:00:00.000Z",
    })["id"]
    mk(T, "dispositions", {"case": oc_stale_later, "type": "released",
                           "disposed_at": "2026-01-10 10:00:00.000Z",
                           "org": ORG})
    check("a case left open BEFORE the last disposition does not override it",
          animal_state(oc_stale)[0] == "at_large_released",
          animal_state(oc_stale))
    # ...and correcting that admission date to after the release does. This is
    # the `admitted_at` half of main.pb.js's update trigger: the answer has to
    # move with no disposition touched at all.
    s, _ = req("PATCH", f"/api/collections/cases/records/{oc_stale_open}", T,
               {"admitted_at": "2026-06-01 09:00:00.000Z"})
    check("setup: the stale case turns out to be the later admission", s == 200,
          f"status {s}")
    check("re-dating an admission re-derives from the new order",
          animal_state(oc_stale)[0] == "in_care", animal_state(oc_stale))
    s, _ = req("PATCH", f"/api/collections/cases/records/{oc_stale_open}", T,
               {"admitted_at": "2025-02-01 09:00:00.000Z"})
    check("setup: ...and back to where it was", s == 200, f"status {s}")
    check("...both ways", animal_state(oc_stale)[0] == "at_large_released",
          animal_state(oc_stale))

    # Closing and re-opening the case is the `status` half of the same trigger,
    # and deleting it is the third leg. Case delete is supervisor-only.
    oc_del = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    oc_del_first = mk(T, "cases", {"animal": oc_del, "active_carer": A,
                                   "org": ORG,
                                   "admitted_at": "2026-02-01 09:00:00.000Z"})["id"]
    mk(T, "dispositions", {"case": oc_del_first, "type": "released",
                           "disposed_at": "2026-03-01 10:00:00.000Z",
                           "org": ORG})
    oc_del_open = mk(T, "cases", {"animal": oc_del, "active_carer": A,
                                  "org": ORG,
                                  "admitted_at": "2026-07-01 09:00:00.000Z"})["id"]
    check("setup: the second admission makes it in_care",
          animal_state(oc_del)[0] == "in_care", animal_state(oc_del))
    s, _ = req("PATCH", f"/api/collections/cases/records/{oc_del_open}", T,
               {"status": "disposed"})
    check("setup: that case is closed", s == 200, f"status {s}")
    check("a closed case stops speaking for the bird",
          animal_state(oc_del)[0] == "at_large_released", animal_state(oc_del))
    s, _ = req("PATCH", f"/api/collections/cases/records/{oc_del_open}", T,
               {"status": "ready_for_release"})
    check("setup: and is re-opened, at ready_for_release", s == 200,
          f"status {s}")
    check("ready_for_release is still an open case (the same active set)",
          animal_state(oc_del)[0] == "in_care", animal_state(oc_del))
    s, _ = req("DELETE", f"/api/collections/cases/records/{oc_del_open}",
               toks["sup"])
    check("setup: the open case is deleted", s == 204, f"status {s}")
    check("deleting the open case hands the answer back to the disposition",
          animal_state(oc_del)[0] == "at_large_released", animal_state(oc_del))

    # ── a disposition cannot have happened tomorrow (federfall-j163) ─────────
    # `disposed_at` is the order key, and since 1700000077 the latest event also
    # decides `current_aviary`, i.e. who may write about the bird. A row dated
    # 2099 would stay "latest" against everything that actually happens
    # afterwards. The app cannot produce one (disposition_sheet.dart picks
    # through `pickDate`, whose lastDate is today), so this refuses hand-crafted
    # requests only — but it refuses them for every writer, superuser included,
    # which is why this block drives it with T.
    print("\n[disposition dates]")
    dd_animal = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    dd_case = mk(T, "cases", {"animal": dd_animal, "active_carer": A,
                              "org": ORG,
                              "admitted_at": "2026-01-02 09:00:00.000Z"})["id"]
    s, _ = req("POST", "/api/collections/dispositions/records", T,
               {"case": dd_case, "type": "released", "org": ORG,
                "disposed_at": stamp(days=2)})
    check("a disposition dated two days out is refused", s == 400, f"status {s}")
    s, _ = req("POST", "/api/collections/dispositions/records", T,
               {"case": dd_case, "type": "placed_in_aviary", "aviary": cu_av,
                "org": ORG, "disposed_at": "2099-01-01 10:00:00.000Z"})
    check("...and one dated 2099 too", s == 400, f"status {s}")
    check("...so nothing pinned the bird's derived state",
          animal_state(dd_animal) == ("in_care", ""), animal_state(dd_animal))
    # A date-only value normalises to midnight UTC, which is still outside the
    # window — the guard reads the STORED value, not the string sent.
    s, _ = req("POST", "/api/collections/dispositions/records", T,
               {"case": dd_case, "type": "released", "org": ORG,
                "disposed_at": stamp(days=3)[:10]})
    check("a date-only future value is refused as well", s == 400, f"status {s}")
    # It is a window, not "any instant after now": a client clock running ahead,
    # or a device as far east as UTC+14, must still be able to record a release.
    s, dd_ok = req("POST", "/api/collections/dispositions/records", T,
                   {"case": dd_case, "type": "released", "org": ORG,
                    "disposed_at": stamp(hours=1)})
    check("a disposition an hour ahead still goes through (clock skew)",
          s == 200, f"status {s}")
    check("...and decides the bird's state as usual",
          animal_state(dd_animal)[0] == "at_large_released",
          animal_state(dd_animal))
    # The update leg fires only on a CHANGED date, so correcting anything else
    # on an existing row is untouched.
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{dd_ok['id']}",
               T, {"disposed_at": stamp(days=2)})
    check("re-dating an existing disposition into the future is refused",
          s == 400, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{dd_ok['id']}",
               T, {"reason": "Wildbahn, unauffällig"})
    check("...while editing the rest of it still works", s == 200, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{dd_ok['id']}",
               T, {"disposed_at": "2026-04-04 10:00:00.000Z"})
    check("...and re-dating it into the past still works", s == 200,
          f"status {s}")

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

    # ── animal merge: every child collection is re-pointed (federfall-0ua6) ──
    # The merge ends in tx.delete(duplicate), and EVERY collection with a
    # direct `animal` relation cascades on it. So a collection the re-point
    # loop forgets is not left behind — it is destroyed, inside the merge
    # transaction, with a 200 on the wire. `egg_records` and `aviary_stays`
    # were both added after that list was written and were being erased by
    # every merge. This block is the guard for the whole list, so add a case
    # here whenever a new collection points at `animals`.
    print("\n[animal merge]")
    mg_av_a = mk(T, "aviaries", {"name": "Merge-Voliere A", "keeper": SUP,
                                 "org": ORG})["id"]
    mg_av_b = mk(T, "aviaries", {"name": "Merge-Voliere B", "keeper": SUP,
                                 "org": ORG})["id"]
    # Both records are aviary residents, in DIFFERENT enclosures — the case
    # that produces two open stays on one animal if the ledger is re-pointed
    # without reconciling it.
    mg_keep = mk(T, "animals", {
        "species": "Stadttaube", "name": "Bleibt", "org": ORG,
        "current_aviary": mg_av_a, "lifetime_status": "in_aviary",
    })["id"]
    mg_gone = mk(T, "animals", {
        "species": "Stadttaube", "name": "Dublette", "org": ORG,
        "current_aviary": mg_av_b, "lifetime_status": "in_aviary",
    })["id"]
    mg_case = mk(T, "cases", {
        "animal": mg_gone, "active_carer": A, "org": ORG,
    })["id"]
    mg_weight = mk(T, "weights", {
        "animal": mg_gone, "weight_g": 280, "org": ORG,
    })["id"]
    mg_marking = mk(T, "markings", {
        "animal": mg_gone, "type": ti77_type, "org": ORG,
    })["id"]
    mg_egg = mk(T, "egg_records", {
        "animal": mg_gone, "count": 2, "org": ORG,
    })["id"]
    mg_vacc = mk(T, "vaccinations", {
        "animal": mg_gone, "vaccine": "Colombovac PMV", "org": ORG,
    })["id"]
    # federfall-5s5j — the one child here that does NOT cascade (1700000085), so
    # it would SURVIVE a forgotten re-point rather than be destroyed by one. It
    # still has to move: an orphaned patronage is invisible to every keeper (no
    # animal, so no current_aviary, so nothing the read rule can reach) and the
    # retention cron sweeps it — leaving it behind would silently end a live
    # patronage on the bird that is being kept.
    mg_sponsor = mk(T, "sponsorships", {
        "animal": mg_gone, "sponsor_name": "Merle Pate", "org": ORG,
    })["id"]
    mg_stay = listf(T, "aviary_stays", f'animal = "{mg_gone}"')
    check("the duplicate starts with one open stay",
          len(mg_stay) == 1 and mg_stay[0]["ended_at"] == "", mg_stay)
    mg_stay = mg_stay[0]["id"] if mg_stay else ""

    # Supervisor-only end to end, and that role gate is also what stands in for
    # a custody check on this route (merge_animals.pb.js): a supervisor holds
    # every bird in the org, so requireCustody would be a literal no-op. The gate
    # itself was going unchecked — and it is load-bearing twice over, because a
    # merge rewrites the survivor's identity and DESTROYS the duplicate. If this
    # route is ever widened below supervisor, custody has to arrive in the same
    # change, and this is where that has to be noticed.
    for who, label in (("a", "a carer"), ("coord", "a coordinator")):
        s, d = req("POST", "/api/federfall/merge-animals", toks[who],
                   {"survivor": mg_keep, "duplicate": mg_gone, "fields": {}})
        check(f"{label} cannot merge two animals", s == 403, f"{s} {d}")
    _, mg_intact = req("GET", f"/api/collections/animals/records/{mg_gone}", T)
    check("...and the duplicate is still there",
          (mg_intact or {}).get("id") == mg_gone, mg_intact)

    s, _ = req("POST", "/api/federfall/merge-animals", toks["sup"],
               {"survivor": mg_keep, "duplicate": mg_gone, "fields": {}})
    check("merge succeeds", s == 200, f"status {s}")
    for coll, rec_id, label in [
        ("cases", mg_case, "cases"),
        ("weights", mg_weight, "weights"),
        ("markings", mg_marking, "markings"),
        ("egg_records", mg_egg, "egg records"),
        ("vaccinations", mg_vacc, "vaccinations"),
        ("aviary_stays", mg_stay, "aviary stays"),
        ("sponsorships", mg_sponsor, "patronages"),
    ]:
        s, d = req("GET", f"/api/collections/{coll}/records/{rec_id}", T)
        check(f"the duplicate's {label} survive the merge, on the survivor",
              s == 200 and (d or {}).get("animal") == mg_keep, f"{s} {d}")

    mg_stays = listf(T, "aviary_stays", f'animal = "{mg_keep}"')
    mg_open = [x for x in mg_stays if x["ended_at"] == ""]
    check("the merged bird is resident in exactly ONE enclosure",
          len(mg_open) == 1 and mg_open[0]["aviary"] == mg_av_a, mg_stays)
    check("...with the duplicate's residency closed, not deleted",
          len(mg_stays) == 2
          and any(x["id"] == mg_stay and x["ended_at"] != "" for x in mg_stays),
          mg_stays)
    s, mg_survivor = req("GET", f"/api/collections/animals/records/{mg_keep}", T)
    check("the survivor keeps its own enclosure",
          (mg_survivor or {}).get("current_aviary") == mg_av_a, mg_survivor)
    # ...and reads `in_care` rather than `in_aviary`, because the duplicate's
    # OPEN case came across with everything else and is now the survivor's
    # latest event (federfall-8f1m). The enclosure not following is the whole
    # point: `current_aviary` is a custody pointer, and the merged bird is a
    # resident under treatment — the legitimate, reachable pair.
    check("...while the case it inherited says it is in care",
          (mg_survivor or {}).get("lifetime_status") == "in_care", mg_survivor)

    # A case-less residency (add_animal_sheet.dart adds a resident straight to
    # an enclosure, no case and therefore no disposition) lives ONLY on the
    # animal record — so the merge's disposition-driven re-derivation used to
    # reset it to "in care" and evict the bird.
    mg2_keep = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    mg2_gone = mk(T, "animals", {
        "species": "Stadttaube", "org": ORG,
        "current_aviary": mg_av_b, "lifetime_status": "in_aviary",
    })["id"]
    s, _ = req("POST", "/api/federfall/merge-animals", toks["sup"],
               {"survivor": mg2_keep, "duplicate": mg2_gone, "fields": {}})
    check("merging a case-less resident succeeds", s == 200, f"status {s}")
    s, mg2 = req("GET", f"/api/collections/animals/records/{mg2_keep}", T)
    check("a case-less residency survives the merge",
          (mg2 or {}).get("current_aviary") == mg_av_b
          and (mg2 or {}).get("lifetime_status") == "in_aviary", mg2)
    mg2_stays = listf(T, "aviary_stays", f'animal = "{mg2_keep}"')
    mg2_open = [x for x in mg2_stays if x["ended_at"] == ""]
    check("...as one open stay in that enclosure",
          len(mg2_open) == 1 and mg2_open[0]["aviary"] == mg_av_b, mg2_stays)

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

    # ── the give/pause cycle (federfall-wmbi) ───────────────────────────────
    # 5 days on / 2 days off from 2026-06-01 08:00, dosed every 12 h. Cycle days
    # run from the START INSTANT, not from a UTC midnight, so day k is
    # [start + k*24h, start + (k+1)*24h) and the whole thing is timezone-free.
    #
    # Three candidates decide the implementation:
    #   a) a dose inside a giving day     -> untouched, last + 12 h
    #   b) the dose that ends day 4       -> lands on day 5, the first pause day,
    #                                        and must jump to the next cycle
    #   c) a dose deep inside the pause   -> same jump, from a different phase
    cycstart = "2026-06-01 08:00:00.000Z"
    def cycle_med(last_dose):
        m = mk(T, "medications", {
            "case": mdcase, "drug": "Panacur", "frequency_kind": "scheduled",
            "interval_hours": 12, "cycle_on_days": 5, "cycle_off_days": 2,
            "started_at": cycstart, "dose_unit": "mg", "org": ORG,
        })["id"]
        mk(T, "medication_administrations", {
            "case": mdcase, "medication": m, "drug": "Panacur",
            "administered_at": last_dose, "org": ORG,
        })
        s, row = req("GET", f"/api/collections/medication_due/records/{m}",
                     toks["a"])
        return s, (row or {})

    # (a) last dose 2026-06-03 08:00 is day 2 -> +12 h is still day 2.
    s, row = cycle_med("2026-06-03 08:00:00.000Z")
    check("cycle: a dose inside a giving day is untouched", s == 200 and
          row.get("next_due", "").startswith("2026-06-03 20:00"),
          f"{s} {row.get('next_due')}")
    check("medication_due exposes cycle_on_days", row.get("cycle_on_days") == 5,
          f"{row.get('cycle_on_days')}")
    check("medication_due exposes cycle_off_days", row.get("cycle_off_days") == 2,
          f"{row.get('cycle_off_days')}")

    # (b) last dose 2026-06-05 20:00 ends day 4; +12 h = 06-06 08:00 = day 5,
    # the first pause day. Next cycle starts at day 7 = 2026-06-08 08:00.
    s, row = cycle_med("2026-06-05 20:00:00.000Z")
    check("cycle: a dose falling on the first pause day jumps the pause",
          s == 200 and row.get("next_due", "").startswith("2026-06-08 08:00"),
          f"{s} {row.get('next_due')}")

    # (c) same jump reached from the far side of the pause: 06-07 12:00 is day 6,
    # +12 h = 06-08 00:00, still day 6 -> next cycle, 2026-06-08 08:00.
    s, row = cycle_med("2026-06-07 12:00:00.000Z")
    check("cycle: a dose late in the pause lands on the next cycle's first day",
          s == 200 and row.get("next_due", "").startswith("2026-06-08 08:00"),
          f"{s} {row.get('next_due')}")

    # A cycle is a qualifier on an interval, and half a pair is not a cycle:
    # both must be present or the plan is the plain "every 12 h" it was before.
    halfmed = mk(T, "medications", {
        "case": mdcase, "drug": "Panacur", "frequency_kind": "scheduled",
        "interval_hours": 12, "cycle_on_days": 5, "started_at": cycstart,
        "dose_unit": "mg", "org": ORG,
    })["id"]
    mk(T, "medication_administrations", {
        "case": mdcase, "medication": halfmed, "drug": "Panacur",
        "administered_at": "2026-06-07 12:00:00.000Z", "org": ORG,
    })
    s, row = req("GET", f"/api/collections/medication_due/records/{halfmed}",
                 toks["a"])
    check("half a cycle is ignored, not half-applied",
          s == 200 and (row or {}).get("next_due", "").startswith("2026-06-08 00:00"),
          f"{s} {(row or {}).get('next_due')}")

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

    # ── federfall-s0wk: the carer-load view ─────────────────────────────────
    # The workload card's figures as counts rather than as a full collection on
    # the device. The rule does the scoping, so nothing re-implements
    # who-may-see-what in JS.
    #
    # 1700000070 added a second view here, `case_viewer_counts`. It is gone
    # (1700000071, federfall-45o4): the dashboard's status figures count on
    # `cases` instead, because the list rule scopes a count exactly as it
    # scopes the list each tile taps through to — which a viewer-scoped view
    # cannot do for a coordinator reading org-wide.
    print("\n[dashboard count view]")

    s0_animal = mk(T, "animals", {"species": "s0wk Taube", "org": ORG})["id"]
    # One case A is the active carer of, one also shared with B (whose own
    # caseload is otherwise empty), so "may see" and "is carer of" cannot be
    # confused.
    mk(T, "cases", {"animal": s0_animal, "active_carer": A, "org": ORG})
    s0_shared = mk(T, "cases", {"animal": s0_animal, "active_carer": A,
                                "org": ORG})["id"]
    mk(T, "case_shares", {"case": s0_shared, "shared_with": B,
                          "access": "read", "org": ORG})

    # The workload view is org-wide by construction, so it is gated like every
    # other org-wide figure — the card that shows it is canViewReports-only.
    check("a carer CANNOT read the org-wide carer load",
          len(listf(toks["a"], "case_carer_load", "id != ''")) == 0,
          "non-empty")
    load = {r.get("carer"): r.get("open_cases")
            for r in listf(toks["sup"], "case_carer_load", "id != ''")}

    def cases_of(uid, extra=""):
        """`totalItems` for this member's cases in THIS org, optionally
        narrowed further. The org clause is load-bearing: the view groups by
        (org, carer), so a member who also carries a case elsewhere has a row
        per org and an org-blind count would exceed any single one."""
        flt = f'active_carer = "{uid}" && org = "{ORG}"' + extra
        st, d = req("GET", "/api/collections/cases/records?perPage=1&filter="
                    + urllib.parse.quote(flt), T)
        return d.get("totalItems") if st == 200 else -1

    def open_of(uid):
        """Open cases by SUBTRACTION rather than with `status != "disposed"`.

        Once a workaround for a filter I suspected of over-matching; a live
        probe cleared it, and the 25 that started the doubt turned out to be an
        org-blind count of a carer holding a case in a second org — the very
        thing `cases_of`'s org clause above exists to exclude (federfall-jt5u).
        Kept as subtraction anyway: it pins the SQL view against arithmetic
        rather than against a second spelling of the view's own predicate."""
        return cases_of(uid) - cases_of(uid, ' && status = "disposed"')

    check("the carer load is exactly that member's open caseload",
          load.get(A, 0) == open_of(A),
          f'view {load.get(A)} vs cases {open_of(A)}')
    # B has a case SHARED with them above; a share must not show up as load.
    check("...and a share does not add to the recipient's load",
          load.get(B, 0) == open_of(B),
          f'view {load.get(B)} vs cases {open_of(B)}')

    s, _ = req("POST", "/api/collections/case_carer_load/records", toks["sup"],
               {"org": ORG})
    check("case_carer_load is read-only even for a supervisor", s != 200,
          f"status {s}")

    # And the view that used to sit beside it is really gone, not merely
    # unread — an unused collection keeps answering, so this pins the drop.
    s, _ = req("GET", "/api/collections/case_viewer_counts/records",
               toks["sup"])
    check("case_viewer_counts is gone (federfall-45o4)", s == 404,
          f"status {s}")

    # ── federfall-trep: the case browser's filters, run on the server ───────
    # The browser stopped pulling `cases` + `animals` to the device to filter
    # them there. Every facet is now a PocketBase filter, and three of them
    # reach outside the case row — a forward relation and two back-relations.
    # Those forms are new to this client, so they are checked against a real
    # PocketBase rather than only against the expression the repository builds.
    print("\n[case browser filters]")

    trep_animal = mk(T, "animals", {"species": "trep Hohltaube",
                                    "name": "trep Pip", "org": ORG})["id"]
    trep_other = mk(T, "animals", {"species": "trep Ringeltaube",
                                   "org": ORG})["id"]
    trep_mtype = listf(T, "marking_types", "id != ''")[0]["id"]
    mk(T, "markings", {"animal": trep_animal, "type": trep_mtype,
                       "code": "TREP-4711", "is_active": True, "org": ORG})
    trep_case = mk(T, "cases", {"animal": trep_animal, "active_carer": A,
                                "case_number": "TREP-001", "org": ORG})["id"]
    trep_plain = mk(T, "cases", {"animal": trep_other, "active_carer": A,
                                 "case_number": "TREP-002", "org": ORG})["id"]
    # One code-list diagnosis and one typed as free text — the filter matches
    # by LABEL precisely so both are reachable.
    trep_cond = mk(T, "conditions", {"label": "trep Fraktur", "active": True,
                                     "org": ORG})["id"]
    mk(T, "case_conditions", {"case": trep_case, "condition": trep_cond,
                              "org": ORG})
    mk(T, "case_conditions", {"case": trep_case, "free_text": "trep Katzenbiss",
                              "org": ORG})
    # Re-dispositioned, so "carries a disposition of this type" and "its
    # TERMINAL one is of this type" genuinely differ on this row.
    mk(T, "dispositions", {"case": trep_case, "type": "placed_in_aviary",
                           "disposed_at": "2026-03-01 10:00:00.000Z",
                           "org": ORG})
    mk(T, "dispositions", {"case": trep_case, "type": "released",
                           "disposed_at": "2026-05-01 10:00:00.000Z",
                           "org": ORG})

    def browse(tok, flt):
        return {c["id"] for c in listf(tok, "cases", flt)}

    CO = toks["coord"]
    check("species filters through the animal relation",
          browse(CO, 'animal.species = "trep Hohltaube"') == {trep_case},
          "forward traversal")
    check("text search matches the animal's name",
          trep_case in browse(CO, 'animal.name ~ "trep Pip"'), "no match")
    check("text search matches a marking code on the animal",
          browse(CO, 'animal.markings_via_animal.code ~ "TREP-4711"')
          == {trep_case}, "back-relation traversal")
    check("diagnosis matches a code-list label",
          browse(CO, 'case_conditions_via_case.condition.label ?= '
                     '"trep Fraktur"') == {trep_case},
          "nested back-relation")
    check("diagnosis matches free text of the same shape",
          browse(CO, 'case_conditions_via_case.free_text ?= '
                     '"trep Katzenbiss"') == {trep_case}, "free text missed")

    # The outcome facet: the filter is a SUPERSET of what the browser means,
    # which is why the app narrows the page it gets back to the terminal
    # disposition. Both halves are asserted so a PocketBase that one day CAN
    # express "the latest one" is a visible change, not a silent one.
    check("outcome matches the terminal disposition",
          trep_case in browse(CO, 'dispositions_via_case.type ?= "released"'),
          "terminal outcome missed")
    check("...and over-matches a superseded one, hence the client's last pass",
          trep_case in browse(CO,
                              'dispositions_via_case.type ?= '
                              '"placed_in_aviary"'),
          "no longer a superset — the app's refinement can be dropped")

    # The one that matters: with no carer clause at all, the browser's "all"
    # scope is whatever the list rule allows. It must still be nothing of
    # another carer's, however the facets are combined.
    check("a carer's widened scope still excludes another carer's case",
          browse(toks["b"], 'animal.species = "trep Hohltaube"') == set(),
          "leaked across carers")
    check("...and the case is there to be missed",
          browse(toks["a"], 'animal.species = "trep Hohltaube"')
          == {trep_case}, "fixture did not land")

    # An explicit status set rather than `status != "disposed"` — a preference
    # in the repository, not a precaution (federfall-jt5u).
    open_set = browse(CO, f'(status = "in_care" || status = '
                          f'"ready_for_release" || status = "") && '
                          f'animal.species ~ "trep "')
    check("the active split is expressible as a status set",
          trep_plain in open_set, "open case missing from the explicit set")

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
    check("guest sees no case_carer_load",
          len(listf(gtok, "case_carer_load", "id != ''")) == 0, "non-empty")
    check("supervisor sees case_report_rows (wall check is non-vacuous)",
          len(listf(toks["sup"], "case_report_rows", "id != ''")) > 0, "empty")
    check("guest sees no case_report_rows",
          len(listf(gtok, "case_report_rows", "id != ''")) == 0, "non-empty")
    # federfall-75sy: the same wall, on the ROUTES. Every hook route bypasses
    # the collection rules it writes through and therefore re-states the
    # boundary itself (lib_auth.js). The sweep above walks collections, so a
    # route that forgot the guest clause would sail through it — this reads the
    # route table out of pb_hooks/ so a route added later is swept whether or
    # not anyone remembers to add it here.
    hooks_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "..", "pb_hooks")
    declared = set()
    for name in sorted(os.listdir(hooks_dir)):
        if not name.endswith(".pb.js"):
            continue
        src = open(os.path.join(hooks_dir, name), encoding="utf-8").read()
        for m in re.finditer(
                r'routerAdd\(\s*"(GET|POST|PUT|PATCH|DELETE)"\s*,\s*"([^"]+)"',
                src):
            declared.add((m.group(1), m.group(2)))
    # `/api/federfall/info` is deliberately public — it is what an unconfigured
    # client probes BEFORE it can have a token (federfall-7nf.1). It is the one
    # exemption, and naming it here is what makes it a decision rather than an
    # omission.
    PUBLIC = {("GET", "/api/federfall/info")}
    check("the route sweep found the hook routes to walk",
          len(declared - PUBLIC) >= 6, sorted(declared))
    for method, path in sorted(declared - PUBLIC):
        # A placeholder is filled with a real id where one is to hand: the gate
        # must come before the lookup, so a guest is refused either way — but a
        # real id makes a 404-before-403 mistake visible instead of plausible.
        concrete = path.replace("{id}", tc_case)
        s_guest, _ = req(method, concrete, gtok, {} if method != "GET" else None)
        check(f"guest is refused {method} {path}", s_guest == 403,
              f"status {s_guest}")
        s_anon, _ = req(method, concrete, None, {} if method != "GET" else None)
        check(f"...and so is an anonymous caller ({method} {path})",
              s_anon == 401, f"status {s_anon}")

    # The OAuth2 createRule (@request.context = "oauth2") must NOT let an
    # anonymous API client create users directly (that path is context default).
    s, _ = req("POST", "/api/collections/users/records", None, {
        "email": "intruder@f.local", "password": "Pass12345!",
        "passwordConfirm": "Pass12345!", "role": "supervisor", "org": ORG,
    })
    check("anonymous direct user creation is denied", s != 200, f"status {s}")

    # ── federfall-nmwi: statistics route + the report it must agree with ────
    # GET /api/federfall/stats is the app's statistics screen, computed over
    # the same `case_report_rows` view the annual report prints — one module
    # (pb_hooks/lib_stats.js) serves both, so what is asserted here is that
    # the two really do resolve a period the same way.
    #
    # A cohort of its own (2015/2016) so the figures cannot be perturbed by
    # the fixtures around it: every assertion below is scoped by ?year=.
    print("\n[statistics route]")

    st_animal = mk(T, "animals", {
        "species": "nmwi Ringeltaube", "name": "nmwi Flo", "org": ORG,
    })["id"]

    def st_case(admitted, animal_id=None):
        return mk(T, "cases", {
            "animal": animal_id or st_animal, "active_carer": A, "org": ORG,
            "admitted_at": admitted,
        })["id"]

    st_released = st_case("2016-03-05 09:00:00.000Z")
    st_dead = st_case("2016-03-20 09:00:00.000Z")
    mk(T, "dispositions", {"case": st_released, "type": "released",
                           "disposed_at": "2016-03-15 09:00:00.000Z",
                           "org": ORG})
    mk(T, "dispositions", {"case": st_dead, "type": "euthanized",
                           "disposed_at": "2016-03-30 09:00:00.000Z",
                           "org": ORG})
    mk(T, "case_conditions", {"case": st_released, "free_text": "nmwi Fraktur",
                              "org": ORG})
    # The comparison year, in a different month so the alignment is visible.
    st_case("2015-07-04 09:00:00.000Z")
    # 00:30 UTC on New Year's Day: whose year this is depends entirely on the
    # caller's offset, which is the point of ?tzOffsetMinutes=.
    st_case("2017-01-01 00:30:00.000Z")

    def stats(tok, query=""):
        s, d = req("GET", "/api/federfall/stats" + query, tok)
        return s, (d if isinstance(d, dict) else {})

    s, _ = stats(None)
    check("stats route requires auth", s == 401, f"status {s}")
    s, _ = stats(gtok)
    check("guest CANNOT read the statistics", s == 403, f"status {s}")
    s, _ = stats(toks["a"])
    check("a carer CANNOT read the org-wide statistics", s == 403,
          f"status {s}")
    s, _ = stats(toks["sup"], "?year=not-a-year")
    check("a garbled ?year= is rejected, not silently reported on",
          s == 400, f"status {s}")

    s, st = stats(toks["coord"], "?year=2016&tzOffsetMinutes=0")
    totals = st.get("totals", {})
    check("coordinator reads the statistics", s == 200, f"status {s}")
    check("intakes count the cohort ADMITTED in the period",
          totals.get("intakes") == 2, totals)
    check("closed/inCare split the cohort by whether it ended",
          totals.get("closed") == 2 and totals.get("inCare") == 0, totals)
    # Both rates are over the cases that ENDED, never over intakes.
    check("release rate is the share of ended cases released",
          totals.get("releaseRate") == 0.5, totals)
    check("mortality counts died AND euthanized",
          totals.get("mortalityRate") == 0.5, totals)
    check("mean stay is fractional days, not whole ones",
          abs((totals.get("avgDaysInCare") or 0) - 10.0) < 0.001, totals)

    series = st.get("series", {})
    points = {p["key"]: p["count"] for p in series.get("points", [])}
    check("a year's series is twelve months, zeros included",
          series.get("kind") == "month" and len(series.get("points", [])) == 12,
          series)
    check("the month with the intakes carries them", points.get(3) == 2, points)
    prev = series.get("previous") or {}
    prev_points = {p["key"]: p["count"] for p in prev.get("points", [])}
    check("the previous year comes back for comparison",
          prev.get("year") == 2015 and prev_points.get(7) == 1, prev)

    outcomes = {o["type"]: o["count"] for o in st.get("outcomes", [])}
    check("outcomes break the ended cases down by type",
          outcomes.get("released") == 1 and outcomes.get("euthanized") == 1,
          outcomes)
    species = {sp["label"]: sp["count"] for sp in st.get("species", [])}
    check("species counts the period's intakes",
          species.get("nmwi Ringeltaube") == 2, species)
    conditions = {c["label"]: c["count"] for c in st.get("conditions", [])}
    check("diagnoses are narrowed to the period's cases",
          conditions.get("nmwi Fraktur") == 1, conditions)
    check("intakeYears lists the years with intakes, newest first",
          st.get("intakeYears") == sorted(st.get("intakeYears", []),
                                          reverse=True)
          and 2016 in st.get("intakeYears", [])
          and 2015 in st.get("intakeYears", []),
          st.get("intakeYears"))

    s, st_all = stats(toks["sup"], "?tzOffsetMinutes=0")
    check("no ?year= reports every case, bucketed by calendar year",
          s == 200 and st_all.get("series", {}).get("kind") == "year"
          and (st_all.get("series", {}).get("previous") is None),
          st_all.get("series"))

    # ── The boundary, and the agreement with the annual report ─────────────
    # 2017-01-01 00:30 UTC is 2016-12-31 22:30 for a caller at UTC-2, so it
    # belongs to that caller's 2016. The report route must place it in exactly
    # the same year — that is the whole reason both read lib_stats.js.
    _, st_utc = stats(toks["sup"], "?year=2016&tzOffsetMinutes=0")
    _, st_west = stats(toks["sup"], "?year=2016&tzOffsetMinutes=-120")
    check("a New Year's Eve admission follows the CALLER's midnight",
          st_utc.get("totals", {}).get("intakes") == 2
          and st_west.get("totals", {}).get("intakes") == 3,
          f'{st_utc.get("totals")} vs {st_west.get("totals")}')

    def annual_rows(query):
        s, body, _ = req_bytes(
            "GET", "/api/federfall/reports/annual" + query, toks["sup"])
        if s != 200 or not body:
            return None
        text = body.decode("utf-8-sig").strip()
        return len(text.split("\r\n")) - 1  # minus the header row

    check("the annual report puts it in the same year the screen does",
          annual_rows("?year=2016&format=csv&tzOffsetMinutes=0") == 2
          and annual_rows("?year=2016&format=csv&tzOffsetMinutes=-120") == 3,
          "report and stats disagree about the period")

    # ── A month is a period too (federfall-nmwi follow-up) ─────────────────
    # Same machinery, one rung finer: ?month= narrows to a calendar month,
    # buckets become DAYS, and the comparison is the same month a year earlier
    # rather than the month before — seasonality is the question being asked.
    s, st_mar = stats(toks["sup"], "?year=2016&month=3&tzOffsetMinutes=0")
    check("a month is a valid period", s == 200, f"status {s}")
    check("the month's cohort is only its own intakes",
          st_mar.get("totals", {}).get("intakes") == 2,
          st_mar.get("totals"))
    mar_series = st_mar.get("series", {})
    check("a month's series is one bucket per DAY, all 31 of them",
          mar_series.get("kind") == "day"
          and len(mar_series.get("points", [])) == 31, mar_series.get("kind"))
    mar_points = {p["key"]: p["count"] for p in mar_series.get("points", [])}
    check("the days with intakes carry them, the rest are zeros",
          mar_points.get(5) == 1 and mar_points.get(20) == 1
          and sum(mar_points.values()) == 2, mar_points)
    check("February 2016 is a different period",
          stats(toks["sup"], "?year=2016&month=2&tzOffsetMinutes=0")[1]
          .get("totals", {}).get("intakes") == 0)
    # 2015 has its one intake in JULY, so March 2016 has no March 2015 to
    # compare against — an all-zero comparison is omitted rather than drawn.
    check("a comparison month with no intakes is omitted",
          mar_series.get("previous") is None, mar_series.get("previous"))
    _, st_jul = stats(toks["sup"], "?year=2016&month=7&tzOffsetMinutes=0")
    prev_jul = st_jul.get("series", {}).get("previous") or {}
    prev_jul_points = {p["key"]: p["count"] for p in prev_jul.get("points", [])}
    check("the comparison is the SAME month a year earlier",
          prev_jul.get("year") == 2015 and prev_jul.get("month") == 7
          and prev_jul_points.get(4) == 1, prev_jul)
    # A day-level period still has to agree with the report route.
    check("the annual report accepts the same month",
          annual_rows("?year=2016&month=3&format=csv&tzOffsetMinutes=0") == 2,
          "report and stats disagree about the month")
    # A month report is not a Jahresbericht, on the page or in the filename.
    s, body, hdrs = req_bytes(
        "GET",
        "/api/federfall/reports/annual?year=2016&month=3&tzOffsetMinutes=0",
        toks["sup"])
    check("a month renders its own PDF, named for the month",
          s == 200 and bool(body) and body[:5] == b"%PDF-"
          and 'filename="federfall-monatsbericht-2016-03.pdf"'
          in hdrs.get("Content-Disposition", ""),
          f'status {s} {hdrs.get("Content-Disposition")}')
    for bad in ["?month=3", "?year=2016&month=0", "?year=2016&month=13",
                "?year=2016&month=abc"]:
        s, _ = stats(toks["sup"], bad)
        check(f"stats rejects {bad}", s == 400, f"status {s}")
        s, _, _ = req_bytes(
            "GET", "/api/federfall/reports/annual" + bad, toks["sup"])
        check(f"the annual report rejects {bad} too", s == 400, f"status {s}")

    # ── federfall-s63u: batch vaccination ───────────────────────────────────
    # Vaccinating an enclosure is ONE act, so it is one transaction: all rows or
    # none. The failure this guards against is not a rejected write but a
    # HALF-written flock, where the missing rows are indistinguishable from the
    # birds somebody meant to skip.
    print("\n[batch vaccination]")
    # An enclosure kept by a plain CARER, so the keeper branch is exercised
    # rather than a coordinator's override.
    bv_av = mk(T, "aviaries", {"name": "Voliere Impfung", "keeper": B,
                               "org": ORG})["id"]
    bv_birds = [
        mk(T, "animals", {
            "species": "Stadttaube", "name": f"Impfling {i}", "org": ORG,
            "current_aviary": bv_av, "lifetime_status": "in_aviary",
        })["id"]
        for i in range(3)
    ]
    # A bird in the same org that B does NOT hold — A's open case. A real
    # roster can contain one, which is the whole reason for the per-animal
    # check.
    bv_foreign = mk(T, "animals", {"species": "Stadttaube", "name": "Fremd",
                                   "org": ORG})["id"]
    mk(T, "cases", {"animal": bv_foreign, "active_carer": A, "org": ORG})
    BV_SHOT = {
        "vaccine": "Colombovac PMV", "target": "Paramyxovirose",
        "administered_at": "2026-08-11 09:00:00.000Z", "batch": "C-4711",
        "dose": 0.2, "dose_unit": "ml", "series": "primary",
        "next_due_at": "2027-08-11 09:00:00.000Z", "vet": "TA Praxis Müller",
    }
    bv_url = "/api/federfall/vaccinate-batch"
    # The per-row event count BEFORE any batch runs: the [vaccinations] block
    # above wrote rows through the collection API and those DID emit
    # vaccination.created, so "the batch emits none" can only be asserted as a
    # difference, never as an absence.
    bv_created_before = len(
        listf(T, "audit_events", 'action = "vaccination.created"'))

    s, _ = req("POST", bv_url, None, {"animals": bv_birds,
                                      "vaccination": BV_SHOT})
    check("batch vaccination requires auth", s == 401, f"status {s}")
    s, _ = req("POST", bv_url, gtok, {"animals": bv_birds,
                                      "vaccination": BV_SHOT})
    check("guest CANNOT vaccinate a batch", s == 403, f"status {s}")
    s, _ = req("POST", bv_url, toks["b"], {"animals": [],
                                           "vaccination": BV_SHOT})
    check("an empty batch is rejected", s == 400, f"status {s}")
    s, _ = req("POST", bv_url, toks["b"], {"animals": bv_birds,
                                           "vaccination": {"target": "x"}})
    check("a batch without a product is rejected", s == 400, f"status {s}")
    s, _ = req("POST", bv_url, toks["b"], {
        "animals": bv_birds,
        "vaccination": dict(BV_SHOT, series="quarterly"),
    })
    check("an unknown series is rejected", s == 400, f"status {s}")

    s, bv = req("POST", bv_url, toks["b"], {
        "animals": bv_birds, "vaccination": BV_SHOT,
        "idempotency_key": "bv-key-1",
    })
    check("the keeper vaccinates the whole enclosure in one call",
          s == 200 and bv.get("created") == 3, f"{s} {bv}")
    bv_rows = listf(T, "vaccinations", f'animal = "{bv_birds[0]}"')
    check("every bird got the shared row, with the batch number",
          len(bv_rows) == 1 and bv_rows[0]["batch"] == "C-4711"
          and bv_rows[0]["vaccine"] == "Colombovac PMV"
          and bv_rows[0]["series"] == "primary",
          bv_rows)
    check("...authored by the caller, never by the body",
          bv_rows and bv_rows[0]["author"] == B, bv_rows)

    # Idempotency (federfall-3ty3's shape): a retried batch replays, it does not
    # vaccinate the flock a second time.
    s, bv2 = req("POST", bv_url, toks["b"], {
        "animals": bv_birds, "vaccination": BV_SHOT,
        "idempotency_key": "bv-key-1",
    })
    check("a replayed batch returns the SAME rows", s == 200 and bv2 == bv,
          f"{s} {bv2}")
    check("...and writes no second row",
          len(listf(T, "vaccinations", f'animal = "{bv_birds[0]}"')) == 1)

    # The point of the whole route: a refusal leaves NOTHING behind.
    s, d = req("POST", bv_url, toks["b"], {
        "animals": bv_birds + [bv_foreign],
        "vaccination": dict(BV_SHOT, batch="C-9999"),
    })
    check("a batch naming a bird the caller does not hold is refused",
          s == 403, f"{s} {d}")
    check("...and the birds it COULD have written stay untouched",
          not listf(T, "vaccinations", 'batch = "C-9999"'))
    s, d = req("POST", bv_url, toks["b"], {
        "animals": [bv_birds[0], "doesnotexist000"],
        "vaccination": dict(BV_SHOT, batch="C-8888"),
    })
    check("an unknown animal refuses the batch whole", s == 400, f"{s} {d}")
    check("...leaving nothing behind either",
          not listf(T, "vaccinations", 'batch = "C-8888"'))
    # Cross-org is "unknown", not "forbidden": naming another org's row must not
    # confirm that it exists.
    s, _ = req("POST", bv_url, toks["b"], {
        "animals": [animal_org2], "vaccination": BV_SHOT,
    })
    check("another org's animal cannot be vaccinated", s >= 400, f"status {s}")

    # A member who holds none of them gets nowhere.
    s, _ = req("POST", bv_url, toks["d"], {"animals": bv_birds,
                                           "vaccination": BV_SHOT})
    check("a member who keeps no enclosure CANNOT vaccinate its residents",
          s == 403, f"status {s}")
    # ...but a coordinator overrides, as everywhere else in the custody model.
    s, bvc = req("POST", bv_url, toks["coord"], {
        "animals": bv_birds, "vaccination": dict(BV_SHOT, batch="C-COORD"),
    })
    check("a coordinator can", s == 200 and bvc.get("created") == 3,
          f"{s} {bvc}")

    # Duplicates in the list mean the bird once — two identical rows on one
    # animal is not a record anybody can read.
    s, bvd = req("POST", bv_url, toks["b"], {
        "animals": [bv_birds[0], bv_birds[0]],
        "vaccination": dict(BV_SHOT, batch="C-DUP"),
    })
    check("a bird named twice is vaccinated once",
          s == 200 and bvd.get("created") == 1, f"{s} {bvd}")

    # ONE audit event for the act, with the animals NAMED — an id in an audit
    # row is a bug unless a label sits beside it (federfall-qt96).
    bv_events = listf(T, "audit_events",
                      'action = "vaccination.batch_recorded"')
    bv_created_after = len(
        listf(T, "audit_events", 'action = "vaccination.created"'))
    check("the batch is audited as one event per call, not as N creates",
          len(bv_events) == 3 and bv_created_after == bv_created_before,
          f"{len(bv_events)} batch events, "
          f"{bv_created_after - bv_created_before} row events")
    bv_detail = (bv_events[0] or {}).get("detail") or {} if bv_events else {}
    check("...naming every bird it vaccinated",
          bv_detail.get("animals") == 3
          and len(bv_detail.get("animal_labels") or []) == 3
          and "Impfling 0" in (bv_detail.get("animal_labels") or []),
          bv_detail)

    # ── federfall-hqhg: batch prescription ──────────────────────────────────
    # Nine birds on the same course is ONE decision, so it is one transaction.
    # Sharper than the flock above: a prescription says what happens NEXT, so a
    # case whose row went missing is never offered as due and the bird is simply
    # never treated.
    print("\n[batch prescription]")
    bp_cases = [
        mk(T, "cases", {
            "animal": mk(T, "animals", {"species": "Stadttaube",
                                        "name": f"Kur {i}", "org": ORG})["id"],
            "active_carer": A, "org": ORG,
        })["id"]
        for i in range(3)
    ]
    # A case in the same org that A does not carry — the reason for the
    # per-case check.
    bp_foreign = mk(T, "cases", {
        "animal": mk(T, "animals", {"species": "Stadttaube", "name": "Fremdkur",
                                    "org": ORG})["id"],
        "active_carer": B, "org": ORG,
    })["id"]
    bp_org2_case = mk(T, "cases", {"animal": animal_org2, "org": org2})["id"]
    # Created rather than looked up: the seeded code list belongs to whichever
    # orgs existed when 1700000041 ran, and org2 is made by this suite.
    route_oral = mk(T, "medication_routes", {"label": "Oral (Kur)",
                                             "org": ORG})["id"]
    route_org2 = mk(T, "medication_routes", {"label": "Oral (fremd)",
                                             "org": org2})["id"]
    BP_PLAN = {
        "drug": "Baycox", "dose_rate": 7, "dose_unit": "mg",
        "concentration_per_ml": 25, "frequency_kind": "scheduled",
        "interval_hours": 24, "cycle_on_days": 2, "cycle_off_days": 5,
        "started_at": "2026-08-11 08:00:00.000Z",
        # Far future on purpose: `medication_due` drops a plan whose end has
        # passed, so a date near this suite's writing would make the due check
        # below start failing on its own one day.
        "ended_at": "2099-12-31 08:00:00.000Z",
        "route": route_oral, "is_controlled": True,
        "instructions": "in den Schnabel", "prescribed_by": "TA Müller",
    }
    bp_url = "/api/federfall/prescribe-batch"
    # The per-row count BEFORE any batch: rows written through the collection
    # API elsewhere in this suite DID emit medication.prescribed, so "the batch
    # emits none" is only assertable as a difference.
    bp_rows_before = len(
        listf(T, "audit_events", 'action = "medication.prescribed"'))

    s, _ = req("POST", bp_url, None, {"cases": bp_cases, "medication": BP_PLAN})
    check("batch prescribing requires auth", s == 401, f"status {s}")
    s, _ = req("POST", bp_url, gtok, {"cases": bp_cases, "medication": BP_PLAN})
    check("guest CANNOT prescribe a batch", s == 403, f"status {s}")
    s, _ = req("POST", bp_url, toks["a"], {"cases": [], "medication": BP_PLAN})
    check("an empty batch is rejected", s == 400, f"status {s}")
    s, _ = req("POST", bp_url, toks["a"], {"cases": bp_cases,
                                           "medication": {"dose": 1}})
    check("a batch without a drug is rejected", s == 400, f"status {s}")
    s, _ = req("POST", bp_url, toks["a"], {
        "cases": bp_cases,
        "medication": dict(BP_PLAN, frequency_kind="hourly"),
    })
    check("an unknown frequency kind is rejected", s == 400, f"status {s}")
    s, _ = req("POST", bp_url, toks["a"], {
        "cases": bp_cases, "medication": dict(BP_PLAN, dose_rate=-1),
    })
    check("a negative rate is rejected", s == 400, f"status {s}")

    s, bp = req("POST", bp_url, toks["a"], {
        "cases": bp_cases, "medication": BP_PLAN,
        "idempotency_key": "bp-key-1",
    })
    check("the carer prescribes one course to the whole group in one call",
          s == 200 and bp.get("created") == 3, f"{s} {bp}")
    bp_written = listf(T, "medications", f'case = "{bp_cases[0]}"')
    check("every case got the shared plan, rhythm and all",
          len(bp_written) == 1 and bp_written[0]["drug"] == "Baycox"
          and bp_written[0]["dose_rate"] == 7
          and bp_written[0]["cycle_on_days"] == 2
          and bp_written[0]["cycle_off_days"] == 5
          and bp_written[0]["is_controlled"] is True
          and bp_written[0]["route"] == route_oral,
          bp_written)
    check("...org comes from the session, never from the body",
          bp_written and bp_written[0]["org"] == ORG, bp_written)
    # The point of the whole route for the worklist: each row is its own plan,
    # so `medication_due` can answer per case.
    _, bp_due = req("GET", "/api/collections/medication_due/records"
                    "?perPage=200", toks["a"])
    bp_due_ids = {r["case_id"] for r in (bp_due.get("items") or [])}
    check("all three come up as due in their own right",
          set(bp_cases) <= bp_due_ids, bp_due_ids)

    # Idempotency (federfall-3ty3's shape): a doubled plan means every dose
    # falls due twice, so a retry must replay rather than write again.
    s, bp2 = req("POST", bp_url, toks["a"], {
        "cases": bp_cases, "medication": BP_PLAN,
        "idempotency_key": "bp-key-1",
    })
    check("a replayed batch returns the SAME rows", s == 200 and bp2 == bp,
          f"{s} {bp2}")
    check("...and writes no second plan",
          len(listf(T, "medications", f'case = "{bp_cases[0]}"')) == 1)

    # A refusal leaves NOTHING behind — the reason the route exists.
    s, d = req("POST", bp_url, toks["a"], {
        "cases": bp_cases + [bp_foreign],
        "medication": dict(BP_PLAN, drug="Refused-A"),
    })
    check("a batch naming a case the caller cannot write is refused",
          s == 403, f"{s} {d}")
    check("...and the cases it COULD have written stay untouched",
          not listf(T, "medications", 'drug = "Refused-A"'))
    s, d = req("POST", bp_url, toks["a"], {
        "cases": [bp_cases[0], "doesnotexist000"],
        "medication": dict(BP_PLAN, drug="Refused-B"),
    })
    check("an unknown case refuses the batch whole", s == 400, f"{s} {d}")
    check("...leaving nothing behind either",
          not listf(T, "medications", 'drug = "Refused-B"'))
    # Cross-org is "unknown", not "forbidden": naming another org's row must not
    # confirm that it exists.
    s, _ = req("POST", bp_url, toks["a"], {"cases": [bp_org2_case],
                                           "medication": BP_PLAN})
    check("another org's case cannot be prescribed for", s >= 400,
          f"status {s}")
    # A route from another org is equally unknown — org_scope.pb.js's check,
    # restated because a route bypasses the rules that would make it.
    s, _ = req("POST", bp_url, toks["a"], {
        "cases": bp_cases, "medication": dict(BP_PLAN, route=route_org2),
    })
    check("a route from another org is refused", s == 400, f"status {s}")

    # An outsider gets nowhere; a supervisor overrides, and so does an
    # edit-share — the three branches of the `medications` create rule.
    s, _ = req("POST", bp_url, toks["d"], {"cases": bp_cases,
                                           "medication": BP_PLAN})
    check("a member carrying none of the cases CANNOT prescribe for them",
          s == 403, f"status {s}")
    s, bps = req("POST", bp_url, toks["sup"], {
        "cases": [bp_foreign], "medication": dict(BP_PLAN, drug="Sup-Kur"),
    })
    check("a supervisor can prescribe on another carer's case",
          s == 200 and bps.get("created") == 1, f"{s} {bps}")
    mk(T, "case_shares", {"case": bp_foreign, "shared_with": A,
                          "shared_by": B, "access": "edit", "org": ORG})
    s, bpe = req("POST", bp_url, toks["a"], {
        "cases": [bp_foreign], "medication": dict(BP_PLAN, drug="Share-Kur"),
    })
    check("an edit-share is enough to prescribe",
          s == 200 and bpe.get("created") == 1, f"{s} {bpe}")

    # Duplicates mean the case once: two identical plans on one case would show
    # the same dose due twice.
    s, bpd = req("POST", bp_url, toks["a"], {
        "cases": [bp_cases[0], bp_cases[0]],
        "medication": dict(BP_PLAN, drug="Doppel"),
    })
    check("a case named twice is prescribed for once",
          s == 200 and bpd.get("created") == 1, f"{s} {bpd}")

    # Half a rhythm is no rhythm — the reading medication_due takes of the
    # stored pair (1700000090), restated so the two cannot disagree.
    s, _ = req("POST", bp_url, toks["a"], {
        "cases": [bp_cases[1]],
        "medication": dict(BP_PLAN, drug="Halb", cycle_off_days=""),
    })
    bp_half = listf(T, "medications", 'drug = "Halb"')
    check("half a cycle is stored as no cycle at all",
          s == 200 and len(bp_half) == 1
          and not bp_half[0]["cycle_on_days"]
          and not bp_half[0]["cycle_off_days"], bp_half)

    # ONE audit event for the act, with the cases NAMED — an id in an audit row
    # is a bug unless a label sits beside it (federfall-qt96).
    bp_events = listf(T, "audit_events",
                      'action = "medication.batch_prescribed"')
    bp_rows_after = len(
        listf(T, "audit_events", 'action = "medication.prescribed"'))
    # Five committed calls: the group of three, the supervisor's, the
    # edit-share's, the duplicate, the half-cycle. The replay committed nothing.
    check("the batch is audited as one event per call, not as N creates",
          len(bp_events) == 5 and bp_rows_after == bp_rows_before,
          f"{len(bp_events)} batch events, "
          f"{bp_rows_after - bp_rows_before} row events")
    bp_detail = (bp_events[0] or {}).get("detail") or {} if bp_events else {}
    check("...naming every case it prescribed for",
          bp_detail.get("cases") == len(bp_detail.get("case_labels") or [])
          and bool(bp_detail.get("case_labels")), bp_detail)

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
        "weight_g": 250.5, "quarantine_days": 10,
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
    # A gram scale reads fractions and `weights.weight_g` has no integer
    # constraint, so the intake must keep the .5 the exam route keeps
    # (federfall-nd2c — intake used to parseInt it away).
    check("intake weight became a weights row, fraction intact",
          len(iw) == 1 and iw[0]["weight_g"] == 250.5, iw)
    iq = listf(T, "quarantine_records", f'case = "{ic["id"]}"')
    check("quarantine override row (admitted+10d), no default duplicate",
          len(iq) == 1 and iq[0]["quarantine_until"][:10] == "2026-06-11", iq)
    # A newly admitted bird is in care from the start. Without this the field
    # stayed empty until the first disposition and the registry showed no
    # status chip at all.
    _, ianimal = req("GET",
                     f"/api/collections/animals/records/{icase['animal']}", T)
    check("intake sets lifetime_status on the new animal",
          ianimal.get("lifetime_status") == "in_care",
          ianimal.get("lifetime_status"))

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

    # ...and re-identifying an EXISTING animal must not write its lifetime
    # state itself. Only the new-animal branch sets the field: a value written
    # here would be one no reconcile can reproduce, and the next disposition
    # edit on that bird would silently flip it back. What DOES move it is the
    # derivation, through the case this route just opened — a resident under
    # treatment reads `in_care` since federfall-8f1m — and the enclosure must
    # survive that untouched, since clearing it would close the open
    # aviary_stays row with a present-dated `ended_at` and revoke the keeper's
    # write access with it (federfall-sinp).
    # A keeps this enclosure, so A may admit its residents (q7ks.4/.5 —
    # asserted just below); the keeper is a plain carer rather than the
    # supervisor so that this exercises the keeper branch and not the role
    # override.
    ri_av = mk(T, "aviaries", {"name": "Voliere Reident", "keeper": A,
                               "org": ORG})["id"]
    ri_animal = mk(T, "animals", {
        "species": "Stadttaube", "org": ORG,
        "lifetime_status": "in_aviary", "current_aviary": ri_av,
    })["id"]
    s, _ = req("POST", "/api/federfall/intake", toks["a"], {"animal": ri_animal})
    check("re-identification intake succeeds", s == 200, f"status {s}")
    _, ri = req("GET", f"/api/collections/animals/records/{ri_animal}", T)
    check("re-identifying a resident makes it read in_care, by derivation",
          ri.get("lifetime_status") == "in_care", ri.get("lifetime_status"))
    check("re-identification leaves the residency intact",
          ri.get("current_aviary") == ri_av, ri.get("current_aviary"))
    ri_stays = listf(T, "aviary_stays", f'animal = "{ri_animal}" && ended_at = ""')
    check("re-identification does not close the open aviary stay",
          len(ri_stays) == 1, ri_stays)

    # ── admitting an existing bird follows custody (q7ks.4/.5) ───────────────
    # This route bypasses collection rules, so 1700000077's custody rules do not
    # reach it: the check lives in lib_custody.js's requireAdmissible(), called
    # from intake.pb.js. Without it the model has a front door standing open —
    # a stranger could take on another keeper's resident by "re-identifying" it.
    #
    # The `cases` create rule (1700000078) is only the coarser backstop: it can
    # check the enclosure and "not deceased", but not "nobody holds it" — that
    # needs a negative existential, and `?!=` means "any of them differs".
    print("\n[custody: admitting an existing bird]")
    s, d = req("POST", "/api/federfall/intake", toks["b"],
               {"animal": ri_animal})
    check("a stranger cannot admit another keeper's resident", s == 403,
          f"{s} {d}")
    s, _ = req("POST", "/api/federfall/intake", toks["coord"],
               {"animal": ri_animal})
    check("...a coordinator can", s == 200, f"status {s}")

    # A bird at large is anyone's to find — the whole point of re-identification.
    ad_free = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    ad_free_case = mk(T, "cases", {"animal": ad_free, "active_carer": A,
                                   "org": ORG})["id"]
    mk(T, "dispositions", {"case": ad_free_case, "type": "released",
                           "org": ORG})
    s, _ = req("POST", "/api/federfall/intake", toks["b"], {"animal": ad_free})
    check("anyone may admit a bird at large", s == 200, f"status {s}")

    # ...but not one already in somebody's acute care. This is the branch the
    # rule cannot express, so it is the one that proves the hook is doing the
    # work rather than the backstop.
    ad_busy = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    mk(T, "cases", {"animal": ad_busy, "active_carer": A, "org": ORG})
    s, d = req("POST", "/api/federfall/intake", toks["b"], {"animal": ad_busy})
    check("a stranger cannot admit a bird already in another carer's care",
          s == 403, f"{s} {d}")
    s, _ = req("POST", "/api/federfall/intake", toks["a"], {"animal": ad_busy})
    check("...while the carer holding it can", s == 200, f"status {s}")

    # A deceased bird is a correction, not an admission.
    ad_dead = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    ad_dead_case = mk(T, "cases", {"animal": ad_dead, "active_carer": A,
                                   "org": ORG})["id"]
    mk(T, "dispositions", {"case": ad_dead_case, "type": "died", "org": ORG})
    s, d = req("POST", "/api/federfall/intake", toks["b"], {"animal": ad_dead})
    check("a deceased bird cannot be admitted by a carer", s == 403, f"{s} {d}")
    s, _ = req("POST", "/api/federfall/intake", toks["sup"],
               {"animal": ad_dead})
    check("...but a supervisor can, to correct the record", s == 200,
          f"status {s}")

    # The backstop rule stands on its own for anything that reaches `cases`
    # directly (no client does, but a script or a future route might).
    s, _ = req("POST", "/api/collections/cases/records", toks["b"],
               {"animal": ri_animal, "active_carer": B, "org": ORG})
    check("the cases create rule also refuses a stranger's case on a resident",
          s >= 400, f"status {s}")
    s, _ = req("POST", "/api/collections/cases/records", toks["b"],
               {"animal": ad_free, "active_carer": B, "org": ORG})
    check("...and allows one on a bird at large", s == 200, f"status {s}")
    # The rule's OTHER half (1700000078): `animal.lifetime_status != "deceased"`
    # unless coordinator/supervisor. A rule is allowed to trust that field in
    # this ONE direction — it lags toward the PAST (federfall-sinp), so it can
    # read stale-alive but never falsely dead, and a refusal on "deceased" can
    # therefore never refuse a living bird. federfall-8f1m only widened that
    # margin: an open case admitted after the death record now reads `in_care`,
    # which is stale-alive again, never the reverse.
    #
    # A FRESH deceased bird, because ad_dead is no longer one: the supervisor's
    # corrective intake above opened a case on it, so it reads `in_care` — and B
    # would then be refused below by CUSTODY (somebody holds it) rather than by
    # the deceased clause, which would leave that clause untested while the
    # check still passed.
    ad_dead2 = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    ad_dead2_case = mk(T, "cases", {"animal": ad_dead2, "active_carer": A,
                                    "org": ORG})["id"]
    mk(T, "dispositions", {"case": ad_dead2_case, "type": "died", "org": ORG})
    _, ad_dead2_rec = req("GET", f"/api/collections/animals/records/{ad_dead2}", T)
    check("setup: a bird whose only case is closed, and closed by a death",
          (ad_dead2_rec or {}).get("lifetime_status") == "deceased",
          ad_dead2_rec)
    s, _ = req("POST", "/api/collections/cases/records", toks["b"],
               {"animal": ad_dead2, "active_carer": B, "org": ORG})
    check("the cases create rule refuses a case on a deceased bird",
          s >= 400, f"status {s}")
    s, _ = req("POST", "/api/collections/cases/records", toks["coord"],
               {"animal": ad_dead2, "active_carer": COORD, "org": ORG})
    check("...unless a coordinator is correcting the record", s == 200,
          f"status {s}")
    # And that correction is visible immediately: the new case is the animal's
    # latest event, so the bird stops reading deceased (federfall-8f1m). Which
    # is what makes the refusal above a statement about the DEAD bird rather
    # than about B.
    _, ad_dead2_rec = req("GET", f"/api/collections/animals/records/{ad_dead2}", T)
    check("...after which it reads in_care, not deceased",
          (ad_dead2_rec or {}).get("lifetime_status") == "in_care",
          ad_dead2_rec)

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

    # ── federfall-epkf / federfall-mpm4: taking a bird back ──────────────────
    # `active_carer` of a DISPOSED case never expires, which since 1700000077 is
    # write authority rather than a label. Two acts reached back through it: a
    # direct `status` write re-opening the case (epkf, `case_status.pb.js`) and a
    # disposition dated just-past that re-derives `current_aviary` (mpm4,
    # `disposition_custody.pb.js`). Both are stated here as the probes that
    # found them, and so is everything they must NOT break — the correction path
    # is what makes this narrow rather than a blanket custody clause.
    print("\n[custody: taking a bird back]")
    rt_av_b = mk(T, "aviaries", {"name": "Voliere B-rt", "keeper": B,
                                 "org": ORG})["id"]
    rt_av_c = mk(T, "aviaries", {"name": "Voliere C-rt", "keeper": C,
                                 "org": ORG})["id"]

    # ── epkf: the case's status may not contradict its outcome ───────────────
    rt_dead = mk(T, "animals", {"species": "Stadttaube", "name": "Wieder da",
                                "org": ORG})["id"]
    rt_dead_case = mk(T, "cases", {"animal": rt_dead, "active_carer": B,
                                   "org": ORG})["id"]
    mk(T, "dispositions", {"case": rt_dead_case, "type": "died", "org": ORG})
    check("setup: the bird is recorded dead and its case closed",
          animal_state(rt_dead) == ("deceased", ""), animal_state(rt_dead))
    check("setup: B, its former carer, holds nothing",
          not edits_animal(toks["b"], rt_dead, "rt-0"), "B could write")
    s, d = req("PATCH", f"/api/collections/cases/records/{rt_dead_case}",
               toks["b"], {"status": "in_care"})
    check("a former carer cannot re-open their own closed case", s == 400,
          f"{s} {d}")
    _, rt_dead_c = req("GET", f"/api/collections/cases/records/{rt_dead_case}", T)
    check("...the case is still disposed",
          (rt_dead_c or {}).get("status") == "disposed", rt_dead_c)
    check("...and B still holds nothing",
          not edits_animal(toks["b"], rt_dead, "rt-1"), "B could write")
    s, _ = req("PATCH", f"/api/collections/cases/records/{rt_dead_case}",
               toks["b"], {"intake_notes": "Notiz nachgetragen"})
    check("...while the rest of a closed case stays editable by its carer",
          s == 200, f"status {s}")

    # The transitions the UI actually offers are untouched, and the contradiction
    # in the other direction is refused too: a case closed with no outcome leaves
    # the browser's active set without ever becoming an ended case in
    # `case_report_rows`, whose `ended_at` comes from the terminal disposition.
    rt_open = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    rt_open_case = mk(T, "cases", {"animal": rt_open, "active_carer": A,
                                   "org": ORG})["id"]
    for rt_want, rt_label in (("ready_for_release", "in_care -> "
                               "ready_for_release stays freely writable"),
                              ("in_care", "...and back again")):
        s, _ = req("PATCH", f"/api/collections/cases/records/{rt_open_case}",
                   toks["a"], {"status": rt_want})
        check(rt_label, s == 200, f"status {s}")
    s, d = req("PATCH", f"/api/collections/cases/records/{rt_open_case}",
               toks["a"], {"status": "disposed"})
    check("a case cannot be closed without an outcome", s == 400, f"{s} {d}")
    s, d = req("POST", "/api/collections/cases/records", toks["a"],
               {"animal": rt_open, "active_carer": A, "org": ORG,
                "status": "disposed"})
    check("...nor be created already closed", s == 400, f"{s} {d}")
    s, _ = req("POST", "/api/collections/cases/records", toks["a"],
               {"animal": rt_open, "active_carer": A, "org": ORG})
    check("...which is this hook and not the create rule refusing it", s == 200,
          f"status {s}")

    # ── mpm4: an outcome that moves a bird needs custody of it ───────────────
    # B's case on this bird closed in 2024; A holds it now. Everything below is
    # B, years later, still passing `childEdit` on that case's dispositions.
    rt_x = mk(T, "animals", {"species": "Stadttaube", "name": "Fremder Vogel",
                             "org": ORG})["id"]
    rt_x_old = mk(T, "cases", {"animal": rt_x, "active_carer": B,
                               "admitted_at": "2024-03-01 09:00:00.000Z",
                               "org": ORG})["id"]
    rt_x_disp = mk(T, "dispositions", {"case": rt_x_old, "type": "released",
                                       "disposed_at": "2024-04-01 09:00:00.000Z",
                                       "org": ORG})["id"]
    mk(T, "cases", {"animal": rt_x, "active_carer": A, "org": ORG})
    check("setup: the bird is in A's acute care and in no enclosure",
          animal_state(rt_x) == ("in_care", ""), animal_state(rt_x))
    s, d = req("POST", "/api/collections/dispositions/records", toks["b"],
               {"case": rt_x_old, "type": "placed_in_aviary",
                "aviary": rt_av_b, "disposed_at": stamp(days=-1), "org": ORG})
    check("a stale carer cannot place another carer's bird by dating an "
          "outcome just-past", s == 403, f"{s} {d}")
    check("...so the bird stays where it was",
          animal_state(rt_x) == ("in_care", ""), animal_state(rt_x))
    check("...and B still cannot write about it",
          not edits_animal(toks["b"], rt_x, "rt-2"), "B could write")
    s, d = req("PATCH", f"/api/collections/dispositions/records/{rt_x_disp}",
               toks["b"], {"type": "placed_in_aviary", "aviary": rt_av_b,
                           "disposed_at": stamp(days=-1)})
    check("...nor by rewriting the outcome the case already carries", s == 403,
          f"{s} {d}")
    s, d = req("DELETE", f"/api/collections/dispositions/records/{rt_x_disp}",
               toks["b"])
    check("...nor by deleting that outcome to re-open the case around it",
          s == 403, f"{s} {d}")
    _, rt_x_old_c = req("GET", f"/api/collections/cases/records/{rt_x_old}", T)
    check("...which leaves the case disposed",
          (rt_x_old_c or {}).get("status") == "disposed", rt_x_old_c)

    # What the same stale carer may still do, because none of it moves the bird:
    # the gate is about `current_aviary`, not about the row's age.
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{rt_x_disp}",
               toks["b"], {"reason": "Nachtrag aus dem Archiv"})
    check("a stale carer may still correct what the outcome SAYS", s == 200,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{rt_x_disp}",
               toks["b"], {"disposed_at": "2024-04-02 09:00:00.000Z"})
    check("...and re-date it, as long as that moves the bird nowhere", s == 200,
          f"status {s}")

    # A resident, so the refusal is stated against the keeper branch too and not
    # only against somebody's open case.
    rt_res = mk(T, "animals", {"species": "Stadttaube", "name": "Bewohnerin C",
                               "org": ORG})["id"]
    rt_res_old = mk(T, "cases", {"animal": rt_res, "active_carer": B,
                                 "org": ORG})["id"]
    mk(T, "dispositions", {"case": rt_res_old, "type": "placed_in_aviary",
                           "aviary": rt_av_c,
                           "disposed_at": "2024-05-01 09:00:00.000Z",
                           "org": ORG})
    check("setup: the bird lives in C's enclosure",
          animal_state(rt_res) == ("in_aviary", rt_av_c), animal_state(rt_res))
    s, d = req("POST", "/api/collections/dispositions/records", toks["b"],
               {"case": rt_res_old, "type": "placed_in_aviary",
                "aviary": rt_av_b, "disposed_at": stamp(days=-1), "org": ORG})
    check("nor may they move a resident into their own enclosure", s == 403,
          f"{s} {d}")
    check("...it stays where it lives",
          animal_state(rt_res) == ("in_aviary", rt_av_c), animal_state(rt_res))
    # The same act by editing the very row that houses it, and the EVICTION that
    # made the moving leg plain custody (federfall-q11w): a placement row is the
    # reason the bird is where it is, so "nobody else holds it once this row is
    # set aside" answers yes for both of these and for an honest correction
    # alike. Nothing in the state tells them apart, so nothing tries.
    rt_res_disp = listf(T, "dispositions", f'case="{rt_res_old}"')[0]["id"]
    s, d = req("PATCH", f"/api/collections/dispositions/records/{rt_res_disp}",
               toks["b"], {"aviary": rt_av_b})
    check("...including by re-pointing the placement that put it there",
          s == 403, f"{s} {d}")
    s, d = req("PATCH", f"/api/collections/dispositions/records/{rt_res_disp}",
               toks["b"], {"type": "released"})
    check("...and they cannot evict it either, which is not an escalation but "
          "is somebody else's flock", s == 403, f"{s} {d}")
    s, d = req("DELETE", f"/api/collections/dispositions/records/{rt_res_disp}",
               toks["b"])
    check("...nor by deleting the placement outright", s == 403, f"{s} {d}")
    check("...still where it lives",
          animal_state(rt_res) == ("in_aviary", rt_av_c), animal_state(rt_res))
    rt_res_stays = [x for x in listf(T, "aviary_stays", f'animal="{rt_res}"')
                    if x["ended_at"] == ""]
    check("...with its residency ledger intact, which is the part no UI could "
          "repair", len(rt_res_stays) == 1 and rt_res_stays[0]["aviary"] ==
          rt_av_c, rt_res_stays)

    # ── handing a bird over is not reversible by whoever handed it over ──────
    # federfall-q11w's price, accepted on purpose: a carer may place the bird
    # they hold into any enclosure, and from that moment the bird is the
    # enclosure's — they can no longer say where it went, withdraw the placement
    # or delete it. The repairs are the keeper's and the supervisor's, and both
    # are exercised below, because a gate whose only repair is a supervisor is a
    # gate that gets worked around.
    rt_z = mk(T, "animals", {"species": "Stadttaube", "name": "Eigener Fehler",
                             "org": ORG})["id"]
    rt_z_case = mk(T, "cases", {"animal": rt_z, "active_carer": A,
                                "org": ORG})["id"]
    rt_z_disp = mk(toks["a"], "dispositions",
                   {"case": rt_z_case, "type": "placed_in_aviary",
                    "aviary": rt_av_b, "org": ORG})["id"]
    check("setup: a carer places the bird they hold into an enclosure they do "
          "not keep", animal_state(rt_z) == ("in_aviary", rt_av_b),
          animal_state(rt_z))
    for rt_body, rt_label in (
        ({"aviary": rt_av_c}, "...and cannot then change which enclosure it "
                              "went to"),
        ({"type": "died"}, "...nor withdraw the placement"),
    ):
        s, d = req("PATCH", f"/api/collections/dispositions/records/{rt_z_disp}",
                   toks["a"], rt_body)
        check(rt_label, s == 403, f"{s} {d}")
    s, d = req("DELETE", f"/api/collections/dispositions/records/{rt_z_disp}",
               toks["a"])
    check("...nor delete it", s == 403, f"{s} {d}")
    check("...the bird stays the enclosure's",
          animal_state(rt_z) == ("in_aviary", rt_av_b), animal_state(rt_z))
    # Repair 1: a supervisor, who overrides every branch.
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{rt_z_disp}",
               toks["sup"], {"aviary": rt_av_c})
    check("a supervisor can correct where it went", s == 200, f"status {s}")
    check("...which moves it", animal_state(rt_z) == ("in_aviary", rt_av_c),
          animal_state(rt_z))
    # Repair 2, and the one that keeps this workable: the KEEPER holds the bird,
    # so 1700000078's keeper branch lets them admit it on a case of their own and
    # place it correctly from there — no supervisor involved.
    s, rt_z_c_case = req("POST", "/api/collections/cases/records", toks["c"],
                         {"animal": rt_z, "active_carer": C, "org": ORG})
    check("the keeper of the enclosure it landed in can admit it themselves",
          s == 200, f"status {s}")
    s, _ = req("POST", "/api/collections/dispositions/records", toks["c"],
               {"case": (rt_z_c_case or {}).get("id"),
                "type": "placed_in_aviary", "aviary": rt_av_b, "org": ORG})
    check("...and place it where it belongs", s == 200, f"status {s}")
    check("...which moves it and closes their case",
          animal_state(rt_z) == ("in_aviary", rt_av_b), animal_state(rt_z))

    # What a carer keeps, because none of it moves a bird anywhere: correcting an
    # outcome that names no enclosure, and deleting the wrong outcome outright —
    # the ordinary "I recorded the wrong thing" repair. The delete is the one act
    # `requireAdmissible` would refuse (the animal reads `deceased` at that
    # moment), and it must not be refused here.
    rt_undo = mk(T, "animals", {"species": "Stadttaube", "name": "Vertippt",
                                "org": ORG})["id"]
    rt_undo_case = mk(T, "cases", {"animal": rt_undo, "active_carer": A,
                                   "org": ORG})["id"]
    rt_undo_disp = mk(toks["a"], "dispositions",
                      {"case": rt_undo_case, "type": "died", "org": ORG})["id"]
    check("setup: a carer records the wrong outcome on their own case",
          animal_state(rt_undo) == ("deceased", ""), animal_state(rt_undo))
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{rt_undo_disp}",
               toks["a"], {"type": "released"})
    check("they may correct an outcome that moves the bird nowhere", s == 200,
          f"status {s}")
    s, _ = req("PATCH", f"/api/collections/dispositions/records/{rt_undo_disp}",
               toks["a"], {"type": "died"})
    check("setup: back to the death record", s == 200, f"status {s}")
    s, d = req("DELETE", f"/api/collections/dispositions/records/{rt_undo_disp}",
               toks["a"])
    check("...and delete it, deceased or not, while nobody else holds the bird",
          s == 204, f"{s} {d}")
    check("...which re-opens their case and restores the bird",
          animal_state(rt_undo) == ("in_care", ""), animal_state(rt_undo))

    # The route the moving leg refuses is not a dead end: admitting a bird at
    # large is what `/api/federfall/intake` is for, and `requireAdmissible`
    # allows it.
    rt_free = mk(T, "animals", {"species": "Stadttaube", "name": "Freigelassen",
                                "org": ORG})["id"]
    rt_free_case = mk(T, "cases", {"animal": rt_free, "active_carer": B,
                                   "org": ORG})["id"]
    mk(T, "dispositions", {"case": rt_free_case, "type": "released",
                           "disposed_at": "2024-06-01 09:00:00.000Z",
                           "org": ORG})
    check("setup: a bird at large, whose only case is B's and closed",
          animal_state(rt_free) == ("at_large_released", ""),
          animal_state(rt_free))
    s, d = req("POST", "/api/collections/dispositions/records", toks["b"],
               {"case": rt_free_case, "type": "placed_in_aviary",
                "aviary": rt_av_b, "disposed_at": stamp(days=-1), "org": ORG})
    check("a stale carer cannot take even an UNHELD bird into an enclosure "
          "this way", s == 403, f"{s} {d}")
    check("...it is still at large",
          animal_state(rt_free) == ("at_large_released", ""),
          animal_state(rt_free))
    s, _ = req("POST", "/api/federfall/intake", toks["b"], {"animal": rt_free})
    check("...while admitting it, the route that exists for that, still works",
          s == 200, f"status {s}")

    # A supervisor overrides all of it, which is what keeps archive backfill
    # (and every repair above) possible. A coordinator does too, but rarely
    # reaches this gate: `childEdit` admits only the case's own carer and SUP.
    s, d = req("POST", "/api/collections/dispositions/records", toks["sup"],
               {"case": rt_x_old, "type": "placed_in_aviary",
                "aviary": rt_av_b, "disposed_at": stamp(days=-1), "org": ORG})
    check("a supervisor backfilling an archive is unaffected", s == 200,
          f"{s} {d}")
    # And the pair this produces is legitimate, not a contradiction: the bird is
    # in an enclosure AND in acute care, because a case decides whether a bird is
    # in care and never where it lives (federfall-8f1m / lib_derive.js).
    check("...the bird moves, while A's open case keeps it in_care",
          animal_state(rt_x) == ("in_care", rt_av_b), animal_state(rt_x))

    # ── federfall-5s5j: Patenschaften ────────────────────────────────────────
    # A sponsorship holds a member of the public's name, address and mobile, and
    # who may read it is decided LIVE by `animal.current_aviary.keeper`
    # (1700000085). That makes the aviary MOVE the feature's whole point and its
    # sharpest edge, so it is asserted in both directions here — a rule that
    # returned nothing to everybody would pass a one-sided test just as well.
    print("\n[sponsorships]")
    sp_av_a = mk(T, "aviaries", {"name": "Patenvoliere A", "keeper": A,
                                 "org": ORG})["id"]
    sp_av_b = mk(T, "aviaries", {"name": "Patenvoliere B", "keeper": B,
                                 "org": ORG})["id"]
    # A resident of A's enclosure whose CASE belongs to C: the carer and the
    # keeper are deliberately different people, because "custody of the bird is
    # not access to the patronage" is the claim being tested.
    sp_bird = mk(T, "animals", {"species": "Stadttaube", "name": "Patenvogel",
                                "current_aviary": sp_av_a, "org": ORG})["id"]
    sp_case = mk(T, "cases", {"animal": sp_bird, "active_carer": C,
                              "org": ORG})["id"]

    def sp_sees(token):
        return {r["id"] for r in listf(token, "sponsorships",
                                       f'animal = "{sp_bird}"')}

    def sp_audit(action):
        flt = f'action = "{action}" && subject_id = "{sp_bird}"'
        s, d = req("GET", "/api/collections/audit_events/records?sort=created"
                   "&perPage=20&filter=" + urllib.parse.quote(flt),
                   toks["sup"])
        return d["items"] if s == 200 else []

    # ── create: the keeper of the enclosure the bird lives in, and nobody else ─
    s, sp_row = req("POST", "/api/collections/sponsorships/records", toks["a"],
                    {"animal": sp_bird, "sponsor_name": "Marlene Wolf",
                     "mobile": "0170 1234567", "city": "Oldenburg",
                     "amount_cents": 1250, "interval": "monthly",
                     "org": ORG})
    check("the keeper of the bird's aviary can record a patronage", s == 200,
          f"{s} {sp_row}")
    sp_id = (sp_row or {}).get("id")
    s, d = req("POST", "/api/collections/sponsorships/records", toks["b"],
               {"animal": sp_bird, "sponsor_name": "Fremd", "org": ORG})
    check("a keeper of a DIFFERENT enclosure cannot", s == 403, f"{s} {d}")
    # The bird's own carer is refused too, which is the distinction this feature
    # exists to make: they hold the bird, they are not the patronage's reader.
    s, d = req("POST", "/api/collections/sponsorships/records", toks["c"],
               {"animal": sp_bird, "sponsor_name": "Pflegestelle", "org": ORG})
    check("...nor the bird's own carer", s == 403, f"{s} {d}")

    # Only aviary residents. On a bird in a carer's flat there is nobody the
    # predicate could grant the row to — not even its author.
    sp_loose = mk(T, "animals", {"species": "Stadttaube", "name": "Ohne Voliere",
                                 "org": ORG})["id"]
    s, d = req("POST", "/api/collections/sponsorships/records", toks["a"],
               {"animal": sp_loose, "sponsor_name": "Zu früh", "org": ORG})
    check("a patronage cannot be recorded on a bird with no enclosure",
          s == 400, f"{s} {d}")
    s, _ = req("POST", "/api/collections/sponsorships/records", toks["coord"],
               {"animal": sp_loose, "sponsor_name": "Auch nicht", "org": ORG})
    check("...not even by a coordinator", s == 400, f"status {s}")

    # ── read: keeper + coord/sup, and nobody else in the org ─────────────────
    check("the keeper reads their resident's patronage", sp_sees(toks["a"]) ==
          {sp_id}, sp_sees(toks["a"]))
    check("another aviary's keeper reads nothing", sp_sees(toks["b"]) == set(),
          sp_sees(toks["b"]))
    check("the bird's own carer reads nothing", sp_sees(toks["c"]) == set(),
          sp_sees(toks["c"]))
    check("a coordinator reads it", sp_sees(toks["coord"]) == {sp_id},
          sp_sees(toks["coord"]))
    check("a supervisor reads it", sp_sees(toks["sup"]) == {sp_id},
          sp_sees(toks["sup"]))
    s, _ = req("GET", f"/api/collections/sponsorships/records/{sp_id}",
               toks["b"])
    check("...and view-by-id is walled the same way as list", s == 404,
          f"status {s}")

    # The guest wall (1700000045), on the collection this migration added.
    check("guest sees no sponsorships",
          len(listf(gtok, "sponsorships", "id != ''")) == 0, "non-empty")
    s, _ = req("POST", "/api/collections/sponsorships/records", gtok,
               {"animal": sp_bird, "sponsor_name": "Gast", "org": ORG})
    check("guest cannot record one", s != 200, f"status {s}")

    # ── the freeze: `animal` may not be re-pointed ───────────────────────────
    s, d = req("PATCH", f"/api/collections/sponsorships/records/{sp_id}",
               toks["a"], {"animal": sp_loose})
    check("the patronage cannot be moved to another bird", s >= 400, f"{s} {d}")
    s, _ = req("PATCH", f"/api/collections/sponsorships/records/{sp_id}",
               toks["a"], {"amount_cents": 2000})
    check("...while its own content stays editable", s == 200, f"status {s}")

    # federfall-ys7z — „Patenschaft beenden" is exactly this write, and nothing
    # else: a date, never a deletion (an ended patronage is never scrubbed, see
    # federfall-5s5j.4). Clearing it again is the undo, which is why the button
    # needs none of its own.
    s, _ = req("PATCH", f"/api/collections/sponsorships/records/{sp_id}",
               toks["a"], {"ended_at": stamp()})
    check("a keeper can end a patronage by writing ended_at", s == 200,
          f"status {s}")
    s, sp_reopened = req("PATCH",
                         f"/api/collections/sponsorships/records/{sp_id}",
                         toks["a"], {"ended_at": ""})
    check("...and clearing the date makes it run again",
          s == 200 and (sp_reopened or {}).get("ended_at") in ("", None),
          f"{s} {sp_reopened}")

    # ── THE MOVE: access follows the bird ────────────────────────────────────
    # A holds the bird (they keep its enclosure), so A may write the placement
    # that hands it — and its patronage — to B.
    s, d = req("POST", "/api/collections/dispositions/records", toks["sup"],
               {"case": sp_case, "type": "placed_in_aviary",
                "aviary": sp_av_b, "org": ORG})
    check("setup: the bird is placed into the other keeper's enclosure",
          s == 200, f"{s} {d}")
    check("...and the animal record says so",
          animal_state(sp_bird)[1] == sp_av_b, animal_state(sp_bird))
    check("the patronage moved WITH the bird: the new keeper reads it",
          sp_sees(toks["b"]) == {sp_id}, sp_sees(toks["b"]))
    check("...and the previous keeper no longer does",
          sp_sees(toks["a"]) == set(), sp_sees(toks["a"]))
    check("...while coordination keeps seeing it throughout",
          sp_sees(toks["coord"]) == {sp_id}, sp_sees(toks["coord"]))

    # federfall-5s5j.5 — that transfer is a disclosure of personal data to a new
    # reader, so it is logged: a COUNT and the enclosures, never a sponsor.
    rows = sp_audit("sponsorship.access_transferred")
    check("moving a sponsored bird emits sponsorship.access_transferred",
          len(rows) == 1, rows)
    ev = rows[0] if rows else {}
    check("...counting the patronages that changed hands",
          (ev.get("detail") or {}).get("sponsorships") == 1, ev.get("detail"))
    check("...naming the keeper who gained access",
          (ev.get("detail") or {}).get("keeper_label") == "b@f.local",
          ev.get("detail"))
    check("...and both enclosures by name, not by id",
          [(c.get("from_label"), c.get("to_label"))
           for c in (ev.get("changes") or [])]
          == [("Patenvoliere A", "Patenvoliere B")], ev.get("changes"))
    check("...as a security-severity event", ev.get("severity") == "security",
          ev)
    sp_blob = json.dumps(ev)
    check("...and it names no sponsor, anywhere in the row",
          "Marlene" not in sp_blob and "0170" not in sp_blob, sp_blob[:200])

    # An unsponsored bird's moves stay out of the log — nearly every move.
    mk(T, "animals", {"species": "Stadttaube", "current_aviary": sp_av_a,
                      "org": ORG})
    check("an unsponsored bird's move emits nothing",
          len(sp_audit("sponsorship.access_transferred")) == 1, "extra rows")

    # ── the terminal case: the bird leaves aviary care ───────────────────────
    # lib_derive.js clears `current_aviary`, so NO keeper can reach the row any
    # more. That is correct — there is no keeper to be the keeper — and it is
    # why winding a patronage down needs a coordinator.
    s, d = req("POST", "/api/collections/dispositions/records", toks["sup"],
               {"case": sp_case, "type": "released",
                "disposed_at": stamp(minutes=1), "org": ORG})
    check("setup: the bird is released", s == 200, f"{s} {d}")
    check("...its enclosure is cleared", animal_state(sp_bird)[1] == "",
          animal_state(sp_bird))
    check("no keeper reads the patronage once the bird has left aviary care",
          sp_sees(toks["a"]) == set() and sp_sees(toks["b"]) == set(),
          f"a={sp_sees(toks['a'])} b={sp_sees(toks['b'])}")
    check("...while a coordinator still can", sp_sees(toks["coord"]) == {sp_id},
          sp_sees(toks["coord"]))
    check("...and a supervisor still can", sp_sees(toks["sup"]) == {sp_id},
          sp_sees(toks["sup"]))
    # The audit row for THAT transfer says the same thing: nobody gained access.
    rows = sp_audit("sponsorship.access_transferred")
    check("leaving aviary care is logged as a transfer too", len(rows) == 2,
          rows)
    check("...with no keeper named, because there is none",
          (rows[1].get("detail") or {}).get("keeper_label") == ""
          if len(rows) > 1 else False,
          rows[1].get("detail") if len(rows) > 1 else rows)

    # ── deleting the bird leaves an orphan, and MUST still be possible ───────
    # The pairing here is exact and was got wrong once: `animal` does not
    # cascade, and if it were also `required` PocketBase would refuse the
    # animal delete outright ("part of a required relation reference") — a
    # supervisor-only operation blocked by a donation record. Optional + no
    # cascade nulls the relation, which is the orphan
    # sponsorship_retention.pb.js sweeps (covered in test_cron.py, since no API
    # call can trigger a cron).
    sp_doomed_bird = mk(T, "animals", {"species": "Stadttaube",
                                       "current_aviary": sp_av_a,
                                       "org": ORG})["id"]
    s, sp_orphan = req("POST", "/api/collections/sponsorships/records",
                       toks["a"], {"animal": sp_doomed_bird,
                                   "sponsor_name": "Orphan Test", "org": ORG})
    check("setup: a patronage on a bird about to be deleted", s == 200,
          f"{s} {sp_orphan}")
    s, d = req("DELETE", f"/api/collections/animals/records/{sp_doomed_bird}",
               toks["sup"])
    check("a sponsored bird can still be deleted", s == 204, f"{s} {d}")
    s, sp_left = req("GET", "/api/collections/sponsorships/records/"
                     + (sp_orphan or {}).get("id", ""), toks["sup"])
    check("...and its patronage survives as an orphan, not silently destroyed",
          s == 200 and (sp_left or {}).get("animal") in ("", None),
          f"{s} {sp_left}")
    check("...which no keeper can read any more",
          not listf(toks["a"], "sponsorships",
                    f'id = "{(sp_orphan or {}).get("id", "")}"'), "still visible")

    # ── the audited surface: content, never the sponsor ──────────────────────
    rows = [r for r in listf(toks["sup"], "audit_events",
                             f'subject_id = "{sp_id}"')]
    actions = {r["action"] for r in rows}
    check("the patronage's own writes are audited",
          {"sponsorship.created", "sponsorship.updated"} <= actions, actions)
    blob = json.dumps(rows)
    check("...with every personal field redacted",
          "Marlene" not in blob and "0170" not in blob and "Oldenburg"
          not in blob, blob[:300])
    check("...and no subject label, which could only be the sponsor's name",
          all(r.get("subject_label") == "" for r in rows), rows)
    check("...while the arrangement itself is readable",
          any(c.get("field") == "amount_cents"
              for r in rows for c in (r.get("changes") or [])), rows)

    # ── federfall-ys7z: the patronage overview ───────────────────────────────
    # One coord/sup screen over every patronage in the org. Two halves are
    # asserted here, because both live on the server: the standing totals the
    # dashboard teaser reads off GET /api/federfall/stats, and the exact filter
    # expressions the list pages with (`sponsorships_repository.dart`'s
    # filterFor) — a facet that a live PocketBase parses differently than the
    # Dart test's string comparison assumes would fail nowhere else.
    print("\n[patronage overview]")

    def sp_totals(tok, query="?tzOffsetMinutes=0"):
        s, d = req("GET", "/api/federfall/stats" + query, tok)
        return s, ((d or {}).get("sponsorships") or {})

    s, sp_before = sp_totals(toks["coord"])
    check("the stats route carries a sponsorships block", s == 200
          and "monthlyCents" in sp_before, f"{s} {sp_before}")

    # A cohort exercising every rhythm, on a bird in A's enclosure so its keeper
    # may record them. Deltas rather than absolutes: earlier blocks left
    # patronages in this org, and a test that pinned the org's total would break
    # every time one of them changed.
    sp_ov_bird = mk(T, "animals", {"species": "Stadttaube", "name": "Patenmix",
                                   "current_aviary": sp_av_a, "org": ORG})["id"]

    def sp_mk(name, cents, interval, ended=None):
        s, d = req("POST", "/api/collections/sponsorships/records", toks["a"], {
            "animal": sp_ov_bird, "sponsor_name": name, "org": ORG,
            "amount_cents": cents, "interval": interval,
            "ended_at": ended or "",
        })
        if s != 200:
            print(f"FATAL: sponsorship create failed: {s} {d}")
            sys.exit(2)
        return d["id"]

    sp_mk("ys7z Monat", 1000, "monthly")
    sp_mk("ys7z Quartal", 3000, "quarterly")
    sp_mk("ys7z Jahr", 12000, "yearly")
    sp_mk("ys7z Einmal", 5000, "one_time")
    # „läuft bis Dezember" — a FUTURE end date is a running patronage.
    sp_future = sp_mk("ys7z Bis Morgen", 500, "monthly", stamp(days=1))
    # Over, and therefore in none of the sums.
    sp_over = sp_mk("ys7z Beendet", 9999, "monthly", stamp(days=-1))

    s, sp_after = sp_totals(toks["coord"])
    check("total counts every patronage, running or over",
          sp_after.get("total", 0) - sp_before.get("total", 0) == 6,
          f'{sp_before.get("total")} → {sp_after.get("total")}')
    check("active counts the running ones, a future end date included",
          sp_after.get("active", 0) - sp_before.get("active", 0) == 5,
          f'{sp_before.get("active")} → {sp_after.get("active")}')
    # 1000 + 3000/3 + 12000/12 + 500 = 3500. The ended one contributes nothing,
    # and the one-off is NOT divided into a month.
    check("recurring amounts are normalised to a month",
          sp_after.get("monthlyCents", 0)
          - sp_before.get("monthlyCents", 0) == 3500,
          f'{sp_before.get("monthlyCents")} → {sp_after.get("monthlyCents")}')
    check("a one-off donation is reported separately, never divided",
          sp_after.get("oneTimeCents", 0)
          - sp_before.get("oneTimeCents", 0) == 5000,
          f'{sp_before.get("oneTimeCents")} → {sp_after.get("oneTimeCents")}')

    # An amount with no rhythm cannot be normalised — and must not be dropped,
    # or the totals are quietly short of money somebody recorded.
    sp_mk("ys7z Ohne Rhythmus", 700, "")
    s, sp_free = sp_totals(toks["coord"])
    check("an amount with no interval is reported on its own line",
          sp_free.get("noIntervalCents", 0)
          - sp_after.get("noIntervalCents", 0) == 700
          and sp_free.get("monthlyCents") == sp_after.get("monthlyCents"),
          f"{sp_after} → {sp_free}")

    # The one thing that must NOT move with the reporting period: 1999 has no
    # cases at all, and what is being given right now has nothing to do with it.
    s, sp_1999 = sp_totals(toks["coord"], "?year=1999&tzOffsetMinutes=0")
    check("the block is period-independent",
          sp_1999 == sp_free, f"{sp_free} vs {sp_1999}")
    check("...while the period itself really did narrow to nothing",
          req("GET", "/api/federfall/stats?year=1999&tzOffsetMinutes=0",
              toks["coord"])[1]["totals"]["intakes"] == 0)

    # ── the facets, as the app actually sends them ───────────────────────────
    sp_now = stamp()
    sp_mine = 'sponsor_name ~ "ys7z"'

    def sp_facet(flt):
        return {r["sponsor_name"]
                for r in listf(toks["coord"], "sponsorships",
                               f'{sp_mine} && ({flt})')}

    active = sp_facet(f'ended_at = "" || ended_at > "{sp_now}"')
    ended = sp_facet(f'ended_at != "" && ended_at <= "{sp_now}"')
    check("the active facet keeps unset AND future end dates",
          "ys7z Monat" in active and "ys7z Bis Morgen" in active
          and "ys7z Beendet" not in active, active)
    check("the ended facet is its exact complement",
          ended == {"ys7z Beendet"}, ended)
    check("...and the two partition the cohort, with no row in both",
          not (active & ended) and len(active) + len(ended) == 7,
          f"{active} | {ended}")
    check("the interval facet matches the stored wire value",
          sp_facet('interval = "quarterly"') == {"ys7z Quartal"},
          sp_facet('interval = "quarterly"'))
    # The search is the sponsor and the town, and deliberately nothing else.
    check("search matches the sponsor's name",
          "ys7z Monat" in sp_facet('sponsor_name ~ "Monat" || city ~ "Monat"'),
          "no match")
    check("...and their town",
          {r["sponsor_name"] for r in
           listf(toks["coord"], "sponsorships",
                 'sponsor_name ~ "Oldenburg" || city ~ "Oldenburg"')}
          == {"Marlene Wolf"}, "town search")

    # A carer's widened view of this screen is still nothing: the route gate is
    # defence in depth, the list rule is the boundary.
    check("a carer cannot list the org's patronages, filter or no filter",
          not listf(toks["c"], "sponsorships", sp_mine), "visible to a carer")
    check("...nor can a keeper of another enclosure",
          not listf(toks["b"], "sponsorships", sp_mine), "visible to B")

    # The rows the app pages through are ordered by sponsor_name, which is the
    # key its cursor is built from — a different sort would page nonsense.
    s, sp_page = req("GET", "/api/collections/sponsorships/records"
                     "?perPage=3&sort=sponsor_name,id&filter="
                     + urllib.parse.quote(sp_mine), toks["coord"])
    names = [r["sponsor_name"] for r in (sp_page or {}).get("items", [])]
    check("the list pages in sponsor_name order", names == sorted(names),
          names)
    check("setup: the overview cohort is reachable at all",
          bool(names) and sp_future and sp_over, names)

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

    # Deliberately NOT also custody-gated (exam.pb.js, federfall-q7ks.5). An
    # exam is a CASE timeline record whose `animal` is only denormalized for the
    # lifetime view, and cross-org re-pointing is already blocked above — so a
    # carer writing up a late exam on their OWN closed case must still get
    # through, even though the bird has moved on and they no longer hold it.
    # That is a correction the model has no reason to forbid. If requireCustody
    # is ever added to this route, THIS is the check that must fail.
    aex_gone_animal = mk(T, "animals", {"species": "Stadttaube",
                                        "name": "Nachtrag", "org": ORG})["id"]
    aex_gone_case = mk(T, "cases", {"animal": aex_gone_animal,
                                    "active_carer": A, "org": ORG})["id"]
    mk(T, "dispositions", {"case": aex_gone_case, "type": "released",
                           "org": ORG})
    check("setup: the bird really has left A's custody",
          not edits_animal(toks["a"], aex_gone_animal, "nicht mehr meins"),
          "A can still edit it")
    s, d = req("POST", "/api/federfall/exam", toks["a"], {
        "case": aex_gone_case, "animal": aex_gone_animal,
        "exam": {"notes": "late write-up", "body_condition": 3},
    })
    check("a carer can still write a late exam on their own CLOSED case",
          s == 200, f"{s} {d}")

    # ── federfall-vl7g / kp7y: microscopy ────────────────────────────────────
    # Kropfabstrich / Kotprobe with per-finding grades, written through
    # POST /api/federfall/microscopy in one transaction (the exam route's
    # stance — see federfall-lov0). Three things are worth pinning here beyond
    # the usual permission matrix: the "ohne Befund" XOR, the fact that a
    # rejected save leaves the PREVIOUS findings intact, and that a sample has
    # no `animal` relation at all (federfall-h27q — its absence is what keeps
    # microscopy out of merge_animals.pb.js's re-point list).
    print("\n[microscopy]")
    mic_case = mk(T, "cases", {"animal": animal, "active_carer": A,
                               "org": ORG})["id"]
    ftypes = listf(T, "microscopy_finding_types", "active = true")
    by_label = {f["label"]: f for f in ftypes}
    check("microscopy finding types seeded", len(ftypes) == 5,
          [f["label"] for f in ftypes])
    check("Trichomonaden applies to the crop swab only",
          by_label.get("Trichomonaden", {}).get("sample_types") == ["crop_swab"],
          by_label.get("Trichomonaden"))
    # The whole reason this is ONE list with an applicability field.
    check("Hefen applies to BOTH sample types",
          sorted(by_label.get("Hefen", {}).get("sample_types") or [])
          == ["crop_swab", "fecal"], by_label.get("Hefen"))
    check("the vocabulary carries no 'Sonstiges' or 'ohne Befund' row",
          not [x for x in by_label
               if "onstige" in x or "hne Befund" in x], list(by_label))
    check("finding types are org-scoped",
          all(f["org"] == ORG for f in ftypes), ftypes)

    trich = by_label["Trichomonaden"]["id"]
    hefen = by_label["Hefen"]["id"]
    spul = by_label["Spulwurmeier"]["id"]

    s, _ = req("POST", "/api/federfall/microscopy", None,
               {"case": mic_case, "sample": {"sample_type": "fecal"}})
    check("microscopy save requires auth", s == 401, f"status {s}")
    s, _ = req("POST", "/api/federfall/microscopy", gtok,
               {"case": mic_case, "sample": {"sample_type": "fecal"}})
    check("guest CANNOT save microscopy", s == 403, f"status {s}")
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"],
               {"case": mic_case, "sample": {}})
    check("microscopy save without a sample_type is rejected", s == 400,
          f"status {s}")
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"],
               {"case": mic_case, "sample": {"sample_type": "nose_swab"}})
    check("unknown sample_type is rejected", s == 400, f"status {s}")

    # Owner creates a graded faecal sample with one vocabulary finding and one
    # free-text one.
    s, mic1 = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case,
        "sample": {"sample_type": "fecal", "method": "flotation",
                   "examined_by": "in_house",
                   "examined_at": "2026-06-25 09:00:00.000Z"},
        "findings": [{"finding_type": spul, "severity": "plus_plus"},
                     {"free_text": "Ziliaten", "severity": "plus"}],
    })
    check("owner creates a microscopy sample via route",
          s == 200 and bool(mic1 and mic1.get("id")), f"{s} {mic1}")
    mic1_id = mic1["id"]
    _, mic1r = req("GET",
                   f"/api/collections/microscopy_samples/records/{mic1_id}", T)
    check("microscopy org/author come from the session",
          mic1r["org"] == ORG and mic1r["author"] == A,
          f"{mic1r['org']} {mic1r['author']}")
    check("a microscopy sample carries NO animal relation",
          "animal" not in mic1r, sorted(mic1r))
    mfinds = listf(T, "microscopy_findings", f'sample = "{mic1_id}"')
    check("findings created in the same call", len(mfinds) == 2, mfinds)
    check("each finding carries exactly one of finding_type / free_text",
          all(bool(f["finding_type"]) != bool(f["free_text"]) for f in mfinds),
          mfinds)
    check("findings inherit the org", all(f["org"] == ORG for f in mfinds),
          mfinds)

    # Direktabstrich / Flotation is a question about a faecal sample only.
    s, micc = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case,
        "sample": {"sample_type": "crop_swab", "method": "flotation"},
        "findings": [{"finding_type": trich, "severity": "plus_plus_plus"}],
    })
    check("crop swab accepted", s == 200, f"status {s}")
    _, miccr = req("GET",
                   f"/api/collections/microscopy_samples/records/{micc['id']}",
                   T)
    check("method is CLEARED for a crop swab", miccr.get("method") in (None, ""),
          miccr.get("method"))

    # "Ohne Befund" is an assertion about the whole sample.
    s, micn = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case,
        "sample": {"sample_type": "crop_swab", "no_findings": True},
        "findings": [],
    })
    check("ohne Befund saves with no findings", s == 200, f"status {s}")
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case,
        "sample": {"sample_type": "crop_swab", "no_findings": True},
        "findings": [{"finding_type": trich, "severity": "plus"}],
    })
    check("ohne Befund CANNOT be combined with findings", s == 400,
          f"status {s}")
    # Neither set is the legitimate "result pending" state — sample sent to a
    # lab, nobody has read it yet. Collapsing it into "ohne Befund" would
    # assert a clean result no one has seen.
    s, micp = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case,
        "sample": {"sample_type": "fecal", "method": "direct_smear",
                   "examined_by": "lab", "external_lab": "Labor Müller"},
        "findings": [],
    })
    check("a pending result (no findings, no ohne-Befund) is allowed",
          s == 200, f"status {s}")

    # Malformed findings.
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case, "sample": {"sample_type": "fecal"},
        "findings": [{"finding_type": spul, "free_text": "both",
                      "severity": "plus"}]})
    check("a finding with BOTH finding_type and free_text is rejected",
          s == 400, f"status {s}")
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case, "sample": {"sample_type": "fecal"},
        "findings": [{"severity": "plus"}]})
    check("a finding with NEITHER is rejected", s == 400, f"status {s}")
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case, "sample": {"sample_type": "fecal"},
        "findings": [{"finding_type": spul, "severity": "++"}]})
    check("an unknown severity is rejected", s == 400, f"status {s}")
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case, "sample": {"sample_type": "fecal"},
        "findings": [{"finding_type": spul}]})
    check("a finding without a severity is rejected", s == 400, f"status {s}")

    # Permission mirror: same-org outsider / read-share cannot; edit-share can.
    s, _ = req("POST", "/api/federfall/microscopy", td,
               {"case": mic_case, "sample": {"sample_type": "fecal"}})
    check("same-org outsider CANNOT save microscopy via route", s == 403,
          f"status {s}")
    mk(T, "case_shares", {"case": mic_case, "shared_with": C, "shared_by": A,
                          "access": "read", "org": ORG})
    tc2 = login("c@f.local")[1]
    s, _ = req("POST", "/api/federfall/microscopy", tc2,
               {"id": mic1_id, "sample": {"sample_type": "fecal"}})
    check("read-share CANNOT edit microscopy via route", s == 403, f"status {s}")
    micseen = listf(tc2, "microscopy_samples", f'case = "{mic_case}"')
    check("read-share CAN read the samples", len(micseen) >= 4, len(micseen))
    micfseen = listf(tc2, "microscopy_findings", f'sample = "{mic1_id}"')
    check("read-share CAN read the findings (grandchild traversal)",
          len(micfseen) == 2, micfseen)
    mk(T, "case_shares", {"case": mic_case, "shared_with": B, "shared_by": A,
                          "access": "edit", "org": ORG})
    s, _ = req("POST", "/api/federfall/microscopy", toks["b"], {
        "id": mic1_id,
        "sample": {"sample_type": "fecal", "method": "flotation"},
        "findings": [{"finding_type": hefen, "severity": "plus"}]})
    check("edit-share CAN edit microscopy via route", s == 200, f"status {s}")

    # Edit replaces the findings as a set, and clears an omitted field.
    mfinds = listf(T, "microscopy_findings", f'sample = "{mic1_id}"')
    check("edit REPLACES the findings set",
          len(mfinds) == 1 and mfinds[0]["finding_type"] == hefen, mfinds)
    _, mic1r = req("GET",
                   f"/api/collections/microscopy_samples/records/{mic1_id}", T)
    check("omitted sample field is cleared on edit (full replace)",
          mic1r.get("examined_by") in (None, ""), mic1r.get("examined_by"))

    # THE point of the route: a rejected save must not eat the previous
    # findings — the failure mode federfall-lov0 found on the exam sheet.
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "id": mic1_id, "sample": {"sample_type": "fecal"},
        "findings": [{"finding_type": hefen, "severity": "plus"},
                     {"finding_type": spul, "severity": "nope"}]})
    check("an invalid finding rejects the whole save", s >= 400, f"status {s}")
    mfinds = listf(T, "microscopy_findings", f'sample = "{mic1_id}"')
    check("failed edit keeps the previous findings intact (atomic)",
          len(mfinds) == 1 and mfinds[0]["finding_type"] == hefen, mfinds)

    # A vocabulary entry from another org must not be reachable.
    fmic = mk(T, "microscopy_finding_types",
              {"label": "Fremdbefund", "org": org2, "active": True})["id"]
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": mic_case, "sample": {"sample_type": "fecal"},
        "findings": [{"finding_type": fmic, "severity": "plus"}]})
    check("a foreign-org finding type is rejected", s == 400, f"status {s}")
    fmic_case = mk(T, "cases", {"animal": fanimal, "org": org2})["id"]
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "case": fmic_case, "sample": {"sample_type": "fecal"}})
    check("microscopy CANNOT be written onto a foreign-org case", s == 400,
          f"status {s}")

    # Boundary guards (1700000043, inline from the start here): a sample cannot
    # be re-pointed into another case, nor a finding into another sample.
    # `>= 400` like the [immutable boundary relations] block above: a guard
    # makes the update rule stop matching the record, and PocketBase answers a
    # non-matching update with 404 rather than 400.
    s, _ = req("PATCH",
               f"/api/collections/microscopy_samples/records/{mic1_id}",
               toks["a"], {"case": aex_case})
    check("microscopy sample CANNOT be re-pointed at another case", s >= 400,
          f"status {s}")
    s, _ = req("PATCH",
               f"/api/collections/microscopy_findings/records/{mfinds[0]['id']}",
               toks["a"], {"sample": micc["id"]})
    check("microscopy finding CANNOT be re-pointed at another sample",
          s >= 400, f"status {s}")

    # The code list is supervisor-managed, like every other vocabulary.
    s, _ = req("POST", "/api/collections/microscopy_finding_types/records",
               toks["a"], {"label": "Carer-Wunsch", "org": ORG})
    check("a carer CANNOT add a finding type", s in (400, 403), f"status {s}")
    s, _ = req("POST", "/api/collections/microscopy_finding_types/records",
               toks["sup"], {"label": "Supervisor-Befund", "org": ORG,
                           "active": True, "sample_types": ["fecal"]})
    check("a supervisor CAN add a finding type", s == 200, f"status {s}")
    s, gtypes = req("GET", "/api/collections/microscopy_finding_types/records",
                    gtok)
    check("guest CANNOT read the finding types",
          s != 200 or not (gtypes or {}).get("items"), f"status {s}")

    # Deleting a type nulls the reference and keeps the finding — the
    # `conditions` behaviour, not `marking_types`' (finding_type is optional).
    s, _ = req("DELETE",
               f"/api/collections/microscopy_finding_types/records/{hefen}",
               toks["sup"])
    check("a supervisor CAN delete a finding type still in use", s == 204,
          f"status {s}")
    mfinds = listf(T, "microscopy_findings", f'sample = "{mic1_id}"')
    check("the finding survives its type's deletion, keeping its severity",
          len(mfinds) == 1 and mfinds[0]["finding_type"] == ""
          and mfinds[0]["severity"] == "plus", mfinds)

    # Attachments: multipart with @jsonPayload beside the files, the shape the
    # Dart SDK sends (and /api/federfall/intake already uses). The edit path is
    # the interesting one — `keep_attachments` lists the SURVIVORS, so a name
    # left out is what deletes that file.
    def multipart_microscopy(token, payload_obj, filename="slide.png"):
        boundary = "----fedmicboundary"
        payload = json.dumps(payload_obj)
        mp = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="@jsonPayload"\r\n\r\n'
            f"{payload}\r\n"
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="attachments"; filename="{filename}"\r\n'
            "Content-Type: image/png\r\n\r\n"
        ).encode() + _PNG_1X1 + f"\r\n--{boundary}--\r\n".encode()
        r = urllib.request.Request(
            BASE + "/api/federfall/microscopy", data=mp, method="POST",
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}",
                     "Authorization": token})
        try:
            resp = urllib.request.urlopen(r)
            return resp.status, json.loads(resp.read().decode())
        except urllib.error.HTTPError as err:
            return err.code, None

    s, mica = multipart_microscopy(toks["a"], {
        "case": mic_case,
        "sample": {"sample_type": "crop_swab"},
        "findings": [{"finding_type": trich, "severity": "plus"}]})
    check("multipart microscopy (jsonPayload + attachment) succeeds",
          s == 200 and bool(mica and mica.get("id")), f"{s} {mica}")
    _, micar = req("GET",
                   f"/api/collections/microscopy_samples/records/{mica['id']}",
                   T)
    check("the attachment is stored", len(micar.get("attachments") or []) == 1,
          micar.get("attachments"))
    check("multipart parsed the jsonPayload fields",
          micar.get("sample_type") == "crop_swab", micar.get("sample_type"))
    kept_name = micar["attachments"][0]
    # A second upload that KEEPS the first: both must survive.
    s, _ = multipart_microscopy(toks["a"], {
        "id": mica["id"], "sample": {"sample_type": "crop_swab"},
        "findings": [], "keep_attachments": [kept_name]}, "second.png")
    check("a second upload keeps the named survivor", s == 200, f"status {s}")
    _, micar = req("GET",
                   f"/api/collections/microscopy_samples/records/{mica['id']}",
                   T)
    check("both attachments are present",
          len(micar.get("attachments") or []) == 2, micar.get("attachments"))
    # Omitting a name is what drops that file.
    s, _ = req("POST", "/api/federfall/microscopy", toks["a"], {
        "id": mica["id"], "sample": {"sample_type": "crop_swab"},
        "findings": [], "keep_attachments": [kept_name]})
    check("an omitted attachment is dropped", s == 200, f"status {s}")
    _, micar = req("GET",
                   f"/api/collections/microscopy_samples/records/{mica['id']}",
                   T)
    check("only the survivor remains",
          micar.get("attachments") == [kept_name], micar.get("attachments"))
    # The field is protected (1700000027's stance, born-correct here): a bare
    # URL must not serve it. Both halves are asserted, because a rejection on
    # its own would also be what a wrong URL looks like — the token fetch is
    # what proves the path is right and the protection is doing the work.
    mic_file_path = (
        f"/api/files/microscopy_samples/{mica['id']}/{kept_name}")

    def mic_file_status(path):
        r = urllib.request.Request(BASE + path, method="GET")
        try:
            return urllib.request.urlopen(r).status
        except urllib.error.HTTPError as err:
            return err.code

    check("a microscopy attachment is NOT served without a file token",
          mic_file_status(mic_file_path) != 200,
          mic_file_status(mic_file_path))
    _, mtokd = req("POST", "/api/files/token", toks["a"])
    check("the carer's file token serves the attachment",
          mic_file_status(f"{mic_file_path}?token={mtokd['token']}") == 200,
          mic_file_status(f"{mic_file_path}?token={mtokd['token']}"))
    # The MIME allowlist keeps script-bearing uploads out (1700000048).
    s, _ = multipart_microscopy(toks["a"], {
        "case": mic_case, "sample": {"sample_type": "crop_swab"},
        "findings": []}, "evil.svg")
    check("an image/png part named .svg is still accepted (type, not name)",
          s == 200, f"status {s}")

    # Deleting the case takes the samples and their findings with it.
    s, _ = req("DELETE", f"/api/collections/cases/records/{mic_case}",
               toks["sup"])
    check("supervisor deletes the microscopy case", s == 204, f"status {s}")
    check("samples cascade with the case",
          not listf(T, "microscopy_samples", f'case = "{mic_case}"'))
    check("findings cascade with the sample",
          not listf(T, "microscopy_findings", f'sample = "{mic1_id}"'))

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
    # federfall-z9lh: this is the shape the "Bei Fund" flag produces — the
    # flag is provenance, `applied_at` is still a real date, and the window
    # reads the date. Set both, so a future change that starts deriving the
    # date from the flag drops this ring out of the report and fails here.
    mk(T, "markings", {"animal": ar_animal, "org": ORG, "type": ar_type,
                       "code": "DEH-A9002", "is_active": True,
                       "present_at_find": True,
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
    # The flag is for the reader of the timeline; the report prints the ring
    # the same way either way, because at release it is simply a ring the bird
    # carried and who put it on is not what this column answers.
    check("...and being flagged present-at-find does not change how it prints",
          "DEH-A9002" in row and "present_at_find" not in row, row)
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

    # ── federfall-qt96.1: audit log (append-only, supervisor-only) ──────────
    print("\n[audit log]")
    # Real rows come from hook emitters (federfall-qt96.3+), which bypass rules
    # the same way the superuser token does here. Standing in for an emitter is
    # what lets the whole read/append-only surface be tested before the first
    # emitter exists.
    arow = mk(T, "audit_events", {
        "org": ORG, "action": "case.handoff",
        "actor_id": A, "actor_label": "Carer A", "actor_role": "carer",
        "actor_kind": "user",
        "subject_collection": "cases", "subject_id": case,
        "subject_label": "F-2026-0001", "case_id": case, "severity": "info",
        "refs": {"animal": animal},
        "changes": [{"field": "active_carer", "from": A, "to": B}],
        "detail": {"from": A, "to": B}, "request_id": "req-audit-test",
    })["id"]

    check("supervisor can list audit events (wall check is non-vacuous)",
          len(listf(toks["sup"], "audit_events", "id != ''")) > 0, "empty")
    s, _ = req("GET", f"/api/collections/audit_events/records/{arow}", toks["sup"])
    check("supervisor can view an audit event", s == 200, f"status {s}")
    # Everyone below a supervisor is walled off — a list is filtered to nothing
    # rather than refused, so both shapes are checked.
    for who in ("a", "coord"):
        check(f"{who} sees no audit events",
              len(listf(toks[who], "audit_events", "id != ''")) == 0, "non-empty")
        s, _ = req("GET", f"/api/collections/audit_events/records/{arow}", toks[who])
        check(f"{who} CANNOT view an audit event", s != 200, f"status {s}")
    check("guest sees no audit events",
          len(listf(gtok, "audit_events", "id != ''")) == 0, "non-empty")
    s, _ = req("GET", f"/api/collections/audit_events/records/{arow}", None)
    check("anonymous CANNOT view an audit event", s != 200, f"status {s}")

    # No role may write through the API: the rules are null, so even the
    # supervisor who can read the log cannot forge, rewrite or erase it.
    for who, tok in (("carer", toks["a"]), ("coordinator", toks["coord"]),
                     ("supervisor", toks["sup"]), ("guest", gtok)):
        s, _ = req("POST", "/api/collections/audit_events/records", tok, {
            "org": ORG, "action": "case.handoff", "actor_kind": "user",
        })
        check(f"{who} CANNOT create an audit event", s != 200, f"status {s}")
        s, _ = req("PATCH", f"/api/collections/audit_events/records/{arow}", tok,
                   {"action": "case.forged"})
        check(f"{who} CANNOT update an audit event", s != 200, f"status {s}")
        s, _ = req("DELETE", f"/api/collections/audit_events/records/{arow}", tok)
        check(f"{who} CANNOT delete an audit event", s != 200, f"status {s}")

    # The hook guard, which is the layer the rules cannot provide: the superuser
    # dashboard bypasses rules, and it is exactly the operator the log records.
    s, d = req("PATCH", f"/api/collections/audit_events/records/{arow}", T,
               {"action": "case.forged"})
    check("superuser CANNOT update an audit event (hook, not rule)",
          s >= 400, f"status {s} {d}")
    s, d = req("GET", f"/api/collections/audit_events/records/{arow}", toks["sup"])
    check("the row is unchanged after the rejected edit",
          d and d.get("action") == "case.handoff", f"{d}")

    # Cross-org: an audit row belongs to one org and never leaks out of it.
    rrow = mk(T, "audit_events", {
        "org": rorg, "action": "user.role_changed", "actor_id": RSUP,
        "actor_label": "Removal Sup", "actor_role": "supervisor",
        "actor_kind": "user", "severity": "security",
    })["id"]
    check("a foreign-org supervisor does not see it",
          all(x["id"] != rrow
              for x in listf(toks["sup"], "audit_events", "id != ''")),
          "leaked")
    s, _ = req("GET", f"/api/collections/audit_events/records/{rrow}", toks["sup"])
    check("a foreign-org supervisor CANNOT view it", s != 200, f"status {s}")
    check("its own org's supervisor does see it",
          any(x["id"] == rrow
              for x in listf(trsup, "audit_events", "id != ''")), "missing")

    # federfall-qt96.1: the actor is `actor_id` TEXT rather than a relation
    # precisely so this works. PocketBase nullifies a non-cascade relation by
    # SAVING the referring row, which would hit the append-only guard above and
    # turn "remove a member" into a 400 for every user who had ever been audited.
    ghost = mkuser(T, "audited-ghost@f.local", "carer", org=rorg)["id"]
    mk(T, "audit_events", {
        "org": rorg, "action": "user.deactivated", "actor_id": RSUP,
        "actor_kind": "user", "subject_collection": "users",
        "subject_id": ghost, "subject_label": "Ghost", "severity": "notice",
    })
    s, _ = req("DELETE", f"/api/collections/users/records/{ghost}", trsup)
    check("an audited user can still be deleted", s == 204, f"status {s}")

    # The delete guard reads the row's OWN age against its org's retention
    # window — that is what lets the retention cron (federfall-qt96.12) purge
    # without a bypass flag, and it is the only way a row ever leaves.
    s, _ = req("DELETE", f"/api/collections/audit_events/records/{rrow}", T)
    check("superuser CANNOT delete a fresh audit event", s >= 400, f"status {s}")
    req("PATCH", f"/api/collections/organisations/records/{rorg}", T,
        {"settings": {"audit_retention_days": 0}})
    s, _ = req("DELETE", f"/api/collections/audit_events/records/{rrow}", T)
    check("retention 0 means keep forever, not delete now", s >= 400, f"status {s}")
    # A window small enough that a row written moments ago has already outlived
    # it (0.000001 d ≈ 86 ms) — the only way to reach the aged-out branch inside
    # one test run. Nobody would configure this; the cron's window is in years.
    req("PATCH", f"/api/collections/organisations/records/{rorg}", T,
        {"settings": {"audit_retention_days": 0.000001}})
    s, _ = req("DELETE", f"/api/collections/audit_events/records/{rrow}", T)
    check("a row past its org's retention window CAN be deleted", s == 204,
          f"status {s}")

    # ── federfall-qt96.3: domain emitters (Tier A) ──────────────────────────
    # Every write through the ordinary collection API becomes one named event.
    print("\n[audit emitters]")

    def audit_for(subject_id, action=None):
        flt = f'subject_id = "{subject_id}"'
        if action:
            flt += f' && action = "{action}"'
        s, d = req("GET", "/api/collections/audit_events/records?sort=created"
                   "&perPage=50&filter=" + urllib.parse.quote(flt), toks["sup"])
        return d["items"] if s == 200 else []

    def audit_count():
        s, d = req("GET", "/api/collections/audit_events/records?perPage=1",
                   toks["sup"])
        return d["totalItems"] if s == 200 else -1

    ea_animal = mk(toks["a"], "animals",
                   {"species": "Ringeltaube", "name": "Pip", "org": ORG})["id"]
    rows = audit_for(ea_animal, "animal.created")
    check("creating an animal emits animal.created", len(rows) == 1, rows)
    ev = rows[0] if rows else {}
    check("the event snapshots who acted",
          ev.get("actor_id") == A and ev.get("actor_role") == "carer"
          and ev.get("actor_kind") == "user", ev)
    check("the event names its subject", ev.get("subject_label") == "Pip"
          and ev.get("subject_collection") == "animals", ev)

    ea_case = mk(toks["a"], "cases",
                 {"animal": ea_animal, "active_carer": A, "org": ORG})["id"]
    rows = audit_for(ea_case, "case.created")
    check("creating a case emits case.created", len(rows) == 1, rows)
    ev = rows[0] if rows else {}
    check("a case event carries its own case_id", ev.get("case_id") == ea_case, ev)
    check("...and the animal in refs",
          (ev.get("refs") or {}).get("animal") == ea_animal, ev)

    ea_weight = mk(toks["a"], "weights", {"animal": ea_animal, "case": ea_case,
                                          "weight_g": 300, "org": ORG})["id"]
    check("a case-scoped row is correlated to its case",
          (audit_for(ea_weight, "weight.created") or [{}])[0].get("case_id")
          == ea_case, "wrong case_id")

    req("PATCH", f"/api/collections/weights/records/{ea_weight}", toks["a"],
        {"weight_g": 310})
    rows = audit_for(ea_weight, "weight.updated")
    check("updating emits weight.updated with the field change",
          len(rows) == 1 and rows[0]["changes"] == [
              {"field": "weight_g", "from": 300, "to": 310}],
          rows[0]["changes"] if rows else rows)

    # A PATCH that changes nothing is not an event: only `updated` moved, and
    # a log full of "X changed X to X" is a log nobody reads.
    req("PATCH", f"/api/collections/weights/records/{ea_weight}", toks["a"],
        {"weight_g": 310})
    check("a no-op update emits nothing",
          len(audit_for(ea_weight, "weight.updated")) == 1, "duplicate")

    # e.next() runs before the emit, so a rejected write cannot be logged.
    before_n = audit_count()
    s, _ = req("PATCH", f"/api/collections/weights/records/{ea_weight}",
               toks["a"], {"weight_g": -5})
    check("a rejected write is not logged", s >= 400 and audit_count() == before_n,
          f"status {s}")
    before_n = audit_count()
    s, _ = req("POST", "/api/collections/weights/records", toks["d"],
               {"animal": ea_animal, "case": ea_case, "weight_g": 1,
                "org": "org00000notreal"})
    check("a write refused by the rules is not logged either",
          s >= 400 and audit_count() == before_n, f"status {s}")

    # The rest of the timeline, one create each.
    ea_journal = mk(toks["a"], "journal_entries",
                    {"case": ea_case, "text": "wound check", "org": ORG})["id"]
    ea_marking = mk(toks["a"], "markings",
                    {"animal": ea_animal, "type": ar_type, "code": "AB-12",
                     "org": ORG})["id"]
    ea_egg = mk(toks["a"], "egg_records",
                {"animal": ea_animal, "count": 2, "org": ORG})["id"]
    ea_med = mk(toks["a"], "medications",
                {"case": ea_case, "drug": "Meloxicam",
                 "frequency_kind": "as_needed", "dose_unit": "mg",
                 "org": ORG})["id"]
    ea_adm = mk(toks["a"], "medication_administrations",
                {"case": ea_case, "medication": ea_med, "drug": "Meloxicam",
                 "administered_at": "2026-06-20 08:00:00.000Z", "org": ORG})["id"]
    # federfall-z9lh — "the bird already wore this when it was found" is a
    # claim about provenance, not a formatting choice: it has to be in
    # CONTENT_FIELDS, or correcting it later leaves no trace of the correction.
    #
    # Corrected BEFORE the disposition below, because since 1700000079 rewriting
    # a marking needs custody of the bird and releasing it ends that — an
    # ex-carer does not get to revise what a bird was wearing after it has gone.
    req("PATCH", f"/api/collections/markings/records/{ea_marking}", toks["a"],
        {"present_at_find": True})
    mk_changes = [c for r in audit_for(ea_marking, "marking.updated")
                  for c in (r.get("changes") or [])
                  if c.get("field") == "present_at_find"]
    check("flipping present_at_find is recorded",
          len(mk_changes) == 1 and mk_changes[0].get("to") is True,
          mk_changes)

    ea_disp = mk(toks["a"], "dispositions",
                 {"case": ea_case, "type": "released",
                  "disposed_at": "2026-06-21 09:00:00.000Z", "org": ORG})["id"]
    # ...and once it has: the same edit is now refused.
    s, _ = req("PATCH", f"/api/collections/markings/records/{ea_marking}",
               toks["a"], {"present_at_find": False})
    check("an ex-carer cannot revise a released bird's marking", s >= 400,
          f"status {s}")
    for what, sid, action in (
        ("journal", ea_journal, "journal.created"),
        ("marking", ea_marking, "marking.created"),
        ("egg record", ea_egg, "egg_record.created"),
        ("medication", ea_med, "medication.prescribed"),
        ("administration", ea_adm, "administration.logged"),
        ("disposition", ea_disp, "disposition.created"),
    ):
        check(f"a {what} emits {action}", len(audit_for(sid, action)) == 1,
              [r["action"] for r in audit_for(sid)])
    check("the marking is labelled by its code",
          (audit_for(ea_marking) or [{}])[0].get("subject_label") == "AB-12",
          "no label")

    # federfall-by7w.1 — an event that does not say WHAT it was about is not
    # worth writing. Every audited collection has to produce a label.
    def label_of(subject_id):
        return (audit_for(subject_id) or [{}])[0].get("subject_label")

    # Each row snapshots the value AS IT WAS then: the create says 300 g and the
    # later update says 310 g, so the log reads correctly however the record
    # changes afterwards.
    wrows = audit_for(ea_weight)
    check("a weight is labelled with the weight it recorded",
          [r["subject_label"] for r in wrows][:2] == ["300 g", "310 g"],
          [r["subject_label"] for r in wrows])
    check("a medication is labelled with the drug",
          label_of(ea_med) == "Meloxicam", label_of(ea_med))
    check("an administration is labelled with the drug too",
          label_of(ea_adm) == "Meloxicam", label_of(ea_adm))

    # Resolved from another record: the id of a code-list row is meaningless in
    # a log, and that row can be renamed or deleted later, so the emitter
    # snapshots its label the way it snapshots every other label.
    ea_cond = listf(T, "conditions", "active = true")[0]
    ea_cc = mk(toks["sup"], "case_conditions",
               {"case": ea_case, "condition": ea_cond["id"], "org": ORG})["id"]
    check("a diagnosis is labelled with the diagnosis, not its id",
          label_of(ea_cc) == ea_cond["label"], label_of(ea_cc))

    # A journal entry deliberately has none: it is free clinical text its author
    # can still edit or delete, and copying it into an append-only table would
    # quietly make it permanent.
    check("a journal entry carries no copy of its text",
          label_of(ea_journal) == "", label_of(ea_journal))

    # federfall-9k2g — a create used to record nothing at all about what it
    # wrote, so "Ausgang erfasst" never said whether the bird was released or
    # died. Content lands in `changes` with from=null, the same shape an update
    # produces, so one renderer handles all three verbs.
    def content_of(subject_id, action):
        rows = audit_for(subject_id, action)
        return {c["field"]: c.get("to", c.get("from"))
                for c in ((rows or [{}])[0].get("changes") or [])}

    disp = content_of(ea_disp, "disposition.created")
    check("a disposition records WHICH outcome it was",
          disp.get("type") == "released", disp)
    check("...and when", "disposed_at" in disp, disp)
    # federfall-by7w.3 — a disposition's consequences are bigger than itself:
    # the hook closes the case and re-derives the bird's lifetime status. Those
    # belong in the detail of the act that caused them, not in events of their
    # own — and were recorded nowhere at all.
    ddet = (audit_for(ea_disp, "disposition.created") or [{}])[0].get("detail") or {}
    check("a disposition records that it closed the case",
          ddet.get("case_status") == "disposed", ddet)
    check("...and what it made of the bird",
          ddet.get("lifetime_status") == "at_large_released", ddet)
    # record.get() hands JS a Go types.DateTime, not a string; stringifying one
    # naively stores it WITH quotes, which then parses as no date at all.
    check("a recorded date is a plain value, not a quoted one",
          '"' not in str(disp.get("disposed_at", "")), disp)
    check("an unset date is not recorded as an empty string",
          all(v not in ("", '""') for v in disp.values()), disp)
    check("an egg record records the count", 
          content_of(ea_egg, "egg_record.created").get("count") == 2,
          content_of(ea_egg, "egg_record.created"))
    med = content_of(ea_med, "medication.prescribed")
    check("a medication records the regimen, not just the drug name",
          med.get("dose_unit") == "mg" and med.get("frequency_kind") == "as_needed",
          med)
    check("the drug itself is not repeated — it is already the label",
          "drug" not in med, med)

    # A delete is the harsher case: afterwards the record is gone and this row
    # is the only description of it that survives.
    ea_doomed = mk(toks["sup"], "egg_records",
                   {"animal": ea_animal, "count": 4, "org": ORG})["id"]
    req("DELETE", f"/api/collections/egg_records/records/{ea_doomed}", toks["sup"])
    gone = audit_for(ea_doomed, "egg_record.deleted")
    check("a delete records what was destroyed", len(gone) == 1, gone)
    check("...as a `from` value, so it reads as cleared rather than set",
          [c for c in ((gone or [{}])[0].get("changes") or [])
           if c["field"] == "count"] == [{"field": "count", "from": 4}],
          (gone or [{}])[0].get("changes"))

    # Free clinical text stays out of the log entirely, on create as on delete.
    jrows = audit_for(ea_journal)
    check("a journal entry never records its text",
          "wound check" not in json.dumps(jrows), "text leaked")

    # federfall-g5ap — and not on an EDIT either, which is where it leaked:
    # CONTENT_FIELDS kept prose out of a create, but diff() is a denylist, so
    # editing an entry stored 500 characters of the old AND the new text in a
    # table nothing can delete from. A carer taking a name back out of a note
    # must not leave the original behind in the audit trail.
    req("PATCH", f"/api/collections/journal_entries/records/{ea_journal}",
        toks["a"], {"text": "wound check — Frau Meier rang about the bird"})
    jrows = audit_for(ea_journal)
    check("...not even when it is edited",
          "Meier" not in json.dumps(jrows)
          and "wound check" not in json.dumps(jrows), "text leaked")
    jchanges = [c for r in audit_for(ea_journal, "journal.updated")
                for c in (r.get("changes") or [])]
    check("...though the edit itself is still logged, as a withheld value",
          {"field": "text", "redacted": True} in jchanges, jchanges)

    # federfall-g5ap — `cases.admission_reasons` is this schema's one MULTI
    # relation (maxSelect 99), and it logged its raw JSON id array: unreadable
    # then, and unreadable forever after, since a reason is a code list a
    # supervisor can rename or deactivate. Both ends carry the labels the
    # reasons had at the time.
    ea_reasons = listf(T, "admission_reasons", "active = true")[:2]
    check("there are seeded admission reasons to select (parse guard)",
          len(ea_reasons) == 2 and all(r.get("label") for r in ea_reasons),
          ea_reasons)

    def reason_change(action="case.updated"):
        rows = audit_for(ea_case, action)
        for c in ((rows or [{}])[-1].get("changes") or []):
            if c["field"] == "admission_reasons":
                return c
        return {}

    req("PATCH", f"/api/collections/cases/records/{ea_case}", toks["sup"],
        {"admission_reasons": [ea_reasons[0]["id"]]})
    ch = reason_change()
    check("selecting an admission reason names it, not its id",
          ch.get("to_label") == ea_reasons[0]["label"], ch)
    check("...and an empty list reads as nothing, not as '[]'",
          ch.get("from") in ("", None) and not ch.get("from_label"), ch)

    req("PATCH", f"/api/collections/cases/records/{ea_case}", toks["sup"],
        {"admission_reasons": [r["id"] for r in ea_reasons]})
    ch = reason_change()
    check("adding a second one names both ends of the change",
          ch.get("from_label") == ea_reasons[0]["label"]
          and ch.get("to_label") == f"{ea_reasons[0]['label']}, "
                                    f"{ea_reasons[1]['label']}", ch)
    check("...while the ids stay in the row, as they do for every relation",
          ea_reasons[1]["id"] in str(ch.get("to", "")), ch)

    # A renamed reason must not change what the row says about the past — the
    # whole reason a label is snapshotted rather than looked up on the way out.
    req("PATCH", f"/api/collections/admission_reasons/records/"
                 f"{ea_reasons[0]['id']}", toks["sup"], {"label": "Umbenannt"})
    check("renaming a reason afterwards does not rewrite the old event",
          reason_change().get("from_label") == ea_reasons[0]["label"],
          reason_change())

    # federfall-by7w.2 — case_id is an opaque id; without the number beside it
    # no case-scoped line names anything a person recognises.
    s, ea_case_rec = req("GET", f"/api/collections/cases/records/{ea_case}",
                         toks["sup"])
    ea_number = ea_case_rec["case_number"]
    check("a case-scoped event carries the case NUMBER, not just its id",
          (audit_for(ea_journal) or [{}])[0].get("case_label") == ea_number,
          (audit_for(ea_journal) or [{}])[0].get("case_label"))
    check("the case's own event carries it too",
          (audit_for(ea_case, "case.created") or [{}])[0].get("case_label")
          == ea_number, "missing")
    check("an event that belongs to no case has no case label",
          (audit_for(ea_animal, "animal.created") or [{}])[0].get("case_label")
          == "", "spurious")

    # Deleting is an event in its own right — and the one that most needs to
    # outlive its subject, since the row it describes is gone.
    s, _ = req("DELETE", f"/api/collections/journal_entries/records/{ea_journal}",
               toks["a"])
    rows = audit_for(ea_journal, "journal.deleted")
    check("deleting emits journal.deleted", s == 204 and len(rows) == 1,
          f"status {s} {rows}")
    check("the deletion event survives its subject",
          (rows or [{}])[0].get("case_id") == ea_case, rows)

    # A handoff is one action, not three: the placement is the record, and the
    # carer move + share-on-handoff it triggers ride along in `detail`.
    # Counted before/after rather than asserted to be zero: this case has been
    # edited directly further up, and those edits are events in their own right.
    case_updates_before = len(audit_for(ea_case, "case.updated"))
    ea_place = mk(toks["a"], "placements",
                  {"case": ea_case, "to_user": B, "org": ORG})["id"]
    rows = audit_for(ea_place, "case.handoff")
    check("a placement naming a to_user is a case.handoff", len(rows) == 1, rows)
    check("...labelled with who took the case on",
          (rows or [{}])[0].get("subject_label") == "b@f.local",
          (rows or [{}])[0].get("subject_label"))
    ev = rows[0] if rows else {}
    check("the handoff records both ends and the derived carer move",
          (ev.get("detail") or {}).get("from") == A
          and (ev.get("detail") or {}).get("to") == B
          and (ev.get("detail") or {}).get("carer_moved") is True, ev)
    # federfall-ybua.1: an id names nobody. Both ends carry the name they had
    # at the time, snapshotted like every other label in the log — the display
    # name where there is one (A is "Alice"), the address where there is not.
    check("...and NAMES both ends, not just their ids",
          (ev.get("detail") or {}).get("to_label") == "b@f.local"
          and (ev.get("detail") or {}).get("from_label") == "Alice",
          ev.get("detail"))
    check("no separate event for the derived carer change",
          len(audit_for(ea_case, "case.updated")) == case_updates_before,
          "case.updated leaked")

    # A supervisor changing org settings is exactly the kind of change that
    # should leave a trace; the superuser dashboard is audited the same way,
    # taking the org from the record because a superuser has none of their own.
    req("PATCH", f"/api/collections/organisations/records/{ORG}", toks["sup"],
        {"settings": {"quarantineDefaultDays": 14}})
    rows = audit_for(ORG, "org.settings_updated")
    check("an org settings change is logged", len(rows) >= 1, rows)
    check("...with the supervisor as actor",
          (rows or [{}])[-1].get("actor_role") == "supervisor", rows)
    req("PATCH", f"/api/collections/organisations/records/{ORG}", T,
        {"settings": {"quarantineDefaultDays": 15}})
    rows = audit_for(ORG, "org.settings_updated")
    check("a superuser dashboard change is logged too",
          len(rows) >= 2 and rows[-1].get("actor_kind") == "superuser",
          [r.get("actor_kind") for r in rows])

    # A finder is a member of the public: the log records THAT one was touched
    # and never who they are, or finder_retention.pb.js's scrub would be
    # defeated by the one table that has no delete path.
    ea_finder = mk(toks["a"], "finders",
                   {"last_name": "Geheim", "phone": "0151 4711",
                    "city": "Bremen", "org": ORG})["id"]
    rows = audit_for(ea_finder, "finder.created")
    check("creating a finder is logged", len(rows) == 1, rows)
    check("...but never by name", (rows or [{}])[0].get("subject_label") == "",
          rows)
    # As a supervisor: the finders update rule only reaches a carer through a
    # linked case, and this finder deliberately has none. Redaction is a
    # property of the emitter, not of who triggered it.
    req("PATCH", f"/api/collections/finders/records/{ea_finder}", toks["sup"],
        {"phone": "0151 0000", "city": "Kiel"})
    changed = (audit_for(ea_finder, "finder.updated") or [{}])[0].get("changes") or []
    by_field = {c["field"]: c for c in changed}
    check("a finder's contact detail is redacted to the fact of the change",
          by_field.get("phone") == {"field": "phone", "redacted": True},
          by_field.get("phone"))
    check("...while what the GDPR scrub keeps stays readable",
          by_field.get("city", {}).get("to") == "Kiel", by_field.get("city"))
    check("no finder PII reaches the log at all",
          "Geheim" not in json.dumps(audit_for(ea_finder))
          and "4711" not in json.dumps(audit_for(ea_finder)), "PII leaked")

    # Where a bird went is recorded on the DISPOSITION that sent it there, and
    # nowhere else. `animals.current_aviary` is written by main.pb.js's reconcile
    # through `app.save()`, and the emitters are onRecord*Request hooks — a
    # derived write is not a request and emits nothing (the same property that
    # keeps a cascade delete from writing a row per timeline child).
    #
    # This block used to move the bird with a direct PATCH and assert the
    # resulting animal.updated. That path was the federfall-7no9 bug: a client
    # relocating a resident with no disposition to explain it. 1700000075 closes
    # it, which leaves the disposition as the ONLY witness — so `aviary` had to
    # join CONTENT_FIELDS, or closing the hole would have blinded the log to
    # every aviary placement.
    ea_aviary = mk(toks["sup"], "aviaries", {"name": "Voliere Audit",
                                             "keeper": SUP,
                                             "org": ORG})["id"]
    check("creating an aviary is logged",
          len(audit_for(ea_aviary, "aviary.created")) == 1, "missing")
    # A dedicated bird: disposing `ea_case` would close the case that the exam,
    # microscopy, share and report checks below still need open.
    ea_resident = mk(toks["a"], "animals", {"species": "Stadttaube",
                                            "name": "Bewohner", "org": ORG})["id"]
    ea_res_case = mk(toks["a"], "cases", {"animal": ea_resident,
                                          "active_carer": A, "org": ORG})["id"]
    ea_placed = mk(toks["a"], "dispositions",
                   {"case": ea_res_case, "aviary": ea_aviary,
                    "type": "placed_in_aviary", "org": ORG})["id"]
    placed = (audit_for(ea_placed, "disposition.created") or [{}])[0]
    pc = placed.get("changes") or []
    check("placing a bird names the enclosure it went into",
          any(c["field"] == "aviary" and c["to"] == ea_aviary for c in pc), pc)
    # federfall-ybua.2: a relation's value is an id, so the change also carries
    # what it pointed AT. Without this the most interesting disposition in the
    # log read "Voliere: 8k2m4p7q1w3e5r9".
    check("...and what that aviary is CALLED",
          any(c["field"] == "aviary" and c.get("to_label") == "Voliere Audit"
              for c in pc), pc)
    check("...attributed to the human who filed it",
          placed.get("actor_id") == A, placed)
    # The derived writes are deliberately silent: neither the animal's own
    # current_aviary/lifetime_status change nor the residency ledger row is a
    # second event. The disposition stands for all three.
    check("the derived animal write is not a second event",
          len(audit_for(ea_resident, "animal.updated")) == 0,
          audit_for(ea_resident, "animal.updated"))
    check("the derived residency ledger is not a second event",
          len(listf(toks["sup"], "audit_events",
                    'subject_collection = "aviary_stays"')) == 0, "leaked")

    # ── federfall-qt96.4: the custom routes (Tier B) ────────────────────────
    # These write with tx.save inside one transaction, so no request hook ever
    # fires — each emits a single semantic event instead of one row per record.
    print("\n[audit: custom routes]")
    before_n = audit_count()
    s, _ = req("POST", "/api/federfall/intake", toks["a"], {})
    check("a rejected intake logs nothing",
          s == 400 and audit_count() == before_n, f"status {s}")

    s, ic = req("POST", "/api/federfall/intake", toks["a"], {
        "species": "Türkentaube", "name": "Nils",
        "finder": {"last_name": "Vertraulich", "phone": "0151 2222"},
        "weight_g": 280, "idempotency_key": "audit-intake-1",
        "case": {"intake_notes": "gefunden am Deich"},
    })
    check("intake succeeds", s == 200, f"{s} {ic}")
    ir = audit_for(ic["id"], "case.intake") if s == 200 else []
    check("an intake is ONE case.intake event", len(ir) == 1, ir)
    ev = ir[0] if ir else {}
    check("...labelled with the case number it just assigned",
          ev.get("subject_label") == ic.get("case_number"), ev)
    check("...and the intake route supplies the case number for free",
          ev.get("case_label") == ic.get("case_number"), ev)
    check("...carrying the animal and the finder as ids",
          (ev.get("refs") or {}).get("animal") == ic.get("animal")
          and bool((ev.get("refs") or {}).get("finder")), ev.get("refs"))
    check("...and what kind of intake it was",
          (ev.get("detail") or {}).get("species") == "Türkentaube"
          and (ev.get("detail") or {}).get("reidentified") is False
          and (ev.get("detail") or {}).get("has_finder") is True, ev.get("detail"))
    check("the finder is still never named", "Vertraulich" not in json.dumps(ev),
          "PII leaked")
    # The five records it wrote are NOT five events: request hooks cannot fire
    # for a tx.save, which is the whole reason this route emits by hand.
    check("no per-record events for the intake's own writes",
          len(audit_for(ic["animal"], "animal.created")) == 0
          and len(audit_for(ic["id"], "case.created")) == 0, "duplicated")

    before_n = audit_count()
    req("POST", "/api/federfall/intake", toks["a"], {
        "species": "Türkentaube", "idempotency_key": "audit-intake-1",
    })
    check("replaying the idempotency key logs nothing new",
          audit_count() == before_n, "replay logged")

    # An exam replaces its findings wholesale; the event says how many there
    # were and how many were abnormal, not one row per finding.
    # As the supervisor: the case was handed to B and disposed above, so A no
    # longer has edit access to it.
    n_finding_events = len(listf(toks["sup"], "audit_events",
                                 'subject_collection = "exam_findings"'))
    s, ex = req("POST", "/api/federfall/exam", toks["sup"], {
        "case": ea_case, "animal": ea_animal,
        "exam": {"examined_at": "2026-06-22 10:00:00.000Z"},
        "findings": [{"system": "eyes", "status": "normal"},
                     {"system": "wings", "status": "abnormal", "note": "links"}],
    })
    check("exam route succeeds", s == 200, f"{s} {ex}")
    xr = audit_for(ex["id"], "exam.saved") if s == 200 else []
    check("saving an exam is ONE exam.saved event", len(xr) == 1, xr)
    ev = xr[0] if xr else {}
    check("...counting its findings",
          (ev.get("detail") or {}).get("findings") == 2
          and (ev.get("detail") or {}).get("abnormal") == 1, ev.get("detail"))
    check("...correlated to the case it belongs to",
          ev.get("case_id") == ea_case, ev)
    check("no per-finding events",
          len(listf(toks["sup"], "audit_events",
                    'subject_collection = "exam_findings"')) == n_finding_events,
          "the route's own finding writes were logged separately")

    # federfall-kp7y — the same stance for microscopy: one event for the sample
    # and the findings it replaced wholesale, correlated to its case, with the
    # finding types NAMED rather than referenced by id (an id in an audit row
    # is a bug unless a label sits beside it). And a finding edited directly
    # must reach its case through `sample`, the CASE_VIA hop exam_findings
    # needed for the same reason.
    mic_trich = listf(toks["sup"], "microscopy_finding_types",
                      'label = "Trichomonaden"')[0]["id"]
    n_mfind_events = len(listf(toks["sup"], "audit_events",
                               'subject_collection = "microscopy_findings"'))
    s, msamp = req("POST", "/api/federfall/microscopy", toks["sup"], {
        "case": ea_case,
        "sample": {"sample_type": "crop_swab",
                   "examined_at": "2026-06-22 11:00:00.000Z"},
        "findings": [{"finding_type": mic_trich, "severity": "plus_plus"},
                     {"free_text": "Ziliaten", "severity": "plus"}],
    })
    check("microscopy route succeeds", s == 200, f"{s} {msamp}")
    mr = audit_for(msamp["id"], "microscopy.saved") if s == 200 else []
    check("saving microscopy is ONE microscopy.saved event", len(mr) == 1, mr)
    mev = mr[0] if mr else {}
    mdet = mev.get("detail") or {}
    check("...counting its findings and naming the worst grade",
          mdet.get("findings") == 2 and mdet.get("worst_severity") == "plus_plus",
          mdet)
    check("...recording the probe kind",
          mdet.get("sample_type") == "crop_swab", mdet)
    check("...naming the findings rather than referencing ids",
          sorted(mdet.get("finding_labels") or [])
          == ["Trichomonaden", "Ziliaten"], mdet.get("finding_labels"))
    check("...correlated to the case it belongs to",
          mev.get("case_id") == ea_case, mev)
    check("no per-finding events from the route",
          len(listf(toks["sup"], "audit_events",
                    'subject_collection = "microscopy_findings"'))
          == n_mfind_events,
          "the route's own finding writes were logged separately")
    mic_finding = listf(toks["sup"], "microscopy_findings",
                        f'sample = "{msamp["id"]}"')[0]
    req("PATCH",
        f"/api/collections/microscopy_findings/records/{mic_finding['id']}",
        toks["sup"], {"severity": "plus_plus_plus"})
    mfr = audit_for(mic_finding["id"], "microscopy_finding.updated")
    check("editing a microscopy finding directly is logged", len(mfr) == 1, mfr)
    check("...against the case its sample belongs to",
          (mfr or [{}])[0].get("case_id") == ea_case, (mfr or [{}])[0])

    # federfall-01wb — a finding edited DIRECTLY (which the rules allow, and
    # which is why exam_finding.* actions exist at all) has no `case` field of
    # its own: it reaches its case only through its exam. It therefore filed
    # under no case and never showed up in the activity of the case it was
    # actually about.
    ea_finding = listf(toks["sup"], "exam_findings", f'exam = "{ex["id"]}"')[0]
    req("PATCH", f"/api/collections/exam_findings/records/{ea_finding['id']}",
        toks["sup"], {"note": "rechts auch"})
    fr = audit_for(ea_finding["id"], "exam_finding.updated")
    check("editing a finding directly is logged", len(fr) == 1, fr)
    check("...against the case its exam belongs to",
          (fr or [{}])[0].get("case_id") == ea_case, (fr or [{}])[0])
    _, ea_case_rec = req("GET", f"/api/collections/cases/records/{ea_case}", T)
    check("...and named by that case's number, like every other case row",
          (fr or [{}])[0].get("case_label")
          == (ea_case_rec or {}).get("case_number"),
          (fr or [{}])[0].get("case_label"))

    # A merge destroys a record. The duplicate's id and name survive only in
    # the event, which is why it is emitted before the delete.
    m_keep = mk(toks["sup"], "animals",
                {"species": "Stadttaube", "name": "Behalten", "org": ORG})["id"]
    m_gone = mk(toks["sup"], "animals",
                {"species": "Stadttaube", "name": "Doppelt", "org": ORG})["id"]
    s, _ = req("POST", "/api/federfall/merge-animals", toks["sup"],
               {"survivor": m_keep, "duplicate": m_gone, "fields": {}})
    check("merge succeeds", s == 200, f"status {s}")
    mr = audit_for(m_keep, "animal.merged")
    check("merging emits animal.merged on the survivor", len(mr) == 1, mr)
    ev = mr[0] if mr else {}
    check("...describing the animal it absorbed, which no longer exists",
          (ev.get("detail") or {}).get("duplicate_id") == m_gone
          and (ev.get("detail") or {}).get("duplicate_label") == "Doppelt", ev)
    check("...as a notice, not routine noise", ev.get("severity") == "notice", ev)
    s, _ = req("GET", f"/api/collections/animals/records/{m_gone}", toks["sup"])
    check("the duplicate really is gone", s == 404, f"status {s}")

    # ── federfall-qt96.5: auth, people and access (Tier D) ──────────────────
    print("\n[audit: auth & access]")
    au_user = mkuser(T, "audited@f.local", "carer")["id"]
    rows = audit_for(au_user, "user.invited")
    check("inviting a member is logged", len(rows) == 1, rows)
    check("...as a security event",
          (rows or [{}])[0].get("severity") == "security", rows)

    s, au_tok = login("audited@f.local")
    check("login succeeds", s == 200, f"status {s}")
    rows = audit_for(au_user, "auth.login")
    check("a successful login is logged", len(rows) == 1, rows)
    check("...attributed to the user who just signed in, not to 'system'",
          (rows or [{}])[0].get("actor_id") == au_user
          and (rows or [{}])[0].get("actor_kind") == "user", rows)

    s, _ = login("audited@f.local", "WrongPass1!")
    check("a wrong password is refused", s != 200, f"status {s}")
    rows = audit_for(au_user, "auth.login_failed")
    check("a failed login is logged", len(rows) == 1, rows)
    check("...saying it stands for a window, not a count",
          (rows[0].get("detail") or {}).get("window_minutes") == 5
          if rows else False, rows)
    # Collapsed: someone hammering the form must not be able to fill a table
    # with no delete path. One row per user per five-minute bucket.
    for _ in range(5):
        login("audited@f.local", "WrongPass1!")
    check("repeated failures collapse into that one row",
          len(audit_for(au_user, "auth.login_failed")) == 1,
          len(audit_for(au_user, "auth.login_failed")))
    # An unknown identity has no user and therefore no org: an unauthenticated
    # caller must not be able to write into an org's table by guessing emails.
    before_n = audit_count()
    login("nobody-at-all@f.local", "WrongPass1!")
    check("a failed login for an unknown email writes nothing",
          audit_count() == before_n, "wrote a row")

    # The updates that matter are filed under what they did, not as a generic
    # user.updated — that is the whole reason refine() exists.
    req("PATCH", f"/api/collections/users/records/{au_user}", toks["sup"],
        {"role": "coordinator"})
    rows = audit_for(au_user, "user.role_changed")
    check("a role change is its own action", len(rows) == 1, rows)
    check("...recording both ends",
          (rows[0].get("detail") or {}) == {"from": "carer", "to": "coordinator"}
          if rows else False, rows)
    req("PATCH", f"/api/collections/users/records/{au_user}", toks["sup"],
        {"is_active": False})
    check("a deactivation is its own action",
          len(audit_for(au_user, "user.deactivated")) == 1, "missing")
    req("PATCH", f"/api/collections/users/records/{au_user}", toks["sup"],
        {"is_active": True})
    check("...and so is a reactivation",
          len(audit_for(au_user, "user.reactivated")) == 1, "missing")
    req("PATCH", f"/api/collections/users/records/{au_user}", toks["sup"],
        {"phone": "0151 12345"})
    rows = audit_for(au_user, "user.updated")
    check("an ordinary profile edit stays a plain user.updated",
          len(rows) == 1, [r["action"] for r in audit_for(au_user)])

    # Credentials never appear, but the fact that they changed does.
    req("PATCH", f"/api/collections/users/records/{au_user}", T,
        {"password": "Newpass12345!", "passwordConfirm": "Newpass12345!"})
    rows = audit_for(au_user, "auth.password_changed")
    check("a password change is logged", len(rows) == 1, rows)
    ch = (rows[0].get("changes") if rows else []) or []
    check("...with the value redacted, not stored",
          {"field": "password", "redacted": True} in ch
          and not any("from" in c for c in ch if c["field"] == "password"), ch)
    check("no credential material reaches the log",
          "Newpass12345!" not in json.dumps(audit_for(au_user)), "leaked")

    # A share is the closest thing this app has to a permission grant.
    sh = mk(toks["sup"], "case_shares",
            {"case": ea_case, "shared_with": D, "shared_by": SUP,
             "access": "read", "org": ORG})["id"]
    rows = audit_for(sh, "case.shared")
    check("sharing a case is logged", len(rows) == 1, rows)
    check("...labelled with who it was shared with",
          (rows or [{}])[0].get("subject_label") == "d@f.local",
          (rows or [{}])[0].get("subject_label"))
    check("...naming who with, at what access, on which case",
          (rows[0].get("detail") or {}) == {"with": D, "with_label": "d@f.local",
                                            "access": "read"}
          and rows[0].get("case_id") == ea_case if rows else False, rows)
    req("DELETE", f"/api/collections/case_shares/records/{sh}", toks["sup"])
    check("revoking it is logged too",
          len(audit_for(sh, "case.share_revoked")) == 1, "missing")

    # ── federfall-qt96.6: exports (data leaving the system) ─────────────────
    # No bulk-read logging by design, with one exception: an export takes the
    # data off-system, so it is the read worth recording.
    print("\n[audit: exports]")

    def audit_by_action(action):
        s, d = req("GET", "/api/collections/audit_events/records?sort=created"
                   "&perPage=50&filter=" + urllib.parse.quote(
                       f'action = "{action}"'), toks["sup"])
        return d["items"] if s == 200 else []

    n_before = len(audit_by_action("report.exported"))
    req_bytes("GET", "/api/federfall/reports/annual?year=2019", toks["sup"])
    req_bytes("GET", "/api/federfall/reports/annual?year=2019&format=csv",
              toks["sup"])
    rows = audit_by_action("report.exported")
    check("both report formats are logged as exports",
          len(rows) == n_before + 2, len(rows) - n_before)
    formats = [(r.get("detail") or {}).get("format") for r in rows[-2:]]
    check("...distinguishing the PDF from the spreadsheet",
          formats == ["pdf", "csv"], formats)
    check("...recording which period left the building",
          (rows[-1].get("detail") or {}).get("year") == 2019, rows[-1])

    n_before = len(audit_by_action("case_report.printed"))
    req_bytes("GET", f"/api/federfall/cases/{ea_case}/report.pdf", toks["sup"])
    req_bytes("GET", f"/api/federfall/cases/{ea_case}/report.pdf?widthDots=576",
              toks["sup"])
    rows = audit_by_action("case_report.printed")
    check("printing a case report is logged, in both shapes",
          len(rows) == n_before + 2, len(rows) - n_before)
    check("...against the case it carried off",
          all(r.get("case_id") == ea_case for r in rows[-2:]), rows[-2:])
    check("...saying which output it was",
          [(r.get("detail") or {}).get("format") for r in rows[-2:]]
          == ["pdf", "receipt"],
          [(r.get("detail") or {}).get("format") for r in rows[-2:]])

    # ── federfall-qt96.7: coverage — the control that replaces a catch-all ──
    # Every emitter in this log is hand-written, which buys readable events and
    # costs the guarantee a blind record.* sweep would have given: a collection
    # added next year is silently unaudited, and nothing complains. This is
    # what complains. Adding a collection now fails here until someone decides,
    # in writing, whether it is audited or deliberately not.
    #
    # The audited set is READ OUT OF lib_audit.js rather than mirrored here on
    # purpose — a copy would keep passing after someone removed a collection
    # from the real map.
    print("\n[audit coverage]")

    # Why each of these is deliberately unaudited.
    NOT_AUDITED = {
        "audit_events": "the log itself — append-only, and unwritable by rule",
        "geocode_cache": "a cache of upstream responses; no human acts on it",
        "idempotency_keys": "internal replay protection, written by the route",
        # federfall-by7w.6, decided: NOT audited. Its rules are null, so the
        # only writer that could ever reach a request hook is a superuser in
        # the PocketBase dashboard — and an event there would sit next to the
        # animal.updated that caused the move, reading as a duplicate of it.
        "aviary_stays": "derived from animals.current_aviary by its own hook; "
                        "the move is audited as that animal.updated, and a "
                        "dashboard write is deliberately not a second event",
    }

    lib = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "pb_hooks", "lib_audit.js")
    with open(lib, encoding="utf-8") as fh:
        lib_src = fh.read()
    block = lib_src[lib_src.index("const COLLECTION_ACTIONS = {"):]
    block = block[:block.index("\n};")]
    audited = set(re.findall(r"^  ([a-z_]+): \{", block, re.M))
    registry = set(re.findall(r'^  [A-Z0-9_]+: "([a-z0-9_]+\.[a-z0-9_]+)",',
                              lib_src, re.M))
    # If either parse breaks, everything below would pass vacuously.
    check("the emitter registry is readable (parse guard)",
          len(audited) >= 15 and len(registry) >= 40,
          f"{len(audited)} collections, {len(registry)} actions")

    # The app side of the same contract, read out of the renderer itself for the
    # federfall-g5ap checks further down. auditFieldLabel() falls back to the
    # raw column name, so "has a label" means "is named in this switch".
    labels_dart = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "..", "..", "..", "apps", "federfall", "lib",
                               "features", "admin", "audit", "audit_labels.dart")
    with open(labels_dart, encoding="utf-8") as fh:
        labels_src = fh.read()
    field_label_fn = labels_src[labels_src.index("String auditFieldLabel("):]
    field_label_fn = field_label_fn[:field_label_fn.index("\n}\n")]
    dart_field_labels = set(re.findall(r"'([a-zA-Z_0-9]+)'", field_label_fn))
    check("the app's field-label table is readable (parse guard)",
          len(dart_field_labels) >= 30, len(dart_field_labels))

    s, cols = req("GET", "/api/collections?perPage=200", T)
    base = [c["name"] for c in cols["items"]
            if c["type"] != "view" and not c["name"].startswith("_")]
    check("the schema has collections to check (parse guard)",
          len(base) >= 25, len(base))
    unclassified = [n for n in base
                    if n not in audited and n not in NOT_AUDITED]
    check("every collection is either audited or explicitly exempt",
          not unclassified,
          "unclassified: " + ", ".join(sorted(unclassified))
          + " — add an emitter in lib_audit.js's COLLECTION_ACTIONS, "
            "or an entry with a reason in this test's NOT_AUDITED")
    stale = [n for n in list(audited) + list(NOT_AUDITED)
             if n not in base]
    check("nothing is classified that no longer exists",
          not stale, "stale: " + ", ".join(sorted(stale)))

    # federfall-by7w.4 — the control that was missing, and the reason four
    # actions shipped recording nothing at all: the check above asserts every
    # collection is AUDITED, never that its events SAY anything. An event that
    # cannot tell you what it was about is not worth the row it occupies.
    #
    # Informative = names its subject, or names its case, or records what
    # changed, or carries a typed payload. Any ONE of those is enough.
    s, d = req("GET", "/api/collections/audit_events/records?perPage=500",
               toks["sup"])
    all_rows = d["items"] if s == 200 else []

    # Deliberately unrecordable: everything about a finder is withheld on
    # purpose (finder_retention.pb.js scrubs their PII on a schedule, and a
    # copy of it here would outlive the scrub). Such a row can only ever say
    # THAT a finder record was touched, by id.
    UNINFORMATIVE_BY_DESIGN = {
        "finder.created", "finder.deleted", "finder.orphan_deleted",
    }

    def informative(r):
        return bool(r.get("subject_label") or r.get("case_label")
                    or r.get("changes") or r.get("detail"))

    empty_actions = sorted({
        r["action"] for r in all_rows
        if not informative(r) and r["action"] not in UNINFORMATIVE_BY_DESIGN
    })
    check("the sweep saw a representative slice of the log (parse guard)",
          len(all_rows) >= 50 and len({r["action"] for r in all_rows}) >= 20,
          f"{len(all_rows)} rows, "
          f"{len({r['action'] for r in all_rows})} distinct actions")
    check("no event is too empty to be worth reading",
          not empty_actions,
          "these say nothing about what they were: " + ", ".join(empty_actions)
          + " — give them a subject label (lib_audit.js LABEL_FIELDS/"
            "LABEL_RELATIONS), content (CONTENT_FIELDS) or a typed detail")

    # federfall-g5ap — the readability contract on the UPDATE path, which
    # nothing checked. `CONTENT_FIELDS` is an ALLOWLIST and covers creates and
    # deletes only; `diff()` is a DENYLIST (IGNORED_FIELDS + SENSITIVE +
    # FREE_TEXT), so an update can surface ANY column of an audited collection.
    # Two things must then hold for every one of those columns:
    #
    #   A. a relation resolves to a snapshotted label — an id in a row nobody
    #      can interpret is the exact failure this design exists to prevent, and
    #      `cases.admission_reasons` shipped that way for want of this check;
    #   B. the field has a translated name in the app, or the line reads as its
    #      raw SQLite column name.
    #
    # The LIVE SCHEMA is the source of truth rather than a list mirrored in this
    # file, which is why the check lives here and not in audit_labels_test.dart:
    # adding a column to an audited collection is what has to fail the build,
    # and only a running PocketBase knows the columns.
    def js_block(src, decl, end="\n};"):
        blk = src[src.index(decl):]
        return blk[:blk.index(end)]

    def js_map_of_lists(src, name):
        blk = js_block(src, f"const {name} = {{")
        return {m.group(1): re.findall(r'"([a-z_0-9]+)"', m.group(2))
                for m in re.finditer(r"(\w+): \[([^\]]*)\]", blk, re.S)}

    relation_targets = dict(re.findall(
        r'(\w+):\s*"([a-z_0-9]+)"',
        js_block(lib_src, "const RELATION_TARGETS = {")))
    relation_fields = {
        m.group(1): dict(re.findall(r'(\w+):\s*"([a-z_0-9]+)"', m.group(2)))
        for m in re.finditer(
            r"(\w+):\s*\{([^}]*)\}",
            js_block(lib_src, "const RELATION_FIELDS = {"), re.S)
    }
    label_fields = js_map_of_lists(lib_src, "LABEL_FIELDS")
    sensitive = js_map_of_lists(lib_src, "SENSITIVE")
    # Both keyed by FIELD NAME rather than by collection, so they are flat lists.
    free_text = re.findall(r'"([a-zA-Z_0-9]+)"',
                           js_block(lib_src, "const FREE_TEXT = [", "\n];"))
    ignored = re.findall(r'"([a-zA-Z_]+)"',
                         js_block(lib_src, "const IGNORED_FIELDS = [", "\n];"))
    check("the emitter's field tables are readable (parse guard)",
          len(relation_targets) >= 20 and len(label_fields) >= 10
          and len(ignored) >= 3 and len(free_text) >= 1,
          f"{len(relation_targets)} relation targets, "
          f"{len(label_fields)} label maps, {len(ignored)} ignored, "
          f"{len(free_text)} free-text maps")

    # A finder is never named in the log, whichever direction the relation is
    # reached from (lib_audit.js's header) — so this one field is EXPECTED to
    # carry a bare id, and labelOf() refuses to resolve it even if asked.
    # …plus an examination, which has no name to snapshot: LABEL_FIELDS could
    # only offer a date, and a label must be neutral text. A finding is located
    # by its case and its examiner.
    # `microscopy_findings.sample`: same reason as exam_findings.exam — a
    # sample has no name of its own (LABEL_FIELDS could only offer a date, and
    # a label must be neutral text), so a finding is located by its case and
    # its sample type instead.
    RELATION_UNLABELLED_BY_DESIGN = {("cases", "finder"),
                                     ("exam_findings", "exam"),
                                     ("microscopy_findings", "sample")}

    # Prose that IS logged verbatim, on purpose: a code list's `description` is
    # a supervisor's own definition of a diagnosis or a drug — org configuration,
    # not a record about a bird or a person, and worth reading back in full.
    PROSE_LOGGED_ON_PURPOSE = {"description"}
    # A text column that can hold a paragraph is prose (federfall-g5ap). The
    # threshold is what separates `notes` (1000+) from a short structured string
    # like `where_holding` or `city`, which the annual report prints anyway.
    PROSE_MAX = 1000

    fields_of = {c["name"]: c.get("fields", []) for c in cols["items"]}
    bare_relations, untranslated, unlabelable, prose = [], [], [], []
    for coll in sorted(audited):
        for f in fields_of.get(coll, []):
            name = f["name"]
            if name in ignored or f.get("system"):
                continue
            if (f["type"] == "text" and (f.get("max") or 0) >= PROSE_MAX
                    and name not in free_text
                    and name not in sensitive.get(coll, [])
                    and name not in PROSE_LOGGED_ON_PURPOSE):
                prose.append(f"{coll}.{name} (max {f.get('max')})")
            if f["type"] == "relation":
                target = (relation_fields.get(coll, {}).get(name)
                          or relation_targets.get(name))
                if not target and (coll, name) not in \
                        RELATION_UNLABELLED_BY_DESIGN:
                    bare_relations.append(f"{coll}.{name}")
                # A target with no LABEL_FIELDS entry makes labelOf() return ""
                # for every row — the table would look wired up and never
                # produce a single label.
                elif target and not label_fields.get(target):
                    unlabelable.append(f"{coll}.{name} → {target}")
            # Redacted fields still render their NAME ("Notiz: geändert (Wert
            # nicht protokolliert)"), so they need a translation as much as any
            # other — only the value is withheld.
            if name not in dart_field_labels:
                untranslated.append(f"{coll}.{name}")

    check("no free prose is copied into the log",
          not prose,
          "an edit would store the old AND new text of: " + ", ".join(prose)
          + " — add the field to lib_audit.js's FREE_TEXT, or to this test's "
            "PROSE_LOGGED_ON_PURPOSE with the reason it is safe to keep")
    check("every relation an audited collection can log resolves to a label",
          not bare_relations,
          "these would log a bare id: " + ", ".join(bare_relations)
          + " — add the field to lib_audit.js's RELATION_TARGETS (or "
            "RELATION_FIELDS where the name means different things in "
            "different collections)")
    check("every relation target can actually produce a label",
          not unlabelable,
          "no LABEL_FIELDS entry for: " + ", ".join(unlabelable))
    check("every field an audited collection can log has a translated name",
          not untranslated,
          "these render as their raw column name: " + ", ".join(untranslated)
          + " — add them to auditFieldLabel in "
            "apps/federfall/lib/features/admin/audit/audit_labels.dart")

    # The other half of the contract: `action` is TEXT, so nothing at write
    # time stops a typo'd action string from being stored — the app would
    # render it as an unknown line forever. Everything this whole suite
    # produced must be in the registry.
    s, d = req("GET", "/api/collections/audit_events/records?perPage=500",
               toks["sup"])
    seen = sorted({r["action"] for r in (d["items"] if s == 200 else [])})
    check("the suite exercised a good part of the registry (parse guard)",
          len(seen) >= 15, f"only {len(seen)} distinct actions")
    check("every action ever emitted is in the registry",
          all(a in registry for a in seen),
          "not registered: " + ", ".join(a for a in seen if a not in registry))

    # ── federfall-0tf: geocode proxy guards ─────────────────────────────────
    # Runs LAST: the flood exhausts the geocode rate budget for this client IP,
    # so nothing may query the geocode routes after this block. All requests
    # here fail input validation (no/overlong q), so no upstream geocoder is
    # ever contacted — the rate limiter counts them regardless, because it runs
    # as middleware before the handler.
    # ── the relation sweep (federfall-v9ap's class, enumerated) ──────────────
    # Three separate holes of ONE shape have now been found one at a time — a
    # relation field that no rule constrains, on a collection whose rules were
    # written to be about something else: federfall-piu5 (`weights.case` /
    # `markings.applied_in_case`), the `cases.animal` half of it, and
    # federfall-v9ap (`animal` on the three record collections). Each was found by
    # somebody probing, not by looking. This block is the looking.
    #
    # It reads the LIVE schema and requires every relation field on every
    # client-writable collection to be classified below. A new collection, or a
    # new relation on an existing one, fails this block until somebody decides
    # what authorises its target — which is the whole point, and the same stance
    # `[audit coverage]` takes for emitters.
    #
    #   frozen    an isset guard on updateRule; verified against the live rule
    #   actor     pinned by authorship.pb.js from the authenticated caller
    #   hook:<f>  a named hook validates the INCOMING target
    #   mutable   changeable by design; the string says why, and by whom
    #
    # The caveat the `mutable` rows used to share — only `animal` was checked
    # for ORG, so every other one could name a row in a DIFFERENT organisation —
    # is closed (federfall-jo1l): org_scope.pb.js checks EVERY relation whose
    # target collection carries an `org`. That is asserted from the schema below
    # rather than believed, in both directions: a classification claiming the
    # hook must name a target the hook actually looks at, and a plain `mutable`
    # must name one it does not — otherwise the registry has drifted away from
    # the guard, which is the failure this whole block exists to prevent.
    print("\n[relation guards]")
    RELATION_GUARDS = {
        "admission_reasons": {"org": "frozen"},
        "animals": {"org": "frozen", "current_aviary": "frozen"},
        "aviaries": {
            # 1700000086 widened aviaries.update to the keeper, so "the whole
            # rule is coordinator/supervisor" no longer carries this field: the
            # rule now names `keeper` itself, admitting it from a keeper only
            # while it still names them. Reassignment stays a coordinator
            # action — see the [aviary keeper] block for both directions.
            "keeper": "hook:org_scope.pb.js — mutable: reassigning a keeper is "
                      "a coordinator action, guarded in-rule since 1700000086",
            "org": "frozen",
        },
        "case_conditions": {
            "case": "frozen",
            "condition": "hook:org_scope.pb.js — mutable: correcting a "
                         "diagnosis, onto the org code list",
            "org": "frozen",
        },
        "case_shares": {
            "case": "frozen",
            "shared_with": "frozen",
            "shared_by": "actor",
            "org": "frozen",
        },
        "cases": {
            "animal": "frozen",
            "admitted_by": "actor",
            "finder": "frozen",
            "active_carer": "hook:org_scope.pb.js — mutable: THE handoff; "
                            "caseEdit-gated and derived by the placements hook",
            "org": "frozen",
            "admission_reasons": "hook:org_scope.pb.js — mutable: correcting "
                                 "intake reasons, onto the org code list",
        },
        "conditions": {"org": "frozen"},
        "dispositions": {
            "case": "frozen",
            "performed_by": "actor",
            "aviary": "hook:org_scope.pb.js — mutable: correcting which "
                      "enclosure a placement named (feeds current_aviary — "
                      "federfall-j163 / federfall-mpm4)",
            "org": "frozen",
        },
        "egg_records": {
            "animal": "hook:org_scope.pb.js + hook:animal_custody_scope.pb.js",
            "author": "actor",
            "org": "frozen",
        },
        # 1700000087. The mirror image of egg_records above: `animal` is FROZEN
        # because re-attributing a shot is not a feature, so the incoming value
        # never has to be checked at all.
        "vaccinations": {
            "animal": "frozen",
            "author": "actor",
            "route": "hook:org_scope.pb.js — mutable: correcting a route, "
                     "like every other route relation here",
            "org": "frozen",
        },
        "exam_findings": {"exam": "frozen", "org": "frozen"},
        "exams": {
            "case": "frozen",
            "animal": "frozen",
            "examiner": "actor",
            "org": "frozen",
        },
        "finders": {"org": "frozen"},
        "follow_ups": {"case": "frozen", "created_by": "actor", "org": "frozen"},
        "journal_entries": {
            "case": "frozen",
            "author": "actor",
            "org": "frozen",
            "aviary": "frozen",
        },
        "marking_types": {"org": "frozen"},
        "markings": {
            "animal": "frozen",
            "applied_by": "actor",
            "applied_in_case": "frozen",
            "org": "frozen",
            "type": "hook:org_scope.pb.js — mutable: correcting a ring type, "
                    "onto the org code list",
        },
        "medication_administrations": {
            "case": "frozen",
            "medication": "frozen",
            "administered_by": "actor",
            "org": "frozen",
            "route": "hook:org_scope.pb.js — mutable: correcting a route, "
                     "onto the org code list",
        },
        "medication_products": {
            "route": "hook:org_scope.pb.js — mutable: correcting a route, "
                     "onto the org code list",
            "org": "frozen",
        },
        "medication_routes": {"org": "frozen"},
        "medications": {
            "case": "frozen",
            "org": "frozen",
            "route": "hook:org_scope.pb.js — mutable: correcting a route, "
                     "onto the org code list",
        },
        "microscopy_finding_types": {"org": "frozen"},
        "microscopy_findings": {
            "sample": "frozen",
            "finding_type": "hook:org_scope.pb.js — mutable: correcting a "
                            "finding, onto the org code list",
            "org": "frozen",
        },
        "microscopy_samples": {
            "case": "frozen",
            # Not authorship-pinned, and deliberately not: `examiner` names WHO
            # READ THE SLIDE, which is routinely somebody else (the vet), and
            # microscopy_sheet.dart sends it as an ordinary field. `author` is
            # set by the route from the session (microscopy.pb.js:200); a direct
            # create could spoof it, and that confers nothing, because
            # microscopy delete is case-scoped rather than author-based — unlike
            # weights / egg_records, where the author gets delete rights.
            "examiner": "hook:org_scope.pb.js — mutable: a recorded fact, not "
                        "the actor",
            "author": "hook:org_scope.pb.js — mutable: route-owned; confers "
                      "nothing (delete is case-scoped)",
            "org": "frozen",
        },
        "placements": {
            "case": "frozen",
            "carer": "hook:org_scope.pb.js — mutable: the placement's own "
                     "subject",
            "from_user": "hook:org_scope.pb.js — mutable: the placement's own "
                         "subject",
            "to_user": "hook:org_scope.pb.js — mutable: THE handoff target; "
                       "the placements hook derives case.active_carer from it",
            "org": "frozen",
        },
        "quarantine_records": {"case": "frozen", "set_by": "actor",
                               "org": "frozen"},
        # federfall-5s5j — both frozen (1700000085). A re-point would push a
        # sponsor's contact details into another keeper's view with nothing
        # warning about it; the ONE intended route is moving the bird, and the
        # disposition sheet says so before it happens.
        "sponsorships": {"animal": "frozen", "org": "frozen"},
        "users": {
            "org": "frozen",
            "invited_by": "hook:org_scope.pb.js — mutable: supervisor-only "
                          "collection (users.update)",
        },
        "vet_appointments": {"case": "frozen", "created_by": "actor",
                             "org": "frozen"},
        "weights": {
            "case": "frozen",
            "author": "actor",
            "org": "frozen",
            "animal": "frozen",
        },
    }

    # `actor` is not asserted from a list here — it is READ OUT of
    # lib_authorship.js, so a field classified as pinned has to actually be the
    # one that hook pins (same stance as [audit coverage] reading lib_audit.js).
    auth_src = open(
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "pb_hooks", "lib_authorship.js"),
        encoding="utf-8",
    ).read()
    actor_block = re.search(r"ACTOR_FIELDS = \{(.*?)\n\};", auth_src, re.S)
    check("the authorship registry is readable (parse guard)",
          actor_block is not None)
    ACTOR_OF = dict(re.findall(r'(\w+):\s*"(\w+)"',
                               actor_block.group(1) if actor_block else ""))
    check("...and names a plausible number of collections",
          len(ACTOR_OF) >= 10, ACTOR_OF)

    # ...and `hook:org_scope.pb.js` is read out of the hook the same way — the
    # classification is a claim about a file, so the file has to exist and still
    # be registered for EVERY collection. A tag list added there later would
    # quietly narrow the scope every row below asserts, and nothing else would
    # notice: the hook would simply stop firing.
    # Read defensively: a DELETED hook is the failure mode this is here to
    # catch, and it should be one loud red line rather than a traceback that
    # takes the rest of the suite with it.
    try:
        org_src = open(
            os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "pb_hooks", "org_scope.pb.js"),
            encoding="utf-8",
        ).read()
    except OSError:
        org_src = ""
    check("org_scope.pb.js is there and calls the shared check",
          "foreignRelation" in org_src, "not found")
    check("...on create and on update, for every collection",
          len(re.findall(r"onRecord(?:Create|Update)\(\(e\) => \{", org_src)) == 2
          and not re.search(r"\}\)\s*,\s*\"", org_src), org_src[:0])

    s, all_colls = req("GET", "/api/collections?perPage=200", T)
    check("the schema is readable (parse guard)",
          s == 200 and len(((all_colls or {}).get("items") or [])) > 20,
          f"status {s}")

    # org_scope.pb.js's own scope, read the way the hook reads it: a relation is
    # checked exactly when its TARGET collection carries an `org`. Knowing that
    # here is what lets a classification be verified instead of believed.
    org_scoped = {c["name"] for c in (all_colls or {}).get("items", [])
                  if any(f["name"] == "org" for f in c.get("fields", []))}
    by_id = {c["id"]: c["name"] for c in (all_colls or {}).get("items", [])}
    check("the schema names org-scoped collections (parse guard)",
          len(org_scoped) >= 15, sorted(org_scoped))

    swept = 0
    unclassified = []
    not_really_frozen = []
    not_really_actor = []
    not_really_hooked = []
    silently_covered = []
    gone = []
    for c in (all_colls or {}).get("items", []):
        name = c["name"]
        if c.get("system") or name.startswith("_") or c.get("type") == "view":
            continue
        # Client-writable means a client can send a body at all. A collection
        # with both rules null is hook-only (aviary_stays, audit_events,
        # idempotency_keys) and nothing here applies to it.
        if c.get("createRule") is None and c.get("updateRule") is None:
            continue
        rels = {f["name"]: by_id.get(f.get("collectionId"), "")
                for f in c.get("fields", []) if f.get("type") == "relation"}
        if not rels:
            continue
        swept += 1
        known = RELATION_GUARDS.get(name, {})
        update_rule = str(c.get("updateRule") or "")
        for field, target in rels.items():
            how = known.get(field)
            if how is None:
                unclassified.append(f"{name}.{field}")
            elif how == "frozen":
                if f"@request.body.{field}:isset = false" not in update_rule:
                    not_really_frozen.append(f"{name}.{field}")
            elif how == "actor" and ACTOR_OF.get(name) != field:
                not_really_actor.append(
                    f"{name}.{field} (authorship pins {ACTOR_OF.get(name)!r})")
            # Both directions of the org-scope claim (federfall-jo1l). Naming
            # the hook for a field it does not look at is a false assurance;
            # NOT naming it for one it does look at means the registry has gone
            # stale against a guard that is silently doing the work.
            if "hook:org_scope.pb.js" in str(how) and target not in org_scoped:
                not_really_hooked.append(f"{name}.{field} → {target or '?'}")
            elif ("hook:org_scope.pb.js" not in str(how)
                    and str(how).startswith("mutable")
                    and target in org_scoped):
                silently_covered.append(f"{name}.{field} → {target}")
        # Nothing classified that no longer exists — a stale entry is a claim
        # about a field nobody checks any more.
        gone += [f"{name}.{f}" for f in known if f not in rels]

    check("the sweep saw the whole schema (parse guard)", swept >= 20,
          f"only {swept} collections swept")
    check("every relation on a client-writable collection is classified",
          not unclassified,
          "classify each as frozen / actor / hook:<file> / mutable:<why> in "
          f"RELATION_GUARDS: {unclassified}")
    check("every field classified `frozen` really is guarded",
          not not_really_frozen,
          f"classified frozen, but no isset guard: {not_really_frozen}")
    check("every field classified `actor` really is the pinned one",
          not not_really_actor, not_really_actor)
    check("every field classified `hook:org_scope.pb.js` is in that hook's scope",
          not not_really_hooked,
          "the hook only checks relations whose target carries an `org`, so "
          f"this claims a guard nothing performs: {not_really_hooked}")
    check("every mutable relation into an org-scoped collection says so",
          not silently_covered,
          "org_scope.pb.js already checks these; classify them "
          f"`hook:org_scope.pb.js — mutable: <why>`: {silently_covered}")
    check("no classification names a field that is gone", not gone, gone)
    stale = [n for n in RELATION_GUARDS
             if n not in {c["name"] for c in (all_colls or {}).get("items", [])}]
    check("no classification names a collection that is gone", not stale, stale)

    # ── the other half of a freeze: the CLIENT (federfall-t7ad) ─────────────
    # An `:isset = false` guard refuses a body that so much as MENTIONS the
    # field — resending its unchanged value is refused exactly like re-pointing
    # it. And a failed UPDATE rule is a 404, not a 403, so the symptom is "not
    # found" on the record the user is looking at, which reads as data loss
    # rather than as a permission answer.
    #
    # Every block above tests a freeze from the attacker's side (a re-point is
    # refused). None tested it from the app's: `aviary_form_sheet.dart` and
    # `disposition_sheet.dart` each built ONE body for create and update, so
    # every aviary edit and every outcome correction 404'd for coordinators and
    # supervisors alike, from 1700000083 and 1700000043 respectively. The suite
    # missed it because every aviary PATCH here uses the SUPERUSER token, and a
    # superuser bypasses access rules entirely — so the guard was never on.
    #
    # Hence: these PATCH as ordinary members, and assert the SHAPE the client
    # sends (frozen fields on create only) rather than any single field's value.
    print("\n[frozen fields vs. the client]")

    # A freeze the registry above does not describe: it only classifies
    # RELATIONS, and `animals.lifetime_status` (1700000077) is an enum. Listed
    # rather than derived, so a new non-relation freeze fails here until
    # somebody states it and checks the client for it.
    NON_RELATION_FROZEN = {
        "animals": {"lifetime_status": "derived by lib_derive.js; the client "
                                       "never writes it"},
    }
    # Not every isset guard is a freeze. Two are written
    # `isset = false || <escape>`, which admits an UNCHANGED value while
    # refusing a re-point — the shape to reach for whenever the client's form
    # sends the field as a matter of course, because a hard freeze there is the
    # 404 this whole block exists for. The escape is asserted, not just
    # declared: tightening one of these into a real freeze breaks a form.
    CONDITIONAL_GUARDS = {
        ("aviaries", "keeper"): "@request.body.keeper = @request.auth.id",
        ("users", "org"): "@request.body.org = @request.auth.org",
    }
    unstated = []
    escape_gone = []
    for c in (all_colls or {}).get("items", []):
        name = c["name"]
        if c.get("system") or name.startswith("_") or c.get("type") == "view":
            continue
        rule = str(c.get("updateRule") or "")
        frozen = set(re.findall(r"@request\.body\.(\w+):isset = false", rule))
        conditional = {f for (coll, f) in CONDITIONAL_GUARDS if coll == name}
        stated = ({f for f, how in RELATION_GUARDS.get(name, {}).items()
                   if how == "frozen"}
                  | set(NON_RELATION_FROZEN.get(name, {}))
                  | conditional)
        unstated += [f"{name}.{f}" for f in sorted(frozen - stated)]
        for field in sorted(conditional):
            if CONDITIONAL_GUARDS[(name, field)] not in rule:
                escape_gone.append(f"{name}.{field}")
    check("every isset-guarded field is a stated freeze",
          not unstated,
          "a new guard nothing describes — state it, and check no client "
          f"update body sends it: {unstated}")
    check("every conditional guard still lets the unchanged value through",
          not escape_gone,
          "the `|| <escape>` half is gone, so this is now a hard freeze — and "
          f"the form that sends the field will 404: {escape_gone}")

    # 1. aviaries — the reported bug. Coordinator AND supervisor: both may edit.
    fz_av = mk(T, "aviaries", {"name": "Voliere Frozen", "keeper": SUP,
                               "org": ORG, "capacity": 4})["id"]
    fz_body = {"name": "Voliere Frozen", "keeper": SUP, "location": "",
               "capacity": 9, "active": True, "notes": ""}
    s, _ = req("PATCH", f"/api/collections/aviaries/records/{fz_av}",
               toks["coord"], fz_body)
    check("coordinator can change an aviary's capacity", s == 200,
          f"status {s} — the client body must not carry `org`")
    s, _ = req("PATCH", f"/api/collections/aviaries/records/{fz_av}",
               toks["sup"], dict(fz_body, capacity=10))
    check("supervisor can change an aviary's capacity", s == 200, f"status {s}")
    s, _ = req("PATCH", f"/api/collections/aviaries/records/{fz_av}",
               toks["sup"], dict(fz_body, org=ORG))
    check("...and mentioning `org` at all is still refused (404, not 403)",
          s == 404, f"status {s}")

    # 2. dispositions — the same defect, found alongside it. The carer of the
    # case corrects an outcome that moves the bird nowhere, so custody is not
    # what is being tested here (disposition_custody.pb.js has its own block).
    fz_animal = mk(T, "animals", {"species": "Stadttaube", "org": ORG})["id"]
    fz_case = mk(T, "cases", {"animal": fz_animal, "active_carer": A,
                              "org": ORG, "admitted_at": stamp(days=-3)})["id"]
    fz_disp = mk(T, "dispositions", {
        "case": fz_case, "org": ORG, "type": "released", "performed_by": A,
        "disposed_at": stamp(days=-1), "release_location": "Wald"})["id"]
    fz_dpath = f"/api/collections/dispositions/records/{fz_disp}"
    fz_dbody = {"type": "released", "performed_by": A,
                "disposed_at": stamp(days=-1), "reason": "",
                "release_location": "Waldrand", "release_type": "",
                "transfer_type": "", "transfer_destination": "", "aviary": "",
                "vet": "", "vet_signed_off": False}
    s, _ = req("PATCH", fz_dpath, toks["a"], fz_dbody)
    check("the carer can correct an outcome's release location", s == 200,
          f"status {s} — the client body must not carry `case` or `org`")
    s, _ = req("PATCH", fz_dpath, toks["a"], dict(fz_dbody, case=fz_case))
    check("...and mentioning `case` at all is still refused", s == 404,
          f"status {s}")
    s, _ = req("PATCH", fz_dpath, toks["a"], dict(fz_dbody, org=ORG))
    check("...and mentioning `org` at all is still refused", s == 404,
          f"status {s}")

    # ── an enclosure's keeper may edit it (1700000086) ──────────────────────
    # `keeper` stopped being a label in 1700000076/77: it is write authority
    # over every resident, the right to place a bird there, and the reader of
    # those birds' patronages. So the keeper edits the enclosure's own facts.
    # What they may not do is hand it over — that gives another member custody
    # of the residents AND the sponsors' names, addresses and mobiles.
    #
    # The refusals below are 404s, not 403s: a failed UPDATE rule is a "not
    # found" (see the block above), which is also why "keeper is unchanged" is
    # re-read from the record rather than inferred from the status.
    print("\n[aviary keeper]")
    kp_av = mk(T, "aviaries", {"name": "Voliere Keeper", "keeper": A,
                               "org": ORG, "capacity": 6})["id"]
    kp_path = f"/api/collections/aviaries/records/{kp_av}"
    # The body aviary_form_sheet.dart sends: every field including `keeper`,
    # which is required and therefore always present.
    kp_body = {"name": "Voliere Keeper", "keeper": A, "location": "Hof",
               "capacity": 12, "active": True, "notes": ""}

    s, _ = req("PATCH", kp_path, toks["a"], kp_body)
    check("the keeper can edit their own aviary", s == 200, f"status {s}")
    check("...including its capacity",
          (req("GET", kp_path, toks["a"])[1] or {}).get("capacity") == 12)
    s, _ = req("PATCH", kp_path, toks["b"], dict(kp_body, capacity=3))
    check("a member who keeps nothing here CANNOT edit it", s == 404,
          f"status {s}")

    # The handover, refused: `keeper` may be sent, but only naming the sender.
    s, _ = req("PATCH", kp_path, toks["a"], dict(kp_body, keeper=B))
    check("the keeper CANNOT hand the aviary to somebody else", s == 404,
          f"status {s}")
    check("...and nothing of that request landed",
          (req("GET", kp_path, T)[1] or {}).get("keeper") == A)
    # Not even by naming a coordinator, i.e. it is the ACT that is refused
    # rather than the target being unworthy.
    s, _ = req("PATCH", kp_path, toks["a"], dict(kp_body, keeper=COORD))
    check("...not even to a coordinator", s == 404, f"status {s}")

    # Everything the widening deliberately did NOT touch.
    s, _ = req("POST", "/api/collections/aviaries/records", toks["a"],
               {"name": "Neue Voliere", "keeper": A, "org": ORG})
    check("the keeper still CANNOT create an aviary", s != 200, f"status {s}")
    s, _ = req("DELETE", kp_path, toks["a"])
    check("the keeper still CANNOT delete one", s == 404, f"status {s}")
    s, _ = req("PATCH", kp_path, toks["a"], dict(kp_body, org=ORG))
    check("`org` is still frozen for the keeper too", s == 404, f"status {s}")

    # The coordinator's half: reassignment, and what it costs the old keeper.
    s, _ = req("PATCH", kp_path, toks["coord"], dict(kp_body, keeper=B))
    check("a coordinator CAN hand the aviary to another keeper", s == 200,
          f"status {s}")
    s, _ = req("PATCH", kp_path, toks["a"], dict(kp_body, keeper=A))
    check("the former keeper cannot take it back", s == 404, f"status {s}")
    s, _ = req("PATCH", kp_path, toks["b"], dict(kp_body, keeper=B,
                                                 capacity=7))
    check("the new keeper can edit it", s == 200, f"status {s}")

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
    # The reverse route has a budget of its own, and it needs the prefix label
    # to bind: while that label was unqualified it lost to the factory "/api/"
    # rule, so reverse lookups ran on the general 300-per-10s default — the one
    # route where a loop actually reaches the upstream geocoder per request,
    # since a moving pin misses the cache every time.
    statuses = []
    for _ in range(45):
        s, _ = req("GET", "/api/federfall/geocode/reverse", toks["a"])
        statuses.append(s)
    check("sustained reverse-geocode traffic hits the rate limit too (429)",
          429 in statuses, f"statuses {sorted(set(statuses))}")

    # ── report render budget (federfall-ds0d) ───────────────────────────────
    # Every report request starts a `typst` process, so an authenticated loop
    # over the case report is a CPU exhaustion primitive. What has to be proven
    # here is not that the rule is STORED — the [rate limiting] block at the top
    # already read it out of settings — but that a PREFIX label actually binds
    # to a path with a record id in the middle of it. Runs last, and lowers the
    # budget to 2/minute for the duration, so proving it costs two renders
    # rather than twenty.
    print("\n[report rate limit]")
    s, rst = req("GET", "/api/settings", T)
    rrules = ((rst or {}).get("rateLimits") or {}).get("rules") or []
    lowered = False
    for r in rrules:
        if str(r.get("label")) == "GET /api/federfall/cases/":
            r["maxRequests"], r["duration"] = 2, 60
            lowered = True
    check("setup: the report budget is there to lower", lowered, rrules)
    s, _ = req("PATCH", "/api/settings", T,
               {"rateLimits": {"enabled": True, "rules": rrules}})
    check("setup: report budget lowered to 2 per minute", s == 200, f"status {s}")
    rstatuses = []
    for _ in range(6):
        rs, _, _ = req_bytes("GET", f"/api/federfall/cases/{case}/report.pdf",
                             toks["a"])
        rstatuses.append(rs)
    check("the budget's own renders go through", rstatuses[0] == 200,
          f"first {rstatuses[0]}")
    check("sustained report rendering hits the rate limit (429)",
          429 in rstatuses, f"statuses {rstatuses}")

    # ── summary ─────────────────────────────────────────────────────────────
    print(f"\n{'='*50}\n{_passed} passed, {_failed} failed")
    sys.exit(1 if _failed else 0)


if __name__ == "__main__":
    main()
