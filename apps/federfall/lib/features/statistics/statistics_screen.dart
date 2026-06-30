import 'dart:convert';
import 'dart:typed_data';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/statistics/case_report.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Reporting statistics (FED-7.2): outcome breakdown, intakes by species,
/// conditions recorded and average time in care. Reached from the dashboard by
/// coordinators/supervisors; figures are org-wide for them.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    ref.liveRefresh(
      const ['cases', 'dispositions'],
      () => ref.invalidate(statisticsProvider),
    );
    final stats = ref.watch(statisticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: l10n.statsExportCsv,
            onPressed: () => _exportCsv(context, ref),
          ),
        ],
      ),
      body: AsyncValueView<Statistics>(
        value: stats,
        onRetry: () => ref.invalidate(statisticsProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        loading: const LinearProgressIndicator(),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(statisticsProvider.future),
          child: ContentBounds(
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
      ),
    );
  }

  /// Builds the per-case CSV (org-wide for the viewer's role) and hands it to
  /// the platform share/download sheet.
  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Load inline from the (keep-alive) repositories rather than a dedicated
      // autoDispose provider, which would dispose mid-await on an imperative
      // read. buildCaseReportRows stays the pure, tested core.
      final casesRepo = await ref.read(casesRepositoryProvider.future);
      final dispositionsRepo = await ref.read(
        dispositionsRepositoryProvider.future,
      );
      final animalsRepo = await ref.read(animalsRepositoryProvider.future);
      final animals = await animalsRepo.list();
      final reasonsById = await ref.read(admissionReasonsByIdProvider.future);
      final rows = buildCaseReportRows(
        cases: await casesRepo.list(),
        dispositions: await dispositionsRepo.list(),
        animalsById: {for (final a in animals) a.id: a},
        admissionReasonsById: reasonsById,
      );
      if (rows.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.statsExportEmpty)));
        return;
      }
      String two(int n) => n.toString().padLeft(2, '0');
      String isoDate(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
      final csv = encodeCaseReportCsv(
        rows: rows,
        header: [
          l10n.csvColCaseNumber,
          l10n.csvColSpecies,
          l10n.csvColName,
          l10n.csvColAdmitted,
          l10n.csvColFound,
          l10n.csvColStatus,
          l10n.csvColOutcome,
          l10n.csvColEnded,
          l10n.csvColDaysInCare,
          l10n.csvColCity,
          l10n.csvColRegion,
          l10n.csvColReasons,
        ],
        status: (s) => caseStatusLabel(l10n, s),
        outcome: (o) => dispositionTypeLabel(l10n, o),
        date: isoDate,
      );
      final filename = 'federfall-cases-${DateTime.now().year}.csv';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(csv)),
              mimeType: 'text/csv',
              name: filename,
            ),
          ],
          fileNameOverrides: [filename],
        ),
      );
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
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
