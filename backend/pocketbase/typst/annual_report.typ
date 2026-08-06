// federfall-dk0c — annual report (REQUIREMENTS.md §10).
//
// Rendered server-side by pb_hooks/annual_report.pb.js via `typst compile
// --input data=<json> annual_report.typ out.pdf`. Same split as report.typ:
// the hook sends structured, untranslated data (wire enum values, raw date
// parts, DB-authored labels) and ALL localization happens here through
// report_common.typ's STRINGS / shared_strings.json.
//
// Layout: portrait summary pages (KPIs, intake curve, breakdowns), then the
// per-case table on LANDSCAPE pages — thirteen columns do not fit portrait,
// and that table is the same table the hook's CSV writes, column for column,
// because both read the same `case_report_rows` view (1700000063 + 1700000066
// + 1700000067).
//
// Markings have no section of their own: they are one column of the case
// table, listing what each bird carried at the end of ITS case (see
// 1700000067). A separate roster of every ring the org applied was tried and
// dropped — it restated the same rows in a second order and answered a
// question this report is not for.
#import "report_common.typ": fmtDate, fmtDateTime, lbl, resolveStrings

#let data = json(bytes(sys.inputs.data))
#let lang = data.at("lang", default: "de")
#let S = resolveStrings(lang)
#let A = S.annual
#let COLS = S.reportColumns

// ── Document ─────────────────────────────────────────────────────────────────
#let periodYear = data.period.at("year", default: none)
#let periodMonth = data.period.at("month", default: none)
// A month report is still the annual report's table over a shorter period, so
// it keeps the same title and simply names the month it covers.
#let docTitle = if periodYear == none {
  A.titleAllTime
} else if periodMonth == none {
  A.title + " " + str(periodYear)
} else {
  // One complete expression per line: a trailing `+` at a line break ends the
  // enclosing `#let` and Typst then reads the continuation as markup (the
  // same trap `orgContact` below is parenthesised against).
  let monthName = A.monthsLong.at(periodMonth - 1, default: str(periodMonth))
  // Not "Jahresbericht März": the document is the same table over a shorter
  // period, and calling a month an annual report is simply wrong.
  A.titleMonthly + " " + monthName + " " + str(periodYear)
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
  sectionTitle(
    if bucketKind == "year" {
      A.sectionYearly
    } else if bucketKind == "day" {
      A.sectionDaily
    } else {
      A.sectionMonthly
    },
  )
  let counts = buckets.map(b => b.count)
  let peak = if counts.len() == 0 { 0 } else { calc.max(..counts) }
  // The hook sends bucket KEYS (a month number, or a calendar year) so the
  // month names stay in this file with the rest of the localization.
  // A day bucket is the day of the month, a month bucket its initial, a year
  // bucket the year itself.
  let bucketLabel(key) = if bucketKind == "month" {
    A.months.at(key - 1, default: str(key))
  } else {
    str(key)
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
  // period's intakes.
  //
  // Every row is printed. An earlier version capped each list at a top-N with a
  // "… + 9 weitere" line to keep the summary on one page, which was the wrong
  // trade for this document: the species and diagnosis breakdowns ARE the
  // report, an org with forty species has forty species, and a reader cannot
  // tell whether the tail they cannot see is nine cases or ninety. The summary
  // simply runs onto a second page when the data needs one (Typst breaks the
  // grid below across pages by itself).
  let breakdown(rows, total: none) = {
    if rows.len() == 0 {
      return muted[#A.emptySection]
    }
    table(
      columns: (1fr, auto, auto),
      align: (left, right, right),
      stroke: none,
      // The count and its share need air between them, or "32" and "23 %"
      // read as one number.
      inset: (x, y) => (left: if x == 0 { 2pt } else { 8pt }, right: 2pt, y: 2.6pt),
      ..rows
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

  // Two columns, each holding a FIXED sequence of whole sections. Three
  // arrangements were tried and this is the one that survives both ends of the
  // data:
  //
  //   • one 2×2 grid of individual sections — the taller cell of a pair pushed
  //     the next pair down, and a long list's continuation landed at the top of
  //     the next page beside an empty column;
  //   • every section stacked full width — uniform, but it pushed a normal
  //     year's summary onto a second page that was 90 % white space;
  //   • this: two columns of stacked sections, so the pair of columns breaks as
  //     one and each side simply continues where it left off.
  //
  // The assignment is fixed rather than balanced by row count, so the report
  // has the same shape every year regardless of the data (see the
  // federfall-ui-prefers-unified-consistent-views note) — Ausgänge/Gründe
  // left, the three genuinely open-ended lists right.
  //
  // Nothing is capped. An earlier version showed a top-8 with a "… + 9 weitere"
  // line, which was the wrong trade for this document: the species and
  // diagnosis breakdowns ARE the report, and a reader cannot tell whether the
  // tail they are not shown is nine cases or ninety.
  let section(title, rows, total: none, footer: none) = {
    sectionTitle(title)
    breakdown(rows, total: total)
    if footer != none { footer }
    v(12pt)
  }

  v(12pt)
  grid(
    columns: (1fr, 1fr),
    column-gutter: 18pt,
    [
      #section(A.sectionOutcomes, outcomeRows, total: t.intakes, footer: [
        // Every intake is in exactly one bucket above (including "still open"),
        // so the column has a total and printing it lets a reader check that.
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
      ])
      #section(A.sectionReasons, data.at("reasons", default: ()), total: t.intakes)
    ],
    [
      #section(A.sectionSpecies, data.at("species", default: ()), total: t.intakes)
      #section(A.sectionConditions, data.at("conditions", default: ()), total: t.intakes)
      #section(A.sectionCities, data.at("cities", default: ()), total: t.intakes)
    ],
  )

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
