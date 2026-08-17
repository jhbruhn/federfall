import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Eggs laid per month over the last twelve months (federfall-4agw).
///
/// A BAR chart, not the cumulative line `WeightTrendChart` uses: laying is
/// seasonal, and a running total would flatten exactly the pattern worth
/// seeing. Renders nothing when the window is empty.
///
/// Presumed eggs are included in a lighter shade rather than hidden — you see
/// the real picture, flagged, instead of a chart that quietly drops guesses.
class EggMonthChart extends StatelessWidget {
  const EggMonthChart({required this.eggs, this.now, super.key});

  final List<EggRecord> eggs;

  /// Injected in tests so the twelve-month window is deterministic.
  final DateTime? now;

  /// How many months the chart spans.
  static const int months = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // MaterialLocalizations has no bare short-month format, and slicing one out
    // of formatShortMonthDay would depend on the locale's field order.
    final month = DateFormat.MMM(Localizations.localeOf(context).toString());
    final today = now ?? DateTime.now();
    // Month buckets oldest → newest, ending with the current month.
    final firstMonth = DateTime(today.year, today.month - (months - 1));

    final confirmed = List<int>.filled(months, 0);
    final presumed = List<int>.filled(months, 0);
    for (final egg in eggs) {
      final at = (egg.laidAt ?? egg.created)?.toLocal();
      if (at == null) continue;
      final index =
          (at.year - firstMonth.year) * 12 + (at.month - firstMonth.month);
      if (index < 0 || index >= months) continue;
      if (egg.attribution == EggAttribution.presumed) {
        presumed[index] += egg.count;
      } else {
        confirmed[index] += egg.count;
      }
    }

    final totals = [
      for (var i = 0; i < months; i++) confirmed[i] + presumed[i],
    ];
    if (totals.every((t) => t == 0)) return const SizedBox.shrink();
    final tallest = totals.reduce((a, b) => a > b ? a : b);
    // Four gridlines at most, on whole eggs, with a step of headroom above the
    // tallest month — `IntakeSeriesChart`'s reasoning, and for the same reason:
    // one line per egg is unreadable the moment a hen has a good month.
    final step = (tallest / 4).ceil().clamp(1, 1 << 30);
    final ceiling = (tallest ~/ step + 1) * step;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.eggChartTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              maxY: ceiling.toDouble(),
              gridData: chartGrid(context, interval: step.toDouble()),
              borderData: FlBorderData(show: false),
              barTouchData: const BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
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
                      // Every third month only — twelve labels would collide.
                      if (i % 3 != 0) return const SizedBox.shrink();
                      return axisLabel(
                        meta,
                        month.format(
                          DateTime(firstMonth.year, firstMonth.month + i),
                        ),
                        style: labelStyle,
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < months; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: totals[i].toDouble(),
                        width: 10,
                        // Rounded at the data end, square on the baseline:
                        // fl_chart rounds every corner by default, so a bar
                        // stood on a half-circle that crossed the zero line.
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        color: theme.colorScheme.primary,
                        // The presumed share sits on top in a lighter shade.
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            confirmed[i].toDouble(),
                            theme.colorScheme.primary,
                          ),
                          BarChartRodStackItem(
                            confirmed[i].toDouble(),
                            totals[i].toDouble(),
                            theme.colorScheme.primaryContainer,
                          ),
                        ],
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
}
