import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Intakes over time (federfall-nmwi): one bar per day of the selected month,
/// per month of the selected year, or per calendar year over all time — with
/// the same period a year earlier beside each bar where there is one to
/// compare against.
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
    // The ceiling is the next multiple of that step, not `tallest + step`:
    // fl_chart labels maxY whatever it is, so a top off the interval printed
    // 0, 3, 6, 9, 12, 14 with the last two labels nearly touching
    // (federfall-p0dd). Rounding up keeps a clear step of headroom above the
    // tallest bar — a tallest that already IS a multiple gets a whole one.
    final ceiling = (tallest ~/ step + 1) * step;

    final label = _bucketLabel(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final monthFormat = DateFormat.MMM(
      Localizations.localeOf(context).toString(),
    );
    String monthName(int m) => monthFormat.format(DateTime(2000, m));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPrevious) ...[
          _Legend(
            currentLabel: _currentLabel(l10n, series, monthName),
            previousLabel: _previousLabel(series, monthName),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            // What one bucket actually gets on this screen: the plot is what
            // is left once the value axis has taken its own width.
            final (bucketLabel, labelEvery) = _axisLabels(
              context,
              (constraints.maxWidth - _valueAxisWidth) / points.length,
              label,
            );
            return SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: ceiling.toDouble(),
                  gridData: chartGrid(context, interval: step.toDouble()),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      // Inverse surface rather than fl_chart's blue-grey: the
                      // default draws body ink on a dark box, and a tooltip on
                      // an edge bar was clipped by the chart's own canvas.
                      getTooltipColor: (_) => colors.inverseSurface,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        // Which bucket AND which year — with two rods per
                        // group, the number alone would be ambiguous.
                        final period = !hasPrevious
                            ? ''
                            : rodIndex == 0
                            ? ' ${_previousLabel(series, monthName)}'
                            : ' ${_currentLabel(l10n, series, monthName)}';
                        return BarTooltipItem(
                          '${label(points[groupIndex].key)}$period'
                          ': ${rod.toY.toInt()}',
                          theme.textTheme.labelMedium?.copyWith(
                                color: colors.onInverseSurface,
                              ) ??
                              TextStyle(color: colors.onInverseSurface),
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
                        reservedSize: _valueAxisWidth,
                        interval: step.toDouble(),
                        getTitlesWidget: (value, meta) => axisLabel(
                          meta,
                          meta.formattedValue,
                          style: labelStyle,
                          fitInside: false,
                        ),
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
                          if (i % labelEvery != 0) {
                            return const SizedBox.shrink();
                          }
                          return axisLabel(
                            meta,
                            bucketLabel(points[i].key),
                            style: labelStyle,
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
                          // The comparison year first, so time reads left to
                          // right inside each group as it does across the
                          // axis.
                          if (hasPrevious)
                            BarChartRodData(
                              toY: (previousByKey[points[i].key] ?? 0)
                                  .toDouble(),
                              width: 7,
                              borderRadius: _rodEnd,
                              color: colors.primaryContainer,
                            ),
                          BarChartRodData(
                            toY: points[i].count.toDouble(),
                            width: hasPrevious ? 7 : 10,
                            borderRadius: _rodEnd,
                            color: colors.primary,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// The selected period's own name for the legend: the year, or the month
  /// and year when a month is selected — the comparison is the SAME month a
  /// year earlier, so the month alone would name both series.
  static String _currentLabel(
    AppLocalizations l10n,
    IntakeSeries series,
    String Function(int) monthName,
  ) {
    final previous = series.previousYear;
    if (previous == null) return l10n.statsExportAllTime;
    final month = series.previousMonth;
    return month == null
        ? '${previous + 1}'
        : '${monthName(month)} ${previous + 1}';
  }

  /// The comparison period's name, on the same pattern.
  static String _previousLabel(
    IntakeSeries series,
    String Function(int) monthName,
  ) {
    final month = series.previousMonth;
    return month == null
        ? '${series.previousYear}'
        : '${monthName(month)} ${series.previousYear}';
  }

  /// Rounded at the data end, square on the baseline. fl_chart rounds every
  /// corner by default, so each bar stood on a half-circle that crossed the
  /// zero line — a one-intake month read as a lozenge hanging off the axis
  /// rather than as a bar standing on it.
  static const BorderRadius _rodEnd = BorderRadius.vertical(
    top: Radius.circular(3),
  );

  /// What the left axis reserves, and therefore what the plot does not get.
  static const double _valueAxisWidth = 32;

  /// Air either side of a bottom label, so two never end up touching.
  static const double _labelGap = 4;

  /// How the bottom axis is labelled in the width it actually has: the label
  /// for a bucket key, and how many buckets there are between labels.
  ///
  /// EVERY month is named. Reading this chart means mapping a bar to a month,
  /// and a label every third column made that a counting exercise. Where three
  /// letters do not fit a column — a phone showing twelve months — the
  /// locale's single-letter form does, and in calendar order it is still read
  /// as months. Days and years have no shorter form to fall back to and keep
  /// labelling every nth: 31 days cannot all be named side by side.
  (String Function(int), int) _axisLabels(
    BuildContext context,
    double column,
    String Function(int) label,
  ) {
    switch (series.kind) {
      // A month has 28–31 columns; a label every fifth day reads as a calendar
      // without crowding.
      case SeriesBucket.day:
        return (label, 5);
      case SeriesBucket.year:
        return (label, (series.points.length / 6).ceil().clamp(1, 1 << 30));
      case SeriesBucket.month:
        final style = Theme.of(context).textTheme.labelSmall;
        int strideFor(String Function(int) form) {
          if (column <= 0) return 1;
          final widest = labelBounds(context, style, [
            for (final p in series.points) form(p.key),
          ]).width;
          return ((widest + _labelGap) / column).ceil().clamp(
            1,
            series.points.length,
          );
        }

        if (strideFor(label) == 1) return (label, 1);
        final narrow = DateFormat(
          // Five Ms is the narrow month: "J" for January, and the locale's own
          // letter rather than a substring of the abbreviation.
          'MMMMM',
          Localizations.localeOf(context).toString(),
        );
        String narrowLabel(int key) => narrow.format(DateTime(2000, key));
        return (narrowLabel, strideFor(narrowLabel));
    }
  }

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
