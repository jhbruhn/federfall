// federfall-gdp8 — per-case PDF report.
//
// Rendered server-side by pb_hooks/case_report.pb.js via `typst compile
// --input data=<json> report.typ out.pdf`. Unlike the first version of this
// file, ALL localization lives HERE (the STRINGS dict below), not in the
// hook — the hook only sends structured, untranslated data: wire enum
// values (e.g. "in_care", "male"), raw date parts, and free text / DB-authored
// labels (drug names, medication-route/marking-type/admission-reason labels,
// user names) that are never translated regardless of report language, same
// as the Flutter app treats them (cases_labels.dart resolves enums; user-
// authored code lists are read as stored). This mirrors the standard Typst
// i18n pattern: a dict-of-dicts keyed by language + a `t()`-style lookup,
// switched by ONE `data.lang` value the hook derives from the request (see
// case_report.pb.js — `?lang=`).
#import "vendor/codetastic/codetastic.typ": qrcode

#let data = json(bytes(sys.inputs.data))
#let lang = data.at("lang", default: "de")

#let STRINGS = (
  de: (
    title: "Fallbericht",
    caseLabel: "Fall",
    sectionIntake: "Aufnahme",
    fieldSex: "Geschlecht",
    fieldAgeClass: "Altersklasse",
    fieldReasons: "Aufnahmegründe",
    fieldFoundAt: "Gefunden am",
    fieldAdmittedAt: "Aufgenommen am",
    fieldFindLocation: "Fundort",
    fieldIntakeNotes: "Aufnahmenotizen",
    fieldFinder: "Finder",
    sectionTimeline: "Verlauf",
    colDate: "Datum",
    colKind: "Art",
    colDetails: "Details",
    emptyTimeline: "Keine Einträge.",
    generatedAtLabel: "Erstellt am",
    pageLabel: "Seite",
    pageOfSep: "von",
    dateFmt: "[day].[month].[year]",
    dateTimeFmt: "[day].[month].[year], [hour]:[minute]",
    sex: (male: "Männlich", female: "Weiblich", unknown: "Unbekannt"),
    ageClass: (
      squab: "Nestling",
      fledgling: "Ästling",
      immature: "Jungvogel",
      adult: "Altvogel",
    ),
    caseStatus: (
      in_care: "In Pflege",
      ready_for_release: "Auswilderungsbereit",
      disposed: "Abgeschlossen",
    ),
    certainty: (suspected: "Verdacht", confirmed: "Bestätigt"),
    disposition: (
      released: "Ausgewildert",
      placed_in_aviary: "In Voliere untergebracht",
      died: "Verstorben",
      euthanized: "Eingeschläfert",
      transferred: "Übergeben",
      returned_to_owner: "An Besitzer zurück",
    ),
    dispositionUnknown: "Unbekannter Ausgang",
    hydration: (normal: "Normal", mild: "Leicht", moderate: "Mäßig", severe: "Schwer"),
    mentation: (
      bright: "Munter",
      quiet: "Ruhig",
      depressed: "Apathisch",
      unresponsive: "Reaktionslos",
    ),
    bodySystem: (
      eyes: "Augen",
      beak_nares: "Schnabel / Nasenlöcher",
      oral: "Mundhöhle",
      integument: "Haut & Gefieder",
      wings: "Flügel",
      legs_feet: "Beine & Füße",
      keel: "Brustbein / Muskulatur",
      respiratory: "Atmung",
      coelom: "Bauchhöhle",
      neuro: "Neurologie",
      vent: "Kloake",
    ),
    findingStatus: (normal: "o. B.", abnormal: "Auffällig"),
    mmColor: (
      pink: "Rosa",
      pale: "Blass",
      cyanotic: "Zyanotisch",
      icteric: "Ikterisch",
      injected: "Injiziert",
    ),
    mmTexture: (moist: "Feucht", tacky: "Klebrig", dry: "Trocken"),
    freq: (once: "Einmalig", as_needed: "Bei Bedarf"),
    freqScheduled: (
      "24": "1× täglich",
      "12": "2× täglich",
      "8": "3× täglich",
      "6": "4× täglich",
      "48": "Jeden 2. Tag",
    ),
    freqEveryNHours: (h) => "Alle " + str(h) + " h",
    controlledBadge: "BtM",
    vetLabel: "Tierarzt",
    prescribedByLabel: "Verordnet von",
    untilLabel: "bis",
    resolvedLabel: "Abgeklungen",
    vetSignedOffLabel: "Tierärztlich freigegeben",
    kindTitle: (
      milestone: "Meilenstein",
      journal: "Journal",
      weight: "Gewicht",
      condition: "Diagnose",
      medication: "Verordnung",
      administration: "Gabe",
      marking: "Markierung",
      placement: "Platzierung",
      disposition: "Ausgang",
      follow_up: "Nachkontrolle",
      exam: "Untersuchung",
      quarantine: "Quarantäne",
    ),
    milestone: (admitted: "Aufgenommen", created: "Fall angelegt"),
    quarantineUntil: (date) => "Quarantäne bis " + date,
    quarantineEnded: "Quarantäne beendet",
    followUpDefault: "Nachkontrolle",
    followUpDone: "erledigt",
    noVitals: "Keine Vitalwerte erfasst",
    vitalBodyCondition: "Ernährungszustand",
    vitalTemp: "Temp.",
    vitalHydration: "Hydratation",
    vitalMentation: "Verhalten",
    vitalMmColor: "Schleimhäute",
    placementMoved: "Platzierung",
    placementHandedOffTo: (name) => "Übergeben an " + name,
  ),
  en: (
    title: "Case Report",
    caseLabel: "Case",
    sectionIntake: "Intake",
    fieldSex: "Sex",
    fieldAgeClass: "Age class",
    fieldReasons: "Reasons for admission",
    fieldFoundAt: "Found on",
    fieldAdmittedAt: "Admitted on",
    fieldFindLocation: "Find location",
    fieldIntakeNotes: "Intake notes",
    fieldFinder: "Finder",
    sectionTimeline: "Timeline",
    colDate: "Date",
    colKind: "Type",
    colDetails: "Details",
    emptyTimeline: "No entries yet.",
    generatedAtLabel: "Generated on",
    pageLabel: "Page",
    pageOfSep: "of",
    dateFmt: "[month]/[day]/[year]",
    dateTimeFmt: "[month]/[day]/[year], [hour]:[minute]",
    sex: (male: "Male", female: "Female", unknown: "Unknown"),
    ageClass: (
      squab: "Nestling",
      fledgling: "Fledgling",
      immature: "Immature",
      adult: "Adult",
    ),
    caseStatus: (
      in_care: "In care",
      ready_for_release: "Ready for release",
      disposed: "Closed",
    ),
    certainty: (suspected: "Suspected", confirmed: "Confirmed"),
    disposition: (
      released: "Released",
      placed_in_aviary: "Placed in aviary",
      died: "Died",
      euthanized: "Euthanized",
      transferred: "Transferred",
      returned_to_owner: "Returned to owner",
    ),
    dispositionUnknown: "Unknown outcome",
    hydration: (normal: "Normal", mild: "Mild", moderate: "Moderate", severe: "Severe"),
    mentation: (
      bright: "Bright",
      quiet: "Quiet",
      depressed: "Depressed",
      unresponsive: "Unresponsive",
    ),
    bodySystem: (
      eyes: "Eyes",
      beak_nares: "Beak / nares",
      oral: "Oral cavity",
      integument: "Skin & feathers",
      wings: "Wings",
      legs_feet: "Legs & feet",
      keel: "Keel / pectoral",
      respiratory: "Respiratory",
      coelom: "Coelom / abdomen",
      neuro: "Neurologic",
      vent: "Vent",
    ),
    findingStatus: (normal: "Normal", abnormal: "Abnormal"),
    mmColor: (
      pink: "Pink",
      pale: "Pale",
      cyanotic: "Cyanotic",
      icteric: "Icteric",
      injected: "Injected",
    ),
    mmTexture: (moist: "Moist", tacky: "Tacky", dry: "Dry"),
    freq: (once: "Once", as_needed: "As needed"),
    freqScheduled: (
      "24": "Once daily",
      "12": "Twice daily",
      "8": "3× daily",
      "6": "4× daily",
      "48": "Every other day",
    ),
    freqEveryNHours: (h) => "Every " + str(h) + " h",
    controlledBadge: "Controlled",
    vetLabel: "Vet",
    prescribedByLabel: "Prescribed by",
    untilLabel: "until",
    resolvedLabel: "Resolved",
    vetSignedOffLabel: "Vet signed off",
    kindTitle: (
      milestone: "Milestone",
      journal: "Journal",
      weight: "Weight",
      condition: "Diagnosis",
      medication: "Prescription",
      administration: "Dose",
      marking: "Marking",
      placement: "Placement",
      disposition: "Outcome",
      follow_up: "Recheck",
      exam: "Exam",
      quarantine: "Quarantine",
    ),
    milestone: (admitted: "Admitted", created: "Case opened"),
    quarantineUntil: (date) => "Quarantine until " + date,
    quarantineEnded: "Quarantine ended",
    followUpDefault: "Recheck",
    followUpDone: "done",
    noVitals: "No vitals recorded",
    vitalBodyCondition: "Body condition",
    vitalTemp: "Temp.",
    vitalHydration: "Hydration",
    vitalMentation: "Attitude",
    vitalMmColor: "Mucous membranes",
    placementMoved: "Placement",
    placementHandedOffTo: (name) => "Handed off to " + name,
  ),
)
#let S = STRINGS.at(lang, default: STRINGS.de)

