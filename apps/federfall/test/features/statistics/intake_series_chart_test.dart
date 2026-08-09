import 'package:federfall/features/statistics/intake_series_chart.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BarChartData?> _pump(
  WidgetTester tester,
  IntakeSeries series, {
  double width = 800,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: IntakeSeriesChart(series: series),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final charts = find.byType(BarChart);
  if (charts.evaluate().isEmpty) return null;
  return tester.widget<BarChart>(charts).data;
}

IntakeSeries _twelveMonths() => IntakeSeries(
  kind: SeriesBucket.month,
  points: [for (var m = 1; m <= 12; m++) IntakePoint(m, m)],
);

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

  testWidgets('a month series is one bar per day, named with its month', (
    tester,
  ) async {
    final data = await _pump(
      tester,
      const IntakeSeries(
        kind: SeriesBucket.day,
        points: [IntakePoint(1, 2), IntakePoint(2, 0), IntakePoint(3, 5)],
        previousYear: 2025,
        previousMonth: 3,
        previousPoints: [IntakePoint(1, 1), IntakePoint(3, 4)],
      ),
    );

    expect([for (final g in data!.barGroups) g.barRods.first.toY], [1, 0, 4]);
    expect([for (final g in data.barGroups) g.barRods.last.toY], [2, 0, 5]);
    // The comparison is the same month a year earlier, so the legend has to
    // name the month on both sides — "2026" alone would not say which March.
    expect(find.text('Mar 2026'), findsOneWidget);
    expect(find.text('Mar 2025'), findsOneWidget);
  });

  testWidgets('the axis top is a tick, not a label wedged above the last one', (
    tester,
  ) async {
    // federfall-p0dd: fl_chart labels maxY whatever it is, so a ceiling off the
    // tick interval read 0, 3, 6, 9, 12, 14 with the top two nearly touching.
    final data = await _pump(
      tester,
      const IntakeSeries(
        kind: SeriesBucket.month,
        points: [IntakePoint(1, 11), IntakePoint(2, 4)],
      ),
    );

    final step = data!.gridData.horizontalInterval!;
    expect(step, 3);
    expect(data.maxY, 12);
    expect(data.maxY % step, 0);
    // The tallest bar still clears the top gridline.
    expect(data.maxY, greaterThan(11));
  });

  testWidgets('a tallest that is already a tick keeps a full step of air', (
    tester,
  ) async {
    final data = await _pump(
      tester,
      const IntakeSeries(
        kind: SeriesBucket.month,
        points: [IntakePoint(1, 12)],
      ),
    );

    expect(data!.gridData.horizontalInterval, 3);
    expect(data.maxY, 15);
  });

  testWidgets('every month is named where the abbreviations fit', (
    tester,
  ) async {
    // A label every third column made reading the chart a counting exercise:
    // the reader had to walk from the nearest label to find their month.
    await _pump(tester, _twelveMonths());

    for (final name in const ['Jan', 'Feb', 'Mar', 'Jun', 'Sep', 'Dec']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('a narrow chart names every month with one letter, not fewer '
      'months', (tester) async {
    // Twelve three-letter labels do not fit a phone. The locale's narrow form
    // does, and in calendar order it still reads as months — which beats
    // dropping two months out of every three.
    await _pump(tester, _twelveMonths(), width: 220);

    expect(find.text('Jan'), findsNothing);
    // J appears for January, June and July; D only for December.
    expect(find.text('J'), findsNWidgets(3));
    expect(find.text('D'), findsOneWidget);
  });

  testWidgets('the tooltip keeps the readable month, narrow axis or not', (
    tester,
  ) async {
    // The axis may be down to initials, but a tap has room to say "Mar".
    final data = await _pump(tester, _twelveMonths(), width: 220);

    final item = data!.barTouchData.touchTooltipData.getTooltipItem(
      data.barGroups[2],
      2,
      data.barGroups[2].barRods.single,
      0,
    );
    expect(item!.text, 'Mar: 3');
  });

  testWidgets('a day series still labels every fifth day', (tester) async {
    // 31 columns have no shorter form to fall back to. One tall day keeps the
    // value axis on tens, so its labels cannot be mistaken for day numbers.
    await _pump(
      tester,
      IntakeSeries(
        kind: SeriesBucket.day,
        points: [for (var d = 1; d <= 31; d++) IntakePoint(d, d == 1 ? 40 : 0)],
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('2'), findsNothing);
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
