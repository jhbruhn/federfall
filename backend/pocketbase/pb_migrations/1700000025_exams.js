/// <reference path="../pb_data/types.d.ts" />

// FED-4.8 — structured exam. A repeatable clinical record on a case (intake
// exam + later re-exams), modelled relationally:
//   - exams: one row per exam. Typed top-line vitals (body_condition,
//     hydration, mentation) live here; `animal` is denormalized (like weights)
//     so the animal lifetime view can aggregate exams across cases.
//   - exam_findings: the open-ended by-system part — one sparse row per system
//     actually ASSESSED (mirrors case_conditions as a child of cases). Adding a
//     body system is a `system` value change, never a schema migration.
//
// Access is case-private clinical (same stance as follow_ups / case_conditions),
// NOT the org-wide weights/markings stance: findings (mentation, body systems)
// are sensitive case detail. exam_findings is a grandchild, so its rules
// traverse `exam.case`. The multi-level relation traversal in those rules needs
// verifying against a live stack (backend/pocketbase/tests/test_rules.py).

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const animals = app.findCollectionByNameOrId("animals");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    // ── exams ───────────────────────────────────────────────────────────────
    app.save(
      new Collection({
        type: "base",
        name: "exams",
        fields: [
          {
            name: "case",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: cases.id,
            cascadeDelete: true,
          },
          // Denormalized from the case so the animal lifetime view aggregates
          // exams across cases (like weights).
          {
            name: "animal",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: animals.id,
            cascadeDelete: true,
          },
          { name: "examined_at", type: "date", required: false },
          {
            name: "examiner",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: users.id,
          },
          // Keel / pectoral condition score, 1 (emaciated) .. 5 (obese).
          {
            name: "body_condition",
            type: "number",
            required: false,
            min: 1,
            max: 5,
            onlyInt: true,
          },
          {
            name: "hydration",
            type: "select",
            required: false,
            maxSelect: 1,
            values: ["normal", "mild", "moderate", "severe"],
          },
          // Attitude / mentation: BAR -> QAR -> depressed -> non-responsive.
          {
            name: "mentation",
            type: "select",
            required: false,
            maxSelect: 1,
            values: ["bright", "quiet", "depressed", "unresponsive"],
          },
          { name: "notes", type: "text", required: false, max: 2000 },
          {
            name: "org",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: organisations.id,
          },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
          { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
        ],
      }),
    );

    // ── exam_findings (one sparse row per assessed body system) ──────────────
    const exams = app.findCollectionByNameOrId("exams");
    app.save(
      new Collection({
        type: "base",
        name: "exam_findings",
        fields: [
          {
            name: "exam",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: exams.id,
            cascadeDelete: true,
          },
          {
            name: "system",
            type: "select",
            required: true,
            maxSelect: 1,
            values: [
              "eyes",
              "beak_nares",
              "oral",
              "integument",
              "wings",
              "legs_feet",
              "keel",
              "respiratory",
              "coelom",
              "neuro",
              "vent",
            ],
          },
          {
            name: "status",
            type: "select",
            required: true,
            maxSelect: 1,
            values: ["normal", "abnormal"],
          },
          { name: "note", type: "text", required: false, max: 2000 },
          {
            name: "org",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: organisations.id,
          },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
          { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
        ],
      }),
    );

    // ── access rules ─────────────────────────────────────────────────────────
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

    // exams: case-private clinical, keyed on `case` (cf. follow_ups).
    const examView = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const examEdit = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;

    const exam = app.findCollectionByNameOrId("exams");
    exam.listRule = examView;
    exam.viewRule = examView;
    exam.createRule = examEdit;
    exam.updateRule = examEdit;
    exam.deleteRule = examEdit;
    app.save(exam);

    // exam_findings: grandchild — traverse `exam.case`.
    const findView = `${AUTH} && exam.case.org = @request.auth.org && (exam.case.active_carer = @request.auth.id || ${COORD_SUP} || exam.case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const findEdit = `${AUTH} && exam.case.org = @request.auth.org && (exam.case.active_carer = @request.auth.id || ${SUP} || (exam.case.case_shares_via_case.shared_with ?= @request.auth.id && exam.case.case_shares_via_case.access ?= "edit"))`;

    const findings = app.findCollectionByNameOrId("exam_findings");
    findings.listRule = findView;
    findings.viewRule = findView;
    findings.createRule = findEdit;
    findings.updateRule = findEdit;
    findings.deleteRule = findEdit;
    app.save(findings);
  },
  (app) => {
    // exam_findings references exams → delete it first.
    app.delete(app.findCollectionByNameOrId("exam_findings"));
    app.delete(app.findCollectionByNameOrId("exams"));
  },
);
