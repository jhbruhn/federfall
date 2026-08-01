import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/features/worklist/worklist_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Dashboard tab of the navigation shell (FED-7.1): the carer's Today preview
/// plus a caseload KPI grid. Each tile taps through to the pre-filtered case
/// browser — or the aviaries list (ctw.6). Scope follows the access rules via
/// [dashboardSummaryProvider].
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Live-sync the caseload KPIs as cases are admitted / dispositioned.
    // A carer's KPIs include cases shared *with* them, so watch 'case_shares'
    // too — a share grants/revokes visibility without changing the case record.
    ref.liveRefresh(
      const ['cases', 'dispositions', 'case_shares'],
      () => ref.invalidate(dashboardSummaryProvider),
    );
    final summary = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle),
        actions: const [AccountMenu()],
      ),
      body: AsyncValueView<DashboardSummary>(
        value: summary,
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
        data: (s) {
          final caseload = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboardCaseloadTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              _KpiGrid(s),
            ],
          );

          // Wide screens place the actionable Today preview and the caseload
          // overview side-by-side (federfall-zbe); narrower ones stack them.
          final body = context.isExpanded
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // showEmptyState so the column is never blank beside the
                    // caseload when nothing is due.
                    const Expanded(
                      child: _WorklistPreview(showEmptyState: true),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: caseload),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // Today always leads — even when nothing is due it shows a
                  // compact "all caught up" card, so the actionable section is
                  // the consistent lead and the caseload reads as reference
                  // below it (federfall-6ds).
                  children: [
                    const _WorklistPreview(showEmptyState: true),
                    caseload,
                  ],
                );

          return RefreshIndicator(
            onRefresh: () => ref.refresh(dashboardSummaryProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [body],
            ),
          );
        },
      ),
    );
  }
}

/// Compact "Today" card at the top of the dashboard: the first few worklist
/// items with a link to the full screen. Renders nothing when nothing is due
/// (so it never adds empty chrome) — unless [showEmptyState], used by the wide
/// two-column layout where a blank column would look broken; there it shows a
/// small "all caught up" card instead.
class _WorklistPreview extends ConsumerWidget {
  const _WorklistPreview({this.showEmptyState = false});

  final bool showEmptyState;

  static const _previewMax = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Live-sync the preview too (else it only updated on the Today tab), plus
    // the 1-minute tick for time-relative items.
    ref
      ..liveRefresh(
        worklistLiveCollections,
        () => ref.invalidate(worklistSourceProvider),
      )
      ..watch(worklistTickerProvider);

    return ref
        .watch(worklistProvider)
        .maybeWhen(
          data: (list) {
            if (list.isEmpty) {
              if (!showEmptyState) return const SizedBox.shrink();
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: ListTile(
                  leading: const IconChip(Icons.check_circle_outline),
                  title: Text(
                    l10n.todayTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(l10n.worklistEmpty),
                ),
              );
            }
            final now = DateTime.now();
            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                children: [
                  ListTile(
                    leading: const IconChip(Icons.today_outlined),
                    title: Text(
                      l10n.todayTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Text(l10n.worklistDueCount(list.length)),
                    trailing: TextButton(
                      onPressed: () => context.push(AppRoutes.today),
                      child: Text(l10n.worklistSeeAll),
                    ),
                  ),
                  for (final item in list.take(_previewMax))
                    WorklistTile(item: item, now: now),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        );
  }
}

/// The caseload KPI grid: a 2-column grid of tappable metric tiles. Each case
/// tile jumps to the Cases tab with its filter applied; the aviary tile
/// switches to the Aviaries tab.
class _KpiGrid extends ConsumerWidget {
  const _KpiGrid(this.summary);

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final year = DateTime.now().year;
    final ready = summary.byStatus[CaseStatus.readyForRelease] ?? 0;

    return KpiGrid([
      KpiCard(
        icon: Icons.medical_information_outlined,
        label: l10n.dashboardActiveCases,
        value: '${summary.activeCount}',
        onTap: () =>
            showCasesFiltered(context, ref, const CaseQuery(allScope: true)),
      ),
      KpiCard(
        icon: Icons.input_outlined,
        label: l10n.dashboardIntakesThisYear,
        value: '${summary.intakesThisYear}',
        onTap: () => showCasesFiltered(
          context,
          ref,
          CaseQuery(
            allScope: true,
            activity: CaseActivity.all,
            admittedRange: DateTimeRange(
              start: DateTime(year),
              end: DateTime(year, 12, 31),
            ),
          ),
        ),
      ),
      KpiCard(
        icon: Icons.task_alt_outlined,
        label: caseStatusLabel(l10n, CaseStatus.readyForRelease),
        value: '$ready',
        onTap: () => showCasesFiltered(
          context,
          ref,
          const CaseQuery(
            allScope: true,
            status: CaseStatus.readyForRelease,
          ),
        ),
      ),
      // The aviary tile switches to the Aviaries tab rather than filtering the
      // case list.
      KpiCard(
        icon: Icons.holiday_village_outlined,
        label: l10n.dashboardInAviary,
        value: '${summary.inAviaryCount}',
        onTap: () => context.go(AppRoutes.aviaries),
      ),
    ]);
  }
}
