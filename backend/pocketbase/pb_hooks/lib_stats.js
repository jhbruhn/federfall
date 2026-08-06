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
//   const org = require(`${__hooks}/lib_auth.js`).requireReporting(e);
//   const stats = require(`${__hooks}/lib_stats.js`);
//   const t = require(`${__hooks}/lib_time.js`).timeContext(query);
//   const period = stats.parsePeriod(e.request.url.query());
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

/**
 * `?year=` + `?month=` → the reporting period: a calendar year, one month of
 * one, or `{year: null, month: null}` for everything on record.
 *
 * Throws BadRequestError on anything else: a garbled param is not a reporting
 * period, and would otherwise produce a confidently empty report. A month
 * without a year is refused for the same reason — "March" alone names no
 * period, and silently reading it as "March this year" would put a figure on
 * screen that the caller never asked for.
 */
function parsePeriod(query) {
  const rawYear = query.get("year");
  let year = null;
  if (rawYear) {
    const parsed = parseInt(rawYear, 10);
    // Deliberately wide but finite.
    if (isNaN(parsed) || parsed < 1900 || parsed > 2200) {
      throw new BadRequestError("year must be a four-digit calendar year.");
    }
    year = parsed;
  }

  const rawMonth = query.get("month");
  let month = null;
  if (rawMonth) {
    const parsed = parseInt(rawMonth, 10);
    if (isNaN(parsed) || parsed < 1 || parsed > 12) {
      throw new BadRequestError("month must be 1-12.");
    }
    if (year === null) {
      throw new BadRequestError("month requires a year.");
    }
    month = parsed;
  }

  return { year: year, month: month };
}

/**
 * The half-open instant range of a period in the caller's zone, or null for
 * an all-time one.
 *
 * The offset is resolved from each boundary instant itself, so a January
 * boundary uses winter time and the period's own year does not shift — and a
 * summer month is not dragged an hour wide by the winter offset.
 */
function periodBounds(period, t) {
  if (period.year === null) return null;
  const month = period.month === null ? 0 : period.month - 1;
  const naiveFrom = Date.UTC(period.year, month, 1);
  const naiveTo =
    period.month === null
      ? Date.UTC(period.year + 1, 0, 1)
      : Date.UTC(period.year, month + 1, 1);
  return {
    fromMs: naiveFrom - t.offsetFor(naiveFrom) * 60000,
    toMs: naiveTo - t.offsetFor(naiveTo) * 60000,
  };
}

/** How many days a period's month has (1-12 → 28..31). */
function daysInMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
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
 * `opts.period` is `{year, month}` and decides the intake buckets: DAYS within
 * a month, months within a year, calendar years over all time. Every bucket of
 * the period is emitted even at zero, so the chart reads as a period rather
 * than as a list of the buckets that happened to have intakes — a Tuesday with
 * no admissions is a fact about the week.
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
  const period = opts.period;
  const year = period.year;
  const month = period.month;

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
      const key = month !== null ? p.d : year !== null ? p.mo : p.y;
      bucketCounts[key] = (bucketCounts[key] || 0) + 1;
    }
  }
  const openCount = rows.length - closed;

  const buckets = [];
  if (month !== null) {
    const days = daysInMonth(year, month);
    for (let d = 1; d <= days; d++) {
      buckets.push({ key: d, count: bucketCounts[d] || 0 });
    }
  } else if (year !== null) {
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
    bucketKind: month !== null ? "day" : year !== null ? "month" : "year",
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

module.exports = {
  parsePeriod: parsePeriod,
  periodBounds: periodBounds,
  daysInMonth: daysInMonth,
  loadCaseRows: loadCaseRows,
  ranked: ranked,
  aggregate: aggregate,
  conditionCounts: conditionCounts,
};
