/// <reference path="../pb_data/types.d.ts" />

// FED-1.11 — API access rules: the security boundary. Implements
// private-by-default + opt-in sharing + handoff chain + supervisor oversight,
// scoped by org. PocketBase rules are enforced server-side, so this is the real
// boundary (not the UI).
//
// Model (requirements §7):
//   view a case  : active_carer  OR shared (any access)  OR coordinator/supervisor
//   edit a case  : active_carer  OR shared with access=edit  OR supervisor
//   create case  : any active member (must set self as active_carer)
//   code lists / user mgmt : supervisor-only
//   finders (PII): only users who can view a case that references the finder
//   animals + markings : org-wide readable — the shared identity layer that
//     re-identification depends on (privacy is enforced at the CASE level)
//
// Correlation note: the edit-share clause
//   (... shared_with ?= @request.auth.id && ... access ?= "edit")
// relies on PocketBase correlating both `?=` conditions to the SAME back-relation
// row. Verified empirically on PB 0.39.4 (a user with only a read share is
// correctly denied edit), so this does not leak a privilege escalation.
//
// Deferred: `users.updateRule` is supervisor-only for now. Self-service profile
// editing needs a field-guard hook (block role/org/is_active escalation by
// non-supervisors) before the rule can widen to self — tracked on FED-1.12.

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP = '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

    const setRules = (name, r) => {
      const c = app.findCollectionByNameOrId(name);
      c.listRule = r.list ?? null;
      c.viewRule = r.view ?? null;
      c.createRule = r.create ?? null;
      c.updateRule = r.update ?? null;
      c.deleteRule = r.delete ?? null;
      if (r.auth !== undefined) c.authRule = r.auth;
      app.save(c);
    };

    // ── organisations (the record's own id IS the org) ──────────────────────
    setRules("organisations", {
      list: `${AUTH} && id = @request.auth.org`,
      view: `${AUTH} && id = @request.auth.org`,
      create: null, // superuser only — single launch org
      update: `${AUTH} && ${SUP} && id = @request.auth.org`,
      delete: null,
    });

    // ── users (auth collection) ─────────────────────────────────────────────
    setRules("users", {
      list: `${AUTH} && org = @request.auth.org`,
      view: `${AUTH} && org = @request.auth.org`,
      create: `${AUTH} && ${SUP} && org = @request.auth.org`, // supervisor invites
      update: `${AUTH} && ${SUP} && org = @request.auth.org`, // self-edit deferred (FED-1.12)
      delete: `${AUTH} && ${SUP} && org = @request.auth.org`,
      auth: "is_active = true", // deactivated users cannot authenticate
    });

    // ── animals + markings: org-wide identity layer (re-identification) ─────
    for (const name of ["animals", "markings"]) {
      setRules(name, {
        list: `${AUTH} && org = @request.auth.org`,
        view: `${AUTH} && org = @request.auth.org`,
        create: `${AUTH} && org = @request.auth.org`,
        update: `${AUTH} && org = @request.auth.org`,
        delete: `${AUTH} && ${SUP} && org = @request.auth.org`,
      });
    }

    // ── conditions code list: read by all, managed by supervisors ───────────
    setRules("conditions", {
      list: `${AUTH} && org = @request.auth.org`,
      view: `${AUTH} && org = @request.auth.org`,
      create: `${AUTH} && ${SUP} && org = @request.auth.org`,
      update: `${AUTH} && ${SUP} && org = @request.auth.org`,
      delete: `${AUTH} && ${SUP} && org = @request.auth.org`,
    });

    // ── aviaries: read by all, managed by coordinator/supervisor ────────────
    setRules("aviaries", {
      list: `${AUTH} && org = @request.auth.org`,
      view: `${AUTH} && org = @request.auth.org`,
      create: `${AUTH} && org = @request.auth.org && ${COORD_SUP}`,
      update: `${AUTH} && org = @request.auth.org && ${COORD_SUP}`,
      delete: `${AUTH} && ${SUP} && org = @request.auth.org`,
    });

    // ── cases: private-by-default + shares + roles ──────────────────────────
    const caseView = `${AUTH} && org = @request.auth.org && (active_carer = @request.auth.id || ${COORD_SUP} || case_shares_via_case.shared_with ?= @request.auth.id)`;
    const caseEdit = `${AUTH} && org = @request.auth.org && (active_carer = @request.auth.id || ${SUP} || (case_shares_via_case.shared_with ?= @request.auth.id && case_shares_via_case.access ?= "edit"))`;
    setRules("cases", {
      list: caseView,
      view: caseView,
      create: `${AUTH} && org = @request.auth.org && active_carer = @request.auth.id`,
      update: caseEdit,
      delete: `${AUTH} && ${SUP} && org = @request.auth.org`,
    });

    // ── case child collections: visibility/edit follow the parent case ──────
    const childView = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const childEdit = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;
    for (const name of ["case_conditions", "weights", "medications", "journal_entries", "placements", "dispositions"]) {
      setRules(name, {
        list: childView,
        view: childView,
        create: childEdit,
        update: childEdit,
        delete: childEdit,
      });
    }

    // ── finders (PII): only users who can view a case referencing the finder ─
    // Created before any case links to them, so create is any active member.
    setRules("finders", {
      list: `${AUTH} && org = @request.auth.org && (${COORD_SUP} || cases_via_finder.active_carer ?= @request.auth.id || cases_via_finder.case_shares_via_case.shared_with ?= @request.auth.id)`,
      view: `${AUTH} && org = @request.auth.org && (${COORD_SUP} || cases_via_finder.active_carer ?= @request.auth.id || cases_via_finder.case_shares_via_case.shared_with ?= @request.auth.id)`,
      create: `${AUTH} && org = @request.auth.org`,
      update: `${AUTH} && org = @request.auth.org && (${COORD_SUP} || cases_via_finder.active_carer ?= @request.auth.id || (cases_via_finder.case_shares_via_case.shared_with ?= @request.auth.id && cases_via_finder.case_shares_via_case.access ?= "edit"))`,
      delete: `${AUTH} && ${SUP} && org = @request.auth.org`,
    });

    // ── case_shares: owner/supervisor manage; participants can see theirs ────
    setRules("case_shares", {
      list: `${AUTH} && org = @request.auth.org && (shared_with = @request.auth.id || shared_by = @request.auth.id || case.active_carer = @request.auth.id || ${COORD_SUP})`,
      view: `${AUTH} && org = @request.auth.org && (shared_with = @request.auth.id || shared_by = @request.auth.id || case.active_carer = @request.auth.id || ${COORD_SUP})`,
      create: `${AUTH} && org = @request.auth.org && shared_by = @request.auth.id && (case.active_carer = @request.auth.id || ${SUP})`,
      update: `${AUTH} && org = @request.auth.org && (case.active_carer = @request.auth.id || shared_by = @request.auth.id || ${SUP})`,
      delete: `${AUTH} && org = @request.auth.org && (case.active_carer = @request.auth.id || shared_by = @request.auth.id || ${SUP})`,
    });
  },
  (app) => {
    // Revert app collections to the superuser-only default (null rules) they had
    // immediately after their creating migrations.
    const nullRules = [
      "organisations", "animals", "markings", "conditions", "aviaries", "cases",
      "case_conditions", "weights", "medications", "journal_entries", "placements",
      "dispositions", "finders", "case_shares",
    ];
    for (const name of nullRules) {
      const c = app.findCollectionByNameOrId(name);
      c.listRule = null;
      c.viewRule = null;
      c.createRule = null;
      c.updateRule = null;
      c.deleteRule = null;
      app.save(c);
    }
    // Restore the PocketBase default `users` rules.
    const users = app.findCollectionByNameOrId("users");
    users.listRule = "id = @request.auth.id";
    users.viewRule = "id = @request.auth.id";
    users.createRule = "";
    users.updateRule = "id = @request.auth.id";
    users.deleteRule = "id = @request.auth.id";
    users.authRule = "";
    app.save(users);
  },
);
