import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_labels.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/features/worklist/worklist_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The "Today" screen (UX Phase D, cr3.2): the signed-in carer's derived
/// worklist grouped by kind — medications due, quarantines ending, inactive
/// cases — each row deep-linking to its case. Mobile-first quick glance.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  /// Display order of the groups (most time-critical first).
  static const List<WorklistKind> _order = [
    WorklistKind.medicationDue,
    WorklistKind.quarantineEnding,
    WorklistKind.staleCase,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final items = ref.watch(worklistProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.todayTitle)),
      body: AsyncValueView<List<WorklistItem>>(
        value: items,
        onRetry: () => ref.invalidate(worklistProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (list) {
          if (list.isEmpty) {
            return EmptyView(
              icon: Icons.check_circle_outline,
              message: l10n.worklistEmpty,
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(worklistProvider.future),
            child: ListView(
              children: [
                for (final kind in _order)
                  ..._group(context, kind, list, now),
              ],
            ),
          );
        },
      ),
    );
  }

  /// A section header + tiles for one [kind], or nothing if it has no items.
  List<Widget> _group(
    BuildContext context,
    WorklistKind kind,
    List<WorklistItem> all,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final group = all.where((i) => i.kind == kind).toList();
    if (group.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Text(
          worklistGroupLabel(context.l10n, kind),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
      for (final item in group) WorklistTile(item: item, now: now),
    ];
  }
}
