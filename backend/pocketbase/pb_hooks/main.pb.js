/// <reference path="../pb_data/types.d.ts" />

// FED-1.12 — server-side hooks (the backend logic layer).
//
//   1. cases on create: auto per-year `case_number` (e.g. "2026-014"),
//      default `quarantine_until` (admitted_at + 14 days), default `status`.
//   2. dispositions on create: maintain the parent case `status` and the
//      animal `lifetime_status` / `current_aviary`.
//   3. cases on update: share-on-handoff — when `active_carer` changes, the
//      previous carer keeps read access via an automatic case_share.
//   4. users on update: field guard — a non-supervisor may not change
//      role / org / is_active / verified on any user (incl. themselves).
//
// NOTE: each hook callback runs in its own isolated PocketBase JSVM, so
// top-level helpers/constants are NOT in scope inside a handler — any shared
// logic must be defined inside the callback that uses it.

// ── 1. cases: case_number + quarantine_until + status on create ────────────────
onRecordCreate((e) => {
  const rec = e.record;
  const orgId = rec.get("org");
  const admittedStr = rec.getString("admitted_at");
  const pad3 = (n) => String(n).padStart(3, "0");
  // PocketBase returns datetimes space-separated ("2026-03-10 09:00:00.000Z");
  // normalise to ISO 8601 so the JS Date constructor can parse them.
  const parseDate = (s) => new Date(String(s).replace(" ", "T"));

  // Auto per-year case number, scoped to the org. The unique index on
  // case_number is the final guard against the rare concurrent-create race.
  if (!rec.getString("case_number")) {
    const year = admittedStr ? admittedStr.substring(0, 4) : String(new Date().getFullYear());
    let seq = 1;
    const existing = e.app.findRecordsByFilter(
      "cases",
      "org = {:org} && case_number ~ {:prefix}",
      "-case_number",
      1,
      0,
      { org: orgId, prefix: year + "-" },
    );
    if (existing.length > 0) {
      const n = parseInt(existing[0].getString("case_number").split("-")[1], 10);
      if (!isNaN(n)) seq = n + 1;
    }
    rec.set("case_number", year + "-" + pad3(seq));
  }

  // Quarantine defaults to admission + 14 days.
  if (!rec.getString("quarantine_until")) {
    const base = admittedStr ? parseDate(admittedStr) : new Date();
    rec.set("quarantine_until", new Date(base.getTime() + 14 * 24 * 60 * 60 * 1000).toISOString());
  }

  if (!rec.getString("status")) {
    rec.set("status", "in_care");
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

    // placed_in_aviary keeps the case alive as a resident; everything else is
    // a terminal outcome that disposes the case.
    if (type !== "placed_in_aviary") {
      caseRec.set("status", "disposed");
      e.app.save(caseRec);
    }

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

// ── 4. users: field guard against privilege escalation ─────────────────────────
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
  e.next();
}, "users");