// ── Small helpers ────────────────────────────────────────────────────────────
// `lbl` resolves a stable wire value through a STRINGS map, falling back to
// the wire value itself if this app version doesn't know it (mirrors
// dispositionTypeLabel's "unknown enum -> not a guess" stance).
#let lbl(map, wire) = if wire == none { none } else { map.at(wire, default: wire) }
#let joinDash(parts) = parts.filter(p => p != none and p != "").join(" — ")
#let joinDot(parts) = parts.filter(p => p != none and p != "").join(" · ")

#let fmtDate(d) = if d == none {
  none
} else {
  datetime(year: d.y, month: d.mo, day: d.d, hour: 0, minute: 0, second: 0).display(S.dateFmt)
}
#let fmtDateTime(d) = if d == none {
  none
} else {
  datetime(
    year: d.y,
    month: d.mo,
    day: d.d,
    hour: d.at("h", default: 0),
    minute: d.at("mi", default: 0),
    second: 0,
  ).display(S.dateTimeFmt)
}
// Journal + administration show a time-of-day (mirrors formatEventDate's
// withTime split in the app, case_timeline.dart); everything else is a
// date-only entry.
#let fmtAt(e) = if e.kind == "journal" or e.kind == "administration" {
  fmtDateTime(e.at)
} else {
  fmtDate(e.at)
}

