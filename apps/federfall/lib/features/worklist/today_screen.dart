import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
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
/// cases — each row deep-linking to its case.
///
/// On wide screens it shows the worklist beside the selected case's detail
/// (federfall-zbe), holding the selection itself rather than via go_router — so
/// this stays a single pushed route. On narrow screens a row deep-links to the
/// case full-screen, the original mobile-first quick glance.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  /// Display order of the groups (most time-critical first).
  static const List<WorklistKind> _order = [
    WorklistKind.medicationDue,
    WorklistKind.followUpDue,
    WorklistKind.quarantineEnding,
    WorklistKind.staleCase,
  ];

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  String? _selectedCaseId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Live-sync: re-fetch the worklist when its source collections change,
    // plus a 1-minute tick so time-relative items surface as they fall due.
    ref
      ..liveRefresh(
        worklistLiveCollections,
        () => ref.invalidate(worklistProvider),
      )
      ..watch(worklistTickerProvider);
    final items = ref.watch(worklistProvider);
    final now = DateTime.now();
    final expanded = context.isExpanded;

    final list = Scaffold(
      appBar: AppBar(title: Text(l10n.todayTitle)),
      body: AsyncValueView<List<WorklistItem>>(
        value: items,
        onRetry: () => ref.invalidate(worklistProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (data) {
          if (data.isEmpty) {
            return EmptyView(
              icon: Icons.check_circle_outline,
              message: l10n.worklistEmpty,
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(worklistProvider.future),
            child: ListView(
              children: [
                for (final kind in TodayScreen._order)
                  ..._group(context, kind, data, now, expanded: expanded),
              ],
            ),
          );
        },
      ),
    );

    if (!expanded) return list;

    // Wide: worklist on the left, the selected case (its own Scaffold) or the
    // empty-selection placeholder on the right — like the other two-pane
    // surfaces.
    final selectedId = _selectedCaseId;
    return Row(
      children: [
        SizedBox(width: kListPaneWidth, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: selectedId == null
              ? DetailPanePlaceholder(
                  icon: Icons.medical_information_outlined,
                  message: l10n.listDetailSelectCase,
                )
              : CaseDetailScreen(
                  // Rebuild the detail when the selection changes.
                  key: ValueKey(selectedId),
                  caseId: selectedId,
                ),
        ),
      ],
    );
  }

  /// A section header + tiles for one [kind], or nothing if it has no items.
  List<Widget> _group(
    BuildContext context,
    WorklistKind kind,
    List<WorklistItem> all,
    DateTime now, {
    required bool expanded,
  }) {
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
      for (final item in group)
        WorklistTile(
          item: item,
          now: now,
          // Wide: select into the side pane; narrow: the tile's default
          // deep-link to the case full-screen.
          onTap: expanded
              ? () => setState(() => _selectedCaseId = item.caseId)
              : null,
          selected: expanded && item.caseId == _selectedCaseId,
        ),
    ];
  }
}
