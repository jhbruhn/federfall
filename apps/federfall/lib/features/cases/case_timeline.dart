import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/cases/conditions/condition_entry_sheet.dart';
import 'package:federfall/features/cases/conditions/condition_entry_tile.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/disposition/disposition_providers.dart';
import 'package:federfall/features/cases/disposition/disposition_sheet.dart';
import 'package:federfall/features/cases/disposition/disposition_tile.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/journal/journal_entry_tile.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/markings/marking_sheet.dart';
import 'package:federfall/features/cases/markings/marking_tile.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/medications/medication_tiles.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
import 'package:federfall/features/cases/placements/placement_sheet.dart';
import 'package:federfall/features/cases/placements/placement_tile.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/features/cases/weights/weight_entry_sheet.dart';
import 'package:federfall/features/cases/weights/weight_entry_tile.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The case's single, unified chronology (FED-4.3 + FED-4.7): intake milestones
/// and journal entries interleaved newest-first in one ordered list. Further
/// Phase 4 records (weights, medications, conditions, dispositions) become
/// additional event kinds here rather than separate sections.
class CaseTimeline extends ConsumerWidget {
  const CaseTimeline({
    required this.medicalCase,
    this.showTitle = true,
    super.key,
  });

  final Case medicalCase;

  /// Whether to show the "timeline" heading. Hidden when the timeline already
  /// sits under a "History" tab that names it.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final caseId = medicalCase.id;
    final journal = ref.watch(journalForCaseProvider(caseId));
    final weights = ref.watch(weightsForCaseProvider(caseId));
    final conditions = ref.watch(caseConditionsForCaseProvider(caseId));
    final meds = ref.watch(medicationsForCaseProvider(caseId));
    final doses = ref.watch(administrationsForCaseProvider(caseId));
    final markings = ref.watch(markingsForAnimalProvider(medicalCase.animal));
    final placements = ref.watch(placementsForCaseProvider(caseId));
    final dispositions = ref.watch(dispositionsForCaseProvider(caseId));
    final isLoading = journal.isLoading ||
        weights.isLoading ||
        conditions.isLoading ||
        meds.isLoading ||
        doses.isLoading ||
        markings.isLoading ||
        placements.isLoading ||
        dispositions.isLoading;
    final error = journal.error ??
        weights.error ??
        conditions.error ??
        meds.error ??
        doses.error ??
        markings.error ??
        placements.error ??
        dispositions.error;

    final events = <_Event>[
      if (medicalCase.admittedAt case final d?)
        _MilestoneEvent(
          d,
          Icons.event_available_outlined,
          l10n.caseEventAdmitted,
        ),
      if (medicalCase.created case final d?)
        _MilestoneEvent(d, Icons.flag_outlined, l10n.caseEventCreated),
      for (final entry in journal.value ?? const <JournalEntry>[])
        _JournalEvent(entry),
      for (final weight in weights.value ?? const <Weight>[])
        _WeightEvent(weight),
      for (final condition in conditions.value ?? const <CaseCondition>[])
        _ConditionEvent(condition),
      for (final plan in meds.value ?? const <Medication>[])
        _PrescriptionEvent(plan),
      for (final dose
          in doses.value ?? const <MedicationAdministration>[])
        _AdministrationEvent(dose),
      for (final marking in markings.value ?? const <Marking>[])
        _MarkingEvent(marking),
      for (final placement in placements.value ?? const <Placement>[])
        _PlacementEvent(placement),
      for (final disposition in dispositions.value ?? const <Disposition>[])
        _DispositionEvent(disposition),
    ]..sort((a, b) => b.at.compareTo(a.at));

