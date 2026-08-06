/// <reference path="../pb_data/types.d.ts" />

// federfall-nmwi — the reporting core: what a period is, which rows fall in
// it, and every figure computed over them.
//
// Two consumers, one definition:
//   • annual_report.pb.js — the Typst PDF and its CSV twin
//   • stats.pb.js         — GET /api/federfall/stats, i.e. the app's
//                           statistics screen
// The screen and the printed report are answers to the same question, so
// "2026" has to mean the same instant range in both, an outcome rate has to
// have the same denominator, and the mean stay has to be the same mean. That
// is only guaranteed if there is one implementation — hence this module rather
// than a second copy of the ~150 lines that used to live in annual_report.pb.js.
//
// Usage — `require()` INSIDE the handler, never at file level, and always with
// the `${__hooks}` absolute form (a relative path fails with "Invalid module"),
// exactly as lib_audit.js documents:
//
//   const stats = require(`${__hooks}/lib_stats.js`);
//   const t = stats.timeContext(e.request.url.query());
//   const year = stats.parseYear(e.request.url.query());
//   const rows = stats.loadCaseRows(e.app, org, bounds.fromMs, bounds.toMs, t);
//
// This file is NOT named *.pb.js, so PocketBase does not load it as a hook —
// it is only ever reachable through that require(). A required module keeps
// its own file-level scope (verified for lib_audit.js on 0.39.8), which is why
// the helpers below can live out here at all: inside a hook handler they could
// not, since each handler runs in an isolated JSVM context.
//
// STATELESS, like lib_audit.js: PocketBase pools JSVMs and each pooled VM holds
// its own instance of this module, so nothing here may cache between calls.

// ── Caller-local time ────────────────────────────────────────────────────────
// goja has no Intl and the image carries no tzdata, so a zone name cannot be
// resolved server-side. The client states its own UTC offset instead
// (`?tzOffsetMinutes=`, the same convention case_report.pb.js uses); absent or
// out of range, we fall back to the EU's own Europe/Berlin DST rule, which is
// right for this app's users and never worse than assuming UTC.

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

/**
 * The date helpers for one request, all sharing the caller's offset.
 *
 * `query` is `e.request.url.query()`. `.get()` yields "" (not null) for an
 * absent param — the convention geocode.pb.js and case_report.pb.js follow.
 */
function timeContext(query) {
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

  // Wall-clock parts in the caller's zone. The Typst templates build a
  // `datetime` from these and format it themselves; the CSV renders them as
  // ISO yyyy-mm-dd; the statistics route buckets on `.y`/`.mo`. Note this is
  // the caller's LOCAL calendar date — formatting PocketBase's UTC instant
  // instead printed 2025-12-31 for a case admitted at 00:30 on New Year's Day
  // in UTC+2, disagreeing with the very year filter that selected it.
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

  // The stored PocketBase date format, so a bound can be compared directly by
  // a collection filter.
  const pbStamp = (ms) => new Date(ms).toISOString().replace("T", " ");

  return {
    explicitOffsetMinutes: explicitOffsetMinutes,
    offsetFor: offsetFor,
    parseMs: parseMs,
    partsOf: partsOf,
    pbStamp: pbStamp,
  };
}

/**
 * `?year=` → a four-digit calendar year, or null for "everything on record".
 * Throws BadRequestError on anything else: a garbled param is not a reporting
 * period, and would otherwise produce a confidently empty report.
 */
function parseYear(query) {
  const raw = query.get("year");
  if (!raw) return null;
  const parsed = parseInt(raw, 10);
  // Deliberately wide but finite.
  if (isNaN(parsed) || parsed < 1900 || parsed > 2200) {
    throw new BadRequestError("year must be a four-digit calendar year.");
  }
  return parsed;
}

/**
 * The half-open instant range of a calendar year in the caller's zone.
 *
 * The offset is resolved from the boundary instant itself, so a January
 * boundary uses winter time and the period's own year does not shift.
 */
function yearBounds(year, t) {
  const naiveFrom = Date.UTC(year, 0, 1);
  const naiveTo = Date.UTC(year + 1, 0, 1);
  return {
    fromMs: naiveFrom - t.offsetFor(naiveFrom) * 60000,
    toMs: naiveTo - t.offsetFor(naiveTo) * 60000,
  };
}

