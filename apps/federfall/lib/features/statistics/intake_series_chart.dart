import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Intakes over time (federfall-nmwi): one bar per month of the selected year,
/// or one per calendar year over all time, with the previous year beside each
/// bar where there is one to compare against.
///
/// A BAR chart, like `EggMonthChart` and for the same reason: admissions are
/// seasonal, and this is the first question an annual report asks ("is this
/// year busier than last?"). The comparison year sits BESIDE each bar rather
/// than stacked behind it — stacked, the two would read as a sum, which they
/// are not.
///
/// Every bucket the server sent is drawn, zeros included: a February with no
/// admissions is a fact about the year, not a gap in the chart.
class IntakeSeriesChart extends StatelessWidget {
  const IntakeSeriesChart({required this.series, super.key});

  final IntakeSeries series;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final points = series.points;
    if (points.isEmpty) {
      return Text(
        l10n.statsEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      );
    }

    // Aligned by key, not by position: the comparison year is a full period of
    // its own, so a month missing from it must read as zero rather than shift
    // every later bar one column left.
    final previousByKey = {
      for (final p in series.previousPoints) p.key: p.count,
    };
    final hasPrevious = series.previousYear != null && previousByKey.isNotEmpty;

    var tallest = 0;
    for (final p in points) {
      tallest = p.count > tallest ? p.count : tallest;
    }
    for (final count in previousByKey.values) {
      tallest = count > tallest ? count : tallest;
    }
    // Four gridlines at most, on whole birds — a half-intake axis label would
    // be nonsense.
    final step = (tallest / 4).ceil().clamp(1, 1 << 30);

    final label = _bucketLabel(context);
    // Twelve months, or a long run of years, will not fit as labels side by
    // side; every nth keeps them readable and the bars in place.
    final labelEvery = series.kind == SeriesBucket.month
        ? 3
        : (points.length / 6).ceil().clamp(1, 1 << 30);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPrevious) ...[
          _Legend(
            currentLabel: series.points.isEmpty
                ? ''
                : _currentLabel(l10n, series),
            previousLabel: '${series.previousYear}',
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: (tallest + step).toDouble(),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step.toDouble(),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    // Which bucket AND which year — with two rods per group,
                    // the number alone would be ambiguous.
                    final period = !hasPrevious
                        ? ''
                        : rodIndex == 0
                        ? ' ${series.previousYear}'
                        : ' ${_currentLabel(l10n, series)}';
                    return BarTooltipItem(
                      '${label(points[groupIndex].key)}$period'
                      ': ${rod.toY.toInt()}',
                      theme.textTheme.labelMedium ?? const TextStyle(),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: step.toDouble(),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      if (i % labelEvery != 0) return const SizedBox.shrink();
                      return Text(
                        label(points[i].key),
                        style: theme.textTheme.labelSmall,
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      // The comparison year first, so time reads left to right
                      // inside each group as it does across the axis.
                      if (hasPrevious)
                        BarChartRodData(
                          toY: (previousByKey[points[i].key] ?? 0).toDouble(),
                          width: 7,
                          color: colors.primaryContainer,
                        ),
                      BarChartRodData(
                        toY: points[i].count.toDouble(),
                        width: hasPrevious ? 7 : 10,
                        color: colors.primary,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The selected period's own name: the year, or "all time" when the series
  /// is itself a run of years.
  static String _currentLabel(AppLocalizations l10n, IntakeSeries series) =>
      series.previousYear == null
      ? l10n.statsExportAllTime
      : '${series.previousYear! + 1}';

  /// Bucket key → axis label: a short month name, or the year itself.
  String Function(int) _bucketLabel(BuildContext context) {
    if (series.kind != SeriesBucket.month) return (key) => '$key';
    // MaterialLocalizations has no bare short-month format, and slicing one out
    // of formatShortMonthDay would depend on the locale's field order.
    final month = DateFormat.MMM(Localizations.localeOf(context).toString());
    return (key) => month.format(DateTime(2000, key));
  }
}

/// Which colour is this period and which is the one behind it.
class _Legend extends StatelessWidget {
  const _Legend({required this.currentLabel, required this.previousLabel});

  final String currentLabel;
  final String previousLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        _LegendEntry(color: colors.primary, label: currentLabel),
        _LegendEntry(color: colors.primaryContainer, label: previousLabel),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
