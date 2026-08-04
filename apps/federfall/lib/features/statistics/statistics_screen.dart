import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/statistics/annual_report_sheet.dart';
import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/back_or_home.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

    final scaffold = Scaffold(
      appBar: AppBar(
        // Pushed over the app, so a cold open has nothing to pop back to.
        leading: const BackOrHomeButton(),
        title: Text(l10n.statsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: l10n.statsExportAction,
            // The busy state lives in the sheet, on the format button that was
            // actually tapped (federfall-dk0c) — the report is compiled
            // server-side and can take a moment, and a spinner on the button
            // you pressed says more than one on the app bar.
            onPressed: () => showAnnualReportSheet(context),
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
                BreakdownCard(
                  title: l10n.statsSectionOutcomes,
                  emptyMessage: l10n.statsEmpty,
                  rows: [
                    for (final o in s.outcomes)
                      BreakdownRow(
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
                BreakdownCard(
                  title: l10n.statsSectionSpecies,
                  emptyMessage: l10n.statsEmpty,
                  rows: [
                    for (final c in s.bySpecies)
                      BreakdownRow(
                        c.label,
                        c.count,
                        onTap: () => _showCases(CaseQuery(species: c.label)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                BreakdownCard(
                  title: l10n.statsSectionConditions,
                  emptyMessage: l10n.statsEmpty,
                  rows: [
                    for (final c in s.byCondition)
                      BreakdownRow(
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

    return BackOrHomeScope(child: scaffold);
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
        // `go`, not `push`: the map is a child of /statistics, so this keeps the
        // address bar honest AND leaves the statistics page beneath it to pop
        // back to — no fallback needed here.
        onTap: () => context.go(AppRoutes.intakeMap),
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
