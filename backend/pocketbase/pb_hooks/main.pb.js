/// <reference path="../pb_data/types.d.ts" />

// FED-1.12 — server-side hooks (the backend logic layer).
//
//   1. cases on create: auto per-year `case_number` (e.g. "2026-014") and
//      default `status`; after create, a default 14-day quarantine_records row.
//   2. dispositions on create: maintain the parent case `status` and the
//      animal `lifetime_status` / `current_aviary`.
//   3. cases on update: share-on-handoff — when `active_carer` changes, the
//      previous carer keeps read access via an automatic case_share.
//   4. placements on create: a record with `to_user` set IS a handoff — the
//      case's `active_carer` is updated in the same transaction.
//   5. users on update: field guard — a non-supervisor may not change
//      role / org / is_active / verified on any user (incl. themselves).
//   6. users on update/delete: lockout guard — the last active supervisor of
//      an org cannot be demoted, deactivated, moved or deleted.
//
// NOTE: each hook callback runs in its own isolated PocketBase JSVM, so
// top-level helpers/constants are NOT in scope inside a handler — any shared
// logic must be defined inside the callback that uses it.

// ── 1. cases: case_number + status on create ───────────────────────────────────
onRecordCreate((e) => {
  const rec = e.record;
  const orgId = rec.get("org");
  const admittedStr = rec.getString("admitted_at");
  const pad3 = (n) => String(n).padStart(3, "0");

  // Auto per-year case number, scoped to the org (federfall-4k4).
  //
  // The max is derived NUMERICALLY in SQL — a lexicographic sort breaks at
  // 1000 ("2026-999" > "2026-1000" as strings, so every create that year
  // would recompute seq 1000 and die on the unique index). The LIKE pattern
  // is anchored at the start so a manual number like "ALT-2026-1" (which
  // CONTAINS "2026-") can't pollute the lookup. NOTE: the year is the UTC
  // year of admitted_at (tracked separately: org-local timezone).
  //
  // Concurrency: this hook runs inside the save transaction. The no-op
  // UPDATE grabs SQLite's write lock BEFORE the max is read, so a second
  // concurrent create blocks here and then sees the first one's committed
  // number instead of racing to the same seq. The unique index on
  // case_number stays as the final guard.
  if (!rec.getString("case_number")) {
    const year = admittedStr ? admittedStr.substring(0, 4) : String(new Date().getFullYear());
    const prefix = year + "-";
    if (orgId) {
      e.app
        .db()
        .newQuery("UPDATE organisations SET updated = updated WHERE id = {:org}")
        .bind({ org: orgId })
        .execute();
    }
    const row = new DynamicModel({ max_seq: 0 });
    e.app
      .db()
      .newQuery(
        "SELECT COALESCE(MAX(CAST(substr(case_number, {:start}) AS INTEGER)), 0) AS max_seq " +
          "FROM cases WHERE org = {:org} AND case_number LIKE {:pattern}",
      )
      .bind({ start: prefix.length + 1, org: orgId, pattern: prefix + "%" })
      .one(row);
    rec.set("case_number", prefix + pad3(row.max_seq + 1));
  }

  if (!rec.getString("status")) {
    rec.set("status", "in_care");
  }

  e.next();
}, "cases");

// ── 1b. cases: default 14-day quarantine as a timeline record ───────────────────
// Quarantine is a timeline kind (quarantine_records), not a case field, so the
// default initial quarantine is a real row created after the case exists —
// mirroring how the intake weight is a real `weights` row. Backdated to
// admission so it sits at the admission point on the chronology. Idempotent: a
// case that somehow already has a quarantine row gets no second default.
onRecordAfterCreateSuccess((e) => {
  const caseRec = e.record;
  const existing = e.app.findRecordsByFilter(
    "quarantine_records", "case = {:c}", "", 1, 0, { c: caseRec.id },
  );
  if (existing.length === 0) {
    // PocketBase returns datetimes space-separated ("2026-03-10 09:00:00.000Z");
    // normalise to ISO 8601 so the JS Date constructor can parse them.
    const parseDate = (s) => new Date(String(s).replace(" ", "T"));
    const admittedStr = caseRec.getString("admitted_at");
    const base = admittedStr ? parseDate(admittedStr) : new Date();

    // Default duration is org-configurable (org.settings.quarantineDefaultDays);
    // fall back to 14 days when unset or invalid. The app overrides this per
    // case by updating this record after intake, so this also covers cases
    // created outside the app (Admin UI / import).
    let days = 14;
    const orgId = caseRec.get("org");
    if (orgId) {
      try {
        const org = e.app.findRecordById("organisations", orgId);
        const settings = org.get("settings");
        const v = settings && settings.quarantineDefaultDays;
        const n = parseInt(v, 10);
        if (!isNaN(n) && n > 0) days = n;
      } catch (_) {
        // No org / no settings — keep the 14-day fallback.
      }
    }
    const until = new Date(base.getTime() + days * 24 * 60 * 60 * 1000);

    const rec = new Record(e.app.findCollectionByNameOrId("quarantine_records"));
    rec.set("case", caseRec.id);
    rec.set("quarantine_until", until.toISOString());
    rec.set("set_at", base.toISOString());
    const carer = caseRec.get("active_carer");
    if (carer) rec.set("set_by", carer);
    rec.set("org", caseRec.get("org"));
    e.app.save(rec);
  }

  e.next();
}, "cases");

