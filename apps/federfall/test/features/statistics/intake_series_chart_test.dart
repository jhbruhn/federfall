import 'package:federfall/features/statistics/intake_series_chart.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BarChartData?> _pump(WidgetTester tester, IntakeSeries series) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: IntakeSeriesChart(series: series)),
    ),
  );
  await tester.pumpAndSettle();
  final charts = find.byType(BarChart);
  if (charts.evaluate().isEmpty) return null;
  return tester.widget<BarChart>(charts).data;
}

void main() {
  testWidgets('draws every bucket the server sent, zeros included', (
    tester,
  ) async {
    // A month with no admissions is a fact about the year, so it keeps its
    // column instead of collapsing the chart to the busy months.
    final data = await _pump(
      tester,
      const IntakeSeries(
        kind: SeriesBucket.month,
        points: [IntakePoint(1, 3), IntakePoint(2, 0), IntakePoint(3, 1)],
      ),
    );

    expect(data!.barGroups, hasLength(3));
    expect([for (final g in data.barGroups) g.barRods.single.toY], [3, 0, 1]);
  });

  testWidgets('aligns the comparison year by bucket key, not by position', (
    tester,
  ) async {
    // The previous year is a period of its own: a bucket missing from it must
    // read as zero under the matching month, not shift every later bar one
    // column to the left.
    final data = await _pump(
      tester,
      const IntakeSeries(
        kind: SeriesBucket.month,
        points: [IntakePoint(1, 3), IntakePoint(2, 4), IntakePoint(3, 1)],
        previousYear: 2025,
        previousPoints: [IntakePoint(1, 5), IntakePoint(3, 2)],
      ),
    );

    // Two rods per group: the comparison year first, then this period's.
    expect([for (final g in data!.barGroups) g.barRods.first.toY], [5, 0, 2]);
    expect([for (final g in data.barGroups) g.barRods.last.toY], [3, 4, 1]);
  });

  testWidgets('names both years in a legend when there is a comparison', (
    tester,
  ) async {
    await _pump(
      tester,
      const IntakeSeries(
        kind: SeriesBucket.month,
        points: [IntakePoint(1, 3)],
        previousYear: 2025,
        previousPoints: [IntakePoint(1, 5)],
      ),
    );

    // The current period is named off the comparison year, so a colour on the
    // chart is readable as a period without a caption elsewhere.
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
  });

  testWidgets('an all-time series is one run of years, with no legend', (
    tester,
  ) async {
    final data = await _pump(
      tester,
      const IntakeSeries(
        kind: SeriesBucket.year,
        points: [IntakePoint(2024, 4), IntakePoint(2025, 9)],
      ),
    );

    expect([for (final g in data!.barGroups) g.barRods.length], [1, 1]);
    // The years are the axis; with one series there is nothing to caption, so
    // the legend (which would name this period "All time") stays away.
    expect(find.text('All time'), findsNothing);
  });

  testWidgets('an empty series says so instead of drawing an empty axis', (
    tester,
  ) async {
    final data = await _pump(
      tester,
      const IntakeSeries(kind: SeriesBucket.year),
    );

    expect(data, isNull);
    expect(find.text('Not enough data yet'), findsOneWidget);
  });
}
