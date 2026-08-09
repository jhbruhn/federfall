/// <reference path="../pb_data/types.d.ts" />

// federfall-kp7y — atomic microscopy save. Design: docs/MICROSCOPY_DESIGN.md.
//
// A microscopy record is a parent (`microscopy_samples`) plus a set of graded
// findings (`microscopy_findings`) that is replaced wholesale on every save.
// Written from the client that would be: create sample → create N findings, or
// on edit update sample → delete the old findings → re-create the new set. This
// app is online-only, so a network drop mid-sequence permanently loses the
// clinical findings (the deletes have already committed) and a failed create
// leaves a duplicate sample behind on retry. That is federfall-lov0, found on
// the exam sheet; this route exists so microscopy never repeats it. Any failure
// rolls everything back.
//
// Request — multipart with `@jsonPayload` + zero or more `attachments` files
// (the shape /api/federfall/intake already uses), or plain JSON when there is
// nothing to upload:
//
//   id                existing sample id → update; absent → create
//   case              case id (create only; on update it comes from the record)
//   sample            whitelisted sample fields (full-replace: an omitted field
//                     is CLEARED, so un-setting one on edit actually clears it)
//   findings          [{finding_type?, free_text?, severity}] — the complete set
//   keep_attachments  [filename] — the stored files to KEEP (edit); anything
//                     omitted is dropped. New uploads are appended to these.
//
// org and author always come from the authenticated user / the existing record;
// permission mirrors the microscopy_samples create/update rule (case-private
// clinical: active carer OR edit-share OR supervisor, same org).
//
// Deletes are NOT here — an ordinary DELETE on the collection cascades the
// findings and is picked up by audit_domain.pb.js with no extra code.
routerAdd(
  "POST",
  "/api/federfall/microscopy",
  (e) => {
    // The boundary this route bypasses, stated once for every route that
    // bypasses one — see lib_auth.js.
    const org = require(`${__hooks}/lib_auth.js`).requireMember(e);
    // The gate above checks the caller; the per-case access check and the
    // author field below still need their identity.
    const auth = e.auth;

    // NB every helper this handler uses is defined INSIDE it. A hook handler
    // runs in an isolated JSVM context where file-level bindings are out of
    // scope (ReferenceError), which is why the shared parts live in lib_*.js
    // and are require()d here rather than declared above.
    const body = e.requestInfo().body || {};
    const str = (v) => (v === undefined || v === null ? "" : String(v).trim());

    const SAMPLE_TYPES = ["crop_swab", "fecal"];
    const METHODS = ["direct_smear", "flotation"];
    const EXAMINED_BY = ["in_house", "vet", "lab"];
    const SEVERITIES = ["plus", "plus_plus", "plus_plus_plus"];

    const sampleId = str(body.id);
    const sampleData =
      body.sample && typeof body.sample === "object" ? body.sample : {};
    const findings = Array.isArray(body.findings) ? body.findings : [];
    const keepAttachments = Array.isArray(body.keep_attachments)
      ? body.keep_attachments.map(str).filter((n) => n !== "")
      : [];

    let uploads = [];
    try {
      uploads = e.findUploadedFiles("attachments") || [];
    } catch (_) {
      // Not multipart / no files staged.
    }

    // ── Validation ───────────────────────────────────────────────────────────
    //
    // Every check below is something a collection rule cannot express, which is
    // the standing reason this codebase puts them in hooks.

    const sampleType = str(sampleData.sample_type);
    if (SAMPLE_TYPES.indexOf(sampleType) === -1) {
      throw new BadRequestError("'sample.sample_type' is required.");
    }

    // Direktabstrich / Flotation is a question about a faecal sample only.
    // Clearing rather than rejecting keeps a stale client that still sends the
    // field working, while making "Kropfabstrich, Flotation" unstorable.
    let method = str(sampleData.method);
    if (sampleType !== "fecal") method = "";
    if (method !== "" && METHODS.indexOf(method) === -1) {
      throw new BadRequestError("Unknown 'sample.method'.");
    }

    const examinedBy = str(sampleData.examined_by);
    if (examinedBy !== "" && EXAMINED_BY.indexOf(examinedBy) === -1) {
      throw new BadRequestError("Unknown 'sample.examined_by'.");
    }

    const noFindings = sampleData.no_findings === true;

    // "Ohne Befund" is an assertion about the whole sample, so it cannot
    // coexist with a finding. The mutual exclusion is enforced in the sheet too
    // — there for feel, here for truth.
    if (noFindings && findings.length > 0) {
      throw new BadRequestError(
        "'no_findings' cannot be combined with findings.",
      );
    }

    // NOT rejected: neither set. That is the legitimate "result pending" state
    // — the sample was taken and sent to a lab, and nobody has read it yet.
    // Collapsing it into "ohne Befund" would assert a clean result no one has
    // seen.

    const clean = [];
    for (const f of findings) {
      if (!f || typeof f !== "object") continue;
      const findingType = str(f.finding_type);
      const freeText = str(f.free_text);
      const severity = str(f.severity);
      // Exactly one of the two — the case_conditions shape. Both would make the
      // row ambiguous to render; neither leaves a grade attached to nothing.
      if ((findingType === "") === (freeText === "")) {
        throw new BadRequestError(
          "Each finding needs exactly one of 'finding_type' or 'free_text'.",
        );
      }
      if (SEVERITIES.indexOf(severity) === -1) {
        throw new BadRequestError("Each finding needs a valid 'severity'.");
      }
      clean.push({
        finding_type: findingType,
        free_text: freeText,
        severity: severity,
      });
    }

    // Full-replace semantics for the whitelisted sample fields: the sheet
    // always sends the form's complete state, so an omitted field means
    // "cleared". `method` is the resolved value from above, not the raw one.
    const resolved = {
      sample_type: sampleType,
      method: method,
      examined_at: sampleData.examined_at,
      examined_by: examinedBy,
      examiner: str(sampleData.examiner),
      external_lab: str(sampleData.external_lab),
      no_findings: noFindings,
      notes: str(sampleData.notes),
    };
    const FIELDS = Object.keys(resolved);

    let saved = null;
    let createdNow = false;
    e.app.runInTransaction((tx) => {
      // Mirrors the microscopy_samples create/update rule: `case.org =
      // @request.auth.org && (case.active_carer = @request.auth.id ||
      // supervisor || edit-share)`. The route bypasses collection rules, so it
      // must enforce this itself.
      const assertCanEditCase = (caseRec) => {
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

      let rec;
      if (sampleId) {
        try {
          rec = tx.findRecordById("microscopy_samples", sampleId);
        } catch (_) {
          throw new BadRequestError("Unknown microscopy sample.");
        }
        if (rec.getString("org") !== org) {
          throw new BadRequestError("Unknown microscopy sample.");
        }
        assertCanEditCase(tx.findRecordById("cases", rec.getString("case")));
      } else {
        const caseId = str(body.case);
        if (!caseId) {
          throw new BadRequestError("'case' is required.");
        }
        let caseRec;
        try {
          caseRec = tx.findRecordById("cases", caseId);
        } catch (_) {
          throw new BadRequestError("Unknown case.");
        }
        assertCanEditCase(caseRec);
        rec = new Record(tx.findCollectionByNameOrId("microscopy_samples"));
        rec.set("case", caseId);
        rec.set("author", auth.id);
        rec.set("org", org);
        createdNow = true;
      }

      for (const f of FIELDS) {
        rec.set(f, resolved[f] === undefined ? null : resolved[f]);
      }

      // Files: the survivors the client still shows, plus whatever it just
      // picked. Setting the field to the survivors is what deletes the rest —
      // PocketBase treats the new value as the complete list.
      if (sampleId) {
        const kept = [];
        const stored = rec.original().get("attachments") || [];
        for (const name of stored) {
          if (keepAttachments.indexOf(String(name)) !== -1) kept.push(name);
        }
        rec.set("attachments", kept.concat(uploads));
      } else if (uploads.length > 0) {
        rec.set("attachments", uploads);
      }

      tx.save(rec);
      saved = rec;

      // Replace the findings as a set — the set is small, so a clean replace
      // beats diffing (exam.pb.js's call), and this time it is atomic with the
      // sample rather than a sequence the network can interrupt halfway.
      for (const old of tx.findRecordsByFilter(
        "microscopy_findings",
        "sample = {:s}",
        "",
        0,
        0,
        { s: rec.id },
      )) {
        tx.delete(old);
      }
      for (const f of clean) {
        // A vocabulary entry must belong to the caller's org. Applicability to
        // the sample type is deliberately NOT checked: a supervisor narrowing a
        // type's `sample_types` later must not invalidate history, and an
        // inactive type stays valid on rows that already reference it.
        if (f.finding_type) {
          let type;
          try {
            type = tx.findRecordById(
              "microscopy_finding_types",
              f.finding_type,
            );
          } catch (_) {
            throw new BadRequestError("Unknown finding type.");
          }
          if (type.getString("org") !== org) {
            throw new BadRequestError("Unknown finding type.");
          }
        }
        const row = new Record(
          tx.findCollectionByNameOrId("microscopy_findings"),
        );
        row.set("sample", rec.id);
        row.set("finding_type", f.finding_type);
        row.set("free_text", f.free_text);
        row.set("severity", f.severity);
        row.set("org", org);
        tx.save(row);
      }

      // One event for the sample and the findings it replaced wholesale
      // (exam.saved's stance): neither fires request hooks here — everything is
      // tx.save — and per-finding rows would bury the one fact worth reading,
      // which is that a sample was examined and what it showed.
      //
      // No id travels without a label beside it (federfall-qt96): the finding
      // types are named, not referenced.
      const audit = require(`${__hooks}/lib_audit.js`);
      const labels = [];
      for (const f of clean) {
        if (f.free_text) {
          labels.push(f.free_text.slice(0, 200));
          continue;
        }
        try {
          labels.push(
            tx
              .findRecordById("microscopy_finding_types", f.finding_type)
              .getString("label"),
          );
        } catch (_) {
          labels.push("");
        }
      }
      const worst = clean.reduce((acc, f) => {
        return SEVERITIES.indexOf(f.severity) > SEVERITIES.indexOf(acc)
          ? f.severity
          : acc;
      }, "");

      audit.emit(e, "microscopy.saved", {
        app: tx,
        org: org,
        subject: {
          collection: "microscopy_samples",
          id: rec.id,
          label: "",
        },
        caseId: rec.getString("case"),
        detail: {
          created: createdNow,
          sample_type: sampleType,
          method: method,
          examined_by: examinedBy,
          no_findings: noFindings,
          findings: clean.length,
          finding_labels: labels,
          // The strongest grade is the reason anybody reads this row again.
          worst_severity: worst,
          attachments: (rec.get("attachments") || []).length,
        },
      });
    });

    return e.json(200, { id: saved.id });
  },
  $apis.requireAuth(),
);