// ── 2. dispositions: maintain case.status + animal.lifetime_status ─────────────
onRecordAfterCreateSuccess((e) => {
  const disp = e.record;
  const type = disp.getString("type");
  const caseId = disp.get("case");

  if (caseId) {
    const caseRec = e.app.findRecordById("cases", caseId);

    // Every disposition — including placed_in_aviary — closes (disposes) the
    // case: the animal is well enough to leave acute care. Aviary placement
    // additionally makes the animal a resident (lifetime_status=in_aviary,
    // current_aviary set below); a resident that later falls ill gets a NEW
    // case rather than reopening this one.
    caseRec.set("status", "disposed");
    e.app.save(caseRec);

    const animalId = caseRec.get("animal");
    if (animalId) {
      const animal = e.app.findRecordById("animals", animalId);
      let lifetime = "";
      switch (type) {
        case "died":
        case "euthanized":
          lifetime = "deceased";
          break;
        case "placed_in_aviary":
          lifetime = "in_aviary";
          break;
        case "released":
        case "returned_to_owner":
        case "transferred":
          // No longer in our care, presumed alive (the 4-state lifetime model
          // folds these into "at large").
          lifetime = "at_large_released";
          break;
      }
      if (lifetime) animal.set("lifetime_status", lifetime);
      animal.set("current_aviary", type === "placed_in_aviary" ? disp.get("aviary") : "");
      e.app.save(animal);
    }
  }

  e.next();
}, "dispositions");

// ── 2b. dispositions: re-derive case.status + animal lifetime on update/delete ──
// Editing or deleting a disposition (UX Phase B correction path) must keep the
// derived state honest: a deleted terminal disposition re-opens the case, and
// the animal's lifetime is recomputed from its latest REMAINING disposition
// across all its cases (so a returning bird falls back correctly). The helper
// is defined inside each callback because pb_hooks callbacks run in isolated
// JSVMs — file-level functions are not in scope. `created` is an ISO-ish
// string, so its lexicographic max is the latest disposition.
onRecordAfterUpdateSuccess((e) => {
  function reconcile(app, caseId) {
    if (!caseId) return;
    const caseRec = app.findRecordById("cases", caseId);
    const remaining = app.findRecordsByFilter(
      "dispositions", "case = {:c}", "-created", 200, 0, { c: caseId },
    );
    caseRec.set("status", remaining.length > 0 ? "disposed" : "in_care");
    app.save(caseRec);
    const animalId = caseRec.get("animal");
    if (!animalId) return;
    const cases = app.findRecordsByFilter(
      "cases", "animal = {:a}", "", 200, 0, { a: animalId },
    );
    let latest = null;
    for (const c of cases) {
      const disps = app.findRecordsByFilter(
        "dispositions", "case = {:c}", "-created", 200, 0, { c: c.id },
      );
      for (const d of disps) {
        if (!latest || d.getString("created") > latest.getString("created")) {
          latest = d;
        }
      }
    }
    const animal = app.findRecordById("animals", animalId);
    let lifetime = "in_care";
    let aviary = "";
    if (latest) {
      switch (latest.getString("type")) {
        case "died":
        case "euthanized":
          lifetime = "deceased";
          break;
        case "placed_in_aviary":
          lifetime = "in_aviary";
          aviary = latest.get("aviary");
          break;
        case "released":
        case "returned_to_owner":
        case "transferred":
          lifetime = "at_large_released";
          break;
      }
    }
    animal.set("lifetime_status", lifetime);
    animal.set("current_aviary", aviary);
    app.save(animal);
  }
  reconcile(e.app, e.record.get("case"));
  e.next();
}, "dispositions");

onRecordAfterDeleteSuccess((e) => {
  function reconcile(app, caseId) {
    if (!caseId) return;
    const caseRec = app.findRecordById("cases", caseId);
    const remaining = app.findRecordsByFilter(
      "dispositions", "case = {:c}", "-created", 200, 0, { c: caseId },
    );
    caseRec.set("status", remaining.length > 0 ? "disposed" : "in_care");
    app.save(caseRec);
    const animalId = caseRec.get("animal");
    if (!animalId) return;
    const cases = app.findRecordsByFilter(
      "cases", "animal = {:a}", "", 200, 0, { a: animalId },
    );
    let latest = null;
    for (const c of cases) {
      const disps = app.findRecordsByFilter(
        "dispositions", "case = {:c}", "-created", 200, 0, { c: c.id },
      );
      for (const d of disps) {
        if (!latest || d.getString("created") > latest.getString("created")) {
          latest = d;
        }
      }
    }
    const animal = app.findRecordById("animals", animalId);
    let lifetime = "in_care";
    let aviary = "";
    if (latest) {
      switch (latest.getString("type")) {
        case "died":
        case "euthanized":
          lifetime = "deceased";
          break;
        case "placed_in_aviary":
          lifetime = "in_aviary";
          aviary = latest.get("aviary");
          break;
        case "released":
        case "returned_to_owner":
        case "transferred":
          lifetime = "at_large_released";
          break;
      }
    }
    animal.set("lifetime_status", lifetime);
    animal.set("current_aviary", aviary);
    app.save(animal);
  }
  reconcile(e.app, e.record.get("case"));
  e.next();
}, "dispositions");

