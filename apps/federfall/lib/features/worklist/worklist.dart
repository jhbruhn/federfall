import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';

/// The kinds of derived task surfaced on the worklist (UX Phase D, cr3.1).
enum WorklistKind {
  medicationDue,
  followUpDue,
  quarantineEnding,
  staleCase,
}

/// Whether an item is already past its due moment or merely approaching it.
enum WorklistSeverity { overdue, upcoming }

/// A single derived to-do for the signed-in carer. Carries only data — the
/// human-readable label is built in the UI so l10n stays out of this pure
/// layer. [dueAt] is the moment the item becomes/became actionable; the list
/// is sorted by it.
@immutable
class WorklistItem {
  const WorklistItem({
    required this.kind,
    required this.caseId,
    required this.dueAt,
    required this.severity,
    this.caseNumber,
    this.animalName,
    this.drug,
    this.medication,
    this.followUp,
  });

  final WorklistKind kind;
  final String caseId;
  final DateTime dueAt;
  final WorklistSeverity severity;

  /// The case's display number, for the row title (null on an unnumbered case).
  final String? caseNumber;

  /// The animal's name, shown alongside the case number (null if unnamed).
  final String? animalName;

  /// The drug name, for [WorklistKind.medicationDue] items only.
  final String? drug;

  /// The prescription behind a [WorklistKind.medicationDue] item, so a dose can
  /// be logged straight from the worklist (prefilling the administration
  /// sheet). Null for ad-hoc dues and other kinds.
  final Medication? medication;

  /// The recheck behind a [WorklistKind.followUpDue] item, so it can be marked
  /// done from the worklist. Null for other kinds.
  final FollowUp? followUp;

  @override
  bool operator ==(Object other) =>
      other is WorklistItem &&
      other.kind == kind &&
      other.caseId == caseId &&
      other.dueAt == dueAt &&
      other.severity == severity &&
      other.caseNumber == caseNumber &&
      other.animalName == animalName &&
      other.drug == drug &&
      other.medication == medication &&
      other.followUp == followUp;

  @override
  int get hashCode => Object.hash(
    kind,
    caseId,
    dueAt,
    severity,
    caseNumber,
    animalName,
    drug,
    medication,
    followUp,
  );
}

/// How far ahead a scheduled dose counts as "due" on the worklist — a dose
/// landing later today should show; one days out should not.
const medicationDueWindow = Duration(hours: 24);

/// How far ahead a recheck counts as "due" on the worklist.
const followUpDueWindow = Duration(days: 7);

/// How long an active case may go untouched before it counts as "stale".
const staleThreshold = Duration(days: 7);

/// How many days past its end a quarantine still surfaces on the worklist, so
/// a carer who skipped the end day still sees the release cue once (7zf).
const quarantineGraceDays = 3;

/// Builds the carer's worklist from cases they are responsible for plus the
/// medications/doses on those cases, as of [now]. Pure and PocketBase-free so
/// it can be unit-tested directly.
///
/// [cases] should already be scoped to the relevant set (the provider passes
/// the carer's own active cases). [lastActivityByCase] maps a case id to the
/// newest activity on it (from the case_activity view); a case missing from the
/// map is never flagged stale. Items are returned soonest-due first.
List<WorklistItem> buildWorklist({
  required List<Case> cases,
  required List<MedicationDue> medicationsDue,
  required DateTime now,
  List<FollowUp> followUps = const [],
  Map<String, DateTime?> lastActivityByCase = const {},
  Map<String, DateTime?> quarantineUntilByCase = const {},
  Map<String, String?> animalNameById = const {},
  Duration medicationWindow = medicationDueWindow,
  Duration followUpWindow = followUpDueWindow,
  Duration staleAfter = staleThreshold,
}) {
  final items = <WorklistItem>[];
  final casesById = {for (final c in cases) c.id: c};

  // Quarantines ending today, plus a short grace window after — a neutral
  // note, never overdue. A quarantine simply concludes; it isn't an obligation
  // you fall behind on, and "end now" just moves the end to today, so it
  // should leave a gentle "ends today" marker rather than flip to a red
  // "overdue" item the moment it passes. The grace window makes sure a carer
  // who didn't open the app on the end day still sees the release cue once
  // ("ended N days ago"); after [quarantineGraceDays] it goes quiet for good
  // rather than nag indefinitely.
  for (final c in cases) {
    final until = quarantineUntilByCase[c.id];
    if (until == null) continue;
    final endedDaysAgo = localDaysBetween(until, now);
    if (endedDaysAgo < 0 || endedDaysAgo > quarantineGraceDays) continue;
    items.add(
      WorklistItem(
        kind: WorklistKind.quarantineEnding,
        caseId: c.id,
        dueAt: until,
        severity: WorklistSeverity.upcoming,
        caseNumber: c.caseNumber,
        animalName: animalNameById[c.animal],
      ),
    );
  }

  // Medications whose server-computed next-due falls within the window.
  final medicationThreshold = now.add(medicationWindow);
  for (final md in medicationsDue) {
    final c = casesById[md.caseId];
    final due = md.nextDue;
    if (c == null || due == null || !due.isBefore(medicationThreshold)) {
      continue;
    }
    items.add(
      WorklistItem(
        kind: WorklistKind.medicationDue,
        caseId: md.caseId,
        dueAt: due,
        severity: due.isAfter(now)
            ? WorklistSeverity.upcoming
            : WorklistSeverity.overdue,
        caseNumber: c.caseNumber,
        animalName: animalNameById[c.animal],
        drug: md.drug,
        // Reconstruct the plan so a dose can be logged from the worklist.
        medication: Medication(
          id: md.id,
          caseId: md.caseId,
          drug: md.drug,
          dose: md.dose,
          doseUnit: md.doseUnit,
          route: md.route,
          frequencyKind: md.frequencyKind,
          intervalHours: md.intervalHours,
          startedAt: md.startedAt,
          endedAt: md.endedAt,
        ),
      ),
    );
  }

  // Open rechecks due within the window (or already overdue).
  final followUpThreshold = now.add(followUpWindow);
  for (final f in followUps) {
    final c = casesById[f.caseId];
    final due = f.dueAt;
    if (c == null || f.doneAt != null || due == null) continue;
    if (!due.isBefore(followUpThreshold)) continue;
    items.add(
      WorklistItem(
        kind: WorklistKind.followUpDue,
        caseId: f.caseId,
        dueAt: due,
        severity: due.isAfter(now)
            ? WorklistSeverity.upcoming
            : WorklistSeverity.overdue,
        caseNumber: c.caseNumber,
        animalName: animalNameById[c.animal],
        followUp: f,
      ),
    );
  }

  // Active cases untouched for longer than the threshold.
  final staleBefore = now.subtract(staleAfter);
  for (final c in cases) {
    final last = lastActivityByCase[c.id];
    if (last == null || !last.isBefore(staleBefore)) continue;
    items.add(
      WorklistItem(
        kind: WorklistKind.staleCase,
        caseId: c.id,
        dueAt: last,
        severity: WorklistSeverity.overdue,
        caseNumber: c.caseNumber,
        animalName: animalNameById[c.animal],
      ),
    );
  }

  items.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return items;
}

/// Whole calendar days from [a]'s local date to [b]'s local date (0 = same
/// day, positive when [b] is later). Quarantine ends are stored UTC; the carer
/// thinks in their own day, so compare local dates, not raw instants.
int localDaysBetween(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return DateTime(
    lb.year,
    lb.month,
    lb.day,
  ).difference(DateTime(la.year, la.month, la.day)).inDays;
}