    final isDisposed = (dispositions.value ?? const []).isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: showTitle
                  ? Text(l10n.caseTimelineTitle,
                      style: theme.textTheme.titleMedium)
                  : const SizedBox.shrink(),
            ),
            PopupMenuButton<void>(
              icon: const Icon(Icons.add),
              tooltip: l10n.timelineAddTooltip,
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => showJournalEntrySheet(context, caseId: caseId),
                  child: Text(l10n.timelineAddNote),
                ),
                PopupMenuItem(
                  onTap: () => showWeightEntrySheet(
                    context,
                    animalId: medicalCase.animal,
                    caseId: caseId,
                  ),
                  child: Text(l10n.timelineAddWeight),
                ),
                PopupMenuItem(
                  onTap: () =>
                      showConditionEntrySheet(context, caseId: caseId),
                  child: Text(l10n.timelineAddCondition),
                ),
                PopupMenuItem(
                  onTap: () =>
                      showPrescriptionSheet(context, caseId: caseId),
                  child: Text(l10n.timelineAddPrescription),
                ),
                PopupMenuItem(
                  onTap: () =>
                      showAdministrationSheet(context, caseId: caseId),
                  child: Text(l10n.timelineAddDose),
                ),
                PopupMenuItem(
                  onTap: () => showMarkingSheet(
                    context,
                    animalId: medicalCase.animal,
                    caseId: caseId,
                  ),
                  child: Text(l10n.timelineAddMarking),
                ),
                PopupMenuItem(
                  onTap: () => showPlacementSheet(
                    context,
                    medicalCase: medicalCase,
                    mode: PlacementMode.handoff,
                  ),
                  child: Text(l10n.timelineAddHandoff),
                ),
                PopupMenuItem(
                  onTap: () =>
                      showPlacementSheet(context, medicalCase: medicalCase),
                  child: Text(l10n.timelineAddPlacement),
                ),
                if (!isDisposed)
                  PopupMenuItem(
                    onTap: () =>
                        showDispositionSheet(context, caseId: caseId),
                    child: Text(l10n.timelineRecordOutcome),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isLoading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              errorMessage(l10n, error),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        if (events.isEmpty && !isLoading)
          Text(l10n.caseTimelineEmpty, style: theme.textTheme.bodyMedium)
        else
          for (var i = 0; i < events.length; i++)
            switch (events[i]) {
              _JournalEvent(:final entry) => JournalEntryTile(
                entry: entry,
                caseId: caseId,
                isLast: i == events.length - 1,
              ),
              _WeightEvent(:final weight) => WeightEntryTile(
                weight: weight,
                caseId: caseId,
                isLast: i == events.length - 1,
              ),
              _ConditionEvent(:final condition) => ConditionEntryTile(
                entry: condition,
                caseId: caseId,
                isLast: i == events.length - 1,
              ),
              _PrescriptionEvent(:final plan) => PrescriptionTile(
                plan: plan,
                caseId: caseId,
                isLast: i == events.length - 1,
              ),
              _AdministrationEvent(:final dose) => AdministrationTile(
                administration: dose,
                caseId: caseId,
                isLast: i == events.length - 1,
              ),
              _MarkingEvent(:final marking) => MarkingTile(
                marking: marking,
                caseId: caseId,
                isLast: i == events.length - 1,
              ),
              _PlacementEvent(:final placement) => PlacementTile(
                placement: placement,
                medicalCase: medicalCase,
                isLast: i == events.length - 1,
              ),
              _DispositionEvent(:final disposition) => DispositionTile(
                disposition: disposition,
                caseId: caseId,
                isLast: i == events.length - 1,
              ),
              _MilestoneEvent(:final icon, :final label, :final at) =>
                TimelineItem(
                  icon: icon,
                  date: MaterialLocalizations.of(context).formatMediumDate(at),
                  isLast: i == events.length - 1,
                  child: Text(label, style: theme.textTheme.bodyLarge),
                ),
            },
      ],
    );
  }
}

/// A timeline item: anything that carries a timestamp [at] for ordering.
sealed class _Event {
  const _Event();

  DateTime get at;
}

/// A fixed lifecycle moment derived from the case record (admitted, opened…).
class _MilestoneEvent extends _Event {
  const _MilestoneEvent(this.at, this.icon, this.label);

  @override
  final DateTime at;
  final IconData icon;
  final String label;
}

/// A journal entry placed on the timeline by its entry date (or created time).
class _JournalEvent extends _Event {
  const _JournalEvent(this.entry);

  final JournalEntry entry;

  @override
  DateTime get at =>
      entry.entryAt ??
      entry.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// A weight measurement placed on the timeline by its measurement date.
class _WeightEvent extends _Event {
  const _WeightEvent(this.weight);

  final Weight weight;

  @override
  DateTime get at =>
      weight.measuredAt ??
      weight.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// A diagnosis placed on the timeline by its onset date (or created time).
class _ConditionEvent extends _Event {
  const _ConditionEvent(this.condition);

  final CaseCondition condition;

  @override
  DateTime get at =>
      condition.onsetDate ??
      condition.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// A prescription placed on the timeline by its start date (or created time).
class _PrescriptionEvent extends _Event {
  const _PrescriptionEvent(this.plan);

  final Medication plan;

  @override
  DateTime get at =>
      plan.startedAt ??
      plan.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// An administered dose placed on the timeline by when it was given.
class _AdministrationEvent extends _Event {
  const _AdministrationEvent(this.dose);

  final MedicationAdministration dose;

  @override
  DateTime get at =>
      dose.administeredAt ??
      dose.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// A marking placed on the timeline by when it was applied.
class _MarkingEvent extends _Event {
  const _MarkingEvent(this.marking);

  final Marking marking;

  @override
  DateTime get at =>
      marking.appliedAt ??
      marking.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// A placement / handoff placed on the timeline by when the move happened.
class _PlacementEvent extends _Event {
  const _PlacementEvent(this.placement);

  final Placement placement;

  @override
  DateTime get at =>
      placement.movedInAt ??
      placement.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// A case outcome placed on the timeline by when the case was disposed.
class _DispositionEvent extends _Event {
  const _DispositionEvent(this.disposition);

  final Disposition disposition;

  @override
  DateTime get at =>
      disposition.disposedAt ??
      disposition.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