/**
 * The org's cases as pre-joined `case_report_rows` rows (1700000063 +
 * 1700000066 + 1700000067), decoded and sorted by admission.
 *
 * `fromMs`/`toMs` are the half-open period bounds, or null/null for every case
 * on record. A case with no admission date cannot belong to a period, so the
 * filter already excludes it from a bounded read (PocketBase stores an unset
 * date as "", which fails both comparisons); in an unbounded read it is kept
 * and sorted LAST rather than first, which is what a plain ascending sort on
 * the empty string would have done.
 *
 * ── Reading a view row ──────────────────────────────────────────────────────
 * PocketBase can only infer a view column's type when the column traces back to
 * a real collection field. `case_number`, `status`, `admitted_at`, `found_at`,
 * `city` and `region` do (plain `c.<field>` references, typed date/text as
 * expected), but every COMPUTED column — species, name, outcome, ended_at,
 * markings, reasons — falls back to type `json`, and `getString()` on a json
 * field returns the raw JSON, i.e. `"Hohltaube"` WITH the quotes. The REST API
 * decodes that on the way out, which is why only a server-side reader sees it.
 *
 * Left un-decoded it is not merely cosmetic: `ended_at` would fail to parse (so
 * every case would read as still open), an outcome would never match its label
 * map, and the CSV's formula guard would inspect a leading `"` instead of the
 * `=` it exists to catch. So the json-typed columns are asked for BY TYPE and
 * decoded, rather than guessed at per value — a city legitimately named `true`
 * or `123` would parse as JSON just fine.
 */
