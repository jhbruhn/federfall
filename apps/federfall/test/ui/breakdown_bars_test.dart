import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  List<ChartEntry> entries, {
  required int total,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BreakdownBars(
          entries: entries,
          total: total,
          caption: 'Share of intakes',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The fraction of the track each bar actually fills.
List<double> _widthFactors(WidgetTester tester) => tester
    .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
    .map((b) => b.widthFactor!)
    .toList();

void main() {
  testWidgets('a bar is as long as the percentage beside it (federfall-qogh)', (
    tester,
  ) async {
    // The bug this widget replaces: 2 of 14 intakes drew HALF a ring and was
    // labelled 14%. A bar is measured against the stated total and nothing
    // else, so the geometry and the label cannot come apart.
    await _pump(
      tester,
      const [
        ChartEntry('PMV', 2),
        ChartEntry('Gefiederschaden', 1),
        ChartEntry('Suems', 1),
      ],
      total: 14,
    );

    expect(_widthFactors(tester), [2 / 14, 1 / 14, 1 / 14]);
    expect(find.text('14%'), findsOneWidget);
    expect(find.text('7%'), findsNWidgets(2));
  });

  testWidgets('overlapping counts are each their own share, not a partition', (
    tester,
  ) async {
    // A case carries several diagnoses, so these sum past the intakes — which
    // is exactly why they are not slices of one ring. Every bar stays a share
    // of the total, none of them is rescaled to make room for the others.
    await _pump(
      tester,
      const [ChartEntry('PMV', 8), ChartEntry('Fraktur', 6)],
      total: 10,
    );

    expect(_widthFactors(tester), [0.8, 0.6]);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
  });

  testWidgets('bars are ranked and capped; the rows below carry the rest', (
    tester,
  ) async {
    await _pump(
      tester,
      const [
        ChartEntry('Sixth', 1),
        ChartEntry('A', 6),
        ChartEntry('B', 5),
        ChartEntry('C', 4),
        ChartEntry('D', 3),
        ChartEntry('E', 2),
      ],
      total: 10,
    );

    expect(_widthFactors(tester), hasLength(BreakdownBars.maxBars));
    expect(_widthFactors(tester).first, 0.6);
    expect(find.text('Sixth'), findsNothing);
  });

  testWidgets('a share too small to round up never reads as nothing', (
    tester,
  ) async {
    await _pump(tester, const [ChartEntry('Rarity', 1)], total: 400);

    expect(find.text('0%'), findsNothing);
    expect(find.text('<1%'), findsOneWidget);
  });

  testWidgets('names the denominator, because a percent of nothing is a lie', (
    tester,
  ) async {
    await _pump(tester, const [ChartEntry('PMV', 2)], total: 14);

    expect(find.text('Share of intakes'), findsOneWidget);
  });

  testWidgets('nothing to plot renders nothing at all', (tester) async {
    await _pump(tester, const [], total: 14);
    expect(find.byType(FractionallySizedBox), findsNothing);

    await _pump(tester, const [ChartEntry('Nil', 0)], total: 14);
    expect(find.byType(FractionallySizedBox), findsNothing);

    // No intakes: there is no denominator to measure anything against.
    await _pump(tester, const [ChartEntry('PMV', 2)], total: 0);
    expect(find.byType(FractionallySizedBox), findsNothing);
  });
}
