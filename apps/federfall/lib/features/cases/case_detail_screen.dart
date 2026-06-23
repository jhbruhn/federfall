import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/cases/case_timeline.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/weights/weight_trend_chart.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Case detail overview (FED-4.3): a name-first header, the intake summary and
/// a chronological timeline. The clinical sub-records — weights, conditions,
/// medications, journal, dispositions — plug into the timeline as they land in
/// the rest of Phase 4.
class CaseDetailScreen extends ConsumerWidget {
  const CaseDetailScreen({required this.caseId, super.key});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final caseAsync = ref.watch(caseByIdProvider(caseId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.caseDetailTitle)),
      body: AsyncValueView<Case>(
        value: caseAsync,
        onRetry: () => ref.invalidate(caseByIdProvider(caseId)),
        errorMessage: (e) => errorMessage(l10n, e),
        data: _CaseDetail.new,
      ),
    );
  }
}

class _CaseDetail extends ConsumerWidget {
  const _CaseDetail(this.medicalCase);

  final Case medicalCase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animal = ref.watch(animalByIdProvider(medicalCase.animal)).value;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _Header(medicalCase: medicalCase, animal: animal),
        const SizedBox(height: AppSpacing.lg),
        _IntakeSection(medicalCase: medicalCase, animal: animal),
        const SizedBox(height: AppSpacing.lg),
        WeightTrendChart(caseId: medicalCase.id),
        CaseTimeline(medicalCase: medicalCase),
      ],
    );
  }
}

/// Name-first identity header: the animal's name dominates, with species and
/// case number beneath and the current status as a chip.
class _Header extends StatelessWidget {
  const _Header({required this.medicalCase, required this.animal});

  final Case medicalCase;
  final Animal? animal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final name = animal?.name;
    final hasName = name != null && name.isNotEmpty;
    final title = hasName ? name : (animal?.species ?? l10n.caseAnimalLabel);

    final subtitleParts = <String>[
      if (hasName && animal != null) animal!.species,
      if (medicalCase.caseNumber != null) medicalCase.caseNumber!,
    ];
    final status = medicalCase.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        if (subtitleParts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitleParts.join(' · '),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (status != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Chip(
            label: Text(caseStatusLabel(l10n, status)),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}

/// The structured intake summary, rendered as a card of labelled rows. Empty
/// fields are skipped so the card stays as terse as the record allows.
class _IntakeSection extends ConsumerWidget {
  const _IntakeSection({required this.medicalCase, required this.animal});

  final Case medicalCase;
  final Animal? animal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);

    String? date(DateTime? d) =>
        d == null ? null : materialL10n.formatMediumDate(d);

    final reasons = medicalCase.reasonsForAdmission
        .map((r) => admissionReasonLabel(l10n, r))
        .join(', ');
    final sex = animal?.sex;
    final ageClass = medicalCase.ageClass;
    final weight = medicalCase.intakeWeightG;

    final rows = <_DetailRow>[
      if (sex != null)
        _DetailRow(Icons.transgender_outlined, l10n.caseFieldSex,
            sexLabel(l10n, sex)),
      if (ageClass != null)
        _DetailRow(Icons.cake_outlined, l10n.caseFieldAgeClass,
            ageClassLabel(l10n, ageClass)),
      if (reasons.isNotEmpty)
        _DetailRow(Icons.report_outlined, l10n.caseReasonsFieldLabel, reasons),
      if (date(medicalCase.foundAt) case final d?)
        _DetailRow(Icons.event_outlined, l10n.caseFieldFoundAt, d),
      if (date(medicalCase.admittedAt) case final d?)
        _DetailRow(Icons.event_available_outlined, l10n.caseFieldAdmittedAt, d),
      if (medicalCase.findLocation case final loc?)
        _DetailRow(Icons.place_outlined, l10n.caseFieldFindLocation, loc),
      if (weight != null)
        _DetailRow(Icons.monitor_weight_outlined, l10n.caseFieldIntakeWeight,
            '$weight g'),
      if (medicalCase.intakeNotes case final notes?)
        _DetailRow(Icons.notes_outlined, l10n.caseFieldIntakeNotes, notes),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.caseSectionIntake,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (rows.isEmpty)
              Text(l10n.emptyGeneric,
                  style: Theme.of(context).textTheme.bodyMedium)
            else
              for (final row in rows) row,
            if (medicalCase.finder case final finderId?)
              _FinderRow(finderId),
          ],
        ),
      ),
    );
  }
}

/// One labelled value inside the intake card.
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves and renders the linked finder's contact details, when present.
class _FinderRow extends ConsumerWidget {
  const _FinderRow(this.finderId);

  final String finderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final finder = ref.watch(finderByIdProvider(finderId)).value;
    if (finder == null) return const SizedBox.shrink();

    final name = [finder.firstName, finder.lastName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
    final value = [
      if (name.isNotEmpty) name,
      ?finder.phone,
      ?finder.email,
      ?finder.city,
    ].join(' · ');
    if (value.isEmpty) return const SizedBox.shrink();

    return _DetailRow(
      Icons.person_pin_circle_outlined,
      l10n.caseFinderLabel,
      value,
    );
  }
}
