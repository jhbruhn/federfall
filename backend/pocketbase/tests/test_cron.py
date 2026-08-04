#!/usr/bin/env python3
"""federfall-qt96.12 — the audit retention cron, observed actually running.

Driven by run_cron.sh, which provisions a throwaway instance whose
`auditRetention` job is due every minute. Standalone otherwise, against an
instance you have patched the same way:

    FED_TEST_URL=http://localhost:8098 python3 test_cron.py

Why this is not in test_rules.py: a `cronAdd` job cannot be triggered through
the API, so that suite can only test the GUARD a purge has to satisfy — that a
fresh row refuses to be deleted and an expired one consents. Whether the job
itself ever deletes anything, honours each organisation's own window, or records
what it did was untested until this file existed.

The retention window is expressed in DAYS, and nothing can backdate a row
(`created` is an autodate the server owns). So the window is made
vanishingly small instead — 0.000001 days is 86 ms — which is the same trick
test_rules.py uses on the delete guard. The cutoff arithmetic under test is
identical either way; only the wait is shorter.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("FED_TEST_URL", "http://localhost:8098")
ADMIN_EMAIL = os.environ.get("FED_ADMIN_EMAIL", "admin@federfall.local")
ADMIN_PASS = os.environ.get("FED_ADMIN_PASS", "Admin12345!")
KEEP_ORG = "org00000default"  # seeded by 1700000001

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
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = token
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, headers=headers,
                               method=method)
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


def mk(token, coll, body):
    s, d = req("POST", f"/api/collections/{coll}/records", token, body)
    if s != 200:
        print(f"FATAL: failed to create {coll}: {s} {d}")
        sys.exit(2)
    return d


def audit_row(token, org, action="case.updated"):
    """One audit row in [org]. Superuser-only: the collection has no create
    rule, and a null rule admits nobody else."""
    return mk(token, "audit_events", {
        "org": org, "action": action, "actor_kind": "user",
        "actor_id": "usrcronprobe000", "actor_label": "Cron Probe",
        "subject_collection": "cases", "subject_id": "casecronprobe00",
        "subject_label": "2026-999", "severity": "info",
    })["id"]


def exists(token, row_id):
    s, _ = req("GET", f"/api/collections/audit_events/records/{row_id}", token)
    return s == 200


def main():
    s, d = req("POST", "/api/collections/_superusers/auth-with-password",
               body={"identity": ADMIN_EMAIL, "password": ADMIN_PASS})
    if s != 200:
        print("FATAL: cannot authenticate superuser", s, d)
        sys.exit(2)
    T = d["token"]

    print("\n[audit retention cron]")

    # Two organisations, two policies. The second one is the whole reason this
    # test is worth its wall-clock minute: the window is read out of a JSON
    # field, and `record.get()` on one of those hands the JSVM a BYTE ARRAY, so
    # `settings.audit_retention_days` reads as undefined and every org silently
    # falls back to the default (federfall-jumi — it disabled the configurable
    # windows in finder_retention.pb.js and main.pb.js exactly this way). A test
    # with one org could not tell a working settings read from a broken one.
    purge_org = mk(T, "organisations", {
        "name": "Purge Now", "settings": {"audit_retention_days": 0.000001},
    })["id"]
    req("PATCH", f"/api/collections/organisations/records/{KEEP_ORG}", T,
        {"settings": {"audit_retention_days": 0}})

    doomed = [audit_row(T, purge_org) for _ in range(3)]
    kept = [audit_row(T, KEEP_ORG) for _ in range(2)]
    check("the probe rows exist to begin with (parse guard)",
          all(exists(T, r) for r in doomed + kept), "some row was not created")

    # The job is due every minute; a boundary is at most ~60 s away, and the
    # purge itself is a handful of deletes. Poll rather than sleep blindly so a
    # working cron finishes in whatever time it takes.
    print("  … waiting for the cron to fire (up to 100 s)")
    deadline = time.time() + 100
    while time.time() < deadline:
        if not any(exists(T, r) for r in doomed):
            break
        time.sleep(2)

    check("the cron ran and purged everything past the window",
          not any(exists(T, r) for r in doomed),
          "rows still present — the job never fired, or it purged nothing")

    # 0 means keep forever, and it is the setting most likely to be silently
    # ignored: it is the one that has to survive a `days === 0` check rather
    # than fall through to the default 730.
    check("an organisation that opted out of retention keeps its rows",
          all(exists(T, r) for r in kept),
          "a keep-forever org was purged")

    # The purge is the only record that the deleted rows ever existed, so it has
    # to leave one — filed under the org it emptied, by the cron, as a notice.
    s, d = req("GET", "/api/collections/audit_events/records"
                      "?perPage=50&filter=" + urllib.parse.quote(
                          'action = "audit.purged"'), T)
    purges = [r for r in (d["items"] if s == 200 else [])
              if r.get("org") == purge_org]
    check("...and said so in the log it just emptied", len(purges) >= 1,
          "no audit.purged event")
    # Asserted over ALL of them, because a window this short means the purge
    # row is itself expired: a later tick deletes it and records that, so the
    # count is per run rather than cumulative.
    check("...attributed to the cron, not to a person",
          purges and all(p.get("actor_kind") == "cron" and not p.get("actor_id")
                         for p in purges),
          [(p.get("actor_kind"), p.get("actor_id")) for p in purges])
    check("...as a notice rather than routine noise",
          purges and all(p.get("severity") == "notice" for p in purges),
          [p.get("severity") for p in purges])
    check("...recording how many rows went and under which window",
          any((p.get("detail") or {}).get("count") == len(doomed)
              and (p.get("detail") or {}).get("retention_days") == 0.000001
              for p in purges),
          [p.get("detail") for p in purges])

    print(f"\n{'=' * 50}\n{_passed} passed, {_failed} failed")
    sys.exit(1 if _failed else 0)


if __name__ == "__main__":
    main()
