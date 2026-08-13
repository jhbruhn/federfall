// federfall-i0wq.1 — shared Typst i18n + timeline-rendering helpers, used by
// report.typ (A4 PDF), receipt.typ (narrow thermal PNG) and
// annual_report.typ (federfall-dk0c). Splitting this out keeps "add a
// language" / "change an event's text" a one-file edit for all three outputs
// instead of three. Callers own their own `data`/`lang`/`S` (each template's
// `sys.inputs` differ — report.typ has no widthDots, receipt.typ does) and
// pass `S` explicitly into the helpers below rather than this file closing
// over a module-level one.
//
// `shared_strings.json` holds the subset a NON-Typst consumer also needs: the
// annual report's CSV is written by annual_report.pb.js, which has no template
// to translate in, so the two enum maps and the report table's column titles
// live in that file and are merged in by `resolveStrings` below (call sites
// still read them as plain `S.caseStatus` / `S.disposition`). Everything that
// is a Typst closure — eggCount, freqEveryNHours, quarantineUntil,
// placementHandedOffTo — necessarily stays here.
#let SHARED = json("shared_strings.json")

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
    // caseStatus + disposition come from shared_strings.json (see SHARED
    // above) — the CSV writer needs the same two maps.
    certainty: (suspected: "Verdacht", confirmed: "Bestätigt"),
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
    eggCount: (n) => if n == 1 { "1 Ei" } else { str(n) + " Eier" },
    eggFertility: (
      unknown: "Unbekannt",
      fertile: "Befruchtet",
      infertile: "Unbefruchtet",
    ),
    eggFate: (
      in_nest: "Im Nest",
      dummy_swapped: "Attrappe eingelegt",
      removed: "Entnommen",
      hatched: "Geschlüpft",
      broken: "Zerbrochen",
      discarded: "Entsorgt",
      unknown: "Unbekannt",
    ),
    eggAttribution: (confirmed: "Bestätigt", presumed: "vermutlich"),
    vetOutcomeLabel: "Ergebnis",
    vetAttended: "Wahrgenommen",
    vetCancelled: "Abgesagt",
    vetUnresolved: "Offen",
    freq: (once: "Einmalig", as_needed: "Bei Bedarf"),
    freqScheduled: (
      "24": "1× täglich",
      "12": "2× täglich",
      "8": "3× täglich",
      "6": "4× täglich",
      "48": "Jeden 2. Tag",
    ),
    freqEveryNHours: (h) => "Alle " + str(h) + " h",
    freqCycle: (on, off) => (
      str(on) + " Tage Gabe / " + str(off) + " Tage Pause"
    ),
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
      vet_appointment: "Tierarzttermin",
      exam: "Untersuchung",
      quarantine: "Quarantäne",
      egg: "Ei-Ablage",
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
    // federfall-dk0c — annual report only. Its per-case table's column titles
    // are NOT here: they live in shared_strings.json's `reportColumns`,
    // because the CSV of that same table prints the same headers.
    annual: (
      title: "Jahresbericht",
      titleMonthly: "Monatsbericht",
      titleAllTime: "Fallbericht — Gesamtzeitraum",
      periodLabel: "Berichtszeitraum",
      periodIntakes: (from, to) => "Aufnahmen " + from + " – " + to,
      periodAllTime: "alle erfassten Aufnahmen",
      kpiIntakes: "Aufnahmen",
      kpiClosed: "Abgeschlossen",
      kpiInCare: "Noch in Pflege",
      kpiAvgDays: "Ø Pflegedauer",
      kpiReleaseRate: "Auswilderungsquote",
      daysUnit: "d",
      sectionMonthly: "Aufnahmen pro Monat",
      sectionYearly: "Aufnahmen pro Jahr",
      sectionDaily: "Aufnahmen pro Tag",
      sectionOutcomes: "Ausgänge",
      sectionSpecies: "Arten",
      sectionReasons: "Aufnahmegründe",
      sectionConditions: "Diagnosen",
      sectionCities: "Fundorte",
      sectionCases: "Fallliste",
      stillOpen: "noch offen",
      total: "Summe",
      decimalSep: ",",
      countCases: (n) => if n == 1 { "1 Fall" } else { str(n) + " Fälle" },
      months: ("J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"),
      monthsLong: (
        "Januar", "Februar", "März", "April", "Mai", "Juni",
        "Juli", "August", "September", "Oktober", "November", "Dezember",
      ),
      empty: "Keine Aufnahmen im Berichtszeitraum.",
      emptySection: "Keine Angaben.",
      // The report counts the cases ADMITTED in the period (see
      // annual_report.pb.js); saying so on the page keeps a reader from
      // reading it as "cases closed in 2026" and mis-adding two reports.
      basisNote: "Grundlage: alle Fälle mit Aufnahmedatum im Berichtszeitraum."
        + " Der Ausgang wird auch dann gezählt, wenn er später erfolgte.",
    ),
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
    // caseStatus + disposition come from shared_strings.json (see SHARED
    // above) — the CSV writer needs the same two maps.
    certainty: (suspected: "Suspected", confirmed: "Confirmed"),
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
    eggCount: (n) => if n == 1 { "1 egg" } else { str(n) + " eggs" },
    eggFertility: (unknown: "Unknown", fertile: "Fertile", infertile: "Infertile"),
    eggFate: (
      in_nest: "In the nest",
      dummy_swapped: "Swapped for a dummy",
      removed: "Removed",
      hatched: "Hatched",
      broken: "Broken",
      discarded: "Discarded",
      unknown: "Unknown",
    ),
    eggAttribution: (confirmed: "Confirmed", presumed: "presumed"),
    vetOutcomeLabel: "Outcome",
    vetAttended: "Attended",
    vetCancelled: "Cancelled",
    vetUnresolved: "Open",
    freq: (once: "Once", as_needed: "As needed"),
    freqScheduled: (
      "24": "Once daily",
      "12": "Twice daily",
      "8": "3× daily",
      "6": "4× daily",
      "48": "Every other day",
    ),
    freqEveryNHours: (h) => "Every " + str(h) + " h",
    freqCycle: (on, off) => (
      str(on) + " days on / " + str(off) + " days off"
    ),
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
      vet_appointment: "Vet appointment",
      exam: "Exam",
      quarantine: "Quarantine",
      egg: "Egg record",
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
    // federfall-dk0c — annual report only. Its per-case table's column titles
    // are NOT here: they live in shared_strings.json's `reportColumns`,
    // because the CSV of that same table prints the same headers.
    annual: (
      title: "Annual Report",
      titleMonthly: "Monthly Report",
      titleAllTime: "Case Report — All Time",
      periodLabel: "Reporting period",
      periodIntakes: (from, to) => "Intakes " + from + " – " + to,
      periodAllTime: "all recorded intakes",
      kpiIntakes: "Intakes",
      kpiClosed: "Closed",
      kpiInCare: "Still in care",
      kpiAvgDays: "Avg. time in care",
      kpiReleaseRate: "Release rate",
      daysUnit: "d",
      sectionMonthly: "Intakes per month",
      sectionYearly: "Intakes per year",
      sectionDaily: "Intakes per day",
      sectionOutcomes: "Outcomes",
      sectionSpecies: "Species",
      sectionReasons: "Reasons for admission",
      sectionConditions: "Diagnoses",
      sectionCities: "Find locations",
      sectionCases: "Case list",
      stillOpen: "still open",
      total: "Total",
      decimalSep: ".",
      countCases: (n) => if n == 1 { "1 case" } else { str(n) + " cases" },
      months: ("J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"),
      monthsLong: (
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
      ),
      empty: "No intakes in the reporting period.",
      emptySection: "No data.",
      // The report counts the cases ADMITTED in the period (see
      // annual_report.pb.js); saying so on the page keeps a reader from
      // reading it as "cases closed in 2026" and mis-adding two reports.
      basisNote: "Basis: every case admitted within the reporting period."
        + " Its outcome is counted even if it happened later.",
    ),
  ),
)

