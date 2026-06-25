import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/cases/cases_labels.dart';
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
    ref.liveRefresh(
      const ['cases', 'dispositions'],
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
        errorMessage: (e) => errorMessage(l10n, e),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardSummaryProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const _WorklistPreview(),
              Text(
                l10n.dashboardCaseloadTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              _KpiGrid(s),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "Today" card at the top of the dashboard: the first few worklist
/// items with a link to the full screen. Renders nothing when nothing is due,
/// so it never adds empty chrome.
class _WorklistPreview extends ConsumerWidget {
  const _WorklistPreview();

  static const _previewMax = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Live-sync the preview too (else it only updated on the Today tab).
    ref.liveRefresh(
      worklistLiveCollections,
      () => ref.invalidate(worklistProvider),
    );

    return ref
        .watch(worklistProvider)
        .maybeWhen(
          data: (list) {
            if (list.isEmpty) return const SizedBox.shrink();
            final now = DateTime.now();
            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      l10n.todayTitle,
                      style: theme.textTheme.titleMedium,
                    ),
                    trailing: TextButton(
                      onPressed: () => context.push(AppRoutes.today),
                      child: Text(l10n.worklistSeeAll),
                    ),
                  ),
                  for (final item in list.take(_previewMax))
                    WorklistTile(item: item, now: now),
                ],
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        );
  }
}

/// The caseload KPI grid: a 2-column grid of tappable metric tiles. Each tile
/// deep-links to the matching pre-filtered case browser, or the aviaries list.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid(this.summary);

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final year = DateTime.now().year;
    final ready = summary.byStatus[CaseStatus.readyForRelease] ?? 0;
    final readyWire = CaseStatus.readyForRelease.wire;

    final tiles = <_Kpi>[
      _Kpi(
        icon: Icons.medical_information_outlined,
        label: l10n.dashboardActiveCases,
        value: summary.activeCount,
        route: AppRoutes.casesBrowse('scope=all&activity=active'),
      ),
      _Kpi(
        icon: Icons.input_outlined,
        label: l10n.dashboardIntakesThisYear,
        value: summary.intakesThisYear,
        route: AppRoutes.casesBrowse('scope=all&activity=all&year=$year'),
      ),
      _Kpi(
        icon: Icons.task_alt_outlined,
        label: caseStatusLabel(l10n, CaseStatus.readyForRelease),
        value: ready,
        route: AppRoutes.casesBrowse('scope=all&status=$readyWire'),
      ),
      // The aviary tile switches to the Aviaries tab rather than a filtered
      // case list, so it navigates (go) instead of pushing a transient view.
      _Kpi(
        icon: Icons.holiday_village_outlined,
        label: l10n.dashboardInAviary,
        value: summary.inAviaryCount,
        route: AppRoutes.aviaries,
        push: false,
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

/// Data for one KPI tile.
class _Kpi {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.route,
    this.push = true,
  });

  final IconData icon;
  final String label;
  final int value;
  final String route;

  /// Push a transient screen over the shell (filtered case browser) vs. switch
  /// to a top-level tab (the aviaries list).
  final bool push;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.kpi);

  final _Kpi kpi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            kpi.push ? context.push(kpi.route) : context.go(kpi.route),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(kpi.icon, color: theme.colorScheme.primary),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('${kpi.value}', style: theme.textTheme.headlineMedium),
              Text(kpi.label, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