// ── 3. cases: share-on-handoff (previous carer keeps read) ─────────────────────
onRecordUpdate((e) => {
  const rec = e.record;
  const oldCarer = rec.original().get("active_carer");
  const newCarer = rec.get("active_carer");

  e.next(); // persist the case update first

  if (oldCarer && oldCarer !== newCarer) {
    // Don't clobber an existing share (e.g. an edit share) for the old carer.
    const existing = e.app.findRecordsByFilter(
      "case_shares",
      "case = {:c} && shared_with = {:u}",
      "",
      1,
      0,
      { c: rec.id, u: oldCarer },
    );
    if (existing.length === 0) {
      const share = new Record(e.app.findCollectionByNameOrId("case_shares"));
      share.set("case", rec.id);
      share.set("shared_with", oldCarer);
      share.set("access", "read");
      share.set("org", rec.get("org"));
      e.app.save(share);
    }
  }
}, "cases");

// ── 4. placements: a handoff record drives the carer change ────────────────────
// federfall-h5m: the client used to create the placements (chain-of-custody)
// record and THEN update cases.active_carer — if the second call failed, the
// log claimed a from→to transfer that never happened. Deriving the carer
// change from the placement inside the SAME transaction makes the handoff
// atomic: either both persist or neither does. `from_user` is also pinned to
// the case's actual current carer, so the log stays honest even when the
// client's view of the case was stale. The cases update hook (§3) then leaves
// the previous carer a read share, still in-transaction.
onRecordCreate((e) => {
  const toUser = e.record.getString("to_user");
  const caseId = e.record.getString("case");
  let caseRec = null;
  if (toUser && caseId) {
    caseRec = e.app.findRecordById("cases", caseId);
    const current = caseRec.getString("active_carer");
    if (current) e.record.set("from_user", current);
  }

  e.next(); // persist the placement first (validation may still reject it)

  if (caseRec && caseRec.getString("active_carer") !== toUser) {
    caseRec.set("active_carer", toUser);
    e.app.save(caseRec);
  }
}, "placements");

// ── 5. users: field guard against privilege escalation ─────────────────────────
// Lets self-service profile edits (name/phone/avatar) through once the
// updateRule is widened to self, while blocking role/org/is_active/verified
// changes by anyone who isn't a supervisor (or superuser).
onRecordUpdateRequest((e) => {
  if (!e.hasSuperuserAuth()) {
    const auth = e.auth;
    const isSupervisor = auth && auth.getString("role") === "supervisor";
    if (!isSupervisor) {
      const orig = e.record.original();
      for (const field of ["role", "org", "is_active", "verified"]) {
        if (String(e.record.get(field)) !== String(orig.get(field))) {
          throw new ForbiddenError("You are not allowed to change '" + field + "'.", null);
        }
      }
    }
  }

  // ── 6. lockout guard (federfall-0kl) ──────────────────────────────────────
  // Nothing above stops a supervisor (or a dashboard superuser) from demoting
  // or deactivating the LAST active supervisor of an org, which locks everyone
  // out of user management. Recovery exists (bootstrap_supervisor.pb.js), but
  // prevention beats cure: block any update that would leave the org without
  // an active supervisor. Moving the last supervisor to another org counts as
  // losing them too. Promote or activate a replacement first.
  {
    const orig = e.record.original();
    const wasActiveSup =
      orig.getString("role") === "supervisor" && orig.getBool("is_active");
    const staysActiveSup =
      e.record.getString("role") === "supervisor" &&
      e.record.getBool("is_active") &&
      e.record.getString("org") === orig.getString("org");
    if (wasActiveSup && !staysActiveSup) {
      const others = e.app.findRecordsByFilter(
        "users",
        "role = 'supervisor' && is_active = true && org = {:org} && id != {:id}",
        "",
        1,
        0,
        { org: orig.getString("org"), id: e.record.id },
      );
      if (others.length === 0) {
        throw new BadRequestError(
          "This is the organisation's last active supervisor — promote or " +
            "activate another supervisor first.",
          null,
        );
      }
    }
  }

  e.next();
}, "users");

// The same lockout applies to deleting the last active supervisor outright.
onRecordDeleteRequest((e) => {
  const rec = e.record;
  if (rec.getString("role") === "supervisor" && rec.getBool("is_active")) {
    const others = e.app.findRecordsByFilter(
      "users",
      "role = 'supervisor' && is_active = true && org = {:org} && id != {:id}",
      "",
      1,
      0,
      { org: rec.getString("org"), id: rec.id },
    );
    if (others.length === 0) {
      throw new BadRequestError(
        "This is the organisation's last active supervisor — promote or " +
          "activate another supervisor first.",
        null,
      );
    }
  }
  e.next();
}, "users");
