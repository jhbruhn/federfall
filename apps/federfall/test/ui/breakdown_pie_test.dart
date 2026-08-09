import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PieChartData?> _pump(
  WidgetTester tester,
  List<ChartEntry> entries, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: BreakdownPie(entries: entries, otherLabel: 'Other'),
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
      ChartEntry('Stadttaube', 10),
      ChartEntry('Ringeltaube', 6),
      ChartEntry('Türkentaube', 3),
      ChartEntry('Hohltaube', 2),
      ChartEntry('Mauersegler', 1),
    ]);

    expect(data!.sections, hasLength(4));
    expect(data.sections.last.value, 3); // 2 + 1, the folded tail
    expect(find.textContaining('Other'), findsOneWidget);
  });

  testWidgets('no fold when everything fits in its own colour', (tester) async {
    final data = await _pump(tester, const [
      ChartEntry('Released', 5),
      ChartEntry('Died', 3),
    ]);

    expect(data!.sections, hasLength(2));
    expect(find.textContaining('Other'), findsNothing);
  });

  testWidgets('slices are ranked, not left in the order given', (tester) async {
    final data = await _pump(tester, const [
      ChartEntry('Small', 1),
      ChartEntry('Big', 9),
    ]);

    expect(data!.sections.first.value, 9);
  });

  testWidgets('names every slice with its share, never colour alone', (
    tester,
  ) async {
    await _pump(tester, const [
      ChartEntry('Released', 3),
      ChartEntry('Died', 1),
    ]);

    expect(find.text('Released · 75%'), findsOneWidget);
    expect(find.text('Died · 25%'), findsOneWidget);
  });

  testWidgets('every arc is its own label: the ring is the sum of the parts', (
    tester,
  ) async {
    // federfall-qogh: the conditions donut drew arcs over the counted sum while
    // labelling them against a bigger denominator, so a half-ring read 14%.
    // There is no denominator to pass any more — this pins that the two agree.
    final data = await _pump(tester, const [
      ChartEntry('Released', 3),
      ChartEntry('Died', 1),
    ]);

    final total = data!.sections.fold<double>(0, (s, x) => s + x.value);
    expect(data.sections.first.value / total, 0.75);
    expect(find.text('Released · 75%'), findsOneWidget);
    expect(data.sections.first.title, '75%');
  });

  testWidgets('nothing to plot renders nothing at all', (tester) async {
    expect(await _pump(tester, const []), isNull);
    expect(await _pump(tester, const [ChartEntry('Nil', 0)]), isNull);
  });

  testWidgets('dark mode gets its own steps, not the light ones', (
    tester,
  ) async {
    // The two palettes were validated separately against their own surfaces;
    // an automatic flip would put the light steps on a dark card.
    final light = await _pump(tester, const [ChartEntry('A', 1)]);
    final dark = await _pump(
      tester,
      const [ChartEntry('A', 1)],
      brightness: Brightness.dark,
    );

    expect(light!.sections.first.color, isNot(dark!.sections.first.color));
  });
}
