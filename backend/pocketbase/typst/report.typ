// federfall-gdp8 — per-case PDF report.
//
// Rendered server-side by pb_hooks/case_report.pb.js via `typst compile
// --input data=<json> report.typ out.pdf`. Unlike the first version of this
// file, ALL localization lives in report_common.typ (the STRINGS dict,
// shared with receipt.typ — see federfall-i0wq), not in the hook — the hook
// only sends structured, untranslated data: wire enum values (e.g.
// "in_care", "male"), raw date parts, and free text / DB-authored labels
// (drug names, medication-route/marking-type/admission-reason labels, user
// names) that are never translated regardless of report language, same as
// the Flutter app treats them (cases_labels.dart resolves enums; user-
// authored code lists are read as stored). This mirrors the standard Typst
// i18n pattern: a dict-of-dicts keyed by language + a `t()`-style lookup,
// switched by ONE `data.lang` value the hook derives from the request (see
// case_report.pb.js — `?lang=`).
#import "vendor/codetastic/codetastic.typ": qrcode
#import "report_common.typ": fmtAt, fmtDate, lbl, renderEvent, resolveStrings

#let data = json(bytes(sys.inputs.data))
#let lang = data.at("lang", default: "de")
#let S = resolveStrings(lang)

// ── Document ─────────────────────────────────────────────────────────────────
#set document(title: S.title + " " + data.case.caseNumber)
#set page(
  paper: "a4",
  margin: (x: 2cm, y: 2cm),
  footer: context [
    #set text(size: 8pt, fill: gray)
    #line(length: 100%, stroke: 0.5pt + gray)
    #v(4pt)
    #data.case.caseNumber #h(1fr)
    #S.generatedAtLabel #fmtDate(S, data.generatedAt) #h(1fr)
    #S.pageLabel #context counter(page).display("1 " + S.pageOfSep + " 1", both: true)
  ],
)
#set text(font: "Libertinus Serif", size: 10.5pt, lang: lang)
#set heading(numbering: none)

// Header: the animal's photo (this case's own intake photo if it has one,
// else the animal's lifetime photo — see case_report.pb.js) and identity on
// the left, a QR deep link (data.case.deepLinkUrl, a federfall:// custom
// scheme the app registers — see case_report.pb.js's comment for why not an
// https:// App Link) top-right.
#let animalName = data.animal.at("name", default: none)
#let statusLabel = lbl(S.caseStatus, data.case.at("status", default: none))
#let photoPath = data.animal.at("photoPath", default: none)
#grid(
  columns: (auto, 1fr, auto),
  align: (left, left, top),
  column-gutter: 10pt,
  if photoPath != none [
    #box(
      width: 2.2cm,
      height: 2.2cm,
      radius: 50%,
      clip: true,
      image(photoPath, width: 2.2cm, height: 2.2cm, fit: "cover"),
    )
  ],
  [
    #text(size: 18pt, weight: "bold")[#S.title]
    #v(2pt)
    #text(size: 13pt)[
      #if animalName != none and animalName != "" [
        *#animalName* — #data.animal.species
      ] else [
        *#data.animal.species*
      ]
    ]
    #v(2pt)
    #text(size: 10pt, fill: gray)[
      #S.caseLabel #data.case.caseNumber
      #if statusLabel != none [ · #statusLabel ]
    ]
  ],
  qrcode(data.case.deepLinkUrl, width: 2.2cm),
)

#v(8pt)
#line(length: 100%, stroke: 0.75pt + black)
#v(10pt)

// Intake summary — mirrors `_IntakeSection` in case_detail_screen.dart.
#let field(label, value) = if value != none and value != "" [
  #box(width: 32%)[#text(fill: gray, size: 9pt)[#label]] #value \
]

#heading(level: 2)[#S.sectionIntake]
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

#v(10pt)

// Chronology — the full case history, oldest first (a hand-off document
// reads as a narrative; the app's own UI is newest-first for triage instead).
#heading(level: 2)[#S.sectionTimeline]
#if data.timeline.len() == 0 [
  #text(fill: gray)[#S.emptyTimeline]
] else [
  #table(
    columns: (auto, auto, 1fr),
    stroke: (x, y) => if y == 0 { (bottom: 0.75pt + black) } else { (bottom: 0.25pt + gray) },
    inset: (x: 4pt, y: 5pt),
    align: (left, left, left),
    table.header[*#S.colDate*][*#S.colKind*][*#S.colDetails*],
    ..data.timeline.map(e => {
      let (title, detail) = renderEvent(S, e)
      (fmtAt(S, e), title, detail)
    }).flatten(),
  )
]