// The shared subset (shared_strings.json — caseStatus, disposition,
// reportColumns) is merged ON TOP of the per-language dict above, so call
// sites read `S.caseStatus` exactly as they did when it was inline. Typst's
// `+` on dictionaries merges, and an unknown `lang` falls back to German in
// both halves independently.
#let resolveStrings(lang) = (
  STRINGS.at(lang, default: STRINGS.de) + SHARED.at(lang, default: SHARED.de)
)

// `lbl` resolves a stable wire value through a STRINGS map, falling back to
// the wire value itself if this app version doesn't know it (mirrors
// dispositionTypeLabel's "unknown enum -> not a guess" stance).
#let lbl(map, wire) = if wire == none { none } else { map.at(wire, default: wire) }
#let joinDash(parts) = parts.filter(p => p != none and p != "").join(" — ")
#let joinDot(parts) = parts.filter(p => p != none and p != "").join(" · ")

#let fmtDate(S, d) = if d == none {
  none
} else {
  datetime(year: d.y, month: d.mo, day: d.d, hour: 0, minute: 0, second: 0).display(S.dateFmt)
}
#let fmtDateTime(S, d) = if d == none {
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
// Journal, administration and vet appointments show a time-of-day (mirrors
// formatEventDate's withTime split in the app, case_timeline.dart — an
// appointment's `starts_at` is required, so it always has a real one);
// everything else is a date-only entry.
#let fmtAt(S, e) = if (
  e.kind == "journal" or e.kind == "administration" or e.kind == "vet_appointment"
) {
  fmtDateTime(S, e.at)
} else {
  fmtDate(S, e.at)
}

