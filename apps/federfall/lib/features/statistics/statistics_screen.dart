import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reporting statistics (FED-7.2): outcome breakdown, intakes by species,
/// conditions recorded and average time in care. Reached from the dashboard by
/// coordinators/supervisors; figures are org-wide for them.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final stats = ref.watch(statisticsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: AsyncValueView<Statistics>(
        value: stats,
        onRetry: () => ref.invalidate(statisticsProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        loading: const LinearProgressIndicator(),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(statisticsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _Kpi(label: l10n.statsTotalCases, value: '${s.totalCases}'),
                  _Kpi(label: l10n.statsOpenCases, value: '${s.openCases}'),
                  _Kpi(
                    label: l10n.statsAvgTimeInCare,
                    value: s.avgTimeInCareDays == null
                        ? '–'
                        : l10n.statsDaysValue(
                            s.avgTimeInCareDays!.toStringAsFixed(1),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Breakdown(
                title: l10n.statsSectionOutcomes,
                rows: [
                  for (final o in s.outcomes)
                    (dispositionTypeLabel(l10n, o.type), o.count),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Breakdown(
                title: l10n.statsSectionSpecies,
                rows: [for (final c in s.bySpecies) (c.label, c.count)],
              ),
              const SizedBox(height: AppSpacing.md),
              _Breakdown(
                title: l10n.statsSectionConditions,
                rows: [for (final c in s.byCondition) (c.label, c.count)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});

  final String label;
  final String value;

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
              Text(value, style: theme.textTheme.headlineMedium),
              Text(label, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled card listing label · count rows, sorted by the caller.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.title, required this.rows});

  final String title;
  final List<(String, int)> rows;

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
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (rows.isEmpty)
              Text(
                l10n.statsEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final (label, count) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(label)),
                      Text('$count', style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
