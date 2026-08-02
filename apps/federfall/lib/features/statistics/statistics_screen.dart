import 'dart:convert';
import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
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

  /// Lists the cases behind a breakdown row. Every figure on this screen is
  /// org-wide and counts closed cases too, so the query has to widen past the
  /// browser's "my active cases" default — otherwise the list would come up
  /// short of the number that was just tapped.
  void _showCases(CaseQuery query) => showCasesFiltered(
    context,
    ref,
    query.copyWith(allScope: true, activity: CaseActivity.all),
  );

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

    // 'case_conditions' matters because the diagnosis breakdown is counted by
    // the `condition_labels` view, which statistics reads through its own
    // provider — invalidating only `statisticsProvider` would re-run the
    // aggregation over the same cached counts.
    ref.liveRefresh(const ['cases', 'dispositions', 'case_conditions'], () {
      ref
        ..invalidate(recordedConditionsProvider)
        ..invalidate(statisticsProvider);
    });
    final stats = ref.watch(statisticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statsTitle),
        actions: [
          IconButton(
            // The same inline busy affordance the other two fetch-then-share
            // actions use (_ShareReportButton / _PrintReportButton in
            // case_detail_screen.dart) — a greyed-out icon alone leaves the
            // user watching a dead button on a slow link.
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: l10n.statsExportCsv,
            // Disabled while an export runs — a second tap would launch
            // another load and a second share sheet.
            onPressed: _exporting ? null : _exportCsv,
          ),
        ],
      ),
      body: AsyncValueView<Statistics>(
        value: stats,
        onRetry: () => ref
          ..invalidate(recordedConditionsProvider)
          ..invalidate(statisticsProvider),
        loading: const LinearProgressIndicator(),
        data: (s) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(recordedConditionsProvider);
            return ref.refresh(statisticsProvider.future);
          },
          child: ContentBounds(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                KpiGrid([
                  KpiCard(
                    icon: Icons.folder_copy_outlined,
                    label: l10n.statsTotalCases,
                    value: '${s.totalCases}',
                  ),
                  KpiCard(
                    icon: Icons.medical_information_outlined,
                    label: l10n.statsOpenCases,
                    value: '${s.openCases}',
                  ),
                  KpiCard(
                    icon: Icons.timelapse_outlined,
                    label: l10n.statsAvgTimeInCare,
                    value: s.avgTimeInCareDays == null
                        ? '–'
                        : l10n.statsDaysValue(
                            formatNumber(
                              l10n,
                              s.avgTimeInCareDays!,
                              maxFractionDigits: 1,
                            ),
                          ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.lg),
                const _IntakeMapCard(),
                const SizedBox(height: AppSpacing.md),
                _Breakdown(
                  title: l10n.statsSectionOutcomes,
                  rows: [
                    for (final o in s.outcomes)
                      _BreakdownRow(
                        dispositionTypeLabel(l10n, o.type),
                        o.count,
                        // A disposition whose wire value this build doesn't
                        // know can be counted but not named in a filter.
                        onTap: o.type == null
                            ? null
                            : () => _showCases(CaseQuery(outcome: o.type)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Breakdown(
                  title: l10n.statsSectionSpecies,
                  rows: [
                    for (final c in s.bySpecies)
                      _BreakdownRow(
                        c.label,
                        c.count,
                        onTap: () => _showCases(CaseQuery(species: c.label)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Breakdown(
                  title: l10n.statsSectionConditions,
                  rows: [
                    for (final c in s.byCondition)
                      _BreakdownRow(
                        c.label,
                        c.count,
                        onTap: () => _showCases(CaseQuery(condition: c.label)),
                      ),
                  ],
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
      // One pre-joined read off the `case_report_rows` view (federfall-80tc)
      // instead of pulling `cases`, `dispositions` and `animals` whole to the
      // device to join them here. Loaded inline from the (keep-alive)
      // repository rather than a dedicated autoDispose provider, which would
      // dispose mid-await on an imperative read.
      final repo = await ref.read(caseReportRowsRepositoryProvider.future);
      final rows = await repo.all();
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

/// One row of a [_Breakdown]: a label, its count, and — when the cases behind
/// that number can be listed — the tap that goes and lists them.
@immutable
class _BreakdownRow {
  const _BreakdownRow(this.label, this.count, {this.onTap});

  final String label;
  final int count;

  /// Null for a bucket no filter can express, which is only the "unknown
  /// outcome" one. The chevron follows this, so a row never promises a
  /// destination it does not have (as [KpiCard] does).
  final VoidCallback? onTap;
}

/// A titled card listing label · count rows, sorted by the caller. Each row
/// taps through to the cases it counts, the way the dashboard KPIs do — a
/// number the user can't ask "which ones?" about is a dead end
/// (federfall-5puj).
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.title, required this.rows});

  final String title;
  final List<_BreakdownRow> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      // The rows ripple edge to edge, so the card has to clip them.
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Text(
                l10n.statsEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            for (final row in rows) _BreakdownTile(row),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _BreakdownTile extends StatelessWidget {
  const _BreakdownTile(this.row);

  final _BreakdownRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: row.onTap,
      child: ConstrainedBox(
        // A real touch target, not just a line of text.
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Expanded(child: Text(row.label)),
              Text('${row.count}', style: theme.textTheme.titleMedium),
              const SizedBox(width: AppSpacing.xs),
              // Reserved even without a chevron, so the counts of a card whose
              // rows aren't uniformly tappable still line up in one column.
              SizedBox(
                width: 18,
                child: row.onTap == null
                    ? null
                    : Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
              ),
            ],
          ),
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

/// A small, non-interactive map thumbnail plotting every given point, fitted
/// to their bounds. Carries [MapAttribution] like every other map in the app
/// (`_FindMap`, the intake map, the location picker): the tile provider's
/// usage policy requires visible attribution on each rendered map, and a
/// thumbnail linking through to an attributed screen does not satisfy that —
/// so its size is not ours to trade the notice against.
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
        const MapAttribution(),
      ],
    );
  }
}
