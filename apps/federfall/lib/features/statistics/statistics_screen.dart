import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/statistics/annual_report_sheet.dart';
import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall/features/statistics/intake_series_chart.dart';
import 'package:federfall/features/statistics/period_selector.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/back_or_home.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart' show LiveRefresh;

/// Reporting statistics (FED-7.2 / federfall-nmwi): intakes over time against
/// the previous year, outcome and mortality rates, and the outcome / species /
/// diagnosis breakdowns behind them — all for one selected period.
///
/// Every figure is computed server-side (`GET /api/federfall/stats`) off the
/// same rows the annual report prints, so the screen and the PDF agree. Reached
/// from the dashboard by coordinators/supervisors; figures are org-wide for
/// them. Re-checks the role so a typed-in URL degrades gracefully — the server
/// rules remain the real boundary.
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  /// Resolved once: the period buttons must not relabel themselves if the
  /// screen happens to be open across midnight on New Year's Eve.
  late final DateTime _now = DateTime.now();

  /// Lists the cases behind a breakdown row. Every figure on this screen is
  /// org-wide and counts closed cases too, so the query has to widen past the
  /// browser's "my active cases" default — otherwise the list would come up
  /// short of the number that was just tapped. It also carries the selected
  /// period: a list that ignored it would not match the figure either.
  void _showCases(CaseQuery query, StatsPeriod period) {
    final year = period.year;
    final month = period.month;
    return showCasesFiltered(
      context,
      ref,
      query.copyWith(
        allScope: true,
        activity: CaseActivity.all,
        admittedRange: year == null
            ? null
            : DateTimeRange(
                start: DateTime(year, month ?? 1),
                // Inclusive to the last instant of the period, not to its
                // midnight — the browser's range test is inclusive on both
                // ends, and a bird admitted on the afternoon of the 31st
                // belongs to the month it was admitted in.
                end: month == null
                    ? DateTime(year, 12, 31, 23, 59, 59, 999)
                    : DateTime(year, month + 1, 0, 23, 59, 59, 999),
              ),
      ),
    );
  }

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

    final period = ref.watch(statisticsPeriodProvider);
    // 'case_conditions' matters because the diagnosis breakdown is part of the
    // same server-side aggregate: a diagnosis recorded anywhere in the org
    // changes a figure on this screen.
    ref.liveRefresh(const ['cases', 'dispositions', 'case_conditions'], () {
      ref.invalidate(statisticsProvider);
    });
    final stats = ref.watch(
      statisticsProvider(year: period.year, month: period.month),
    );

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
      body: AsyncValueView<OrgStatistics>(
        value: stats,
        onRetry: () => ref.invalidate(statisticsProvider),
        loading: const LinearProgressIndicator(),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.refresh(
            statisticsProvider(year: period.year, month: period.month).future,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Keyed on the width actually available, not on the window
              // class: this screen is pushed full-width today, but the same
              // decision has to hold if it ever lands in a pane.
              final twoColumn = constraints.maxWidth >= kStatsTwoColumnMin;
              final chart = _chartCard(l10n, s);
              // The period and the figures it qualifies stay full width; the
              // series does too, because 31 day-bars in half a window is a
              // comb. What splits is the reading BELOW them — four cards that
              // are each a self-contained answer, so a desktop reads two at a
              // time instead of scrolling past one.
              final left = <Widget>[
                const _IntakeMapCard(),
                _species(l10n, s, period),
              ];
              final right = <Widget>[
                _outcomes(l10n, s, period),
                _conditions(l10n, s, period),
              ];

              return ContentBounds(
                maxWidth: twoColumn ? kWideContentMaxWidth : kContentMaxWidth,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    // The period comes first because it qualifies everything
                    // under it — the same control, and the same meaning of
                    // "2026", the export sheet offers.
                    PeriodSelector(
                      selected: period,
                      intakeYears: s.intakeYears,
                      now: _now,
                      onChanged: (picked) => ref
                          .read(statisticsPeriodProvider.notifier)
                          .select(picked),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _kpis(l10n, s, period),
                    const SizedBox(height: AppSpacing.lg),
                    chart,
                    const SizedBox(height: AppSpacing.md),
                    if (twoColumn)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _stack(left)),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: _stack(right)),
                        ],
                      )
                    else
                      _stack([...left.take(1), ...right, ...left.skip(1)]),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    return BackOrHomeScope(child: scaffold);
  }

  /// Cards in one column, spaced like the page.
  Widget _stack(List<Widget> cards) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.md),
        cards[i],
      ],
    ],
  );

  Widget _kpis(AppLocalizations l10n, OrgStatistics s, StatsPeriod period) =>
      KpiGrid([
        KpiCard(
          icon: Icons.folder_copy_outlined,
          label: l10n.statsIntakes,
          value: '${s.intakes}',
          onTap: () => _showCases(const CaseQuery(), period),
        ),
        KpiCard(
          icon: Icons.medical_information_outlined,
          label: l10n.statsInCare,
          value: '${s.inCare}',
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
        // Both rates are shares of the cases that ENDED, not of the intakes
        // beside them, so each carries its own denominator: under the grid the
        // same sentence qualified all five tiles (federfall-v5di). It is also
        // what explains the em dash while nothing has ended yet.
        KpiCard(
          icon: Icons.flight_takeoff_outlined,
          label: l10n.statsReleaseRate,
          value: _rate(l10n, s.releaseRate),
          note: l10n.statsRateBasis(s.closed),
        ),
        KpiCard(
          icon: Icons.trending_down_outlined,
          label: l10n.statsMortalityRate,
          value: _rate(l10n, s.mortalityRate),
          note: l10n.statsRateBasis(s.closed),
        ),
      ]);

  Widget _chartCard(AppLocalizations l10n, OrgStatistics s) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.statsSectionIntakesOverTime,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            IntakeSeriesChart(series: s.series),
          ],
        ),
      ),
    ),
  );

  Widget _outcomes(
    AppLocalizations l10n,
    OrgStatistics s,
    StatsPeriod period,
  ) => BreakdownCard(
    title: l10n.statsSectionOutcomes,
    emptyMessage: l10n.statsEmpty,
    chart: BreakdownPie(
      otherLabel: l10n.statsChartOther,
      entries: [
        for (final o in s.outcomes)
          ChartEntry(dispositionTypeLabel(l10n, o.type), o.count),
      ],
    ),
    rows: [
      for (final o in s.outcomes)
        BreakdownRow(
          dispositionTypeLabel(l10n, o.type),
          o.count,
          // A disposition whose wire value this build doesn't know can be
          // counted but not named in a filter.
          onTap: o.type == null
              ? null
              : () => _showCases(CaseQuery(outcome: o.type), period),
        ),
    ],
  );

  Widget _species(AppLocalizations l10n, OrgStatistics s, StatsPeriod period) =>
      BreakdownCard(
        title: l10n.statsSectionSpecies,
        emptyMessage: l10n.statsEmpty,
        chart: BreakdownPie(
          otherLabel: l10n.statsChartOther,
          entries: [for (final c in s.bySpecies) ChartEntry(c.label, c.count)],
        ),
        rows: [
          for (final c in s.bySpecies)
            BreakdownRow(
              c.label,
              c.count,
              onTap: () => _showCases(CaseQuery(species: c.label), period),
            ),
        ],
      );

  Widget _conditions(
    AppLocalizations l10n,
    OrgStatistics s,
    StatsPeriod period,
  ) => BreakdownCard(
    title: l10n.statsSectionConditions,
    emptyMessage: l10n.statsEmpty,
    // Bars, not a donut: a case can carry several diagnoses, so these counts
    // overlap and share no whole to slice. Each is its own share of the
    // period's intakes (federfall-qogh).
    chart: BreakdownBars(
      total: s.intakes,
      caption: l10n.statsChartShareOfIntakes,
      entries: [for (final c in s.byCondition) ChartEntry(c.label, c.count)],
    ),
    rows: [
      for (final c in s.byCondition)
        BreakdownRow(
          c.label,
          c.count,
          onTap: () => _showCases(CaseQuery(condition: c.label), period),
        ),
    ],
  );

  /// A 0–1 share as a whole-percent figure, or an em dash while the rate is
  /// undefined — nothing has ended yet, which is not the same as 0 %.
  String _rate(AppLocalizations l10n, double? value) => value == null
      ? '–'
      : l10n.statsPercentValue(
          formatNumber(l10n, value * 100, maxFractionDigits: 0),
        );
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
