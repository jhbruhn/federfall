#!/usr/bin/env python3
"""federfall-qt96.12 — the retention crons, observed actually running.

Driven by run_cron.sh, which provisions a throwaway instance whose
`auditRetention`, `finderPiiRetention` and `sponsorshipRetention` jobs are due
every minute. Standalone otherwise, against an instance patched the same way:

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


def finder_of_closed_case(token, org):
    """A finder whose only case has just ENDED, in [org] — i.e. one whose
    retention window is running from this moment.

    `cases.finder` is locked against client writes (1700000044) and written
    only by the intake route; rules do not apply to a superuser, so this can
    set it directly rather than driving intake for a fixture.
    """
    animal = mk(token, "animals", {"species": "Stadttaube", "org": org})["id"]
    finder = mk(token, "finders", {
        "first_name": "Anna", "last_name": "Finderin",
        "phone": "0151 000000", "email": "anna@example.org",
        "notes": "am Bahnhof aufgesammelt",
        "city": "Oldenburg", "region": "Niedersachsen", "org": org,
    })["id"]
    case = mk(token, "cases", {"animal": animal, "org": org, "finder": finder})["id"]
    # The disposition hook closes the case; its `created` is the window's start
    # (never `disposed_at`, which a client could backdate).
    mk(token, "dispositions", {"case": case, "type": "released", "org": org})
    return finder


_seq = [0]


def row_seq():
    """A per-run counter, for fixture emails that have to be unique."""
    _seq[0] += 1
    return _seq[0]


def finder_row(token, finder_id):
    s, d = req("GET", f"/api/collections/finders/records/{finder_id}", token)
    return d if s == 200 else {}


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

    # ── finder PII retention ────────────────────────────────────────────
    # federfall-jumi: this window was read with record.get() on a json field,
    # which hands the JSVM a byte array — so `finder_retention_years` was
    # ALWAYS undefined and every org silently got the 2-year default. Nothing
    # in test_rules.py can reach a cron, so this is the only place that can
    # tell a working settings read from a broken one. Two orgs for exactly
    # that reason: with one, the default and a working read agree.
    print("\n[finder PII retention cron]")

    # The key here is the one the ORG-SETTINGS SCREEN writes —
    # `finderRetentionMonths`, in months (org_settings_providers.dart). Writing
    # the hook's own spelling instead would prove the decode and nothing else:
    # a window a supervisor can set but the cron cannot read is worse than no
    # window at all, and that is exactly the bug this fixture exists to catch.
    scrub_org = mk(T, "organisations", {
        "name": "Scrub Now", "settings": {"finderRetentionMonths": 0.000001},
    })["id"]
    keep_org = mk(T, "organisations", {
        "name": "Keep Long", "settings": {"finderRetentionMonths": 1200},
    })["id"]
    # A self-hoster who hand-set the older, documented years key keeps it.
    legacy_org = mk(T, "organisations", {
        "name": "Legacy Key", "settings": {"finder_retention_years": 0.000001},
    })["id"]

    doomed_finder = finder_of_closed_case(T, scrub_org)
    kept_finder = finder_of_closed_case(T, keep_org)
    legacy_finder = finder_of_closed_case(T, legacy_org)
    check("the probe finders hold PII to begin with (parse guard)",
          all(finder_row(T, f).get("first_name") == "Anna"
              for f in (doomed_finder, kept_finder, legacy_finder)),
          "a fixture finder was not created with its PII")

    print("  … waiting for the finder cron to fire (up to 100 s)")
    deadline = time.time() + 100
    while time.time() < deadline:
        if finder_row(T, doomed_finder).get("pii_purged"):
            break
        time.sleep(2)

    scrubbed = finder_row(T, doomed_finder)
    check("the cron anonymised the finder past its org's window",
          scrubbed.get("pii_purged") is True,
          "still holding PII — the job never fired, or the window was ignored")
    check("...clearing identity, contact and the freeform notes",
          all(not scrubbed.get(f) for f in
              ("first_name", "last_name", "phone", "email", "notes")),
          {f: scrubbed.get(f) for f in
           ("first_name", "last_name", "phone", "email", "notes")})
    # The location is deliberately kept: non-identifying, and it is what feeds
    # "where do birds come from".
    check("...but keeping the non-identifying location",
          scrubbed.get("city") == "Oldenburg"
          and scrubbed.get("region") == "Niedersachsen", scrubbed)

    # The whole point of the two orgs: a 100-year window must still be honoured
    # a minute later. If the settings read is broken this row gets the 2-year
    # default — which also keeps it — so the assertion above is what catches a
    # broken read, and this one catches a window that is ignored in the other
    # direction (scrubbing everything).
    survivor = finder_row(T, kept_finder)
    check("an organisation with a long window keeps its finder's PII",
          survivor.get("pii_purged") is False
          and survivor.get("first_name") == "Anna", survivor)

    # The pre-app key still works, so upgrading does not quietly extend an
    # instance's retention window back to the default.
    check("a window set under the older years key is still honoured",
          finder_row(T, legacy_finder).get("pii_purged") is True,
          finder_row(T, legacy_finder))

    # ── sponsorship orphan retention ────────────────────────────────────────
    # federfall-5s5j.1: `sponsorships.animal` does NOT cascade, on purpose — a
    # donation record must not be destroyed with the bird it documented. What is
    # left is an orphan holding a sponsor's name, address and mobile that no
    # keeper can even read (the predicate resolves through
    # `animal.current_aviary`), so it is deleted after the org's window.
    #
    # Two orgs again, and for the reason above: the window comes out of a JSON
    # field through lib_org.js, and a single-org test cannot tell a working
    # settings read from a silent fall-through to the 24-month default.
    print("\n[sponsorship retention cron]")

    # Both halves of the grace period, the way app_theme_fallbacks_test pins its
    # two: run_cron.sh removed it in the COPY (a 24 h window measured from a
    # server-owned autodate is unreachable in a test), so the committed file is
    # read here to make sure the real one still has it. Without this, deleting
    # the constant outright would make every assertion below pass.
    hook_src = open(
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "..", "pb_hooks", "sponsorship_retention.pb.js"),
        encoding="utf-8",
    ).read()
    check("the shipped cron still holds a fresh orphan for a day",
          "const ORPHAN_GRACE_MS = 24 * 60 * 60 * 1000;" in hook_src,
          "the grace period is gone from the committed hook — a sponsorship "
          "written moments before its animal can now be mistaken for an orphan")

    sp_purge_org = mk(T, "organisations", {
        "name": "Patenschaft Purge",
        "settings": {"sponsorshipRetentionMonths": 0.000001},
    })["id"]
    sp_keep_org = mk(T, "organisations", {
        "name": "Patenschaft Keep",
        "settings": {"sponsorshipRetentionMonths": 1200},
    })["id"]

    def sponsorship_in(org, orphan):
        """A sponsorship in [org]; [orphan] deletes its animal afterwards.

        Rules do not apply to a superuser, so `current_aviary` (isset-guarded
        against clients since 1700000075) and the create-gate hook's keeper
        requirement are both bypassed here — this is a fixture, not a probe of
        those guards; test_rules.py's `[sponsorships]` block owns them.
        """
        # `aviaries.keeper` is required since 1700000076, and it must live in
        # the same org (org_scope.pb.js) — so each fixture enclosure gets its
        # own keeper rather than borrowing one.
        keeper = mk(T, "users", {
            "email": f"keeper-{row_seq()}@f.local",
            "password": "Pass12345!", "passwordConfirm": "Pass12345!",
            "role": "carer", "org": org, "is_active": True, "verified": True,
        })["id"]
        aviary = mk(T, "aviaries", {"name": f"V-{org[:6]}", "keeper": keeper,
                                    "org": org})["id"]
        animal = mk(T, "animals", {"species": "Stadttaube",
                                   "current_aviary": aviary, "org": org})["id"]
        row = mk(T, "sponsorships", {
            "animal": animal, "sponsor_name": "Marlene Wolf",
            "mobile": "0170 1234567", "city": "Oldenburg", "org": org,
        })["id"]
        if orphan:
            req("DELETE", f"/api/collections/animals/records/{animal}", T)
        return row

    def sponsorship_exists(row_id):
        s, _ = req("GET", f"/api/collections/sponsorships/records/{row_id}", T)
        return s == 200

    sp_doomed = sponsorship_in(sp_purge_org, orphan=True)
    sp_long_window = sponsorship_in(sp_keep_org, orphan=True)
    # The branch that matters most: a bird that still exists keeps its patronage
    # however short the org's window is. A cron that ignored this would delete
    # live donation records on a schedule.
    sp_live = sponsorship_in(sp_purge_org, orphan=False)
    check("the probe sponsorships exist to begin with (parse guard)",
          all(sponsorship_exists(r)
              for r in (sp_doomed, sp_long_window, sp_live)),
          "a fixture sponsorship was not created")

    print("  … waiting for the sponsorship cron to fire (up to 100 s)")
    deadline = time.time() + 100
    while time.time() < deadline:
        if not sponsorship_exists(sp_doomed):
            break
        time.sleep(2)

    check("the cron deleted the orphan past its org's window",
          not sponsorship_exists(sp_doomed),
          "still present — the job never fired, or the window was ignored")
    check("an organisation with a long window keeps its orphan",
          sponsorship_exists(sp_long_window),
          "deleted despite a 100-year window — the settings read is broken in "
          "the other direction")
    check("a patronage whose bird still exists is never touched",
          sponsorship_exists(sp_live), "a live donation record was deleted")

    # The deleted row's id is the only remaining evidence it existed, so the
    # sweep records it — as the cron, with no sponsor detail in sight.
    s, d = req("GET", "/api/collections/audit_events/records"
                      "?perPage=50&filter=" + urllib.parse.quote(
                          f'subject_id = "{sp_doomed}"'), T)
    sp_rows = d["items"] if s == 200 else []
    check("...and said so in the audit log",
          any(r.get("action") == "sponsorship.deleted" for r in sp_rows),
          sp_rows)
    check("...attributed to the cron, and marked as an orphan sweep",
          any(r.get("actor_kind") == "cron"
              and (r.get("detail") or {}).get("orphan") is True
              for r in sp_rows),
          [(r.get("actor_kind"), r.get("detail")) for r in sp_rows])
    sp_blob = json.dumps(sp_rows)
    check("...naming no sponsor",
          "Marlene" not in sp_blob and "0170" not in sp_blob
          and "Oldenburg" not in sp_blob, sp_blob[:300])

    print(f"\n{'=' * 50}\n{_passed} passed, {_failed} failed")
    sys.exit(1 if _failed else 0)


if __name__ == "__main__":
    main()
