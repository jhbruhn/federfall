import 'package:federfall/features/cases/weights/weight_trend_chart.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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
}
