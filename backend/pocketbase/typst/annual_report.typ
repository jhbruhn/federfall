// federfall-dk0c — annual report (REQUIREMENTS.md §10).
//
// Rendered server-side by pb_hooks/annual_report.pb.js via `typst compile
// --input data=<json> annual_report.typ out.pdf`. Same split as report.typ:
// the hook sends structured, untranslated data (wire enum values, raw date
// parts, DB-authored labels) and ALL localization happens here through
// report_common.typ's STRINGS / shared_strings.json.
//
// Layout: portrait summary pages (KPIs, intake curve, breakdowns, the
// markings the org applied), then the per-case table on LANDSCAPE pages —
// thirteen columns do not fit portrait, and that table is the same table the
// hook's CSV writes, column for column, because both read the same
// `case_report_rows` view (1700000063 + 1700000066).
#import "report_common.typ": fmtDate, fmtDateTime, lbl, resolveStrings

#let data = json(bytes(sys.inputs.data))
#let lang = data.at("lang", default: "de")
#let S = resolveStrings(lang)
#let A = S.annual
#let COLS = S.reportColumns

// ── Document ─────────────────────────────────────────────────────────────────
#let periodYear = data.period.at("year", default: none)
#let docTitle = if periodYear != none {
  A.title + " " + str(periodYear)
} else {
  A.titleAllTime
}

#set document(title: data.org.name + " — " + docTitle)
#set page(
  paper: "a4",
  margin: (x: 1.6cm, y: 1.6cm),
  footer: context [
    #set text(size: 8pt, fill: gray)
    #line(length: 100%, stroke: 0.5pt + gray)
    #v(4pt)
    #docTitle #h(1fr) #data.org.name #h(1fr)
    #S.pageLabel #context counter(page).display("1 " + S.pageOfSep + " 1", both: true)
  ],
)
#set text(font: "Libertinus Serif", size: 10pt, lang: lang)
#set heading(numbering: none)

#let sectionTitle(body) = block(below: 5pt)[
  #text(size: 10.5pt, weight: "bold", tracking: 0.4pt)[#upper(body)]
  #v(1pt)
  #line(length: 100%, stroke: 0.5pt + black)
]

#let muted(body) = text(fill: gray)[#body]

// ── Header ───────────────────────────────────────────────────────────────────
#let periodLine = if periodYear != none {
  (A.periodIntakes)(fmtDate(S, data.period.from), fmtDate(S, data.period.to))
} else {
  A.periodAllTime
}
// Wrapped in parentheses on purpose: at the top level of a markup file a
// `#let` expression ENDS at the line break, so an unparenthesised method chain
// continuing on the next line would be typeset as literal text instead of
// evaluated (it was — the source of `.filter(...)` printed above the header).
#let orgContact = (
  (
    data.org.at("contactEmail", default: none),
    data.org.at("contactPhone", default: none),
  )
    .filter(v => v != none and v != "")
    .join(" · ")
)

#grid(
  columns: (1fr, auto),
  align: (left + top, right + top),
  [
    #text(size: 11pt)[#data.org.name]
    #v(2pt)
    #text(size: 20pt, weight: "bold")[#docTitle]
    #v(3pt)
    #text(size: 10pt)[#A.periodLabel: #periodLine]
  ],
  [
    #set text(size: 8.5pt, fill: gray)
    #S.generatedAtLabel #fmtDateTime(S, data.generatedAt)
    #if orgContact != "" [ \ #orgContact ]
  ],
)
#v(6pt)
#line(length: 100%, stroke: 0.75pt + black)
#v(10pt)

