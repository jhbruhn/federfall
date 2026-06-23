import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/journal/journal_entry_tile.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
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
    final isLoading = journal.isLoading || weights.isLoading;
    final error = journal.error ?? weights.error;

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
    ]..sort((a, b) => b.at.compareTo(a.at));

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
                  onTap: () => showWeightEntrySheet(context, caseId: caseId),
                  child: Text(l10n.timelineAddWeight),
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
