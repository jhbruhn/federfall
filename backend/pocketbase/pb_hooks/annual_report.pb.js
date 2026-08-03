/// <reference path="../pb_data/types.d.ts" />

// federfall-dk0c — annual report (REQUIREMENTS.md §10), rendered server-side
// with Typst exactly like the per-case report (case_report.pb.js): the binary
// lives in the image via the root Dockerfile's typstfetch stage, templates in
// ../typst/.
//
// ONE route serves BOTH output formats — `?format=pdf` (default) and
// `?format=csv` — for the same reason case_report.pb.js serves its thermal
// receipt off its PDF route: every routerAdd handler is its own isolated JSVM
// context, so two routes could not share the ~200 lines of gathering and
// aggregation below, and the whole point of this change is that the PDF's
// per-case table and the CSV are the SAME table. Both read the
// `case_report_rows` view (1700000063 + 1700000066), which is the single
// definition of that table's columns; neither selects columns of its own.
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
    // ── Auth: mirrors the `case_report_rows` view rule (1700000063) — the
    // figures here are org-wide by construction (every case, regardless of
    // carer or share), which is exactly why that view and the app's
    // statistics screen are both coordinator/supervisor-only. A carer must
    // not get an org-wide roster through a report route the collection rules
    // would have denied.
    const auth = e.auth;
    if (
      !auth ||
      !auth.getBool("is_active") ||
      auth.getString("role") === "guest"
    ) {
      throw new ForbiddenError("Not allowed.");
    }
    const role = auth.getString("role");
    if (role !== "coordinator" && role !== "supervisor") {
      throw new ForbiddenError("Not allowed.");
    }
    const org = auth.getString("org");
    if (!org) throw new ForbiddenError("No organisation.");

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

    const yearParam = query.get("year");
    let year = null;
    if (yearParam) {
      const parsed = parseInt(yearParam, 10);
      // A deliberately wide but finite window: anything outside it is a
      // garbled param, not a reporting period, and would otherwise produce a
      // confidently empty report.
      if (isNaN(parsed) || parsed < 1900 || parsed > 2200) {
        throw new BadRequestError("year must be a four-digit calendar year.");
      }
      year = parsed;
    }

    // ── Caller-local time (duplicated from case_report.pb.js — handlers are
    // isolated JSVM contexts, so file-level helpers are NOT in scope inside
    // one). Falls back to the EU's own Europe/Berlin DST rule when the param
    // is absent or out of range.
    const lastSundayUTC = (y, monthIndex) => {
      const lastDay = new Date(Date.UTC(y, monthIndex + 1, 0));
      return lastDay.getUTCDate() - lastDay.getUTCDay();
    };
    const berlinOffsetMinutes = (utcMs) => {
      const y = new Date(utcMs).getUTCFullYear();
      const dstStart = Date.UTC(y, 2, lastSundayUTC(y, 2), 1, 0, 0);
      const dstEnd = Date.UTC(y, 9, lastSundayUTC(y, 9), 1, 0, 0);
      return (utcMs >= dstStart && utcMs < dstEnd ? 2 : 1) * 60;
    };
    const tzParam = parseInt(query.get("tzOffsetMinutes"), 10);
    const explicitOffsetMinutes =
      !isNaN(tzParam) && tzParam >= -720 && tzParam <= 840 ? tzParam : null;
    const offsetFor = (utcMs) =>
      explicitOffsetMinutes !== null
        ? explicitOffsetMinutes
        : berlinOffsetMinutes(utcMs);

    const parseMs = (value) => {
      if (!value) return null;
      const d = new Date(String(value).replace(" ", "T"));
      return isNaN(d.getTime()) ? null : d.getTime();
    };
    // Wall-clock parts in the caller's zone. The templates build a Typst
    // `datetime` from these and format it themselves; the CSV renders them as
    // ISO yyyy-mm-dd. Note this is the caller's LOCAL calendar date — the
    // superseded client-side CSV formatted PocketBase's UTC instant instead
    // (federfall_models' `pbDate` returns UTC), which printed 2025-12-31 for a
    // case admitted at 00:30 on New Year's Day in UTC+2 and disagreed with the
    // very year filter that selected it.
    const partsOf = (value) => {
      const ms = parseMs(value);
      if (ms === null) return null;
      const local = new Date(ms + offsetFor(ms) * 60000);
      return {
        y: local.getUTCFullYear(),
        mo: local.getUTCMonth() + 1,
        d: local.getUTCDate(),
        h: local.getUTCHours(),
        mi: local.getUTCMinutes(),
      };
    };

    // ── Period bounds, as the stored PocketBase date format so they can be
    // compared directly by the collection filter below.
    const pbStamp = (ms) => new Date(ms).toISOString().replace("T", " ");
    let fromMs = null;
    let toMs = null; // exclusive
    if (year !== null) {
      // The offset is resolved from the boundary instant itself, so a January
      // boundary uses winter time and the report's own year does not shift.
      const naiveFrom = Date.UTC(year, 0, 1);
      const naiveTo = Date.UTC(year + 1, 0, 1);
      fromMs = naiveFrom - offsetFor(naiveFrom) * 60000;
      toMs = naiveTo - offsetFor(naiveTo) * 60000;
    }

    // ── The table: one pre-joined row per case off `case_report_rows`. Its
    // columns ARE the report table (and the CSV) — nothing here adds or
    // renames one.
    const rowFilter =
      year !== null
        ? "org = {:org} && admitted_at >= {:from} && admitted_at < {:to}"
        : "org = {:org}";
    const rowParams =
      year !== null
        ? { org: org, from: pbStamp(fromMs), to: pbStamp(toMs) }
        : { org: org };
    const rows = e.app.findRecordsByFilter(
      "case_report_rows",
      rowFilter,
      "",
      0,
      0,
      rowParams,
    );

    // ── Reading a view row: PocketBase can only infer a view column's type
    // when the column traces back to a real collection field. `case_number`,
    // `status`, `admitted_at`, `found_at`, `city` and `region` do (they are
    // plain `c.<field>` references, typed date/text as expected), but every
    // COMPUTED column — species, name, outcome, ended_at, markings, reasons —
    // falls back to type `json`, and `getString()` on a json field returns the
    // raw JSON, i.e. `"Hohltaube"` WITH the quotes. The REST API decodes that
    // on the way out, which is why the superseded Dart client never saw it and
    // why this only bites a server-side reader.
    //
    // Left un-decoded it is not merely cosmetic: `ended_at` would fail to
    // parse (so every case would read as still open), an outcome would never
    // match its label map, and the CSV's formula guard would inspect a leading
    // `"` instead of the `=` it exists to catch. So the json-typed columns are
    // asked for by type and decoded, rather than guessed at per value — a city
    // legitimately named `true` or `123` would parse as JSON just fine.
    const jsonFields = {};
    for (const field of e.app.findCollectionByNameOrId("case_report_rows")
      .fields) {
      if (field.type() === "json") jsonFields[field.getName()] = true;
    }
    const str = (r, name) => {
      const raw = r.getString(name);
      if (!jsonFields[name]) return raw;
      try {
        const parsed = JSON.parse(raw);
        return parsed === null ? "" : String(parsed);
      } catch (_) {
        // Not valid JSON after all — take it as written rather than dropping
        // a cell the report is supposed to print.
        return raw;
      }
    };

    // A case with no admission date cannot belong to a period, so the filter
    // above already excludes it from a yearly report (PocketBase stores an
    // unset date as "", which fails both comparisons); in an all-time report
    // it is included and sorted last rather than first, which is what a plain
    // ascending sort on the empty string would have done.
    const caseRows = rows.map((r) => {
      const admittedAt = str(r, "admitted_at");
      const endedAt = str(r, "ended_at");
      const admittedMs = parseMs(admittedAt);
      const endedMs = parseMs(endedAt);
      // Same definition the app's own figures use: whole days from admission
      // to the terminal disposition, and never negative (statistics
      // providers and the superseded CaseReportRow.daysInCare both refuse a
      // backwards span rather than reporting a negative stay).
      const spanMs =
        admittedMs !== null && endedMs !== null && endedMs >= admittedMs
          ? endedMs - admittedMs
          : null;
      return {
        id: r.id,
        caseNumber: str(r, "case_number"),
        species: str(r, "species"),
        name: str(r, "name"),
        markings: str(r, "markings"),
        foundAt: str(r, "found_at"),
        admittedAt: admittedAt,
        endedAt: endedAt,
        status: str(r, "status"),
        outcome: str(r, "outcome"),
        city: str(r, "city"),
        region: str(r, "region"),
        reasons: str(r, "reasons"),
        admittedMs: admittedMs,
        spanMs: spanMs,
        days: spanMs === null ? null : Math.floor(spanMs / 86400000),
      };
    });
    caseRows.sort((a, b) => {
      if (a.admittedMs === null && b.admittedMs === null) {
        return a.caseNumber < b.caseNumber ? -1 : 1;
      }
      if (a.admittedMs === null) return 1;
      if (b.admittedMs === null) return -1;
      if (a.admittedMs !== b.admittedMs) return a.admittedMs - b.admittedMs;
      return a.caseNumber < b.caseNumber ? -1 : 1;
    });

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

      const csvName =
        (lang === "en" ? "federfall-annual-report-" : "federfall-jahresbericht-") +
        (year !== null ? String(year) : lang === "en" ? "all-time" : "gesamt");
      e.response
        .header()
        .set("Content-Disposition", 'attachment; filename="' + csvName + '.csv"');
      return e.blob(200, "text/csv; charset=utf-8", new Uint8Array(bytes));
    }

    // ── Aggregates (PDF only) ───────────────────────────────────────────────
    // Every definition here matches the app's statistics screen
    // (statistics_providers.dart's computeStatistics) so the printed report
    // and the on-screen figures agree for the same scope — including the mean
    // stay being a FRACTIONAL day count (hours/24), not the whole days the
    // per-case column shows.
    const ranked = (counts) => {
      const list = Object.keys(counts).map((k) => ({
        label: k,
        count: counts[k],
      }));
      list.sort((a, b) =>
        b.count !== a.count
          ? b.count - a.count
          : a.label < b.label
            ? -1
            : a.label > b.label
              ? 1
              : 0,
      );
      return list;
    };
    const bump = (map, key) => {
      if (!key) return;
      map[key] = (map[key] || 0) + 1;
    };

    const speciesCounts = {};
    const reasonCounts = {};
    const cityCounts = {};
    const outcomeCounts = {};
    const bucketCounts = {};
    let closed = 0;
    let releasedCount = 0;
    let spanTotalDays = 0;
    let spanCount = 0;
    for (const r of caseRows) {
      bump(speciesCounts, r.species);
      bump(cityCounts, r.city);
      // The view joined the admission reasons with "; " into one cell (a
      // multi-relation cannot be a column otherwise), so the breakdown splits
      // that back apart — a code-list label containing "; " itself would be
      // miscounted here, which is why the code list is authored as short
      // labels.
      if (r.reasons) {
        for (const part of r.reasons.split("; ")) {
          bump(reasonCounts, part.trim());
        }
      }
      // Three distinct states, not two: no disposition at all (still open),
      // a disposition whose type this build cannot name, and a named
      // outcome. Bucketing the middle one as "open" would understate the
      // closed count, and dropping it would stop the column adding up.
      if (r.endedAt) {
        closed++;
        outcomeCounts[r.outcome || ""] = (outcomeCounts[r.outcome || ""] || 0) + 1;
        if (r.outcome === "released") releasedCount++;
      }
      if (r.spanMs !== null) {
        spanTotalDays += r.spanMs / 3600000 / 24;
        spanCount++;
      }
      if (r.admittedMs !== null) {
        const p = partsOf(r.admittedAt);
        const key = year !== null ? p.mo : p.y;
        bucketCounts[key] = (bucketCounts[key] || 0) + 1;
      }
    }
    const openCount = caseRows.length - closed;

    // Outcomes: named types first (by count), then the unnamed-type bucket,
    // then "still open" last — it is not an outcome, it is the absence of one.
    const outcomes = ranked(outcomeCounts).map((o) => ({
      type: o.label === "" ? "" : o.label,
      count: o.count,
    }));
    if (openCount > 0) outcomes.push({ type: null, count: openCount });

    // Intake buckets: months within a year, calendar years over all time.
    // Every month is emitted even at zero so the chart reads as a year rather
    // than as a list of the months that happened to have intakes.
    const buckets = [];
    if (year !== null) {
      for (let m = 1; m <= 12; m++) {
        buckets.push({ key: m, count: bucketCounts[m] || 0 });
      }
    } else {
      const years = Object.keys(bucketCounts)
        .map((k) => parseInt(k, 10))
        .sort((a, b) => a - b);
      if (years.length > 0) {
        for (let y = years[0]; y <= years[years.length - 1]; y++) {
          buckets.push({ key: y, count: bucketCounts[y] || 0 });
        }
      }
    }

    // ── Diagnoses: counted per DISTINCT case, exactly as the
    // `condition_labels` view (1700000062) does for the statistics screen —
    // but narrowed to this period's cases, which an org-wide view column
    // cannot be. Resolved the same way too: the code-list label, else the
    // row's free text.
    const caseIds = {};
    for (const r of caseRows) caseIds[r.id] = true;
    const conditionLabels = {};
    for (const c of e.app.findRecordsByFilter("conditions", "id != ''", "", 0, 0)) {
      conditionLabels[c.id] = c.getString("label");
    }
    const seenPerLabel = {};
    const conditionCounts = {};
    for (const cc of e.app.findRecordsByFilter(
      "case_conditions",
      "org = {:org}",
      "",
      0,
      0,
      { org: org },
    )) {
      const caseId = cc.getString("case");
      if (!caseIds[caseId]) continue;
      const label =
        conditionLabels[cc.getString("condition")] || cc.getString("free_text");
      if (!label) continue;
      const key = label + " " + caseId;
      if (seenPerLabel[key]) continue;
      seenPerLabel[key] = true;
      bump(conditionCounts, label);
    }

    // ── Markings: scoped by APPLICATION date, not by the case cohort. "How
    // many rings did we issue in 2026" is the figure a ringing scheme asks
    // for, and it is a different question from "which birds came in in 2026"
    // — a bird admitted in December and ringed in January belongs to one and
    // not the other. The PDF prints each section's basis for that reason.
    // Unlike the per-case `markings` column (which shows what is currently on
    // the bird), this lists removals too: it is the record of what the org
    // did.
    const markingTypeLabels = {};
    for (const t of e.app.findRecordsByFilter(
      "marking_types",
      "id != ''",
      "",
      0,
      0,
    )) {
      markingTypeLabels[t.id] = t.getString("label");
    }
    const markingFilter =
      year !== null
        ? "org = {:org} && applied_at >= {:from} && applied_at < {:to}"
        : "org = {:org}";
    const markingRecords = e.app.findRecordsByFilter(
      "markings",
      markingFilter,
      "applied_at",
      0,
      0,
      rowParams,
    );
    const caseNumbers = {};
    const markingTypeCounts = {};
    const markingRows = markingRecords.map((m) => {
      const inCase = m.getString("applied_in_case");
      if (inCase && caseNumbers[inCase] === undefined) {
        try {
          caseNumbers[inCase] = e.app
            .findRecordById("cases", inCase)
            .getString("case_number");
        } catch (_) {
          // The case was deleted (supervisor-only cascade, see 1700000057)
          // while the animal-level marking survived — the marking is still a
          // real thing the org applied, so it is reported without a case.
          caseNumbers[inCase] = "";
        }
      }
      const typeLabel = markingTypeLabels[m.getString("type")] || "";
      bump(markingTypeCounts, typeLabel);
      return {
        type: typeLabel,
        colour: m.getString("colour"),
        code: m.getString("code"),
        schemeOrg: m.getString("scheme_org"),
        appliedAt: partsOf(m.getString("applied_at")),
        caseNumber: inCase ? caseNumbers[inCase] : "",
        removedAt: partsOf(m.getString("removed_at")),
      };
    });

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
        from: year !== null ? partsOf(pbStamp(fromMs)) : null,
        // The inclusive last day of the period, because that is what a
        // reader expects to see printed ("01.01. – 31.12."), while the filter
        // above is a half-open range.
        to: year !== null ? partsOf(pbStamp(toMs - 1)) : null,
      },
      totals: {
        intakes: caseRows.length,
        closed: closed,
        inCare: openCount,
        avgDaysInCare: spanCount === 0 ? null : spanTotalDays / spanCount,
        releaseRate: closed === 0 ? null : releasedCount / closed,
      },
      bucketKind: year !== null ? "month" : "year",
      intakesByBucket: buckets,
      outcomes: outcomes,
      species: ranked(speciesCounts),
      reasons: ranked(reasonCounts),
      conditions: ranked(conditionCounts),
      cities: ranked(cityCounts),
      markings: {
        total: markingRows.length,
        byType: ranked(markingTypeCounts),
        rows: markingRows,
      },
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
    const outPath =
      $os.tempDir() +
      "/federfall-annual-" +
      (year !== null ? year : "all") +
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
          "/pb",
          "--input",
          "data=" + JSON.stringify(payload),
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

    const pdfName =
      (lang === "en" ? "federfall-annual-report-" : "federfall-jahresbericht-") +
      (year !== null ? String(year) : lang === "en" ? "all-time" : "gesamt");
    e.response
      .header()
      .set("Content-Disposition", 'attachment; filename="' + pdfName + '.pdf"');
    return e.blob(200, "application/pdf", bytes);
  },
  $apis.requireAuth(),
);
