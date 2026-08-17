import 'package:federfall/features/cases/weights/weight_trend_chart.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<Weight> caseWeights = const [],
    List<Weight> animalWeights = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weightsForCaseProvider(
            'c1',
          ).overrideWith((ref) async => caseWeights),
          weightsForAnimalProvider(
            'a1',
          ).overrideWith((ref) async => animalWeights),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The chart's data, once it has one.
  LineChartData chartData(WidgetTester tester) =>
      tester.widget<LineChart>(find.byType(LineChart)).data;

  Weight weight(String id, DateTime at, double grams) =>
      Weight(id: id, animal: 'a1', weightG: grams, measuredAt: at);

  testWidgets('renders nothing with fewer than two points', (tester) async {
    await pump(
      tester,
      const WeightTrendChart.forCase('c1'),
      caseWeights: const [
        Weight(id: 'w1', animal: 'a1', weightG: 300),
      ],
    );

    expect(find.text('Weight trend'), findsNothing);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('plots the trend for a case with two or more weights', (
    tester,
  ) async {
    await pump(
      tester,
      const WeightTrendChart.forCase('c1'),
      caseWeights: [
        Weight(
          id: 'w1',
          animal: 'a1',
          weightG: 300,
          measuredAt: DateTime(2026),
        ),
        Weight(
          id: 'w2',
          animal: 'a1',
          weightG: 320,
          measuredAt: DateTime(2026, 1, 10),
        ),
      ],
    );

    expect(find.text('Weight trend'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('plots the trend for an animal across its whole life', (
    tester,
  ) async {
    await pump(
      tester,
      const WeightTrendChart.forAnimal('a1'),
      animalWeights: [
        Weight(
          id: 'w1',
          animal: 'a1',
          weightG: 300,
          measuredAt: DateTime(2025, 6),
        ),
        Weight(
          id: 'w2',
          animal: 'a1',
          weightG: 340,
          measuredAt: DateTime(2026),
        ),
      ],
    );

    expect(find.byType(LineChart), findsOneWidget);
  });

  // The axis used to be the padded data range itself, which fl_chart labels
  // whatever it is: "272.5" and "372.6", the second one wrapped onto a second
  // line and the first sitting on top of the date below it (federfall-yapf).
  group('the value axis (federfall-yapf)', () {
    testWidgets('is bounded on whole grams, one gridline per label', (
      tester,
    ) async {
      await pump(
        tester,
        const WeightTrendChart.forCase('c1'),
        caseWeights: [
          weight('w1', DateTime(2026, 3, 2), 284),
          weight('w2', DateTime(2026, 3, 9), 297),
          weight('w3', DateTime(2026, 3, 28), 361),
        ],
      );

      final data = chartData(tester);
      final step = data.titlesData.leftTitles.sideTitles.interval!;
      expect(step, step.roundToDouble(), reason: 'a whole number of grams');
      // Every label — the two bounds included — lands on a multiple of the
      // step, so no label can be a fraction and none is off its gridline.
      expect(data.minY % step, 0);
      expect(data.maxY % step, 0);
      expect(data.gridData.horizontalInterval, step);
      // ...and the window still holds every measurement, off the edges.
      expect(data.minY, lessThan(284));
      expect(data.maxY, greaterThan(361));
    });

    testWidgets('keeps a flat series readable', (tester) async {
      // Two identical weights are a zero-height range: rounding it outwards
      // must still leave an axis with a positive height to draw on.
      await pump(
        tester,
        const WeightTrendChart.forCase('c1'),
        caseWeights: [
          weight('w1', DateTime(2026, 3, 2), 300),
          weight('w2', DateTime(2026, 3, 9), 300),
        ],
      );

      final data = chartData(tester);
      expect(data.maxY, greaterThan(data.minY));
      expect(data.minY, lessThan(300));
      expect(data.maxY, greaterThan(300));
    });

    testWidgets('spells a heavy bird out in grams, never "1.4K"', (
      tester,
    ) async {
      await pump(
        tester,
        const WeightTrendChart.forAnimal('a1'),
        animalWeights: [
          weight('w1', DateTime(2024, 5, 3), 180),
          weight('w2', DateTime(2026, 3, 28), 1240),
        ],
      );

      // fl_chart's own number format abbreviates anything over a thousand,
      // which for a weight in grams reads as a different unit.
      expect(find.textContaining('K'), findsNothing);
      expect(find.textContaining('1500'), findsOneWidget);
    });
  });

  testWidgets('labels the first and last measurement and nothing between', (
    tester,
  ) async {
    final materialL10n = await GlobalMaterialLocalizations.delegate.load(
      const Locale('en'),
    );
    final first = DateTime(2026, 3, 2);
    final middle = DateTime(2026, 3, 9);
    final last = DateTime(2026, 3, 28);

    await pump(
      tester,
      const WeightTrendChart.forCase('c1'),
      caseWeights: [
        weight('w1', first, 284),
        weight('w2', middle, 297),
        weight('w3', last, 361),
      ],
    );

    expect(find.text(materialL10n.formatCompactDate(first)), findsOneWidget);
    expect(find.text(materialL10n.formatCompactDate(last)), findsOneWidget);
    // An interval as wide as the range still lands fl_chart on a value of its
    // own choosing inside it, and a date nobody measured on reads as one
    // somebody did.
    expect(find.text(materialL10n.formatCompactDate(middle)), findsNothing);
    // Two dates on the axis, whichever they are: an interval as wide as the
    // range does not by itself stop fl_chart adding one of its own.
    final dates = RegExp(r'^\d+/\d+/\d{4}$');
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && dates.hasMatch(w.data ?? ''),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('keeps a tooltip inside the chart', (tester) async {
    // fl_chart paints the tooltip on its own canvas and clips it there, so one
    // hanging off a point near an edge came out cut in half (federfall-yapf).
    await pump(
      tester,
      const WeightTrendChart.forCase('c1'),
      caseWeights: [
        weight('w1', DateTime(2026, 3, 2), 284),
        weight('w2', DateTime(2026, 3, 28), 361),
      ],
    );

    final tooltip = chartData(tester).lineTouchData.touchTooltipData;
    expect(tooltip.fitInsideHorizontally, isTrue);
    expect(tooltip.fitInsideVertically, isTrue);
  });
}