function loadCaseRows(app, org, fromMs, toMs, t) {
  const bounded = fromMs !== null && fromMs !== undefined;
  const filter = bounded
    ? "org = {:org} && admitted_at >= {:from} && admitted_at < {:to}"
    : "org = {:org}";
  const params = bounded
    ? { org: org, from: t.pbStamp(fromMs), to: t.pbStamp(toMs) }
    : { org: org };
  const rows = app.findRecordsByFilter(
    "case_report_rows",
    filter,
    "",
    0,
    0,
    params,
  );

  const jsonFields = {};
  for (const field of app.findCollectionByNameOrId("case_report_rows").fields) {
    if (field.type() === "json") jsonFields[field.getName()] = true;
  }
  const str = (r, name) => {
    const raw = r.getString(name);
    if (!jsonFields[name]) return raw;
    try {
      const parsed = JSON.parse(raw);
      return parsed === null ? "" : String(parsed);
    } catch (_) {
      // Not valid JSON after all — take it as written rather than dropping a
      // cell the report is supposed to print.
      return raw;
    }
  };

  const caseRows = rows.map((r) => {
    const admittedAt = str(r, "admitted_at");
    const endedAt = str(r, "ended_at");
    const admittedMs = t.parseMs(admittedAt);
    const endedMs = t.parseMs(endedAt);
    // Whole days from admission to the terminal disposition, and never
    // negative — a backwards span is refused rather than reported as a
    // negative stay.
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
  return caseRows;
}

/** Sorts a label→count map into `{label, count}`, highest first then label. */
function ranked(counts) {
  const list = Object.keys(counts).map((k) => ({ label: k, count: counts[k] }));
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
}

/**
 * Every figure the report and the statistics screen show, over `rows`.
 *
 * `opts.year` is the selected calendar year (null = all time) and decides the
 * intake buckets: months within a year, calendar years over all time. Every
 * month of a year is emitted even at zero, so the chart reads as a year rather
 * than as a list of the months that happened to have intakes.
 *
 * Rates, and why they are computed here rather than in the client: the
 * denominator is ENDED cases, not intakes. A rehab's release rate is the share
 * released of the cases that reached an outcome — over intakes it would sag
 * every time admissions rise, which is exactly when it must not. Mortality is
 * `died + euthanized` over the same denominator: a bird that was put down did
 * not survive, and splitting the two would understate what a reader is asking.
 * Both are null when nothing has ended — an undefined rate, not 0%.
 */
function aggregate(rows, opts) {
  const t = opts.t;
  const year = opts.year;

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
  let deadCount = 0;
  let spanTotalDays = 0;
  let spanCount = 0;
  for (const r of rows) {
    bump(speciesCounts, r.species);
    bump(cityCounts, r.city);
    // The view joined the admission reasons with "; " into one cell (a
    // multi-relation cannot be a column otherwise), so the breakdown splits
    // that back apart — a code-list label containing "; " itself would be
    // miscounted here, which is why the code list is authored as short labels.
    if (r.reasons) {
      for (const part of r.reasons.split("; ")) {
        bump(reasonCounts, part.trim());
      }
    }
    // Three distinct states, not two: no disposition at all (still open), a
    // disposition whose type a client cannot name, and a named outcome.
    // Bucketing the middle one as "open" would understate the closed count,
    // and dropping it would stop the column adding up.
    if (r.endedAt) {
      closed++;
      outcomeCounts[r.outcome || ""] = (outcomeCounts[r.outcome || ""] || 0) + 1;
      if (r.outcome === "released") releasedCount++;
      if (r.outcome === "died" || r.outcome === "euthanized") deadCount++;
    }
    if (r.spanMs !== null) {
      spanTotalDays += r.spanMs / 3600000 / 24;
      spanCount++;
    }
    if (r.admittedMs !== null) {
      const p = t.partsOf(r.admittedAt);
      const key = year !== null ? p.mo : p.y;
      bucketCounts[key] = (bucketCounts[key] || 0) + 1;
    }
  }
  const openCount = rows.length - closed;

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

  return {
    totals: {
      intakes: rows.length,
      closed: closed,
      inCare: openCount,
      // A FRACTIONAL day count (hours/24), not the whole days the per-case
      // column shows — the mean of ten short stays is not a whole number.
      avgDaysInCare: spanCount === 0 ? null : spanTotalDays / spanCount,
      releaseRate: closed === 0 ? null : releasedCount / closed,
      mortalityRate: closed === 0 ? null : deadCount / closed,
    },
    // Ended cases by outcome; "" is the bucket for a type the reader cannot
    // name. Still-open cases are NOT an outcome and are left to the caller to
    // append (the PDF does, the statistics screen shows them as a KPI).
    outcomes: ranked(outcomeCounts),
    species: ranked(speciesCounts),
    reasons: ranked(reasonCounts),
    cities: ranked(cityCounts),
    bucketKind: year !== null ? "month" : "year",
    intakesByBucket: buckets,
  };
}

/**
 * Diagnoses counted per DISTINCT case over `rows`, exactly as the
 * `condition_labels` view (1700000062) does for the org — but narrowed to this
 * period's cases, which an org-wide view column cannot be. Resolved the same
 * way too: the code-list label, else the row's free text.
 */
function conditionCounts(app, org, rows) {
  const caseIds = {};
  for (const r of rows) caseIds[r.id] = true;

  const conditionLabels = {};
  for (const c of app.findRecordsByFilter("conditions", "id != ''", "", 0, 0)) {
    conditionLabels[c.id] = c.getString("label");
  }

  const seenPerLabel = {};
  const counts = {};
  for (const cc of app.findRecordsByFilter(
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
    const key = label + " " + caseId;
    if (seenPerLabel[key]) continue;
    seenPerLabel[key] = true;
    counts[label] = (counts[label] || 0) + 1;
  }
  return ranked(counts);
}

/**
 * Rejects anyone who may not read org-wide figures, and returns the caller's
 * org id.
 *
 * Mirrors the `case_report_rows` view rule (1700000063): everything computed
 * from those rows is org-wide by construction — every case, regardless of
 * carer or share — which is exactly why the view, the report route and the
 * app's statistics screen are all coordinator/supervisor-only. A carer must
 * not get an org-wide roster through a route the collection rules would have
 * denied.
 */
function requireReportingAuth(e) {
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
  return org;
}

module.exports = {
  timeContext: timeContext,
  parseYear: parseYear,
  yearBounds: yearBounds,
  loadCaseRows: loadCaseRows,
  ranked: ranked,
  aggregate: aggregate,
  conditionCounts: conditionCounts,
  requireReportingAuth: requireReportingAuth,
};