#let freqLabel(kind, intervalHours) = if kind == "once" {
  S.freq.once
} else if kind == "as_needed" {
  S.freq.as_needed
} else if kind == "scheduled" {
  let named = S.freqScheduled.at(str(intervalHours), default: none)
  if named != none {
    named
  } else if intervalHours != none {
    (S.freqEveryNHours)(intervalHours)
  } else {
    none
  }
} else {
  none
}

#let doseStr(dose, unit) = if dose == none {
  none
} else {
  str(dose) + (if unit != none and unit != "" { " " + unit } else { "" })
}

// ── One (title, detail) pair per timeline-entry kind. All translatable text
// goes through S; free text and DB-authored labels (drug names, route/
// marking-type/condition/admission-reason labels, user names) pass through
// untouched — they aren't part of the app's UI chrome, so there's nothing to
// translate (matches user-authored code lists in the Flutter app, which read
// straight off their `label` column with no l10n step).
#let renderEvent(e) = {
  let title = S.kindTitle.at(e.kind, default: e.kind)
  let detail = if e.kind == "milestone" {
    S.milestone.at(e.milestone, default: e.milestone)
  } else if e.kind == "journal" {
    e.text
  } else if e.kind == "weight" {
    joinDash((doseStr(e.grams, "g"), e.at("notes", default: none)))
  } else if e.kind == "condition" {
    let certainty = lbl(S.certainty, e.at("certainty", default: none))
    let named = if certainty != none { e.label + " (" + certainty + ")" } else { e.label }
    let resolved = fmtDate(e.at("resolvedAt", default: none))
    joinDash((
      named,
      if resolved != none { S.resolvedLabel + " " + resolved } else { none },
      e.at("notes", default: none),
    ))
  } else if e.kind == "medication" {
    let bits = joinDot((
      doseStr(e.at("dose", default: none), e.at("doseUnit", default: none)),
      e.at("route", default: none),
      freqLabel(e.at("frequencyKind", default: none), e.at("intervalHours", default: none)),
      e.at("frequency", default: none),
    ))
    let until = fmtDate(e.at("endedAt", default: none))
    let prescribedBy = e.at("prescribedBy", default: none)
    joinDash((
      e.drug,
      if bits != "" { bits },
      if e.at("isControlled", default: false) { S.controlledBadge },
      if until != none { S.untilLabel + " " + until },
      e.at("instructions", default: none),
      if prescribedBy != none and prescribedBy != "" { S.prescribedByLabel + " " + prescribedBy },
    ))
  } else if e.kind == "administration" {
    let dose = doseStr(e.at("dose", default: none), e.at("doseUnit", default: none))
    let drugDose = if dose != none { e.drug + " " + dose } else { e.drug }
    joinDash((drugDose, e.at("route", default: none), e.at("notes", default: none)))
  } else if e.kind == "marking" {
    let bits = joinDot((
      e.at("colour", default: none),
      e.at("code", default: none),
      e.at("schemeOrg", default: none),
    ))
    joinDash((
      e.type,
      if bits != "" { bits },
      if e.at("removed", default: false) {
        let removedAt = fmtDate(e.at("removedAt", default: none))
        if removedAt != none { S.untilLabel + " " + removedAt } else { "—" }
      },
    ))
  } else if e.kind == "placement" {
    let toName = e.at("toUserName", default: none)
    let placementTitle = if toName != none { (S.placementHandedOffTo)(toName) } else { S.placementMoved }
    let location = joinDot((
      e.at("enclosure", default: none),
      e.at("whereHolding", default: none),
      e.at("area", default: none),
    ))
    joinDash((
      placementTitle,
      if location != "" { location },
      e.at("conditionAtHandoff", default: none),
      e.at("comments", default: none),
    ))
  } else if e.kind == "disposition" {
    let outcome = if e.at("type", default: none) != none {
      lbl(S.disposition, e.type)
    } else {
      S.dispositionUnknown
    }
    let bits = joinDot((
      e.at("releaseLocation", default: none),
      e.at("releaseType", default: none),
      e.at("transferDestination", default: none),
      e.at("transferType", default: none),
    ))
    let vet = e.at("vet", default: none)
    joinDash((
      outcome,
      if bits != "" { bits },
      if vet != none and vet != "" { S.vetLabel + ": " + vet },
      e.at("reason", default: none),
      if e.at("vetSignedOff", default: false) { S.vetSignedOffLabel },
    ))
  } else if e.kind == "follow_up" {
    let note = e.at("note", default: none)
    let base = if note != none and note != "" { note } else { S.followUpDefault }
    if e.at("done", default: false) { base + " (" + S.followUpDone + ")" } else { base }
  } else if e.kind == "exam" {
    let bc = e.at("bodyCondition", default: none)
    let temp = e.at("temperature", default: none)
    let hydration = lbl(S.hydration, e.at("hydration", default: none))
    let mentation = lbl(S.mentation, e.at("mentation", default: none))
    let mmColor = lbl(S.mmColor, e.at("mmColor", default: none))
    let vitals = joinDot((
      if bc != none { S.vitalBodyCondition + " " + str(bc) + "/5" },
      if temp != none { S.vitalTemp + " " + str(temp) + " °C" },
      if hydration != none { S.vitalHydration + " " + hydration },
      if mentation != none { S.vitalMentation + " " + mentation },
      if mmColor != none { S.vitalMmColor + " " + mmColor },
    ))
    let findings = e.at("findings", default: ())
    let abnormalLines = findings.filter(f => f.status == "abnormal").map(f => {
      let note = f.at("note", default: none)
      let noteText = if note != none and note != "" { note } else { lbl(S.findingStatus, "abnormal") }
      lbl(S.bodySystem, f.system) + ": " + noteText
    })
    let normalSystems = findings.filter(f => f.status == "normal").map(f => lbl(S.bodySystem, f.system))
    let parts = (if vitals != "" { vitals } else { S.noVitals },)
    parts += abnormalLines
    if normalSystems.len() > 0 {
      parts += (lbl(S.findingStatus, "normal") + ": " + normalSystems.join(", "),)
    }
    parts += (e.at("notes", default: none),)
    joinDash(parts)
  } else if e.kind == "quarantine" {
    if e.phase == "ended" {
      S.quarantineEnded
    } else {
      let until = fmtDate(e.at("until", default: none))
      let base = if until != none { (S.quarantineUntil)(until) } else { S.kindTitle.quarantine }
      joinDash((base, e.at("reason", default: none)))
    }
  } else {
    ""
  }
  (title, detail)
}

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
    #S.generatedAtLabel #fmtDate(data.generatedAt) #h(1fr)
    #S.pageLabel #context counter(page).display("1 " + S.pageOfSep + " 1", both: true)
  ],
)
#set text(font: "Libertinus Serif", size: 10.5pt, lang: lang)
#set heading(numbering: none)

// Header: title + animal/case identity on the left, QR (bare case number)
// top-right so a phone camera can jump straight to this case.
#let animalName = data.animal.at("name", default: none)
#let statusLabel = lbl(S.caseStatus, data.case.at("status", default: none))
#grid(
  columns: (1fr, auto),
  align: (left, top),
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
  qrcode(data.case.caseNumber, width: 2.2cm),
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
#field(S.fieldFoundAt, fmtDate(data.case.at("foundAt", default: none)))
#field(S.fieldAdmittedAt, fmtDate(data.case.at("admittedAt", default: none)))
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
      let (title, detail) = renderEvent(e)
      (fmtAt(e), title, detail)
    }).flatten(),
  )
]
