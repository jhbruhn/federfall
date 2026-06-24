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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    final spots = [
      for (final (at, grams) in points)
        FlSpot(at.millisecondsSinceEpoch.toDouble(), grams),
    ];
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final ys = points.map((p) => p.$2);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    // Pad the value axis so the line is not glued to the edges.
    final pad = ((maxY - minY) * 0.15).clamp(5.0, double.infinity);

    String dateLabel(double ms) => materialL10n.formatShortDate(
          DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
        );

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              // Label only the first and last measurement to avoid crowding.
              interval: (maxX - minX).clamp(1, double.infinity),
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  dateLabel(value),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
