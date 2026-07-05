/// <reference path="../pb_data/types.d.ts" />

// federfall-gdp8 — per-case PDF report: the full case chronology rendered
// server-side with Typst (bundled into the image by the root Dockerfile's
// typstfetch stage; template + vendored QR package in ../typst/).
//
// This hook does NOT localize or format anything for display — it only sends
// structured, untranslated data: stable wire enum values (e.g. "in_care",
// "male"), raw date parts, and free text / DB-authored labels (drug names,
// medication-route/marking-type/condition/admission-reason labels, user
// names) that are never translated regardless of report language. ALL
// translation, date formatting and text joining lives in ../typst/report.typ
// (its STRINGS dict, keyed by `data.lang`) — the standard Typst i18n pattern.
// Keeping that split means adding a language is a template-only change.
//
// `?lang=` picks the report language (falls back to "de" for anything else,
// including a future client that doesn't send it yet — see federfall-qdsa:
// the app itself is locale-locked to German today, so this is forward-looking
// plumbing more than a currently-reachable choice).
//
// Each routerAdd handler is its own isolated JSVM context (see the other
// hooks in this dir) — no file-level helpers; everything below is declared
// inside the one handler that needs it.
routerAdd(
  "GET",
  "/api/federfall/cases/{id}/report.pdf",
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
    if (!org) throw new ForbiddenError("No organisation.");

    const langParam = e.request.url.query().get("lang");
    const lang = langParam === "en" ? "en" : "de";

    const caseId = e.request.pathValue("id");
    let caseRec;
    try {
      caseRec = e.app.findRecordById("cases", caseId);
    } catch (_) {
      throw new NotFoundError("Unknown case.");
    }
    if (caseRec.getString("org") !== org) {
      throw new NotFoundError("Unknown case.");
    }

    // Mirrors the `cases` view rule (1700000010_access_rules.js): coordinator/
    // supervisor, the active carer, or ANY case_shares row (read or edit —
    // unlike editing, viewing/printing doesn't require the "edit" level).
    const role = auth.getString("role");
    const isCoordOrSup = role === "coordinator" || role === "supervisor";
    const isActiveCarer = caseRec.getString("active_carer") === auth.id;
    let hasShare = false;
    if (!isCoordOrSup && !isActiveCarer) {
      hasShare =
        e.app.findRecordsByFilter(
          "case_shares",
          "case = {:c} && shared_with = {:u}",
          "",
          1,
          0,
          { c: caseId, u: auth.id },
        ).length > 0;
    }
    if (!isCoordOrSup && !isActiveCarer && !hasShare) {
      throw new ForbiddenError("Not allowed.");
    }

    // ── Date parts: the template constructs a Typst `datetime` from these and
    // formats/localizes it itself. Parsed in UTC as PocketBase stores it —
    // goja/JSVM has no reliable Intl/timezone-conversion primitive, and this
    // is a hand-off summary, not a legal record, so a ~1-2h skew near local
    // midnight is an accepted known limitation.
    const dateParts = (value) => {
      if (!value) return null;
      const d = new Date(String(value).replace(" ", "T"));
      if (isNaN(d.getTime())) return null;
      return {
        y: d.getUTCFullYear(),
        mo: d.getUTCMonth() + 1,
        d: d.getUTCDate(),
        h: d.getUTCHours(),
        mi: d.getUTCMinutes(),
      };
    };

    // ── Gather everything the case timeline shows (mirrors
    // CaseBundle.fromRecord / case_timeline.dart's event list): the case,
    // animal, finder, and every child-by-case (or child-by-animal, for
    // markings) collection.
    const byCase = (collection) =>
      e.app.findRecordsByFilter(collection, "case = {:c}", "", 0, 0, {
        c: caseId,
      });

    const animalId = caseRec.getString("animal");
    let animalRec = null;
    try {
      animalRec = e.app.findRecordById("animals", animalId);
    } catch (_) {
      // deleted/missing animal — report still renders without it
    }

    const finderId = caseRec.getString("finder");
    let finderRec = null;
    if (finderId) {
      try {
        finderRec = e.app.findRecordById("finders", finderId);
      } catch (_) {
        // stale reference
      }
    }

    // DB-authored labels (NOT enums — read as stored, same as the Flutter app
    // does for these code lists; never translated by report language).
    const reasonLabels = (caseRec.get("admission_reasons") || [])
      .map((rid) => {
        try {
          return e.app
            .findRecordById("admission_reasons", rid)
            .getString("label");
        } catch (_) {
          return null;
        }
      })
      .filter(Boolean);

    const nameOfUser = (id) => {
      if (!id) return null;
      try {
        const u = e.app.findRecordById("users", id);
        const name = u.getString("name");
        if (name) return name;
        const email = u.getString("email");
        const at = email.indexOf("@");
        return at > 0 ? email.substring(0, at) : email;
      } catch (_) {
        return null;
      }
    };
    const routeLabel = (id) => {
      if (!id) return null;
      try {
        return e.app.findRecordById("medication_routes", id).getString("label");
      } catch (_) {
        return null;
      }
    };
    const markingTypeLabel = (id) => {
      if (!id) return "";
      try {
        return e.app.findRecordById("marking_types", id).getString("label");
      } catch (_) {
        return "";
      }
    };
    const conditionLabel = (id) => {
      if (!id) return null;
      try {
        return e.app.findRecordById("conditions", id).getString("label");
      } catch (_) {
        return null;
      }
    };

    // Each raw entry keeps its own sortable Date; the timeline is sorted
    // oldest → newest (a hand-off document reads as a narrative; the app's
    // own timeline is newest-first for triage) before shedding the sort key.
    const raw = [];
    const push = (atValue, kind, fields) => {
      if (!atValue) return;
      const sortAt = new Date(String(atValue).replace(" ", "T"));
      if (isNaN(sortAt.getTime())) return;
      const entry = Object.assign({ at: dateParts(atValue), kind: kind }, fields);
      raw.push({ sortAt: sortAt, entry: entry });
    };

    // Milestones (mirrors case_timeline.dart's _MilestoneEvent pair).
    push(caseRec.getString("admitted_at"), "milestone", { milestone: "admitted" });
    push(caseRec.getString("created"), "milestone", { milestone: "created" });

    for (const r of byCase("journal_entries")) {
      push(r.getString("entry_at") || r.getString("created"), "journal", {
        text: r.getString("text"),
      });
    }

    for (const r of byCase("weights")) {
      push(r.getString("measured_at") || r.getString("created"), "weight", {
        grams: r.getFloat("weight_g"),
        notes: r.getString("notes"),
      });
    }

    for (const r of byCase("case_conditions")) {
      const label =
        conditionLabel(r.getString("condition")) ||
        r.getString("free_text") ||
        "—";
      push(r.getString("onset_date") || r.getString("created"), "condition", {
        label: label,
        certainty: r.getString("certainty") || null,
        resolvedAt: dateParts(r.getString("resolved_date")),
        notes: r.getString("notes"),
      });
    }

    for (const r of byCase("medications")) {
      push(r.getString("started_at") || r.getString("created"), "medication", {
        drug: r.getString("drug"),
        dose: r.getFloat("dose") || null,
        doseUnit: r.getString("dose_unit"),
        route: routeLabel(r.getString("route")),
        frequencyKind: r.getString("frequency_kind") || null,
        intervalHours: r.getInt("interval_hours") || null,
        frequency: r.getString("frequency"),
        isControlled: r.getBool("is_controlled"),
        endedAt: dateParts(r.getString("ended_at")),
        instructions: r.getString("instructions"),
        prescribedBy: r.getString("prescribed_by"),
      });
    }

    for (const r of byCase("medication_administrations")) {
      push(
        r.getString("administered_at") || r.getString("created"),
        "administration",
        {
          drug: r.getString("drug"),
          dose: r.getFloat("dose") || null,
          doseUnit: r.getString("dose_unit"),
          route: routeLabel(r.getString("route")),
          notes: r.getString("notes"),
        },
      );
    }

    if (animalId) {
      const markings = e.app.findRecordsByFilter(
        "markings",
        "animal = {:a}",
        "",
        0,
        0,
        { a: animalId },
      );
      for (const r of markings) {
        push(r.getString("applied_at") || r.getString("created"), "marking", {
          type: markingTypeLabel(r.getString("type")),
          colour: r.getString("colour"),
          code: r.getString("code"),
          schemeOrg: r.getString("scheme_org"),
          removed: !r.getBool("is_active"),
          removedAt: dateParts(r.getString("removed_at")),
        });
      }
    }

    for (const r of byCase("placements")) {
      push(r.getString("moved_in_at") || r.getString("created"), "placement", {
        toUserName: nameOfUser(r.getString("to_user")),
        enclosure: r.getString("enclosure"),
        whereHolding: r.getString("where_holding"),
        area: r.getString("area"),
        conditionAtHandoff: r.getString("condition_at_handoff"),
        comments: r.getString("comments"),
      });
    }

    for (const r of byCase("dispositions")) {
      push(r.getString("disposed_at") || r.getString("created"), "disposition", {
        type: r.getString("type") || null,
        releaseLocation: r.getString("release_location"),
        releaseType: r.getString("release_type"),
        transferDestination: r.getString("transfer_destination"),
        transferType: r.getString("transfer_type"),
        vet: r.getString("vet"),
        reason: r.getString("reason"),
        vetSignedOff: r.getBool("vet_signed_off"),
      });
    }

    for (const r of byCase("follow_ups")) {
      push(r.getString("due_at") || r.getString("created"), "follow_up", {
        note: r.getString("note"),
        done: !!r.getString("done_at"),
      });
    }

    for (const exam of byCase("exams")) {
      const findings = e.app
        .findRecordsByFilter("exam_findings", "exam = {:e}", "", 0, 0, {
          e: exam.id,
        })
        .map((f) => ({
          system: f.getString("system"),
          status: f.getString("status"),
          note: f.getString("note"),
        }));
      push(exam.getString("examined_at") || exam.getString("created"), "exam", {
        bodyCondition: exam.getInt("body_condition") || null,
        temperature: exam.getFloat("temperature") || null,
        hydration: exam.getString("hydration") || null,
        mentation: exam.getString("mentation") || null,
        mmColor: exam.getString("mm_color") || null,
        mmTexture: exam.getString("mm_texture") || null,
        notes: exam.getString("notes"),
        findings: findings,
      });
    }

    for (const r of byCase("quarantine_records")) {
      const until = r.getString("quarantine_until");
      push(r.getString("set_at") || r.getString("created"), "quarantine", {
        phase: "started",
        reason: r.getString("reason"),
        until: dateParts(until),
      });
      if (until && new Date(until.replace(" ", "T")) <= new Date()) {
        push(until, "quarantine", { phase: "ended" });
      }
    }

    raw.sort((a, b) => a.sortAt - b.sortAt);
    const timeline = raw.map((r) => r.entry);

    const payload = {
      lang: lang,
      generatedAt: dateParts(new Date().toISOString()),
      case: {
        caseNumber: caseRec.getString("case_number") || caseRec.id,
        status: caseRec.getString("status") || null,
        admittedAt: dateParts(caseRec.getString("admitted_at")),
        foundAt: dateParts(caseRec.getString("found_at")),
        findLocation: caseRec.getString("find_location"),
        intakeNotes: caseRec.getString("intake_notes"),
        ageClass: caseRec.getString("age_class") || null,
      },
      animal: {
        species: animalRec ? animalRec.getString("species") : "",
        name: animalRec ? animalRec.getString("name") || null : null,
        sex: animalRec ? animalRec.getString("sex") || null : null,
      },
      finder: finderRec
        ? {
            name: [
              finderRec.getString("first_name"),
              finderRec.getString("last_name"),
            ]
              .filter(Boolean)
              .join(" "),
            phone: finderRec.getString("phone"),
            email: finderRec.getString("email"),
            city: finderRec.getString("city"),
          }
        : null,
      reasons: reasonLabels,
      timeline: timeline,
    };

    // ── Render: Typst writes the PDF to a file (not stdout) so the binary
    // response never round-trips through a JS string. `--root` stays the
    // static, shared /pb/typst — only the per-request output lives in the OS
    // temp dir, cleaned up below.
    const outPath =
      $os.tempDir() +
      "/federfall-report-" +
      caseId +
      "-" +
      Date.now() +
      "-" +
      Math.floor(Math.random() * 1e9) +
      ".pdf";
    try {
      $os
        .cmd(
          "typst",
          "compile",
          "--root",
          "/pb/typst",
          "--input",
          "data=" + JSON.stringify(payload),
          "/pb/typst/report.typ",
          outPath,
        )
        .run();
    } catch (err) {
      e.app
        .logger()
        .error("case report: typst compile failed", "error", String(err), "case", caseId);
      return e.json(500, { error: "Report generation failed." });
    }

    let bytes;
    try {
      bytes = $os.readFile(outPath);
    } finally {
      try {
        $os.remove(outPath);
      } catch (_) {
        // best-effort cleanup
      }
    }

    const caseNumber = caseRec.getString("case_number") || caseRec.id;
    e.response
      .header()
      .set("Content-Disposition", 'attachment; filename="case-' + caseNumber + '.pdf"');
    return e.blob(200, "application/pdf", bytes);
  },
  $apis.requireAuth(),
);
