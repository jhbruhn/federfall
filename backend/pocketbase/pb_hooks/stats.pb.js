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
//   "period":  { "year": 2026 | null, "month": 3 | null },
//   "totals":  { "intakes", "closed", "inCare",
//                "avgDaysInCare"|null, "releaseRate"|null, "mortalityRate"|null },
//   "series":  { "kind": "day" | "month" | "year",
//                "points":   [{ "key": 1..31 | 1..12 | <year>, "count": n }],
//                "previous": { "year": 2025, "month": 3|null, "points": [...] }
//                            | null },
//   "outcomes":   [{ "type": "released" | "", "count": n }],
//   "species":    [{ "label": "Stadttaube", "count": n }],
//   "conditions": [{ "label": "Trichomoniasis", "count": n }],
//   "intakeYears": [2026, 2025, 2024],
//   "sponsorships": { "total", "active", "monthlyCents",
//                     "oneTimeCents", "noIntervalCents" }
// }
//
// `series.kind` follows the period: "day" for a selected month (keys 1..28-31),
// "month" for a selected year (keys 1–12), "year" over all time (keys are
// calendar years, the range filled in so a gap year is a zero and not a missing
// column). Every bucket of the period is emitted even at zero. `previous` is
// the SAME period one year earlier — last March for March, not February — and
// is omitted when that period had no intakes at all, since an all-zero
// comparison series is noise rather than a comparison.
//
// `sponsorships` is the ONE block here that is not period-scoped
// (federfall-ys7z): it is what is being given right now, which `?year=` has no
// bearing on. It is served from this route rather than from a count view because
// the route is already `canViewReports`-gated and already the app's one place
// for org-wide figures — and because a patronage total cannot be summed on the
// device (federfall-trep: no screen reads a collection to aggregate it locally).
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
    const period = stats.parsePeriod(query);
    const year = period.year;
    const month = period.month;
    const t = require(`${__hooks}/zv_time.js`).timeContext(query);

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
    const monthOf = (r) => {
      const p = t.partsOf(r.admittedAt);
      return p === null ? null : p.mo;
    };
    const rowsIn = (y, mo) =>
      rows.filter(
        (r) => yearOf(r) === y && (mo === null || monthOf(r) === mo),
      );

    const periodRows = year === null ? rows : rowsIn(year, month);
    const agg = stats.aggregate(periodRows, { t: t, period: period });

    // The comparison is always the SAME period a year earlier — March against
    // last March, not against February. Seasonality is what a rehab is asking
    // about ("are we busier than last spring?"); the month before answers a
    // different question and answers it badly, since half the difference is
    // just the season turning.
    let previous = null;
    if (year !== null) {
      const prevPeriod = { year: year - 1, month: month };
      const prevRows = rowsIn(prevPeriod.year, month);
      if (prevRows.length > 0) {
        previous = {
          year: prevPeriod.year,
          month: month,
          points: stats.aggregate(prevRows, { t: t, period: prevPeriod })
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
      period: { year: year, month: month },
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
      // Standing figure, unaffected by `period` above — see the header.
      sponsorships: stats.sponsorshipTotals(e.app, org, t),
    });
  },
  $apis.requireAuth(),
);
