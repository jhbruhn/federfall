import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';

/// The kinds of derived task surfaced on the worklist (UX Phase D, cr3.1).
enum WorklistKind { medicationDue, quarantineEnding, staleCase }

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
    this.drug,
  });

  final WorklistKind kind;
  final String caseId;
  final DateTime dueAt;
  final WorklistSeverity severity;

  /// The drug name, for [WorklistKind.medicationDue] items only.
  final String? drug;

  @override
  bool operator ==(Object other) =>
      other is WorklistItem &&
      other.kind == kind &&
      other.caseId == caseId &&
      other.dueAt == dueAt &&
      other.severity == severity &&
      other.drug == drug;

  @override
  int get hashCode => Object.hash(kind, caseId, dueAt, severity, drug);
}

/// How far ahead a quarantine end counts as "soon" (mirrors the dashboard).
const quarantineDueWindow = Duration(days: 7);

/// How far ahead a scheduled dose counts as "due" on the worklist — a dose
/// landing later today should show; one days out should not.
const medicationDueWindow = Duration(hours: 24);

/// How long an active case may go untouched before it counts as "stale".
const staleThreshold = Duration(days: 7);

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
  required List<Medication> medications,
  required List<MedicationAdministration> administrations,
  required DateTime now,
  Map<String, DateTime?> lastActivityByCase = const {},
  Duration quarantineWindow = quarantineDueWindow,
  Duration medicationWindow = medicationDueWindow,
  Duration staleAfter = staleThreshold,
}) {
  final items = <WorklistItem>[];
  final caseIds = {for (final c in cases) c.id};

  // Quarantines ending within the window (or already overdue).
  final quarantineThreshold = now.add(quarantineWindow);
  for (final c in cases) {
    final until = c.quarantineUntil;
    if (until == null || !until.isBefore(quarantineThreshold)) continue;
    items.add(
      WorklistItem(
        kind: WorklistKind.quarantineEnding,
        caseId: c.id,
        dueAt: until,
        severity: until.isAfter(now)
            ? WorklistSeverity.upcoming
            : WorklistSeverity.overdue,
      ),
    );
  }

  // Latest dose per prescription plan, to project the next due time.
  final lastDoseByMed = <String, DateTime>{};
  for (final a in administrations) {
    final med = a.medication;
    final at = a.administeredAt;
    if (med == null || at == null) continue;
    final current = lastDoseByMed[med];
    if (current == null || at.isAfter(current)) lastDoseByMed[med] = at;
  }

  // Scheduled and one-off medications that are due within the window.
  final medicationThreshold = now.add(medicationWindow);
  for (final m in medications) {
    if (!caseIds.contains(m.caseId)) continue;
    final ended = m.endedAt;
    if (ended != null && ended.isBefore(now)) continue;

    final due = _nextDue(m, lastDoseByMed[m.id]);
    if (due == null || !due.isBefore(medicationThreshold)) continue;

    items.add(
      WorklistItem(
        kind: WorklistKind.medicationDue,
        caseId: m.caseId,
        dueAt: due,
        severity: due.isAfter(now)
            ? WorklistSeverity.upcoming
            : WorklistSeverity.overdue,
        drug: m.drug,
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
      ),
    );
  }

  items.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return items;
}

/// The next moment [m] is due given its [lastDose], or `null` when it has no
/// schedule (as-needed) or has already been satisfied (a one-off that was
/// given). Scheduled doses recur every `interval_hours`; the first dose of any
/// plan is due at its start.
DateTime? _nextDue(Medication m, DateTime? lastDose) {
  switch (m.frequencyKind) {
    case MedicationFrequencyKind.scheduled:
      final interval = m.intervalHours;
      if (interval == null) return null;
      if (lastDose == null) return m.startedAt;
      return lastDose.add(Duration(hours: interval));
    case MedicationFrequencyKind.once:
      // Due once; once given, it drops off the list.
      return lastDose == null ? (m.startedAt ?? m.created) : null;
    case MedicationFrequencyKind.asNeeded:
    case null:
      return null;
  }
}
