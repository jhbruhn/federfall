import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Dashboard tab of the navigation shell (FED-7.1). KPI cards plus the
/// active-case status breakdown and quarantines ending soon. Scope follows the
/// access rules via [dashboardSummaryProvider].
///
/// Tap-through to a pre-filtered all-cases browser arrives with FED-7.4; for
/// now the quarantine list links straight to each case.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
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
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _KpiCard(
                    label: l10n.dashboardActiveCases,
                    value: s.activeCount,
                    icon: Icons.medical_information_outlined,
                  ),
                  _KpiCard(
                    label: l10n.dashboardIntakesThisYear,
                    value: s.intakesThisYear,
                    icon: Icons.input_outlined,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _StatusBreakdown(s),
              const SizedBox(height: AppSpacing.md),
              _QuarantineSoon(s.quarantineEndingSoon),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: SizedBox(
        width: 160,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: AppSpacing.sm),
              Text('$value', style: theme.textTheme.headlineMedium),
              Text(label, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown(this.summary);

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Only surface statuses that actually occur: several lifecycle stages have
    // no transition into them yet, so showing them stuck at 0 just confuses.
    // See federfall-blp.1 for the lifecycle decision.
    final present =
        summary.byStatus.entries.where((e) => e.value > 0).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.dashboardByStatus, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (present.isEmpty)
              Text(
                l10n.dashboardByStatusEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final entry in present)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(caseStatusLabel(l10n, entry.key)),
                      Text(
                        '${entry.value}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _QuarantineSoon extends StatelessWidget {
  const _QuarantineSoon(this.cases);

  final List<Case> cases;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dashboardQuarantineSoon,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (cases.isEmpty)
              Text(
                l10n.dashboardQuarantineSoonEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final c in cases)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(c.caseNumber ?? c.id),
                  trailing: Text(_quarantineBadge(l10n, c.quarantineUntil!)),
                  onTap: () => context.go(AppRoutes.caseDetail(c.id)),
                ),
          ],
        ),
      ),
    );
  }
}

/// Human-readable label for how soon a quarantine ends, relative to today.
String _quarantineBadge(AppLocalizations l10n, DateTime until) {
  final today = DateUtils.dateOnly(DateTime.now());
  final days = DateUtils.dateOnly(until).difference(today).inDays;
  if (days < 0) return l10n.dashboardQuarantineOverdue;
  if (days == 0) return l10n.dashboardQuarantineToday;
  return l10n.dashboardQuarantineInDays(days);
}
