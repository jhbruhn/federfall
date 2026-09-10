import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/worklist/worklist_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// „Aktuelle Behandlung" — what this bird is being treated FOR and WITH, at the
/// top of the case overview (federfall-78k6.2).
///
/// Both facts already existed, but only as individual events scattered down the
/// History tab's chronology in the order somebody entered them, so "is she
/// still on the Baytril?" was a scroll-and-reconstruct job.
///
/// **One card, not two.** The request arrived as two — "a nice overview of the
/// currently prescribed medication" and "the diagnosis/medication TODOs as a
/// block" — and they are the same block: a course that is running IS the thing
/// to do. Splitting them would rebuild the second, partial menu competing for
/// authority that federfall-do5g already took off this screen once (see
/// `_CaseActions`).
///
/// This is a projection of the timeline, not a replacement for it — the same
/// relationship the weight chart has to the weight entries. Nothing here is
/// the record; the History tab still is. So it stays terse: no notes, no
/// prescriber, no instructions. It is what a carer reads at 06:00 with a bird
/// in one hand.
///
/// Renders **nothing at all** when the bird is on nothing and carries no open
/// diagnosis. An empty card would cost a slot to say "no".
class CurrentTreatmentCard extends ConsumerWidget {
  const CurrentTreatmentCard({required this.caseId, super.key});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    // Both off the case bundle, which the screen has already fetched.
    final conditions =
        ref.watch(caseConditionsForCaseProvider(caseId)).value ?? const [];
    final plans =
        ref.watch(medicationsForCaseProvider(caseId)).value ?? const [];
    final codes = ref.watch(conditionsByIdProvider).value ?? const {};
    // The server's next-due times. Absent while it loads or if it fails — the
    // card still states the treatment, it just cannot yet say when.
    final nextDue =
        ref.watch(nextDoseByMedicationProvider(caseId)).value ?? const {};
    final canEdit = ref.watch(canEditCaseProvider(caseId)).value ?? false;

    final now = DateTime.now();
    final open = [
      for (final c in conditions)
        if (c.resolvedDate == null) c,
    ];
    // The same predicate PrescriptionTile applies, so the card and the
    // timeline cannot disagree about which course is still running. A future
    // end date is still running.
    final running = [
      for (final p in plans)
        if (p.endedAt == null || p.endedAt!.isAfter(now)) p,
    ];

    if (open.isEmpty && running.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The same style `_CardTitle` gives every other card on this
              // tab; that helper is private to the screen and this card is
              // not worth widening its API for.
              Text(
                l10n.caseSectionCurrentTreatment,
                style: theme.textTheme.titleMedium,
              ),
              if (open.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _SubHeading(l10n.treatmentDiagnosesHeading),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final c in open)
                      _DiagnosisChip(entry: c, codes: codes),
                  ],
                ),
              ],
              if (running.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _SubHeading(l10n.treatmentMedicationsHeading),
                for (final plan in running)
                  _RunningCourse(
                    plan: plan,
                    caseId: caseId,
                    canEdit: canEdit,
                    nextDue: nextDue[plan.id],
                    now: now,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the card's two section labels.
class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// An unresolved diagnosis: its label, plus the two badges that change what
/// somebody does next.
///
/// Certainty is deliberately dropped here — the timeline tile carries it, and
/// on a summary "Fraktur" and "Fraktur (Verdacht)" both mean "this is what we
/// are treating". Notifiable and contagious stay, in the colours the timeline
/// gives them: one is a legal obligation and the other changes where the bird
/// may be housed.
class _DiagnosisChip extends StatelessWidget {
  const _DiagnosisChip({required this.entry, required this.codes});

  final CaseCondition entry;
  final Map<String, Condition> codes;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final code = entry.condition == null ? null : codes[entry.condition];
    final label = code?.label ?? entry.freeText ?? '—';

    if (code?.isNotifiable ?? false) {
      return TagChip(
        label: '$label · ${l10n.conditionNotifiable}',
        color: theme.colorScheme.errorContainer,
        onColor: theme.colorScheme.onErrorContainer,
      );
    }
    if (code?.isContagious ?? false) {
      return TagChip(
        label: '$label · ${l10n.conditionContagious}',
        color: theme.colorScheme.tertiaryContainer,
        onColor: theme.colorScheme.onTertiaryContainer,
      );
    }
    return TagChip(label: label);
  }
}

/// One running course: what it is, when the next dose falls, and the one verb
/// that belongs on a summary.
///
/// Only "give". Stopping a course lives on the timeline's own tile, where the
/// confirmation can name the date and the record it is about to change; a
/// summary is the wrong place to end a treatment from.
class _RunningCourse extends ConsumerWidget {
  const _RunningCourse({
    required this.plan,
    required this.caseId,
    required this.canEdit,
    required this.nextDue,
    required this.now,
  });

  final Medication plan;
  final String caseId;
  final bool canEdit;
  final DateTime? nextDue;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final routesById =
        ref.watch(medicationRoutesByIdProvider).value ?? const {};

    // Built exactly as PrescriptionTile builds its detail line — a rate-based
    // plan shows the rate, because that is what was prescribed and the amount
    // it works out to changes with every weighing.
    final unit = plan.doseUnit ?? '';
    final dosing = plan.doseRate != null
        ? formatDose(l10n, plan.doseRate, unit.isEmpty ? null : '$unit/kg')
        : formatDose(l10n, plan.dose, plan.doseUnit);
    final frequency = medicationFrequencyLabel(
      l10n,
      plan.frequencyKind,
      plan.intervalHours,
      cycleOnDays: plan.cycleOnDays,
      cycleOffDays: plan.cycleOffDays,
    );
    final detail = [
      if (dosing case final d when d.isNotEmpty) d,
      ?routesById[plan.route]?.label,
      if (frequency.isNotEmpty) frequency,
    ].join(' · ');

    final due = nextDue;
    final overdue = due != null && !due.isAfter(now);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.drug, style: theme.textTheme.bodyLarge),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                // Omitted rather than guessed at when the view names no next
                // dose: an as-needed course has none, and it is still running.
                if (due != null)
                  Text(
                    l10n.treatmentNextDose(
                      relativeDueLabel(l10n, due, now),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: overdue
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.vaccines_outlined),
              tooltip: l10n.medLogDose,
              onPressed: () => showAdministrationSheet(
                context,
                caseId: caseId,
                plan: plan,
              ),
            ),
        ],
      ),
    );
  }
}
