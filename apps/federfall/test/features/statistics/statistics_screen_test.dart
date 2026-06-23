import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/features/statistics/statistics_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Statistics stats) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [statisticsProvider.overrideWith((ref) async => stats)],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatisticsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders KPIs and outcome/species/condition breakdowns',
      (tester) async {
    await _pump(
      tester,
      const Statistics(
        totalCases: 12,
        openCases: 4,
        outcomes: [
          OutcomeStat(DispositionType.released, 5),
          OutcomeStat(DispositionType.died, 3),
        ],
        bySpecies: [StatCount('Columba livia', 9)],
        byCondition: [StatCount('Trichomoniasis', 6)],
        avgTimeInCareDays: 15.4,
      ),
    );

    expect(find.text('12'), findsOneWidget); // total cases
    expect(find.text('15.4 d'), findsOneWidget); // avg time in care
    expect(find.text('Released'), findsOneWidget);
    expect(find.text('Columba livia'), findsOneWidget);
    expect(find.text('Trichomoniasis'), findsOneWidget);
  });

  testWidgets('shows an empty hint for breakdowns with no data',
      (tester) async {
    await _pump(
      tester,
      const Statistics(
        totalCases: 0,
        openCases: 0,
        outcomes: [],
        bySpecies: [],
        byCondition: [],
        avgTimeInCareDays: null,
      ),
    );

    expect(find.text('Not enough data yet'), findsWidgets);
    expect(find.text('–'), findsOneWidget); // avg with no data
  });
}
