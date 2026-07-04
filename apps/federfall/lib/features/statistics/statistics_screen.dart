import 'dart:convert';
import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/statistics/case_report.dart';
import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

/// Reporting statistics (FED-7.2): outcome breakdown, intakes by species,
/// conditions recorded and average time in care. Reached from the dashboard by
/// coordinators/supervisors; figures are org-wide for them. Re-checks the role
/// so a typed-in URL degrades gracefully — the server rules remain the real
/// boundary.
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canViewReports(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.statsTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

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
            // Disabled while an export runs — a second tap would launch
            // another multi-collection load and a second share sheet.
            onPressed: _exporting ? null : _exportCsv,
          ),
        ],
      ),
      body: AsyncValueView<Statistics>(
        value: stats,
        onRetry: () => ref.invalidate(statisticsProvider),
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
                const _IntakeMapCard(),
                const SizedBox(height: AppSpacing.md),
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
  Future<void> _exportCsv() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
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
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
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

/// Entry point into the intake map screen (federfall-xr8t): a title + pin
/// count over a small non-interactive preview map, the whole card tappable.
/// All intakes with a find-location (no period filter — the full screen
/// offers that), so the preview reads as a stable "where things are" snapshot
/// rather than shifting with the screen's own segmented filter.
class _IntakeMapCard extends ConsumerWidget {
  const _IntakeMapCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locations = ref.watch(intakeLocationsProvider()).value;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.intakeMap),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.intakeMapTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          l10n.intakeMapCardCount(locations?.length ?? 0),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 140,
                  child: locations == null || locations.isEmpty
                      ? ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                        )
                      : _MapPreview(locations: locations),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small, non-interactive, un-attributed map thumbnail plotting every given
/// point, fitted to their bounds. Attribution is dropped here — it belongs on
/// the interactive intake map screen this card links to, not on a thumbnail
/// too small to make it legible without cluttering the card.
class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.locations});

  final List<IntakeLocation> locations;

  @override
  Widget build(BuildContext context) {
    final points = [for (final l in locations) l.point];
    final bounds = points.length == 1
        ? LatLngBounds(points.single, points.single)
        : LatLngBounds.fromPoints(points);

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(AppSpacing.md),
          maxZoom: 14,
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        const MapTileLayer(),
        MarkerLayer(
          markers: [
            for (final point in points)
              Marker(
                point: point,
                width: 12,
                height: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.error,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