// ── No data at all: say so and stop, rather than printing a page of zeros ────
#let cases = data.at("cases", default: ())
#if cases.len() == 0 [
  #muted[#A.empty]
] else {

  // ── KPI band ───────────────────────────────────────────────────────────────
  let t = data.totals
  let pct(value) = str(calc.round(value * 100)) + " %"
  let kpi(label, value) = block(
    width: 100%,
    inset: (x: 6pt, y: 7pt),
    radius: 3pt,
    stroke: 0.5pt + luma(150),
    [
      #align(center)[
        #text(size: 15pt, weight: "bold")[#value]
        #v(1pt)
        #text(size: 7.5pt, fill: gray)[#label]
      ]
    ],
  )
  let avgDays = t.at("avgDaysInCare", default: none)
  let releaseRate = t.at("releaseRate", default: none)
  grid(
    columns: (1fr, 1fr, 1fr, 1fr, 1fr),
    column-gutter: 6pt,
    kpi(A.kpiIntakes, str(t.intakes)),
    kpi(A.kpiClosed, str(t.closed)),
    kpi(A.kpiInCare, str(t.inCare)),
    kpi(
      A.kpiAvgDays,
      if avgDays == none { "–" } else {
        // A German report may not print "23.4 d" — Typst's `str` always emits
        // a decimal point, so the locale's separator is applied here (the app
        // does the same via `formatNumber` for the same figure on screen).
        (
          str(calc.round(avgDays, digits: 1)).replace(".", A.decimalSep)
            + " "
            + A.daysUnit
        )
      },
    ),
    kpi(A.kpiReleaseRate, if releaseRate == none { "–" } else { pct(releaseRate) }),
  )
  v(4pt)
  text(size: 7.5pt, fill: gray)[#A.basisNote]

  // ── Intakes over time ──────────────────────────────────────────────────────
  // Plain Typst rects rather than a plotting package: one bar per bucket, so
  // there is nothing here worth vendoring a dependency for (the QR package in
  // vendor/ earns its place; a bar does not).
  let buckets = data.at("intakesByBucket", default: ())
  let bucketKind = data.at("bucketKind", default: "month")
  v(12pt)
  sectionTitle(if bucketKind == "year" { A.sectionYearly } else { A.sectionMonthly })
  let counts = buckets.map(b => b.count)
  let peak = if counts.len() == 0 { 0 } else { calc.max(..counts) }
  // The hook sends bucket KEYS (a month number, or a calendar year) so the
  // month names stay in this file with the rest of the localization.
  let bucketLabel(key) = if bucketKind == "year" {
    str(key)
  } else {
    A.months.at(key - 1, default: str(key))
  }
  if peak == 0 [
    #muted[#A.emptySection]
  ] else {
    let barHeight = 2.2cm
    // An all-time report can have as few as one bucket, and a bar filling
    // half the page reads as a design element rather than as a measurement —
    // so past a handful of buckets the bars share the width, below it they
    // keep a fixed one.
    let barWidth = if buckets.len() > 8 { 55% } else { 1.2cm }
    grid(
      columns: buckets.len() * (1fr,),
      align: center + bottom,
      row-gutter: 3pt,
      ..buckets.map(b => [
        #text(size: 7pt, fill: gray)[#if b.count > 0 [#b.count]]
        #v(1.5pt)
        #rect(
          width: barWidth,
          height: barHeight * b.count / peak,
          fill: luma(75),
          stroke: none,
        )
      ]),
      ..buckets.map(b => text(size: 7.5pt)[#bucketLabel(b.key)]),
    )
  }

  // ── Breakdowns ─────────────────────────────────────────────────────────────
  // One shared shape for every label→count list: label, count, share of the
  // period's intakes. `limit` keeps a long tail from pushing the case list
  // onto another page; the remainder is stated rather than silently dropped.
  let breakdown(rows, limit: 8, total: none) = {
    if rows.len() == 0 {
      return muted[#A.emptySection]
    }
    let shown = if rows.len() > limit { rows.slice(0, limit) } else { rows }
    let hidden = rows.len() - shown.len()
    table(
      columns: (1fr, auto, auto),
      align: (left, right, right),
      stroke: none,
      // The count and its share need air between them, or "32" and "23 %"
      // read as one number.
      inset: (x, y) => (left: if x == 0 { 2pt } else { 8pt }, right: 2pt, y: 2.6pt),
      ..shown
        .map(r => (
          text(size: 9pt)[#r.label],
          text(size: 9pt)[#r.count],
          if total == none or total == 0 {
            []
          } else {
            text(size: 8.5pt, fill: gray)[#str(calc.round(r.count / total * 100)) %]
          },
        ))
        .flatten(),
    )
    if hidden > 0 {
      text(size: 8pt, fill: gray)[#(A.more)(hidden)]
    }
  }

  // Outcomes carry three distinct states the hook keeps apart: `none` is the
  // "not disposed yet" bucket (so the column reconciles to the intake total,
  // which a breakdown over dispositions alone would not), `""` is a
  // disposition whose type is unset, and anything else is a wire value —
  // printed as itself when unmapped rather than guessed at.
  let outcomeRows = data
    .at("outcomes", default: ())
    .map(o => (
      label: {
        let wire = o.at("type", default: none)
        if wire == none {
          A.stillOpen
        } else if wire == "" {
          S.dispositionUnknown
        } else {
          lbl(S.disposition, wire)
        }
      },
      count: o.count,
    ))

  v(12pt)
  grid(
    columns: (1fr, 1fr),
    column-gutter: 16pt,
    row-gutter: 12pt,
    [
      #sectionTitle(A.sectionOutcomes)
      // Every intake is in exactly one bucket above (including "still open"),
      // so the column has a total and printing it lets a reader check that.
      #breakdown(outcomeRows, limit: 8, total: t.intakes)
      #v(1pt)
      #line(length: 100%, stroke: 0.5pt + black)
      #v(1pt)
      #table(
        columns: (1fr, auto),
        align: (left, right),
        stroke: none,
        inset: (x: 2pt, y: 2.6pt),
        text(size: 9pt, weight: "bold")[#A.total],
        text(size: 9pt, weight: "bold")[#t.intakes],
      )
    ],
    [
      #sectionTitle(A.sectionSpecies)
      #breakdown(data.at("species", default: ()), total: t.intakes)
    ],
    [
      #sectionTitle(A.sectionReasons)
      #breakdown(data.at("reasons", default: ()), total: t.intakes)
    ],
    [
      #sectionTitle(A.sectionConditions)
      #breakdown(data.at("conditions", default: ()), total: t.intakes)
    ],
  )

  v(12pt)
  sectionTitle(A.sectionCities)
  breakdown(data.at("cities", default: ()), limit: 12, total: t.intakes)

  // ── Markings ───────────────────────────────────────────────────────────────
  // Scoped by APPLICATION date, not by the case cohort above (the hook says
  // so too): "how many rings did we issue in 2026" is the figure a ringing
  // scheme or authority asks for, and it is not the same question as "which
  // birds came in in 2026". Each section states its own basis so the two
  // cannot be misread as one.
  let markings = data.at("markings", default: (total: 0, byType: (), rows: ()))
  let markingBasis = if periodYear != none {
    (A.markingsApplied)(fmtDate(S, data.period.from), fmtDate(S, data.period.to))
  } else {
    A.markingsAppliedAll
  }
  pagebreak(weak: true)
  sectionTitle(A.sectionMarkings)
  text(size: 8.5pt, fill: gray)[
    #(A.countMarkings)(markings.total) · #markingBasis
  ]
  v(5pt)
  if markings.rows.len() == 0 [
    #muted[#A.emptySection]
  ] else {
    if markings.byType.len() > 0 {
      text(size: 9pt)[
        #markings.byType.map(b => b.label + " " + str(b.count)).join(" · ")
      ]
      v(6pt)
    }
    // Only `Schema` is free text of unbounded length, so it takes the slack;
    // everything else is a code or a date and `auto` sizes it exactly.
    table(
      columns: (auto, auto, auto, 1fr, auto, auto, auto),
      align: (left, left, left, left, left, left, left),
      stroke: (x, y) => if y == 0 {
        (bottom: 0.75pt + black)
      } else {
        (bottom: 0.25pt + luma(200))
      },
      inset: (x: 3pt, y: 3.5pt),
      table.header(
        text(size: 8.5pt, weight: "bold")[#A.colMarkingType],
        text(size: 8.5pt, weight: "bold")[#A.colMarkingColour],
        text(size: 8.5pt, weight: "bold")[#A.colMarkingCode],
        text(size: 8.5pt, weight: "bold")[#A.colMarkingScheme],
        text(size: 8.5pt, weight: "bold")[#A.colMarkingApplied],
        text(size: 8.5pt, weight: "bold")[#A.colMarkingCase],
        text(size: 8.5pt, weight: "bold")[#A.colMarkingRemoved],
      ),
      ..markings.rows
        .map(m => (
          m.at("type", default: ""),
          m.at("colour", default: ""),
          m.at("code", default: ""),
          m.at("schemeOrg", default: ""),
          fmtDate(S, m.at("appliedAt", default: none)),
          m.at("caseNumber", default: ""),
          fmtDate(S, m.at("removedAt", default: none)),
        ))
        .flatten()
        .map(cell => text(size: 8.5pt)[#if cell == none [] else [#cell]]),
    )
  }

  // ── Case list (landscape) ──────────────────────────────────────────────────
  // Thirteen columns need the long edge. `set page` merges field-wise, so the
  // footer set at the top of this file carries over unchanged.
  set page(flipped: true)
  sectionTitle(A.sectionCases)
  text(size: 8.5pt, fill: gray)[#(A.countCases)(cases.len())]
  v(5pt)
  // Every text cell here is user-authored and can be arbitrarily long, and a
  // single long word (a region like "Niedersachsen", a compound species name)
  // does NOT wrap on its own — it overflows its column and prints on top of
  // the next one, which is how this table first rendered. Hyphenation makes
  // that impossible rather than merely unlikely, which is what a column of
  // free text needs.
  set text(hyphenate: true)
  let head(body) = text(size: 8pt, weight: "bold")[#body]
  let cell(value) = text(size: 8pt)[#if value == none or value == "" [] else [#value]]
  table(
    // Dates, the case number and the day count are fixed-width content, so
    // `auto` sizes them exactly; the free-text columns share what is left,
    // with reasons and markings (the two that routinely wrap) widest.
    columns: (
      auto, 1.4fr, 1fr, 1.9fr, auto, auto, auto, auto,
      1.4fr, 1.6fr, 1.3fr, 1.2fr, 2fr,
    ),
    align: (
      left, left, left, left, left, left, left, right, left, left, left, left, left,
    ),
    stroke: (x, y) => if y == 0 {
      (bottom: 0.75pt + black)
    } else {
      (bottom: 0.25pt + luma(200))
    },
    inset: (x: 3pt, y: 3.5pt),
    table.header(
      head(COLS.caseNumber),
      head(COLS.species),
      head(COLS.name),
      head(COLS.markings),
      head(COLS.found),
      head(COLS.admitted),
      head(COLS.ended),
      head(COLS.days),
      head(COLS.status),
      head(COLS.outcome),
      head(COLS.city),
      head(COLS.region),
      head(COLS.reasons),
    ),
    ..cases
      .map(c => (
        c.at("caseNumber", default: ""),
        c.at("species", default: ""),
        c.at("name", default: ""),
        c.at("markings", default: ""),
        fmtDate(S, c.at("foundAt", default: none)),
        fmtDate(S, c.at("admittedAt", default: none)),
        fmtDate(S, c.at("endedAt", default: none)),
        c.at("days", default: none),
        lbl(S.caseStatus, c.at("status", default: none)),
        lbl(S.disposition, c.at("outcome", default: none)),
        c.at("city", default: ""),
        c.at("region", default: ""),
        c.at("reasons", default: ""),
      ))
      .flatten()
      .map(cell),
  )
}
