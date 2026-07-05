// federfall-i0wq.1 — narrow thermal-receipt case report, rendered to a PNG
// raster for ESC/POS printing (unified_esc_pos_printer's Ticket.image()).
// Shares report_common.typ (STRINGS/i18n + renderEvent) with report.typ so
// adding a language or changing an event's text stays a one-file edit for
// both outputs — this file only differs in layout: single column, stacked
// timeline blocks instead of a 3-col table, no animal photo (thermal raster
// of a photo looks rough at this dpi/width), and a page sized to the caller's
// exact dot width.
//
// `widthDots` (from `?widthDots=` on case_report.pb.js) is the printer head's
// raster width in dots — for raster printing 1 image px = 1 printer dot, so
// this is the ONLY thing that determines physical fit; the mm/dpi figures
// below are just how Typst's `pt`-sized text maps to a pixel count at
// compile time (`--ppi` must match RECEIPT_PPI for the two to agree). See
// federfall-i0wq epic notes: this makes the server generic for any printer
// head width, not just a fixed set of named paper sizes.
#import "vendor/codetastic/codetastic.typ": qrcode
#import "report_common.typ": fmtAt, fmtDate, lbl, renderEvent, resolveStrings

#let data = json(bytes(sys.inputs.data))
#let lang = data.at("lang", default: "de")
#let S = resolveStrings(lang)

#let RECEIPT_PPI = 203
#let widthDots = int(sys.inputs.widthDots)
#let pageWidth = (widthDots / RECEIPT_PPI) * 1in

#set document(title: S.title + " " + data.case.caseNumber)
#set page(width: pageWidth, height: auto, margin: (x: 6pt, y: 8pt))
// A bold sans-mono face and plain black everywhere (see below) instead of
// report.typ's Libertinus Serif + gray labels: the printer library thresholds
// every pixel to pure black/white at a fixed midpoint (no dithering), so (a)
// `fill: gray` sits right at that threshold and prints as a patchy mess, and
// (b) a thin-stroked serif's anti-aliased edges get chewed up by the same
// hard cutoff. A bold, blockier face at a larger size survives that far
// better — DejaVu Sans Mono is also the only non-serif face Typst bundles
// without relying on system fonts (verified via `typst fonts
// --ignore-system-fonts` against the production image's font set: only
// DejaVu Sans Mono / Libertinus Serif / New Computer Modern are guaranteed
// present). Label/value hierarchy that used to come from gray now comes from
// size + weight instead.
#set text(font: "DejaVu Sans Mono", size: 9pt, weight: "bold", lang: lang)
#set heading(numbering: none)

// Header: no photo (thermal raster of a photo looks rough at this
// dpi/width) — just identity, centered, over a small QR deep link.
#let animalName = data.animal.at("name", default: none)
#let statusLabel = lbl(S.caseStatus, data.case.at("status", default: none))
#align(center)[
  #text(size: 14pt)[#S.title]
  #v(2pt)
  #text(size: 10pt)[
    #if animalName != none and animalName != "" [
      #animalName — #data.animal.species
    ] else [
      #data.animal.species
    ]
  ]
  #v(2pt)
  #text(size: 9pt)[
    #S.caseLabel #data.case.caseNumber
    #if statusLabel != none [ · #statusLabel ]
  ]
  #v(6pt)
  #qrcode(data.case.deepLinkUrl, width: pageWidth * 0.4)
]

#v(6pt)
#line(length: 100%, stroke: 1pt + black)
#v(6pt)

// Intake summary — mirrors report.typ's field list, one line per fact
// instead of a label/value grid (no room for columns at this width).
#let field(label, value) = if value != none and value != "" [
  #text(size: 8pt)[#label:] #value \
]

#heading(level: 2)[#text(size: 10pt)[#S.sectionIntake]]
#field(S.fieldSex, lbl(S.sex, data.animal.at("sex", default: none)))
#field(S.fieldAgeClass, lbl(S.ageClass, data.case.at("ageClass", default: none)))
#field(S.fieldReasons, data.reasons.join(", "))
#field(S.fieldFoundAt, fmtDate(S, data.case.at("foundAt", default: none)))
#field(S.fieldAdmittedAt, fmtDate(S, data.case.at("admittedAt", default: none)))
#field(S.fieldFindLocation, data.case.at("findLocation", default: none))
#field(S.fieldIntakeNotes, data.case.at("intakeNotes", default: none))
#let finder = data.at("finder", default: none)
#if finder != none [
  #field(
    S.fieldFinder,
    (
      finder.at("name", default: none),
      finder.at("phone", default: none),
      finder.at("email", default: none),
      finder.at("city", default: none),
    )
      .filter(v => v != none and v != "")
      .join(" · "),
  )
]

#v(6pt)
#line(length: 100%, stroke: 1pt + black)
#v(6pt)

// Chronology — stacked blocks (date/kind header line, detail line below)
// instead of report.typ's 3-column table; a narrow receipt has no room for
// columns. Same oldest-first ordering as the PDF (a hand-off document reads
// as a narrative).
#heading(level: 2)[#text(size: 10pt)[#S.sectionTimeline]]
#if data.timeline.len() == 0 [
  #text(size: 8pt)[#S.emptyTimeline]
] else [
  #for e in data.timeline [
    #let (title, detail) = renderEvent(S, e)
    #block(below: 5pt)[
      #text(size: 8pt)[#fmtAt(S, e) — #title]
      #if detail != none and detail != "" [
        \ #text(size: 8pt, weight: "regular")[#detail]
      ]
    ]
  ]
]
