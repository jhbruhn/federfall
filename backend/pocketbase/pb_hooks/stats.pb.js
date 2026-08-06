/// <reference path="../pb_data/types.d.ts" />

// federfall-nmwi — GET /api/federfall/stats: everything the app's statistics
// screen shows, computed server-side over the `case_report_rows` view.
//
// Why server-side. The screen used to aggregate client-side over `cases` +
// `dispositions` + `animals`, pulled unpaginated to the device — the same
// mistake federfall-80tc fixed for the CSV export. A monthly series with the
// previous year behind it needs MORE history than that, not less, so the
// aggregation moved to where the rows already are.
//
// Why the same module as the annual report. The screen and the printed report
// answer the same question, and a reader will put them side by side. So the
// period, the row set and every figure come from lib_stats.js, which
// annual_report.pb.js also uses: "2026" is one instant range, the release rate
// has one denominator, and the mean stay is one mean.
//
// ── Response ────────────────────────────────────────────────────────────────
// {
//   "period":  { "year": 2026 | null },
//   "totals":  { "intakes", "closed", "inCare",
//                "avgDaysInCare"|null, "releaseRate"|null, "mortalityRate"|null },
//   "series":  { "kind": "month" | "year",
//                "points":   [{ "key": 1..12 | <year>, "count": n }],
//                "previous": { "year": 2025, "points": [...] } | null },
//   "outcomes":   [{ "type": "released" | "", "count": n }],
//   "species":    [{ "label": "Stadttaube", "count": n }],
//   "conditions": [{ "label": "Trichomoniasis", "count": n }],
//   "intakeYears": [2026, 2025, 2024]
// }
//
// `series.kind` is "month" for a selected year (keys 1–12, every month emitted
// even at zero) and "year" over all time (keys are calendar years, the range
// filled in so a gap year is a zero and not a missing column). `previous` is
// the year before the selected one and is omitted when that year had no
// intakes at all — an all-zero comparison series is noise, not a comparison.
//
// `outcomes` counts ENDED cases only; `""` is a disposition type the reader's
// build cannot name. Still-open cases are reported as `totals.inCare`, not as
// an outcome. `intakeYears` is org-wide regardless of the selected period —
// it is what the period picker (and the annual report's) offers.
//
// Values stay WIRE strings; translating them is the reader's job, exactly as
// for the audit log. Deliberately NOT audited: this is an aggregate read, and
// the audit log records data LEAVING the system (report.exported), not looking
// at it.
routerAdd(
  "GET",
  "/api/federfall/stats",
  (e) => {
    const stats = require(`${__hooks}/lib_stats.js`);
    const org = require(`${__hooks}/lib_auth.js`).requireReporting(e);

    const query = e.request.url.query();
    const year = stats.parseYear(query);
    const t = stats.timeContext(query);

    // Every case on record, once, then partitioned in JS — the previous year's
    // series, the selected period and the list of years with intakes all come
    // out of the same read, where three filtered queries would cost three
    // joins over the same view. Bucketing by the row's LOCAL admission year is
    // equivalent to the annual report's `admitted_at >= from && < to` filter:
    // both resolve the boundary through the caller's offset, so a case admitted
    // at 00:30 on New Year's Day lands in the same year for both.
    const rows = stats.loadCaseRows(e.app, org, null, null, t);
    const yearOf = (r) => {
      const p = t.partsOf(r.admittedAt);
      return p === null ? null : p.y;
    };

    const periodRows =
      year === null ? rows : rows.filter((r) => yearOf(r) === year);
    const agg = stats.aggregate(periodRows, { t: t, year: year });

    let previous = null;
    if (year !== null) {
      const prevRows = rows.filter((r) => yearOf(r) === year - 1);
      if (prevRows.length > 0) {
        previous = {
          year: year - 1,
          points: stats.aggregate(prevRows, { t: t, year: year - 1 })
            .intakesByBucket,
        };
      }
    }

    const seen = {};
    const intakeYears = [];
    for (const r of rows) {
      const y = yearOf(r);
      if (y === null || seen[y]) continue;
      seen[y] = true;
      intakeYears.push(y);
    }
    intakeYears.sort((a, b) => b - a);

    return e.json(200, {
      period: { year: year },
      totals: agg.totals,
      series: {
        kind: agg.bucketKind,
        points: agg.intakesByBucket,
        previous: previous,
      },
      // `{label, count}` from the module → `{type, count}`: the key names a
      // disposition's WIRE value, not a display label, and the reader
      // translates it (audit-log stance — the server has no business picking
      // the reader's language).
      outcomes: agg.outcomes.map((o) => ({ type: o.label, count: o.count })),
      species: agg.species,
      // Narrowed to the period's cases, unlike the org-wide `condition_labels`
      // view the screen used to read — a breakdown that ignored the selected
      // period would not add up against the outcomes beside it.
      conditions: stats.conditionCounts(e.app, org, periodRows),
      intakeYears: intakeYears,
    });
  },
  $apis.requireAuth(),
);
