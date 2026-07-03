import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/conditions/condition_entry_tile.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/disposition/disposition_providers.dart';
import 'package:federfall/features/cases/disposition/disposition_tile.dart';
import 'package:federfall/features/cases/exams/exam_tile.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/follow_ups/follow_up_tile.dart';
import 'package:federfall/features/cases/follow_ups/follow_ups_providers.dart';
import 'package:federfall/features/cases/journal/journal_entry_tile.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/markings/marking_tile.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/cases/medications/medication_tiles.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/placements/placement_tile.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_tile.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/features/cases/weights/weight_entry_tile.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Refetches everything the [CaseTimeline] (and the case header) shows, so a
/// pull-to-refresh or a realtime event rebuilds the whole chronology from the
/// server. Every per-case source derives from the one [caseBundleProvider]
/// (federfall-kh0u), so this is a single request — invalidating a derived
/// leaf provider would only re-read the cached bundle.
void invalidateCaseTimeline(Ref ref, {required String caseId}) {
  ref.invalidate(caseBundleProvider(caseId));
}

/// The case's single, unified chronology (FED-4.3 + FED-4.7): intake milestones
/// and journal entries interleaved newest-first in one ordered list. Further
/// Phase 4 records (weights, medications, conditions, dispositions) become
/// additional event kinds here rather than separate sections.
///
/// Renders as a lazy scrollable ([ListView.builder]) and therefore owns the
/// vertical scrolling — hosts must not nest it inside another scroll view.
/// Long cases accumulate hundreds of events (daily doses, journal entries),
/// and realtime invalidation rebuilds the chronology constantly, so only the
/// visible rows may be built.
class CaseTimeline extends ConsumerWidget {
  const CaseTimeline({
    required this.medicalCase,
    this.canEdit = true,
    this.showTitle = true,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Case medicalCase;

  /// Outer inset of the scrollable (a screen-level concern, so the host
  /// supplies it — e.g. the History tab passes its page padding).
  final EdgeInsetsGeometry padding;

  /// Whether the current user may edit this case's records. When false, the
  /// per-entry edit/delete menus are hidden (read-only view). Supplied by the
  /// case detail from `canEditCaseProvider`.
  final bool canEdit;

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
    final markings = ref.watch(markingsForCaseProvider(caseId));
    final placements = ref.watch(placementsForCaseProvider(caseId));
    final dispositions = ref.watch(dispositionsForCaseProvider(caseId));
    final followUps = ref.watch(followUpsForCaseProvider(caseId));
    final exams = ref.watch(examsForCaseProvider(caseId));
    final examFindings = ref.watch(examFindingsForCaseProvider(caseId));
    final quarantines = ref.watch(quarantineForCaseProvider(caseId));
    final isLoading =
        journal.isLoading ||
        weights.isLoading ||
        conditions.isLoading ||
        meds.isLoading ||
        doses.isLoading ||
        markings.isLoading ||
        placements.isLoading ||
        dispositions.isLoading ||
        followUps.isLoading ||
        exams.isLoading ||
        examFindings.isLoading ||
        quarantines.isLoading;
    final error =
        journal.error ??
        weights.error ??
        conditions.error ??
        meds.error ??
        doses.error ??
        markings.error ??
        placements.error ??
        dispositions.error ??
        followUps.error ??
        exams.error ??
        examFindings.error ??
        quarantines.error;

    // The active quarantine is the latest record (forCase sorts newest-first),
    // so only it gets the inline "end now" shortcut.
    final currentQuarantineId =
        (quarantines.value ?? const <Quarantine>[]).firstOrNull?.id;

    final events =
        <_Event>[
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
          for (final dose in doses.value ?? const <MedicationAdministration>[])
            _AdministrationEvent(dose),
          for (final marking in markings.value ?? const <Marking>[])
            _MarkingEvent(marking),
          for (final placement in placements.value ?? const <Placement>[])
            _PlacementEvent(placement),
          for (final disposition in dispositions.value ?? const <Disposition>[])
            _DispositionEvent(disposition),
          for (final followUp in followUps.value ?? const <FollowUp>[])
            _FollowUpEvent(followUp),
          for (final exam in exams.value ?? const <Exam>[])
            _ExamEvent(exam, examFindings.value?[exam.id] ?? const []),
          for (final quarantine
              in quarantines.value ?? const <Quarantine>[]) ...[
            // Every quarantine shows as a "started" entry; once it has
            // lapsed it also gets a separate "ended" marker at its end date.
            _QuarantineEvent(
              quarantine,
              phase: QuarantinePhase.started,
              isCurrent: quarantine.id == currentQuarantineId,
            ),
            if (quarantine.until case final until?
                when !until.isAfter(DateTime.now()))
              _QuarantineEvent(
                quarantine,
                phase: QuarantinePhase.ended,
                isCurrent: quarantine.id == currentQuarantineId,
              ),
          ],
        ]..sort((a, b) {
          final byTime = b.at.compareTo(a.at);
          if (byTime != 0) return byTime;
          // Same instant — e.g. the intake weight is measured at the admission
          // time (new_case_screen). Keep the genesis milestones (Admitted,
          // Case opened) above the records logged at that moment, rather than
          // letting an unstable tie wedge the weight above "Aufgenommen".
          final aRank = a is _MilestoneEvent ? 1 : 0;
          final bRank = b is _MilestoneEvent ? 1 : 0;
          return aRank.compareTo(bRank);
        });

    // The non-event rows (title, first-load progress, error, empty state) lead
    // the same lazy list as the events — a wrapping Column would force every
    // event tile to build eagerly.
    final header = <Widget>[
      // The add-entry trigger now lives on the case detail FAB
      // (showAddEntrySheet); the timeline only renders the chronology.
      if (showTitle) ...[
        Text(l10n.caseTimelineTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
      ],
      // Only on the first load (no events yet). A refresh keeps the existing
      // events on screen and is already signalled by the pull-to-refresh
      // indicator, so showing the bar too would be a second, redundant
      // loading indicator.
      if (isLoading && events.isEmpty) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            errorMessage(l10n, error),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      if (events.isEmpty && !isLoading)
        Text(l10n.caseTimelineEmpty, style: theme.textTheme.bodyMedium),
    ];

    return ListView.builder(
      padding: padding,
      // Pull-to-refresh must keep working when the chronology is shorter than
      // the viewport.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: header.length + events.length,
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        final i = index - header.length;
        return _eventTile(context, events[i], isLast: i == events.length - 1);
      },
    );
  }

  Widget _eventTile(
    BuildContext context,
    _Event event, {
    required bool isLast,
  }) {
    final caseId = medicalCase.id;
    return switch (event) {
      _JournalEvent(:final entry) => JournalEntryTile(
        entry: entry,
        caseId: caseId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _WeightEvent(:final weight) => WeightEntryTile(
        weight: weight,
        caseId: caseId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _ConditionEvent(:final condition) => ConditionEntryTile(
        entry: condition,
        caseId: caseId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _PrescriptionEvent(:final plan) => PrescriptionTile(
        plan: plan,
        caseId: caseId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _AdministrationEvent(:final dose) => AdministrationTile(
        administration: dose,
        caseId: caseId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _MarkingEvent(:final marking) => MarkingTile(
        marking: marking,
        caseId: caseId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _PlacementEvent(:final placement) => PlacementTile(
        placement: placement,
        medicalCase: medicalCase,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _DispositionEvent(:final disposition) => DispositionTile(
        disposition: disposition,
        caseId: caseId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _FollowUpEvent(:final followUp) => FollowUpTile(
        followUp: followUp,
        caseId: caseId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _ExamEvent(:final exam, :final findings) => ExamTile(
        exam: exam,
        findings: findings,
        caseId: caseId,
        animalId: medicalCase.animal,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _QuarantineEvent(:final quarantine, :final phase, :final isCurrent) =>
        QuarantineTile(
          entry: quarantine,
          caseId: caseId,
          phase: phase,
          canEdit: canEdit,
          isCurrent: isCurrent,
          isLast: isLast,
        ),
      _MilestoneEvent(:final icon, :final label, :final at) => TimelineItem(
        icon: icon,
        date: formatEventDate(MaterialLocalizations.of(context), at),
        isLast: isLast,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    };
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
      entry.entryAt ?? entry.created ?? DateTime.fromMillisecondsSinceEpoch(0);
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
      plan.startedAt ?? plan.created ?? DateTime.fromMillisecondsSinceEpoch(0);
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

/// A recheck placed on the timeline by its due date (or created time).
class _FollowUpEvent extends _Event {
  const _FollowUpEvent(this.followUp);

  final FollowUp followUp;

  @override
  DateTime get at =>
      followUp.dueAt ??
      followUp.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// A structured exam placed on the timeline by its exam date (or created time),
/// carrying its already-fetched by-system findings.
class _ExamEvent extends _Event {
  const _ExamEvent(this.exam, this.findings);

  final Exam exam;
  final List<ExamFinding> findings;

  @override
  DateTime get at =>
      exam.examinedAt ?? exam.created ?? DateTime.fromMillisecondsSinceEpoch(0);
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

/// One end of a quarantine period on the timeline: the started imposition
/// (placed at `set_at`) or, once lapsed, the ended marker (placed at `until`).
/// [isCurrent] marks the active record (the latest), which offers "end now".
class _QuarantineEvent extends _Event {
  const _QuarantineEvent(
    this.quarantine, {
    required this.phase,
    required this.isCurrent,
  });

  final Quarantine quarantine;
  final QuarantinePhase phase;
  final bool isCurrent;

  @override
  DateTime get at => switch (phase) {
    QuarantinePhase.started =>
      quarantine.setAt ??
          quarantine.created ??
          DateTime.fromMillisecondsSinceEpoch(0),
    QuarantinePhase.ended =>
      quarantine.until ??
          quarantine.created ??
          DateTime.fromMillisecondsSinceEpoch(0),
  };
}
