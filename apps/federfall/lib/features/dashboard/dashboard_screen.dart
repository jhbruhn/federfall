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
        () => ref.invalidate(worklistProvider),
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
                  leading: const _IconChip(Icons.check_circle_outline),
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
                    leading: const _IconChip(Icons.today_outlined),
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
class _KpiGrid extends StatelessWidget {
  const _KpiGrid(this.summary);

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final year = DateTime.now().year;
    final ready = summary.byStatus[CaseStatus.readyForRelease] ?? 0;

    final tiles = <_Kpi>[
      _Kpi(
        icon: Icons.medical_information_outlined,
        label: l10n.dashboardActiveCases,
        value: summary.activeCount,
        query: const CaseQuery(allScope: true),
      ),
      _Kpi(
        icon: Icons.input_outlined,
        label: l10n.dashboardIntakesThisYear,
        value: summary.intakesThisYear,
        query: CaseQuery(
          allScope: true,
          activity: CaseActivity.all,
          admittedRange: DateTimeRange(
            start: DateTime(year),
            end: DateTime(year, 12, 31),
          ),
        ),
      ),
      _Kpi(
        icon: Icons.task_alt_outlined,
        label: caseStatusLabel(l10n, CaseStatus.readyForRelease),
        value: ready,
        query: const CaseQuery(
          allScope: true,
          status: CaseStatus.readyForRelease,
        ),
      ),
      // The aviary tile switches to the Aviaries tab rather than filtering the
      // case list.
      _Kpi(
        icon: Icons.holiday_village_outlined,
        label: l10n.dashboardInAviary,
        value: summary.inAviaryCount,
        route: AppRoutes.aviaries,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final t in tiles)
              SizedBox(width: width, child: _KpiCard(t)),
          ],
        );
      },
    );
  }
}

/// Data for one KPI tile. Exactly one of [query] (jump to the Cases tab with a
/// filter) or [route] (switch to another tab) is set.
class _Kpi {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    this.query,
    this.route,
  }) : assert(
         (query == null) != (route == null),
         'a KPI needs exactly one of query / route',
       );

  final IconData icon;
  final String label;
  final int value;

  /// Filter to apply on the Cases tab. The tap seeds [pendingCaseQueryProvider]
  /// and switches to the tab — staying inside the shell rather than pushing a
  /// full-screen browser over it.
  final CaseQuery? query;

  /// A top-level tab route to switch to instead (the aviaries tile).
  final String? route;
}

class _KpiCard extends ConsumerWidget {
  const _KpiCard(this.kpi);

  final _Kpi kpi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final query = kpi.query;
          if (query != null) {
            // Seed the Cases tab's filter, then switch to it (go, not push) so
            // the bottom nav stays and we don't open a full-screen browser.
            ref.read(pendingCaseQueryProvider.notifier).queue(query);
            context.go(AppRoutes.cases);
          } else {
            context.go(kpi.route!);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon seated in a soft tonal square: gives the grid a colour
              // rhythm and echoes the empty-state disc language.
              _IconChip(kpi.icon),
              const SizedBox(height: AppSpacing.md),
              // The metric is the hero: large, semibold, tabular figures so
              // stacked tiles align digit-for-digit and don't reflow.
              Text(
                '${kpi.value}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // The label recedes; the chevron moves down beside it so the top
              // row is a single confident icon, not a tug-of-war.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      kpi.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small icon in a soft tonal square — the shared "section icon" language
/// used by the KPI tiles and the Today card (and echoing the empty-state disc).
class _IconChip extends StatelessWidget {
  const _IconChip(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: colors.onPrimaryContainer),
    );
  }
}
