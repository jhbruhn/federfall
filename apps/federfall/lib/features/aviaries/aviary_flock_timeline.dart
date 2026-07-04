import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/aviaries/aviary_flock_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/journal/journal_entry_tile.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The aviary's flock-care chronology (federfall-d5co.3): aviary-scoped
/// journal entries (cleaning, feed changes, group observations — editable)
/// merged with a HISTORICAL rollup of conditions diagnosed on residents while
/// they lived here (read-only, deep-linking to the source case). A smaller
/// analog of `CaseTimeline`'s pattern — two event kinds instead of a dozen.
///
/// Renders as a lazy scrollable ([ListView.builder]); hosts must not nest it
/// inside another scroll view.
class AviaryFlockTimeline extends ConsumerWidget {
  const AviaryFlockTimeline({
    required this.aviaryId,
    this.canEdit = true,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String aviaryId;

  /// Whether the current user may edit the aviary journal (coordinator or
  /// supervisor). The condition rollup is always read-only regardless.
  final bool canEdit;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final journal = ref.watch(aviaryJournalProvider(aviaryId));
    final rollup = ref.watch(aviaryHealthRollupProvider(aviaryId));
    final isLoading = journal.isLoading || rollup.isLoading;
    final error = journal.error ?? rollup.error;

    final events = <_Event>[
      for (final entry in journal.value ?? const <JournalEntry>[])
        _JournalEvent(entry),
      for (final rolled in rollup.value ?? const <AviaryConditionRollupEntry>[])
        _ConditionEvent(rolled),
    ]..sort((a, b) => b.at.compareTo(a.at));

    final header = <Widget>[
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
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: header.length + events.length,
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        final i = index - header.length;
        return _eventTile(events[i], isLast: i == events.length - 1);
      },
    );
  }

  Widget _eventTile(_Event event, {required bool isLast}) {
    return switch (event) {
      _JournalEvent(:final entry) => JournalEntryTile(
        entry: entry,
        aviaryId: aviaryId,
        canEdit: canEdit,
        isLast: isLast,
      ),
      _ConditionEvent(:final rolled) => _ConditionRollupTile(
        entry: rolled,
        isLast: isLast,
      ),
    };
  }
}

sealed class _Event {
  const _Event();

  DateTime get at;
}

class _JournalEvent extends _Event {
  const _JournalEvent(this.entry);

  final JournalEntry entry;

  @override
  DateTime get at =>
      entry.entryAt ?? entry.created ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class _ConditionEvent extends _Event {
  const _ConditionEvent(this.rolled);

  final AviaryConditionRollupEntry rolled;

  @override
  DateTime get at =>
      rolled.condition.onsetDate ??
      rolled.condition.created ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// A read-only condition rolled up from a resident's case history — no
/// edit/delete menu; tapping through opens the source case (federfall-d5co.3
/// wants the rollup traceable back to its clinical record).
class _ConditionRollupTile extends ConsumerWidget {
  const _ConditionRollupTile({required this.entry, required this.isLast});

  final AviaryConditionRollupEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final condition = entry.condition;
    final byId = ref.watch(conditionsByIdProvider).value ?? const {};
    final code = condition.condition == null ? null : byId[condition.condition];
    final label = code?.label ?? condition.freeText ?? '—';
    final animal = entry.animal;
    final hasName = animal?.name != null && animal!.name!.isNotEmpty;
    final animalLabel = animal == null
        ? null
        : (hasName ? animal.name! : animal.species);

    return TimelineItem(
      icon: Icons.coronavirus_outlined,
      date: formatEventDate(
        materialL10n,
        condition.onsetDate ?? condition.created,
      ),
      isLast: isLast,
      trailing: IconButton(
        icon: const Icon(Icons.chevron_right),
        tooltip: l10n.aviaryConditionOpenCase,
        onPressed: () => context.go(AppRoutes.caseDetail(condition.caseId)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(label, style: theme.textTheme.bodyLarge)),
              // Flags a diagnosis that risks spreading to other flock
              // residents — the reason this rollup exists in the first
              // place (a coordinator scanning Pflege needs this at a
              // glance, not just on the source case).
              if (code?.isContagious ?? false) ...[
                const SizedBox(width: AppSpacing.sm),
                TagChip(
                  label: l10n.conditionContagious,
                  color: theme.colorScheme.tertiaryContainer,
                  onColor: theme.colorScheme.onTertiaryContainer,
                ),
              ],
            ],
          ),
          if (animalLabel != null)
            Text(
              animalLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
