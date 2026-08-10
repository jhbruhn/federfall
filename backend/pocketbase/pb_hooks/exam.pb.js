/// <reference path="../pb_data/types.d.ts" />

// federfall-lov0 — atomic exam save.
//
// The exam sheet used to persist an exam and its per-system findings as
// separate client calls: create exam → create N findings, or (on edit) update
// exam → delete ALL old findings → re-create the new set. In an online-only
// app a network drop mid-sequence permanently lost the clinical findings (the
// deletes had already committed), and a failed create left a duplicate exam on
// retry. This route does the whole save in ONE server-side transaction, same
// stance as /api/federfall/intake: any failure rolls everything back.
//
// Request (JSON):
//   id          existing exam id → update (findings are REPLACED as a set)
//   case        case id (create only; on update it comes from the exam)
//   animal      animal id (create only; denormalized like weights)
//   exam        whitelisted exam fields (full-replace: omitted = cleared, so
//               un-assessing a vital on edit actually clears it)
//   findings    [{system, status, note}] — the complete assessed set
//   weight_g    optional (create only): a real `weights` timeline row taken
//               at the exam, like the intake weight
//
// org and examiner always come from the authenticated user / existing record;
// permission mirrors the exams create/update rule (case-private clinical:
// active carer OR edit-share OR supervisor, same org).
routerAdd(
  "POST",
  "/api/federfall/exam",
  (e) => {
    // The boundary this route bypasses, stated once for every route that
    // bypasses one — see lib_auth.js.
    const org = require(`${__hooks}/lib_auth.js`).requireMember(e);
    // The gate above checks the caller; the per-case access check and the
    // examiner/author fields below still need their identity.
    const auth = e.auth;

    const body = e.requestInfo().body || {};
    const str = (v) => (v === undefined || v === null ? "" : String(v).trim());

    const examId = str(body.id);
    const examData =
      body.exam && typeof body.exam === "object" ? body.exam : {};
    const findings = Array.isArray(body.findings) ? body.findings : [];

    // Mirrors the exams create/update rule: `case.org = @request.auth.org &&
    // (case.active_carer = @request.auth.id || supervisor || edit-share)`.
    // The route bypasses collection rules, so it must enforce this itself.
    //
    // This is deliberately NOT also an animal-custody check (lib_custody.js,
    // federfall-q7ks.5): an exam is a CASE timeline record, and its `animal` is
    // only denormalized for the lifetime view — cross-org re-pointing is already
    // blocked by animal_org_scope.pb.js. Requiring custody of the bird here
    // would refuse a carer entering a late exam on their OWN closed case, which
    // is a correction the model has no reason to forbid.
    const assertCanEditCase = (tx, caseRec) => {
      if (caseRec.getString("org") !== org) {
        throw new BadRequestError("Unknown case.");
      }
      if (caseRec.getString("active_carer") === auth.id) return;
      if (auth.getString("role") === "supervisor") return;
      const shares = tx.findRecordsByFilter(
        "case_shares",
        "case = {:c} && shared_with = {:u} && access = 'edit'",
        "",
        1,
        0,
        { c: caseRec.id, u: auth.id },
      );
      if (shares.length === 0) {
        throw new ForbiddenError("Not allowed.");
      }
    };

    // Full-replace semantics for the whitelisted exam fields: the sheet always
    // sends the form's complete state, so an omitted field means "cleared".
    const FIELDS = [
      "examined_at",
      "body_condition",
      "hydration",
      "mentation",
      "temperature",
      "mm_color",
      "mm_texture",
      "notes",
    ];

    let saved = null;
    e.app.runInTransaction((tx) => {
      let rec;
      if (examId) {
        try {
          rec = tx.findRecordById("exams", examId);
        } catch (_) {
          throw new BadRequestError("Unknown exam.");
        }
        if (rec.getString("org") !== org) {
          throw new BadRequestError("Unknown exam.");
        }
        assertCanEditCase(tx, tx.findRecordById("cases", rec.getString("case")));
      } else {
        const caseId = str(body.case);
        const animalId = str(body.animal);
        if (!caseId || !animalId) {
          throw new BadRequestError("'case' and 'animal' are required.");
        }
        let caseRec;
        try {
          caseRec = tx.findRecordById("cases", caseId);
        } catch (_) {
          throw new BadRequestError("Unknown case.");
        }
        assertCanEditCase(tx, caseRec);
        // `animal` is denormalized onto the exam (lifetime view) — don't let
        // a stale/lying client point it at a foreign org's animal.
        let animalRec;
        try {
          animalRec = tx.findRecordById("animals", animalId);
        } catch (_) {
          throw new BadRequestError("Unknown animal.");
        }
        if (animalRec.getString("org") !== org) {
          throw new BadRequestError("Unknown animal.");
        }
        // ...nor at a DIFFERENT bird in the same org (federfall-v9ap). An exam
        // is about its case's animal by construction, and `exam_sheet.dart`
        // always sends the two together — but this route bypasses collection
        // rules, so 1700000079's custody predicate on the `weights` row it
        // writes below does not apply, and 1700000082's freeze cannot reach a
        // `tx.save()`. Without this line the route laundered a weight onto any
        // bird in the org: refused as a direct POST, accepted here.
        //
        // A consistency check rather than a custody one, deliberately: the
        // no-custody stance above is what lets a carer write up a late exam on
        // their OWN closed case, and this keeps that intact.
        if (animalId !== caseRec.getString("animal")) {
          throw new BadRequestError("That animal does not belong to this case.");
        }
        rec = new Record(tx.findCollectionByNameOrId("exams"));
        rec.set("case", caseId);
        rec.set("animal", animalId);
        rec.set("examiner", auth.id);
        rec.set("org", org);
      }

      for (const f of FIELDS) {
        rec.set(f, examData[f] === undefined ? null : examData[f]);
      }
      tx.save(rec);
      saved = rec;

      // Replace the findings as a set (the assessed set is small, so a clean
      // replace beats diffing) — atomically with the exam this time.
      for (const old of tx.findRecordsByFilter(
        "exam_findings",
        "exam = {:e}",
        "",
        0,
        0,
        { e: rec.id },
      )) {
        tx.delete(old);
      }
      for (const f of findings) {
        if (!f || typeof f !== "object") continue;
        const row = new Record(tx.findCollectionByNameOrId("exam_findings"));
        row.set("exam", rec.id);
        row.set("system", str(f.system));
        row.set("status", str(f.status));
        row.set("note", str(f.note));
        row.set("org", org);
        tx.save(row);
      }

      // Exam weight → a real weights row (single source of truth + trend).
      // Create-path only, so editing an exam can never duplicate it.
      if (!examId) {
        const weight = parseFloat(body.weight_g);
        if (!isNaN(weight) && weight > 0) {
          const w = new Record(tx.findCollectionByNameOrId("weights"));
          w.set("animal", rec.getString("animal"));
          w.set("case", rec.getString("case"));
          w.set("weight_g", weight);
          const measured = str(examData.examined_at);
          w.set("measured_at", measured || new Date().toISOString());
          w.set("author", auth.id);
          w.set("org", org);
          tx.save(w);
        }
      }

      // federfall-qt96.4 — one event for the exam and the findings it replaced
      // wholesale. Neither the exam nor its findings fire request hooks here
      // (all tx.save), and the per-finding rows would bury the one fact worth
      // reading: an examination happened and what it concluded.
      require(`${__hooks}/lib_audit.js`).emit(e, "exam.saved", {
        app: tx,
        org: org,
        subject: { collection: "exams", id: rec.id, label: "" },
        caseId: rec.getString("case"),
        refs: { animal: rec.getString("animal") },
        detail: {
          created: !examId,
          findings: findings.length,
          // The abnormal ones are the reason anybody reads an exam again.
          abnormal: findings.filter(
            (f) => f && typeof f === "object" && String(f.status) === "abnormal",
          ).length,
        },
      });
    });

    return e.json(200, { id: saved.id });
  },
  $apis.requireAuth(),
);
