/// <reference path="../pb_data/types.d.ts" />

// federfall-gdp8 — per-case PDF report: the full case chronology rendered
// server-side with Typst (bundled into the image by the root Dockerfile's
// typstfetch stage; templates + vendored QR package in ../typst/). Also
// serves the federfall-i0wq narrow thermal-receipt PNG variant off the same
// route (see the `widthDots` branch below) — same payload, a different
// template.
//
// This hook does NOT localize or format anything for display — it only sends
// structured, untranslated data: stable wire enum values (e.g. "in_care",
// "male"), raw date parts, and free text / DB-authored labels (drug names,
// medication-route/marking-type/condition/admission-reason labels, user
// names) that are never translated regardless of report language. ALL
// translation, date formatting and text joining lives in
// ../typst/report_common.typ (its STRINGS dict, keyed by `data.lang`,
// shared by report.typ and receipt.typ) — the standard Typst i18n pattern.
// Keeping that split means adding a language is a template-only change.
//
// `?lang=` picks the report language (falls back to "de" for anything else,
// including a client that doesn't send it). Live since federfall-qdsa: the app
// follows the device language and sends its resolved locale, so a report really
// can come back in either language now.
//
// Each routerAdd handler is its own isolated JSVM context (see the other
// hooks in this dir) — no file-level helpers; everything below is declared
// inside the one handler that needs it.
routerAdd(
  "GET",
  "/api/federfall/cases/{id}/report.pdf",
  (e) => {
    // Membership only; which CASES this caller may print is checked below
    // against the case itself — see lib_auth.js.
    const org = require(`${__hooks}/lib_auth.js`).requireMember(e);
    // The gate above checks the caller; which CASES they may print is decided
    // below against their role and id.
    const auth = e.auth;

    const langParam = e.request.url.query().get("lang");
    const lang = langParam === "en" ? "en" : "de";

    // ── Receipt (thermal, narrow) branch selection: federfall-i0wq. Presence
    // of `?widthDots=` switches this endpoint from the A4 PDF to a PNG raster
    // sized to exactly that many pixels wide — 1 image px = 1 printer dot for
    // ESC/POS raster printing, so widthDots is the only thing that matters
    // for paper fit; dpi/mm are irrelevant. The client derives it from the
    // user's stored paper-size choice (see profile/settings), so a caller
    // that sends widthDots always means it, hence the strict validation
    // below rather than silently falling back to a guessed width — a wrong
    // guess would print off the edge of the paper on real hardware.
    // `.get()` returns "" (falsy), not null, for a param that's absent —
    // see geocode.pb.js's `if (!q)` for the same convention — so the check
    // below must be truthiness, not a `!== null` comparison (which let ""
    // through to parseInt as NaN and made EVERY plain PDF request without
    // ?widthDots= fail the range check below).
    const widthDotsParam = e.request.url.query().get("widthDots");
    let widthDots = null;
    if (widthDotsParam) {
      const parsed = parseInt(widthDotsParam, 10);
      if (isNaN(parsed) || parsed < 200 || parsed > 1024) {
        throw new BadRequestError(
          "widthDots must be an integer between 200 and 1024.",
        );
      }
      widthDots = parsed;
    }

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
    // formats/localizes it itself, so what it needs is wall-clock parts in the
    // CALLER's zone, not an instant.
    //
    // Caller-local time (federfall-c41f): the `?tzOffsetMinutes=` param, its
    // Europe/Berlin fallback and the parts themselves all live in lib_time.js,
    // which annual_report.pb.js and stats.pb.js read too — this file's own copy
    // was the original those were taken from, and a DST fix then had to be made
    // twice. The client supplies the offset from
    // `DateTime.now().timeZoneOffset` (case_detail_screen.dart).
    const dateParts = require(`${__hooks}/lib_time.js`).timeContext(
      e.request.url.query(),
    ).partsOf;

    // ── Gather everything the case timeline shows (mirrors
    // CaseBundle.fromRecord / case_timeline.dart's event list): the case,
    // animal, finder, and every child-by-case (or child-by-animal, for
    // markings and egg records) collection.
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

    // ── Photo: this case's own intake photo (tied to THIS admission) if it
    // has one, else the animal's lifetime photo. Read via PocketBase's own
    // filesystem abstraction (e.app.newFilesystem() + fsys.getFile()) rather
    // than assuming local disk storage — this is the only path that also
    // works if the instance is ever configured for S3. The reader must be
    // drained into a Uint8Array (NOT a plain Array — reader.read(buf) only
    // fills a typed array in place; verified byte-for-byte against a real
    // upload with a throwaway diagnostic route before writing this). Written
    // to a temp file under the *new* typst --root (see below) so report.typ
    // can `image()` it — a bare "/pb/typst" root would mean writing runtime
    // files into the static template directory.
    let photoRec = null;
    let photoFilename = null;
    const intakePhotos = caseRec.get("intake_photos") || [];
    if (intakePhotos.length > 0) {
      photoRec = caseRec;
      photoFilename = intakePhotos[0];
    } else if (animalRec && animalRec.getString("photo")) {
      photoRec = animalRec;
      photoFilename = animalRec.getString("photo");
    }
    let photoRootRelativePath = null;
    let photoTempDir = null;
    if (photoRec && photoFilename) {
      let fsys, reader;
      try {
        fsys = e.app.newFilesystem();
        reader = fsys.getFile(photoRec.baseFilesPath() + "/" + photoFilename);
        const size = reader.size();
        const bytes = new Uint8Array(size);
        const chunkSize = 65536;
        let total = 0;
        while (total < size) {
          const chunk = new Uint8Array(Math.min(chunkSize, size - total));
          const n = reader.read(chunk);
          if (n <= 0) break;
          bytes.set(chunk.subarray(0, n), total);
          total += n;
        }

        const ext = photoFilename.includes(".")
          ? photoFilename.slice(photoFilename.lastIndexOf("."))
          : "";
        photoTempDir =
          "/pb/report-tmp/photo-" +
          caseId +
          "-" +
          Date.now() +
          "-" +
          Math.floor(Math.random() * 1e9);
        $os.mkdirAll(photoTempDir, 0o755);
        $os.writeFile(photoTempDir + "/photo" + ext, bytes, 0o644);
        photoRootRelativePath = "/" + photoTempDir.slice("/pb/".length) + "/photo" + ext;
      } catch (err) {
        // missing/unreadable file (moved, deleted, ...) — the report renders
        // without a photo rather than failing outright.
        photoRootRelativePath = null;
      } finally {
        try {
          reader?.close();
        } catch (_) {
          // best-effort
        }
        try {
          fsys?.close();
        } catch (_) {
          // best-effort
        }
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
        doseRate: r.getFloat("dose_rate") || null,
        route: routeLabel(r.getString("route")),
        frequencyKind: r.getString("frequency_kind") || null,
        intervalHours: r.getInt("interval_hours") || null,
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

    // Also the case's end for the egg window further down: the LATEST
    // disposition, matching what eggsInCaseWindow reads off the bundle (whose
    // dispositions come newest-first, so it takes the first one).
    let closedAtMs = null;
    for (const r of byCase("dispositions")) {
      const disposedAt = r.getString("disposed_at") || r.getString("created");
      const ms = disposedAt
        ? new Date(String(disposedAt).replace(" ", "T")).getTime()
        : NaN;
      if (!isNaN(ms) && (closedAtMs === null || ms > closedAtMs)) {
        closedAtMs = ms;
      }
      push(disposedAt, "disposition", {
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

    // Egg records (federfall-4agw) are animal-scoped like markings — there is
    // deliberately no `case` field (1700000056), so timeline membership is
    // computed from the animal. Unlike markings, though, they are narrowed to
    // this case's own window, exactly as eggsInCaseWindow (eggs_providers.dart)
    // does: a ring is a standing property of the bird, a laying event is dated,
    // and a lifetime of them would swamp one episode's chronology. Window =
    // admission (unbounded before it when none is recorded) to the latest
    // disposition, or to now while the case is still open.
    if (animalId) {
      const admittedAt = caseRec.getString("admitted_at");
      const fromMs = admittedAt
        ? new Date(String(admittedAt).replace(" ", "T")).getTime()
        : NaN;
      const untilMs = closedAtMs !== null ? closedAtMs : Date.now();
      const eggs = e.app.findRecordsByFilter(
        "egg_records",
        "animal = {:a}",
        "",
        0,
        0,
        { a: animalId },
      );
      for (const r of eggs) {
        const laidAt = r.getString("laid_at") || r.getString("created");
        const ms = laidAt
          ? new Date(String(laidAt).replace(" ", "T")).getTime()
          : NaN;
        if (isNaN(ms)) continue;
        if (!isNaN(fromMs) && ms < fromMs) continue;
        if (ms > untilMs) continue;
        // `attribution` is carried even when it is "confirmed" — the template
        // decides what deserves saying, and a presumed layer must not be
        // printed as an established fact.
        push(laidAt, "egg", {
          count: r.getInt("count") || null,
          fertility: r.getString("fertility") || null,
          fate: r.getString("fate") || null,
          attribution: r.getString("attribution") || null,
          notes: r.getString("notes"),
        });
      }
    }

    // Vet appointments (federfall-fnpo). `attended_at` / `cancelled_at` are two
    // independent stamps, so the two booleans below have THREE meaningful
    // combinations the template must distinguish: attended, cancelled, and
    // neither — an unresolved appointment (including a past one) may not read
    // as attended just because it is over.
    for (const r of byCase("vet_appointments")) {
      push(
        r.getString("starts_at") || r.getString("created"),
        "vet_appointment",
        {
          vet: r.getString("vet"),
          reason: r.getString("reason"),
          // A different fact from `reason` — what the vet actually said — so it
          // is sent as its own field and labelled separately in the template
          // (mirrors VetAppointmentTile's _OutcomeBox).
          outcome: r.getString("outcome"),
          attended: !!r.getString("attended_at"),
          cancelled: !!r.getString("cancelled_at"),
        },
      );
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
        // Deep link for the QR: federfall://case/<caseNumber> — a custom
        // scheme rather than an https:// App Link, because this app's server
        // address is chosen per-install at runtime (native
        // ServerConfigController, self-hosted), so no fixed domain exists for
        // a shared build to ever verify an Android App Link / iOS Universal
        // Link against. Handled app-side by
        // apps/federfall/lib/routing/case_deep_link.dart, which resolves the
        // human case number back to a real case id via
        // CasesRepository.byCaseNumber (org-scoped by the normal view rule,
        // same as everything else here).
        // No fallback to caseRec.id here (unlike caseNumber's display
        // fallback above): the app resolves this path segment via
        // byCaseNumber(), which wouldn't find anything by a raw PB id
        // anyway — an empty case_number degrades to a link that resolves to
        // nothing, same net effect either way.
        deepLinkUrl: "federfall://case/" + caseRec.getString("case_number"),
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
        photoPath: photoRootRelativePath,
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

    // ── Render: Typst writes the output to a file (not stdout) so the binary
    // response never round-trips through a JS string. `--root` is "/pb" (not
    // just "/pb/typst") so the templates can reach the per-request photo temp
    // dir above via a root-relative path while the templates themselves stay
    // static, shared files — only the per-request output + photo live under
    // the OS temp dir / /pb/report-tmp, both cleaned up below.
    //
    // The receipt (widthDots != null) branch is the ONLY thing that differs
    // from the PDF path below: a different template, a `--format png --ppi`
    // pair (dot-for-dot raster; see the receipt.typ header comment for why
    // ppi need not match the physical printer), and an extra `widthDots`
    // template input. Everything above (payload assembly, auth, photo temp
    // file) is shared — JSVM handlers can't share file-level helpers across
    // routes, so branching only here avoids duplicating ~300 lines.
    const RECEIPT_PPI = 203;
    const outPath =
      $os.tempDir() +
      "/federfall-report-" +
      caseId +
      "-" +
      Date.now() +
      "-" +
      Math.floor(Math.random() * 1e9) +
      (widthDots !== null ? ".png" : ".pdf");
    const compile = (p) =>
      widthDots !== null
        ? $os
            .cmd(
              "typst",
              "compile",
              "--root",
              "/pb",
              "--input",
              "data=" + JSON.stringify(p),
              "--input",
              "widthDots=" + widthDots,
              "--format",
              "png",
              "--ppi",
              String(RECEIPT_PPI),
              "/pb/typst/receipt.typ",
              outPath,
            )
            .run()
        : $os
            .cmd(
              "typst",
              "compile",
              "--root",
              "/pb",
              "--input",
              "data=" + JSON.stringify(p),
              "/pb/typst/report.typ",
              outPath,
            )
            .run();
    try {
      try {
        compile(payload);
      } catch (err) {
        // A photo that fails to decode (corrupt upload, format Typst's
        // stricter image crates reject, ...) shouldn't take down the WHOLE
        // report — retry once without it before giving up. Anything else
        // wrong with the data/template fails the same way on retry.
        if (payload.animal.photoPath) {
          e.app
            .logger()
            .warn(
              "case report: compile failed with photo, retrying without it",
              "error",
              String(err),
              "case",
              caseId,
            );
          payload.animal.photoPath = null;
          compile(payload);
        } else {
          throw err;
        }
      }
    } catch (err) {
      e.app
        .logger()
        .error("case report: typst compile failed", "error", String(err), "case", caseId);
      return e.json(500, { error: "Report generation failed." });
    } finally {
      if (photoTempDir) {
        try {
          $os.removeAll(photoTempDir);
        } catch (_) {
          // best-effort cleanup
        }
      }
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

    // Receipt PNGs are fed straight to the printer library, not downloaded —
    // no Content-Disposition; Content-Type is what's authoritative here (the
    // route path segment stays ".pdf" for both branches, cosmetically).
    // federfall-qt96.6 — a case report carries the whole case off-system,
    // finder details included, so both output shapes are logged. Emitted after
    // the render, so a failed one is not reported as a print.
    const auditPrint = (format) => {
      require(`${__hooks}/lib_audit.js`).emit(e, "case_report.printed", {
        record: caseRec,
        subject: {
          collection: "cases",
          id: caseRec.id,
          label: caseRec.getString("case_number"),
        },
        caseId: caseRec.id,
        caseLabel: caseRec.getString("case_number"),
        detail: { format: format },
      });
    };

    if (widthDots !== null) {
      auditPrint("receipt");
      return e.blob(200, "image/png", bytes);
    }

    const caseNumber = caseRec.getString("case_number") || caseRec.id;
    e.response
      .header()
      .set("Content-Disposition", 'attachment; filename="case-' + caseNumber + '.pdf"');
    auditPrint("pdf");
    return e.blob(200, "application/pdf", bytes);
  },
  $apis.requireAuth(),
);
