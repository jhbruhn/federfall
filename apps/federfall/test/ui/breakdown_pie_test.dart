import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PieChartData?> _pump(
  WidgetTester tester,
  List<PieEntry> entries, {
  int? total,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: BreakdownPie(entries: entries, otherLabel: 'Other', total: total),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final charts = find.byType(PieChart);
  if (charts.evaluate().isEmpty) return null;
  return tester.widget<PieChart>(charts).data;
}

void main() {
  testWidgets('folds everything past the coloured slices into one', (
    tester,
  ) async {
    // A pie is an all-pairs form: past three hues a pair lands on screen that
    // even a full-colour reader cannot separate. So the tail folds rather than
    // growing new colours — and the fold is one slice, not a rainbow.
    final data = await _pump(tester, const [
      PieEntry('Stadttaube', 10),
      PieEntry('Ringeltaube', 6),
      PieEntry('Türkentaube', 3),
      PieEntry('Hohltaube', 2),
      PieEntry('Mauersegler', 1),
    ]);

    expect(data!.sections, hasLength(4));
    expect(data.sections.last.value, 3); // 2 + 1, the folded tail
    expect(find.textContaining('Other'), findsOneWidget);
  });

  testWidgets('no fold when everything fits in its own colour', (tester) async {
    final data = await _pump(tester, const [
      PieEntry('Released', 5),
      PieEntry('Died', 3),
    ]);

    expect(data!.sections, hasLength(2));
    expect(find.textContaining('Other'), findsNothing);
  });

  testWidgets('slices are ranked, not left in the order given', (tester) async {
    final data = await _pump(tester, const [
      PieEntry('Small', 1),
      PieEntry('Big', 9),
    ]);

    expect(data!.sections.first.value, 9);
  });

  testWidgets('names every slice with its share, never colour alone', (
    tester,
  ) async {
    await _pump(tester, const [PieEntry('Released', 3), PieEntry('Died', 1)]);

    expect(find.text('Released · 75%'), findsOneWidget);
    expect(find.text('Died · 25%'), findsOneWidget);
  });

  testWidgets('an explicit total is the denominator, not the sum of parts', (
    tester,
  ) async {
    // Diagnoses: one case can carry several, so the shares are of the period's
    // cases and would otherwise add up past what happened.
    await _pump(
      tester,
      const [PieEntry('Fraktur', 3)],
      total: 6,
    );

    expect(find.text('Fraktur · 50%'), findsOneWidget);
  });

  testWidgets('nothing to plot renders nothing at all', (tester) async {
    expect(await _pump(tester, const []), isNull);
    expect(await _pump(tester, const [PieEntry('Nil', 0)]), isNull);
  });

  testWidgets('dark mode gets its own steps, not the light ones', (
    tester,
  ) async {
    // The two palettes were validated separately against their own surfaces;
    // an automatic flip would put the light steps on a dark card.
    final light = await _pump(tester, const [PieEntry('A', 1)]);
    final dark = await _pump(
      tester,
      const [PieEntry('A', 1)],
      brightness: Brightness.dark,
    );

    expect(light!.sections.first.color, isNot(dark!.sections.first.color));
  });
}
