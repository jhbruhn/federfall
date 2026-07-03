import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';

/// One OS-level notification to schedule: a medication dose coming due on a
/// prescription (federfall-3uz). [dueAtUtc] is the absolute instant the server
/// computed as `next_due`; the id is stable per prescription so rescheduling
/// replaces the previous reminder instead of stacking a duplicate.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.dueAtUtc,
    required this.payload,
  });

  /// Stable notification id, see [reminderNotificationId].
  final int id;

  final String title;
  final String body;

  /// The moment to fire, as an absolute UTC instant.
  final DateTime dueAtUtc;

  /// In-app location to open on tap (the case detail).
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.dueAtUtc == dueAtUtc &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, title, body, dueAtUtc, payload);
}

/// A stable 31-bit notification id derived from the prescription's record id
/// (FNV-1a). Platform notification ids are ints; hashing the id — rather than
/// using `String.hashCode`, which is not guaranteed stable across runs —
/// makes every (re)schedule of the same prescription land on the same slot,
/// so updating a reminder replaces the old one.
int reminderNotificationId(String prescriptionId) {
  var hash = 0x811c9dc5;
  for (final unit in prescriptionId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// Builds the medication reminders to have scheduled as of [now]: one per
/// prescription whose server-computed `next_due` lies in the future.
///
/// Deliberately skips anything already due or overdue — those are visible on
/// the worklist, and firing them on every reconcile (app start, each dose
/// logged elsewhere) would nag rather than remind. A reminder only makes
/// sense for a moment that hasn't arrived yet.
List<PlannedReminder> planMedicationReminders({
  required AppLocalizations l10n,
  required List<MedicationDue> medicationsDue,
  required Map<String, Case> casesById,
  required Map<String, String?> animalNameById,
  required DateTime now,
}) {
  final planned = <PlannedReminder>[];
  for (final md in medicationsDue) {
    final due = md.nextDue;
    if (due == null || !due.isAfter(now)) continue;
    final c = casesById[md.caseId];
    if (c == null) continue;

    final name = animalNameById[c.animal];
    var caseTitle = [
      ?c.caseNumber,
      if (name != null && name.isNotEmpty) name,
    ].join(' · ');
    if (caseTitle.isEmpty) caseTitle = l10n.worklistUnnumberedCase;
    final dose = formatDose(md.dose, md.doseUnit);
    final body = [if (dose.isNotEmpty) dose, caseTitle].join(' — ');

    planned.add(
      PlannedReminder(
        id: reminderNotificationId(md.id),
        title: l10n.medicationReminderTitle(md.drug),
        body: body,
        dueAtUtc: due.toUtc(),
        payload: AppRoutes.caseDetail(md.caseId),
      ),
    );
  }
  return planned;
}
