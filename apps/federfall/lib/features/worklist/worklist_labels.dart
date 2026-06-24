import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Display helpers for worklist items — kept beside the pure [WorklistItem] so
/// l10n stays out of the computation layer (the cases_labels pattern).

/// Leading icon for a worklist item's kind.
IconData worklistIcon(WorklistKind kind) => switch (kind) {
  WorklistKind.medicationDue => Icons.vaccines_outlined,
  WorklistKind.quarantineEnding => Icons.shield_outlined,
  WorklistKind.staleCase => Icons.history_outlined,
};

/// Section heading for a group of items of one [kind].
String worklistGroupLabel(AppLocalizations l10n, WorklistKind kind) =>
    switch (kind) {
      WorklistKind.medicationDue => l10n.worklistGroupMeds,
      WorklistKind.quarantineEnding => l10n.worklistGroupQuarantine,
      WorklistKind.staleCase => l10n.worklistGroupStale,
    };

/// Row title — the case number and animal name (whichever are present),
/// falling back to a placeholder when neither is.
String worklistItemTitle(AppLocalizations l10n, WorklistItem item) {
  final name = item.animalName;
  final parts = [
    ?item.caseNumber,
    if (name != null && name.isNotEmpty) name,
  ];
  return parts.isEmpty ? l10n.worklistUnnumberedCase : parts.join(' · ');
}

/// Row subtitle — the drug and/or a relative due/age phrase, as of [now].
String worklistItemDetail(
  AppLocalizations l10n,
  WorklistItem item,
  DateTime now,
) => switch (item.kind) {
  WorklistKind.staleCase => l10n.worklistStaleDays(
    now.difference(item.dueAt).inDays,
  ),
  WorklistKind.medicationDue =>
    item.drug == null
        ? _relativeDue(l10n, item.dueAt, now)
        : '${item.drug} · ${_relativeDue(l10n, item.dueAt, now)}',
  WorklistKind.quarantineEnding => _relativeDue(l10n, item.dueAt, now),
};

/// A relative phrase for [due] vs [now]: "Due in N h/days" ahead, or
/// "Overdue by N h/days" once past.
String _relativeDue(AppLocalizations l10n, DateTime due, DateTime now) {
  if (due.isAfter(now)) {
    final diff = due.difference(now);
    if (diff.inHours < 24) {
      return l10n.worklistDueInHours((diff.inMinutes / 60).ceil());
    }
    return l10n.worklistDueInDays(diff.inDays);
  }
  final over = now.difference(due);
  if (over.inHours < 24) {
    return l10n.worklistOverdueHours((over.inMinutes / 60).ceil());
  }
  return l10n.worklistOverdueDays(over.inDays);
}