// The cycle (federfall-wmbi) is a qualifier on the interval, never a label of
// its own: "2× täglich, 5 Tage Gabe / 2 Tage Pause". A rhythm without an
// interval says nothing about when a dose falls, so it is only appended to a
// scheduled plan that has one.
#let freqLabel(S, kind, intervalHours, cycleOnDays: none, cycleOffDays: none) = (
  if kind == "once" {
    S.freq.once
  } else if kind == "as_needed" {
    S.freq.as_needed
  } else if kind == "scheduled" {
    let named = S.freqScheduled.at(str(intervalHours), default: none)
    let base = if named != none {
      named
    } else if intervalHours != none {
      (S.freqEveryNHours)(intervalHours)
    } else {
      none
    }
    if base != none and cycleOnDays != none and cycleOffDays != none {
      base + ", " + (S.freqCycle)(cycleOnDays, cycleOffDays)
    } else {
      base
    }
  } else {
    none
  }
)

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
#let renderEvent(S, e) = {
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
    let resolved = fmtDate(S, e.at("resolvedAt", default: none))
    joinDash((
      named,
      if resolved != none { S.resolvedLabel + " " + resolved } else { none },
      e.at("notes", default: none),
    ))
  } else if e.kind == "medication" {
    // A rate-based plan carries no fixed dose: the rate is what was prescribed.
    let unit = e.at("doseUnit", default: none)
    let rate = e.at("doseRate", default: none)
    let dosing = if rate != none {
      doseStr(rate, if unit != none { unit + "/kg" } else { "/kg" })
    } else {
      doseStr(e.at("dose", default: none), unit)
    }
    let bits = joinDot((
      dosing,
      e.at("route", default: none),
      freqLabel(
        S,
        e.at("frequencyKind", default: none),
        e.at("intervalHours", default: none),
        cycleOnDays: e.at("cycleOnDays", default: none),
        cycleOffDays: e.at("cycleOffDays", default: none),
      ),
    ))
    let until = fmtDate(S, e.at("endedAt", default: none))
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
        let removedAt = fmtDate(S, e.at("removedAt", default: none))
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
  } else if e.kind == "vet_appointment" {
    // Attended wins if both stamps are somehow set (mirrors _StatusChip's
    // switch order). "Neither" gets its own word instead of being left blank:
    // a past appointment nobody resolved must not read as attended.
    let resolution = if e.at("attended", default: false) {
      S.vetAttended
    } else if e.at("cancelled", default: false) {
      S.vetCancelled
    } else {
      S.vetUnresolved
    }
    let vet = e.at("vet", default: none)
    // Labelled, because "what we went for" and "what came of it" are different
    // facts — the same reason the tile boxes the outcome off.
    let outcome = e.at("outcome", default: none)
    joinDash((
      if vet != none and vet != "" { vet },
      e.at("reason", default: none),
      if outcome != none and outcome != "" { S.vetOutcomeLabel + ": " + outcome },
      resolution,
    ))
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
      let until = fmtDate(S, e.at("until", default: none))
      let base = if until != none { (S.quarantineUntil)(until) } else { S.kindTitle.quarantine }
      joinDash((base, e.at("reason", default: none)))
    }
  } else if e.kind == "egg" {
    let count = e.at("count", default: none)
    // "unknown" is what these store when nobody looked — the tile leaves it
    // out rather than printing a non-answer, and so does this.
    let fertility = e.at("fertility", default: none)
    let fate = e.at("fate", default: none)
    let bits = joinDot((
      if count != none { (S.eggCount)(count) },
      if fertility != none and fertility != "unknown" { lbl(S.eggFertility, fertility) },
      if fate != none and fate != "unknown" { lbl(S.eggFate, fate) },
    ))
    // A layer that is only guessed at is not a fact the report may assert
    // (mirrors EggEntryTile's "presumed" chip); anything but "confirmed" says so.
    let attribution = e.at("attribution", default: none)
    let attr = if attribution != none and attribution != "confirmed" {
      lbl(S.eggAttribution, attribution)
    }
    let head = if attr == none { bits } else if bits == "" { attr } else {
      bits + " (" + attr + ")"
    }
    joinDash((if head != "" { head }, e.at("notes", default: none)))
  } else {
    ""
  }
  (title, detail)
}
