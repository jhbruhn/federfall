import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> _tileWidth(WidgetTester tester, double available) async {
  // The surface has to be wider than the box under test, or the Scaffold
  // clamps it and the grid sizes to the window instead of to its constraints.
  tester.view.physicalSize = Size(available + 200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: available,
          child: KpiGrid([
            for (var i = 0; i < 5; i++)
              KpiCard(icon: Icons.pets, label: 'L$i', value: '$i'),
          ]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(KpiCard).first).width;
}

/// Pumps [labels] as tiles at [available] width and returns each card's rect.
Future<List<Rect>> _tileRects(
  WidgetTester tester,
  double available,
  List<String> labels,
) async {
  tester.view.physicalSize = Size(available + 200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: available,
          child: KpiGrid([
            for (final label in labels)
              KpiCard(icon: Icons.pets, label: label, value: '1'),
          ]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final cards = find.byType(KpiCard);
  return [
    for (var i = 0; i < cards.evaluate().length; i++)
      tester.getRect(cards.at(i)),
  ];
}

void main() {
  testWidgets('a wrapping label lifts the tile beside it', (tester) async {
    // federfall-773v: a `Wrap` gave every tile its own height, so a label that
    // needs a second line left its row ragged along the bottom — measured on
    // the dashboard's own labels, 176px beside 196px. The tallest tile in a row
    // now sets that row's height. A long label rather than a real one so the
    // assertion does not depend on where a particular font happens to break.
    const long = 'A caseload label long enough to need a second line';
    final rects = await _tileRects(tester, 400, const [
      'Short',
      long,
      'Short',
      'Short',
    ]);

    expect(rects, hasLength(4));
    // Row one: flush top and bottom despite the mismatched labels.
    expect(rects[0].top, rects[1].top);
    expect(rects[0].height, rects[1].height);
    // Row two: all short, so it is genuinely shorter — which is what proves
    // row one was lifted by its long label rather than everything being padded
    // to one fixed size.
    expect(rects[2].height, rects[3].height);
    expect(rects[0].height, greaterThan(rects[2].height));
  });

  testWidgets('the real dashboard labels leave no ragged row', (tester) async {
    // The measured case, at the width that reproduced it: a phone's 400px
    // window less the page's 16px padding on each side.
    final rects = await _tileRects(tester, 368, const [
      'Active cases',
      'Intakes this year',
      'Ready for release',
      'In aviary',
    ]);

    expect(rects[0].height, rects[1].height);
    expect(rects[2].height, rects[3].height);
    expect(rects[0].bottom, rects[1].bottom);
    expect(rects[2].bottom, rects[3].bottom);
  });

  testWidgets('a short last row keeps its column width', (tester) async {
    // Three tiles in two columns: the lone third must stay tile-sized rather
    // than stretch across the grid, or the row reads as a different component.
    final rects = await _tileRects(tester, 400, const ['A', 'B', 'C']);

    expect(rects[2].width, rects[0].width);
    expect(rects[2].left, rects[0].left);
  });

  testWidgets('a note stays inside the tile it qualifies', (tester) async {
    // federfall-v5di: "Rates over 8 ended cases" under the grid read as a
    // qualifier on the intake count as well. A tile carries its own.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KpiGrid([
            KpiCard(icon: Icons.pets, label: 'Intakes', value: '12'),
            KpiCard(
              icon: Icons.flight_takeoff_outlined,
              label: 'Release rate',
              value: '63 %',
              note: 'of 8 ended cases',
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(KpiCard, 'Release rate'),
        matching: find.text('of 8 ended cases'),
      ),
      findsOneWidget,
    );
    // A tile with nothing to qualify grows nothing.
    expect(
      find.descendant(
        of: find.widgetWithText(KpiCard, 'Intakes'),
        matching: find.text('of 8 ended cases'),
      ),
      findsNothing,
    );
  });

  testWidgets('a phone keeps two columns', (tester) async {
    final width = await _tileWidth(tester, 360);
    expect(width, closeTo((360 - 16) / 2, 1));
  });

  testWidgets('a wide window earns more columns, up to four', (tester) async {
    // Five tiles in two columns is three rows of scrolling on a desktop.
    expect(await _tileWidth(tester, 800), lessThan(300));
    expect(await _tileWidth(tester, 1200), closeTo((1200 - 48) / 4, 1));
    // ...and never a fifth: past four the eye stops reading a row.
    expect(await _tileWidth(tester, 2000), closeTo((2000 - 48) / 4, 1));
  });
}
