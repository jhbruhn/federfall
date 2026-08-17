import 'dart:math' as math;

import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Weight trend over time (FED-4.4 / 5yg.5): a line chart of weight
/// measurements — a single case's window ([WeightTrendChart.forCase]) or an
/// animal's whole life ([WeightTrendChart.forAnimal]). Renders nothing until
/// there are at least two points — a single weight is not yet a trend.
class WeightTrendChart extends ConsumerWidget {
  const WeightTrendChart.forCase(this.caseId, {super.key}) : animalId = null;

  const WeightTrendChart.forAnimal(this.animalId, {super.key}) : caseId = null;

  /// Case whose weights to plot, or null when plotting an animal's life.
  final String? caseId;

  /// Animal whose lifetime weights to plot, or null when plotting a case.
  final String? animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weights = caseId != null
        ? ref.watch(weightsForCaseProvider(caseId!)).value ?? const []
        : ref.watch(weightsForAnimalProvider(animalId!)).value ?? const [];
    final points = [
      for (final w in weights)
        if (w.measuredAt ?? w.created case final at?) (at, w.weightG),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (points.length < 2) return const SizedBox.shrink();

    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.weightTrendTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 180,
                child: _Chart(points: points),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.points});

  /// (measuredAt, grams), ascending by date.
  final List<(DateTime, double)> points;

  /// Roughly how many steps the value axis is cut into. Four over the ~150 px
  /// the plot keeps leaves enough room between labels that two never touch,
  /// even at a large text scale.
  static const int _valueSteps = 4;

  /// Air between an axis and its labels.
  static const double _labelGap = AppSpacing.sm;

  /// Above this many measurements the dots merge into the line and only add
  /// noise; the line itself still carries every point.
  static const int _dotLimit = 15;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );

    final spots = [
      for (final (at, grams) in points)
        FlSpot(at.millisecondsSinceEpoch.toDouble(), grams),
    ];
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final ys = points.map((p) => p.$2);
    final lowest = ys.reduce((a, b) => a < b ? a : b);
    final highest = ys.reduce((a, b) => a > b ? a : b);

    // The value axis is snapped to round grams rather than to the data: fl
    // chart labels minY and maxY whatever they happen to be, so a window
    // padded off the measurements printed "272,5" and "372,6" — the second of
    // them wrapped onto a second line, and the first landing on top of the
    // date below it (federfall-yapf). Padding first and rounding outwards
    // keeps the line clear of the edges AND every label a whole number on a
    // gridline — 1240 g reads as "1250", never as fl_chart's "1.4 K".
    // The floor stops at zero: rounding the padding outwards over a wide span
    // — a squab at 15 g and the same bird at 400 g — put the axis at -200,
    // and there is no such thing as a bird weighing less than nothing.
    final pad = ((highest - lowest) * 0.1).clamp(1.0, double.infinity);
    final step = _niceStep((highest - lowest + 2 * pad) / _valueSteps);
    final axisMin = math.max<double>(
      0,
      ((lowest - pad) / step).floorToDouble() * step,
    );
    final axisMax = ((highest + pad) / step).ceilToDouble() * step;

    // The unit rides the topmost label alone: a "g" beside every number would
    // cost the plot a fifth of its width on a phone, and the axis is read from
    // the top down anyway.
    String valueLabel(double grams) => grams == axisMax
        ? formatWeightG(l10n, grams)
        : formatNumber(l10n, grams, maxFractionDigits: 0);
    String dateLabel(double ms) => formatLocalDate(
      materialL10n,
      DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      style: DateStyle.compact,
    );

    final values = labelBounds(context, labelStyle, [
      for (var v = axisMin; v <= axisMax + step / 2; v += step) valueLabel(v),
    ]);
    final dates = labelBounds(context, labelStyle, [
      dateLabel(minX),
      dateLabel(maxX),
    ]);

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: axisMin,
        maxY: axisMax,
        gridData: chartGrid(context, interval: step),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => colors.inverseSurface,
            // fl_chart paints the tooltip inside its own canvas and clips it
            // there, so one hanging off a point near an edge — the top-right
            // of a bird that is gaining — came out cut in half. These two
            // slide it back inside instead.
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            // The axis names the two ends only, so the tooltip is where a
            // middle measurement says which day it was taken on.
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  '${formatWeightG(l10n, spot.y)} · ${dateLabel(spot.x)}',
                  theme.textTheme.labelMedium?.copyWith(
                        color: colors.onInverseSurface,
                      ) ??
                      TextStyle(color: colors.onInverseSurface),
                ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: step,
              reservedSize: values.width + _labelGap,
              // Not nudged inside, unlike the dates below: a value label has
              // to sit on the gridline it names, and the band it is laid out
              // in is tall enough that the top and bottom ones are not cut.
              getTitlesWidget: (value, meta) => axisLabel(
                meta,
                valueLabel(value),
                style: labelStyle,
                fitInside: false,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: dates.height + _labelGap,
              // Label the first and last measurement and nothing between:
              // an interval this wide still lands fl_chart on a value of its
              // own choosing inside the range, and a date nobody measured on
              // reads as one that somebody did.
              interval: (maxX - minX).clamp(1, double.infinity),
              getTitlesWidget: (value, meta) =>
                  value == meta.min || value == meta.max
                  ? axisLabel(meta, dateLabel(value), style: labelStyle)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: colors.primary,
            dotData: FlDotData(show: points.length <= _dotLimit),
          ),
        ],
      ),
    );
  }

  /// Grams per gridline: the round multiple at or above [rough].
  ///
  /// Never finer than a whole gram — a scale marked in tenths claims a
  /// precision bird weights do not have, and the labels round to whole grams
  /// anyway, so two lines would carry the same number. The 2.5 rung earns its
  /// place at 25 g and 250 g, where the plain 1-2-5 ladder would otherwise
  /// jump straight to 50 and leave a third of the card empty above the line;
  /// it is skipped at 2.5 itself, which is not a whole gram.
  static double _niceStep(double rough) {
    if (rough <= 1) return 1;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor());
    for (final factor in const [1, 2, 2.5, 5]) {
      final step = magnitude * factor;
      if (step != step.roundToDouble()) continue;
      if (rough <= step) return step.toDouble();
    }
    return (magnitude * 10).toDouble();
  }
}
