import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart' show runQuickAction;

/// Ends [plan] as of now, after a confirmation that names the drug and the
/// date it is about to write and says the record is kept.
///
/// Deliberately not a delete and deliberately not a trip through the
/// prescription sheet. Stopping a course early is the one change somebody makes
/// without wanting to edit anything, and the only way to express it used to be
/// the sheet's `ended_at` field — a form with a dozen inputs, a cycle preview
/// and a dose calculator for a one-word decision. Carers reached for delete
/// instead, which destroys the record that the bird was on the drug at all
/// while leaving its administrations behind, so the case ends up with logged
/// doses of a prescription it never had (federfall-78k6.1).
///
/// Confirmed rather than immediate, unlike the timeline's other one-tap
/// actions: the write is invisible where it matters most. Neither surface that
/// offers this shows that the plan has quietly left the worklist, the Today
/// screen and the on-device dose reminders — the `medication_due` view drops an
/// ended prescription server-side (1700000024) — so a stray tap would stop a
/// bird's antibiotics with no cue that it had. The dialog is not a destructive
/// one: nothing is deleted, and clearing the date under „Bearbeiten" makes the
/// course run again.
///
/// Shared by the timeline's `PrescriptionTile` and the overview's
/// `CurrentTreatmentCard` so the two cannot come to ask different questions or
/// write different things. Invalidating the case bundle is what refreshes both,
/// and `nextDoseByMedication` with them.
Future<void> confirmStopMedication(
  BuildContext context,
  WidgetRef ref, {
  required Medication plan,
  required String caseId,
}) async {
  final l10n = context.l10n;
  final materialL10n = MaterialLocalizations.of(context);
  final now = DateTime.now();
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.medStopConfirmTitle,
    message: l10n.medStopConfirmBody(
      plan.drug,
      formatLocalDate(materialL10n, now),
    ),
    confirmLabel: l10n.medStopConfirmAction,
  );
  if (!confirmed || !context.mounted) return;
  await runQuickAction(context, () async {
    final repo = await ref.read(medicationsRepositoryProvider.future);
    await repo.update(plan.id, {
      'ended_at': now.toUtc().toIso8601String(),
    });
    ref.invalidate(caseBundleProvider(caseId));
  });
}
