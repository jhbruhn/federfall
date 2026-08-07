/// <reference path="../pb_data/types.d.ts" />

// federfall-dk0c — annual report (REQUIREMENTS.md §10), rendered server-side
// with Typst exactly like the per-case report (case_report.pb.js): the binary
// lives in the image via the root Dockerfile's typstfetch stage, templates in
// ../typst/.
//
// ONE route serves BOTH output formats — `?format=pdf` (default) and
// `?format=csv` — because the PDF's per-case table and the CSV are the SAME
// table, printed twice: they share this handler's row set and its localization,
// and every routerAdd handler is its own isolated JSVM context, so two routes
// would each have to build that again. (The period, the rows and the aggregates
// they sit on are shared further still, with the statistics route — see
// lib_stats.js, required below; a required module is the one thing handlers
// CAN share.) Both formats read the `case_report_rows` view (1700000063 +
// 1700000066 + 1700000067), which is the single definition of that table's
// columns; neither selects columns of its own.
// That includes the `markings` column: the view evaluates it at each case's own
// end, so the row says what the bird carried at release (and what it had already
// arrived with, if that ring stayed on) rather than what is on the animal today
// — see 1700000067. There is deliberately no separate markings roster in the
// PDF; the column is the record.
//
// The CSV is why this is the only hook in pb_hooks that localizes anything.
// The PDFs can stay untranslated here because a Typst template does the
// translating (see report_common.typ's STRINGS), but a CSV has no template
// layer — so its column titles and the two enum maps its cells print come from
// ../typst/shared_strings.json, which report_common.typ merges into its own
// STRINGS. That file, not this hook, is where those strings live.
//
// ── Period ──────────────────────────────────────────────────────────────────
// `?year=` selects the cases ADMITTED in that calendar year — the intake
// cohort. A bird admitted in December 2025 and released in February 2026 is a
// 2025 case whose `ended_at` falls in 2026; the report says so on the page
// (STRINGS.annual.basisNote) so two consecutive reports can be added up
// without double-counting. Omitting `?year=` reports every case on record.
// The year's boundaries are the CALLER'S midnight, not UTC's, resolved from
// `?tzOffsetMinutes=` the same way case_report.pb.js resolves its timestamps
// (goja has no Intl, so there is no tzdata to resolve a zone name against).
routerAdd(
  "GET",
  "/api/federfall/reports/annual",
  (e) => {
    // Period resolution, the pre-joined rows and every aggregate come from
    // lib_stats.js — the same module GET /api/federfall/stats reads
    // (federfall-nmwi), so the printed report and the app's statistics screen
    // cannot disagree about what a year is, which cases fall in it, or how a
    // rate is computed. Auth included: it mirrors the `case_report_rows` view
    // rule (1700000063), because these figures are org-wide by construction.
    const stats = require(`${__hooks}/lib_stats.js`);
    const org = require(`${__hooks}/lib_auth.js`).requireReporting(e);

    const query = e.request.url.query();
    const langParam = query.get("lang");
    const lang = langParam === "en" ? "en" : "de";

    // `.get()` yields "" (not null) for an absent param — see geocode.pb.js
    // and case_report.pb.js's widthDots note for the same convention.
    const formatParam = query.get("format");
    if (formatParam && formatParam !== "pdf" && formatParam !== "csv") {
      throw new BadRequestError('format must be "pdf" or "csv".');
    }
    const wantCsv = formatParam === "csv";

    const period = stats.parsePeriod(query);
    const year = period.year;
    const t = require(`${__hooks}/lib_time.js`).timeContext(query);
    const partsOf = t.partsOf;
    const pbStamp = t.pbStamp;
    // Half-open, resolved through the caller's own UTC offset; null for an
    // all-time report.
    const bounds = stats.periodBounds(period, t);

    // Sortable and unambiguous in a downloads folder: 2026, or 2026-03. A
    // month report is named for what it is — calling it a Jahresbericht would
    // be wrong in the filename for the same reason it is wrong on the page.
    const reportBase =
      period.month !== null
        ? lang === "en"
          ? "federfall-monthly-report-"
          : "federfall-monatsbericht-"
        : lang === "en"
          ? "federfall-annual-report-"
          : "federfall-jahresbericht-";
    const periodSlug =
      year === null
        ? lang === "en"
          ? "all-time"
          : "gesamt"
        : period.month === null
          ? String(year)
          : year + "-" + (period.month < 10 ? "0" : "") + period.month;

    // ── The table: one pre-joined row per case off `case_report_rows`. Its
    // columns ARE the report table (and the CSV) — nothing here adds or
    // renames one.
    const caseRows = stats.loadCaseRows(
      e.app,
      org,
      bounds === null ? null : bounds.fromMs,
      bounds === null ? null : bounds.toMs,
      t,
    );

    // ── CSV ─────────────────────────────────────────────────────────────────
    if (wantCsv) {
      // Column titles + the two enum maps come from the file the Typst
      // templates read, so the CSV and the PDF's case table cannot drift
      // apart in wording either. A missing/corrupt file is a hard failure
      // rather than a silent fall back to English or to wire values.
      let shared;
      try {
        shared = JSON.parse(toString($os.readFile("/pb/typst/shared_strings.json")));
      } catch (err) {
        e.app
          .logger()
          .error("annual report: shared_strings.json unreadable", "error", String(err));
        return e.json(500, { error: "Report generation failed." });
      }
      const S = shared[lang] || shared.de;
      if (!S || !S.reportColumns || !S.caseStatus || !S.disposition) {
        e.app.logger().error("annual report: shared_strings.json is missing keys");
        return e.json(500, { error: "Report generation failed." });
      }
      const C = S.reportColumns;

      // An enum value this build does not map is printed as its wire value —
      // the same stance as Typst's `lbl` and the app's own
      // dispositionTypeLabel: an unknown enum is not something to guess at.
      // (The superseded Dart encoder blanked the cell instead, because
      // `DispositionType.fromWire` returned null for it.)
      const label = (map, wire) => (wire ? map[wire] || wire : "");
      const isoDate = (value) => {
        const p = partsOf(value);
        if (p === null) return "";
        const two = (n) => (n < 10 ? "0" + n : String(n));
        return p.y + "-" + two(p.mo) + "-" + two(p.d);
      };

      // Neutralises spreadsheet formula injection (OWASP CSV Injection): the
      // species, name, city, marking-code and admission-reason cells are all
      // user-authored, and Excel/LibreOffice execute a cell starting with
      // `=`, `+`, `-`, `@`, tab or CR. A leading apostrophe forces text; RFC
      // 4180 quoting alone does not prevent it.
      const DANGEROUS = ["=", "+", "-", "@", "\t", "\r"];
      const cell = (value) => {
        let s = value === null || value === undefined ? "" : String(value);
        if (s !== "" && DANGEROUS.indexOf(s.charAt(0)) !== -1) s = "'" + s;
        if (
          s.indexOf('"') !== -1 ||
          s.indexOf(",") !== -1 ||
          s.indexOf("\n") !== -1 ||
          s.indexOf("\r") !== -1
        ) {
          s = '"' + s.split('"').join('""') + '"';
        }
        return s;
      };

      const lines = [
        [
          C.caseNumber,
          C.species,
          C.name,
          C.markings,
          C.found,
          C.admitted,
          C.ended,
          C.days,
          C.status,
          C.outcome,
          C.city,
          C.region,
          C.reasons,
        ]
          .map(cell)
          .join(","),
      ];
      for (const r of caseRows) {
        lines.push(
          [
            r.caseNumber,
            r.species,
            r.name,
            r.markings,
            isoDate(r.foundAt),
            isoDate(r.admittedAt),
            isoDate(r.endedAt),
            r.days === null ? "" : String(r.days),
            label(S.caseStatus, r.status),
            label(S.disposition, r.outcome),
            r.city,
            r.region,
            r.reasons,
          ]
            .map(cell)
            .join(","),
        );
      }
      // CRLF, matching what the Dart `csv` package emitted before this moved
      // server-side (and RFC 4180).
      const text = lines.join("\r\n") + "\r\n";

      // UTF-8 encoded by hand rather than relying on the host's JS-string →
      // []byte conversion: a German report is full of umlauts, and getting
      // that wrong is the kind of failure that only shows up in the finished
      // spreadsheet. The leading EF BB BF is the BOM spreadsheet apps need to
      // read the file as UTF-8 at all.
      const bytes = [0xef, 0xbb, 0xbf];
      for (let i = 0; i < text.length; i++) {
        let cp = text.charCodeAt(i);
        if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < text.length) {
          const low = text.charCodeAt(i + 1);
          if (low >= 0xdc00 && low <= 0xdfff) {
            cp = 0x10000 + ((cp - 0xd800) << 10) + (low - 0xdc00);
            i++;
          }
        }
        if (cp < 0x80) {
          bytes.push(cp);
        } else if (cp < 0x800) {
          bytes.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f));
        } else if (cp < 0x10000) {
          bytes.push(
            0xe0 | (cp >> 12),
            0x80 | ((cp >> 6) & 0x3f),
            0x80 | (cp & 0x3f),
          );
        } else {
          bytes.push(
            0xf0 | (cp >> 18),
            0x80 | ((cp >> 12) & 0x3f),
            0x80 | ((cp >> 6) & 0x3f),
            0x80 | (cp & 0x3f),
          );
        }
      }

      const csvName = reportBase + periodSlug;
      e.response
        .header()
        .set("Content-Disposition", 'attachment; filename="' + csvName + '.csv"');
      // federfall-qt96.6 — an export is data leaving the system, which is the
      // one kind of READ this log records. Emitted after the bytes exist, so a
      // failed render is not reported as an export.
      require(`${__hooks}/lib_audit.js`).emit(e, "report.exported", {
        subject: { collection: "", id: "", label: "" },
        detail: {
          report: "annual",
          format: "csv",
          year: year,
          month: period.month,
          lang: lang,
          rows: caseRows.length,
        },
      });
      return e.blob(200, "text/csv; charset=utf-8", new Uint8Array(bytes));
    }

    // ── Aggregates (PDF only) ───────────────────────────────────────────────
    // One implementation, shared with the statistics route (federfall-nmwi),
    // so the printed report and the on-screen figures agree for the same scope
    // — including the mean stay being a FRACTIONAL day count (hours/24), not
    // the whole days the per-case column shows.
    const agg = stats.aggregate(caseRows, { t: t, period: period });

    // Outcomes: named types first (by count), then the unnamed-type bucket,
    // then "still open" last — it is not an outcome, it is the absence of one,
    // which is why the module leaves appending it to its caller.
    const outcomes = agg.outcomes.map((o) => ({
      type: o.label,
      count: o.count,
    }));
    if (agg.totals.inCare > 0) {
      outcomes.push({ type: null, count: agg.totals.inCare });
    }

    let orgRec = null;
    try {
      orgRec = e.app.findRecordById("organisations", org);
    } catch (_) {
      // A user whose org row vanished still gets a report, just an unnamed one.
    }

    const payload = {
      lang: lang,
      generatedAt: partsOf(new Date().toISOString()),
      org: {
        name: orgRec ? orgRec.getString("name") : "",
        contactEmail: orgRec ? orgRec.getString("contact_email") : "",
        contactPhone: orgRec ? orgRec.getString("contact_phone") : "",
      },
      period: {
        year: year,
        // Null for a whole year; the template titles and labels the report
        // differently when a single month was asked for.
        month: period.month,
        from: bounds === null ? null : partsOf(pbStamp(bounds.fromMs)),
        // The inclusive last day of the period, because that is what a
        // reader expects to see printed ("01.01. – 31.12."), while the filter
        // above is a half-open range.
        to: bounds === null ? null : partsOf(pbStamp(bounds.toMs - 1)),
      },
      totals: agg.totals,
      bucketKind: agg.bucketKind,
      intakesByBucket: agg.intakesByBucket,
      outcomes: outcomes,
      species: agg.species,
      reasons: agg.reasons,
      conditions: stats.conditionCounts(e.app, org, caseRows),
      cities: agg.cities,
      cases: caseRows.map((r) => ({
        caseNumber: r.caseNumber,
        species: r.species,
        name: r.name,
        markings: r.markings,
        foundAt: partsOf(r.foundAt),
        admittedAt: partsOf(r.admittedAt),
        endedAt: partsOf(r.endedAt),
        days: r.days,
        status: r.status || null,
        outcome: r.outcome || null,
        city: r.city,
        region: r.region,
        reasons: r.reasons,
      })),
    };

    // ── Render. Same shape as case_report.pb.js: Typst writes to a file so
    // the bytes never round-trip through a JS string, and `--root` is "/pb"
    // so the template can read shared_strings.json beside itself.
    //
    // federfall-ds0d — the payload goes to Typst as a FILE, not as
    // `--input data=<the whole JSON>`. An argument has a hard size ceiling
    // (~2 MB on Linux, ARG_MAX), and this payload carries one entry per case
    // in the period with lib_stats.loadCaseRows reading unbounded: a few
    // thousand cases and the report stops rendering, with an opaque exec error
    // rather than anything a reader could act on. Passing a path also keeps
    // the case list out of the process table, where every account on the host
    // can read it out of `ps`. The temp file lives under the typst `--root` so
    // the template can reach it (a path outside /pb is unreadable to Typst) —
    // /pb/report-tmp is the same runtime scratch dir case_report.pb.js writes
    // its photo to, deliberately not the static template directory.
    const stamp = Date.now() + "-" + Math.floor(Math.random() * 1e9);
    const dataDir = "/pb/report-tmp/annual-" + periodSlug + "-" + stamp;
    const dataPath = dataDir + "/data.json";
    const outPath =
      $os.tempDir() + "/federfall-annual-" + periodSlug + "-" + stamp + ".pdf";
    try {
      $os.mkdirAll(dataDir, 0o755);
      $os.writeFile(dataPath, JSON.stringify(payload), 0o644);
      $os
        .cmd(
          "typst",
          "compile",
          "--root",
          "/pb",
          "--input",
          "dataPath=" + dataPath.slice("/pb".length),
          "/pb/typst/annual_report.typ",
          outPath,
        )
        .run();
    } catch (err) {
      e.app
        .logger()
        .error(
          "annual report: typst compile failed",
          "error",
          String(err),
          "year",
          year,
        );
      return e.json(500, { error: "Report generation failed." });
    } finally {
      try {
        $os.removeAll(dataDir);
      } catch (_) {
        // best-effort cleanup
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

    const pdfName = reportBase + periodSlug;
    e.response
      .header()
      .set("Content-Disposition", 'attachment; filename="' + pdfName + '.pdf"');
    // federfall-qt96.6 — see the CSV branch above.
    require(`${__hooks}/lib_audit.js`).emit(e, "report.exported", {
      subject: { collection: "", id: "", label: "" },
      detail: {
        report: "annual",
        format: "pdf",
        year: year,
        month: period.month,
        lang: lang,
        rows: caseRows.length,
      },
    });
    return e.blob(200, "application/pdf", bytes);
  },
  $apis.requireAuth(),
);
