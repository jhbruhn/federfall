import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Confirms and then permanently deletes [animal] with everything recorded for
/// it (federfall-vfl7). Resolves to `true` once the delete succeeded, so the
/// caller can navigate away from a screen whose subject no longer exists.
///
/// Supervisor-only — gate the entry point on `canDeleteRecords`; the server
/// rule (1700000010) is the real boundary.
///
/// An open case does NOT block the delete: the usual reason to reach for this
/// is a record that should never have existed, and those almost always carry a
/// live case. The confirmation names the open ones instead of refusing, which
/// is where this differs from member removal (that one blocks, because an
/// orphaned caseload has nobody responsible for it).
Future<bool> confirmDeleteAnimal(
  BuildContext context,
  WidgetRef ref,
  Animal animal,
) async {
  final l10n = context.l10n;

  // AWAITED, not read off a snapshot: a `.value` that happens to be loading
  // would render "No cases" on a dialog whose whole job is to state the damage
  // truthfully. The animal detail already has all of these cached, so in
  // practice this resolves without a request — and where it doesn't, paying for
  // one before an irreversible delete is the right trade.
  //
  // Per-case children (journal, medications, …) would cost one query per case,
  // so they are covered as prose rather than an exact count.
  final cases = await ref.read(casesForAnimalProvider(animal.id).future);
  final openCases = cases.where((c) => c.status != CaseStatus.disposed).length;
  final weights = await ref.read(weightsForAnimalProvider(animal.id).future);
  final eggs = await ref.read(eggsForAnimalProvider(animal.id).future);
  final markings = await ref.read(markingsForAnimalProvider(animal.id).future);
  final exams = await ref.read(examsForAnimalProvider(animal.id).future);
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _DestructiveDialog(
      title: l10n.animalDeleteTitle,
      intro: l10n.animalDeleteIntro(animalTitle(animal)),
      bullets: [
        (l10n.animalDeleteCases(cases.length), false),
        if (openCases > 0) (l10n.animalDeleteCasesOpen(openCases), true),
        (
          l10n.animalDeleteRecordCounts(
            weights.length,
            eggs.fold(0, (sum, e) => sum + e.count),
            markings.length,
            exams.length,
          ),
          false,
        ),
        if (cases.isNotEmpty) (l10n.animalDeleteCaseContents, false),
      ],
      confirmLabel: l10n.animalDeleteAction,
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  var ok = false;
  await runQuickAction(context, () async {
    final repo = await ref.read(animalsRepositoryProvider.future);
    await repo.delete(animal.id);
    // The cascade reaches cases and everything under them, so the registry and
    // every per-animal leaf has to be re-read rather than patched.
    ref
      ..invalidate(animalsRegistryProvider)
      ..invalidate(animalLifetimeProvider(animal.id))
      ..invalidate(casesForAnimalProvider(animal.id));
    ok = true;
  });
  return ok;
}

/// Confirms and then permanently deletes [medicalCase] with its whole timeline.
/// Resolves to `true` once the delete succeeded.
///
/// The animal survives, and so does its animal-level history — weights,
/// markings and egg records deliberately do not cascade from a case (5yg.4,
/// federfall-4agw), so one treatment episode can be erased without losing the
/// bird's weight curve. The dialog says so, because "delete case" reasonably
/// reads as "delete everything".
Future<bool> confirmDeleteCase(
  BuildContext context,
  WidgetRef ref,
  Case medicalCase,
) async {
  final l10n = context.l10n;
  // Awaited for the same reason as the animal counts above: a loading snapshot
  // would quietly report an empty timeline. The case detail has the bundle
  // cached, so this normally resolves immediately.
  final bundle = await ref.read(caseBundleProvider(medicalCase.id).future);
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _DestructiveDialog(
      title: l10n.caseDeleteTitle,
      intro: l10n.caseDeleteIntro(medicalCase.caseNumber ?? ''),
      bullets: [
        (
          l10n.caseDeleteCounts(
            bundle.journal.length,
            bundle.medications.length,
            bundle.administrations.length,
            bundle.exams.length,
          ),
          false,
        ),
        (l10n.caseDeleteKeeps, false),
      ],
      confirmLabel: l10n.caseDeleteAction,
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  var ok = false;
  await runQuickAction(context, () async {
    final repo = await ref.read(casesRepositoryProvider.future);
    await repo.delete(medicalCase.id);
    ref
      ..invalidate(caseBundleProvider(medicalCase.id))
      ..invalidate(casesForAnimalProvider(medicalCase.animal))
      ..invalidate(animalLifetimeProvider(medicalCase.animal));
    ok = true;
  });
  return ok;
}

/// A confirmation that enumerates what is about to be destroyed before offering
/// the button that destroys it. [bullets] pair each line with whether it is a
/// warning (rendered in the error colour).
class _DestructiveDialog extends StatelessWidget {
  const _DestructiveDialog({
    required this.title,
    required this.intro,
    required this.bullets,
    required this.confirmLabel,
  });

  final String title;
  final String intro;
  final List<(String text, bool isWarning)> bullets;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(intro),
          const SizedBox(height: AppSpacing.sm),
          for (final (text, isWarning) in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '• $text',
                style: isWarning
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                      )
                    : theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.animalDeleteIrreversible,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
