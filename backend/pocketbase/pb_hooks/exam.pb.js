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
    const auth = e.auth;
    if (
      !auth ||
      !auth.getBool("is_active") ||
      auth.getString("role") === "guest"
    ) {
      throw new ForbiddenError("Not allowed.");
    }
    const org = auth.getString("org");
    if (!org) {
      throw new ForbiddenError("No organisation.");
    }

    const body = e.requestInfo().body || {};
    const str = (v) => (v === undefined || v === null ? "" : String(v).trim());

    const examId = str(body.id);
    const examData =
      body.exam && typeof body.exam === "object" ? body.exam : {};
    const findings = Array.isArray(body.findings) ? body.findings : [];

    // Mirrors the exams create/update rule: `case.org = @request.auth.org &&
    // (case.active_carer = @request.auth.id || supervisor || edit-share)`.
    // The route bypasses collection rules, so it must enforce this itself.
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
    });

    return e.json(200, { id: saved.id });
  },
  $apis.requireAuth(),
);
